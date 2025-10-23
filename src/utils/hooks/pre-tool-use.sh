#!/usr/bin/env bash
# Hook: PreToolUse - Logs and displays tool usage before execution
# Called by Claude Code before each tool use
# Receives JSON data via stdin

set -euo pipefail

# Find project root robustly (hooks may run in various contexts)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
else
    search_path="$HOOK_DIR"
    while [[ "$search_path" != "/" ]]; do
        if [[ -f "$search_path/VERSION" ]]; then
            PROJECT_ROOT="$search_path"
            break
        fi
        search_path="$(dirname "$search_path")"
    done
    if [[ -z "${PROJECT_ROOT:-}" ]]; then
        PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
    fi
fi
ROOT="$PROJECT_ROOT"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    get_epoch() { date +%s; }
}

# Source shared-state for atomic operations (with fallback)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || true

debug_log() {
    local msg="$1"
    local ts
    ts=$(get_timestamp)
    local log_file="${HOOK_DEBUG_LOG:-$PROJECT_ROOT/hook-debug.log}"
    {
        printf '%s %s\n' "$ts" "$msg"
    } >> "$log_file" 2>/dev/null || true
}

debug_log "hook_project_root_init $PROJECT_ROOT"

# Read hook data from stdin
hook_raw_input=$(cat)
hook_data="$hook_raw_input"
debug_log "hook_invoked raw_len=${#hook_raw_input}"

# Extract tool information
tool_name=$(echo "$hook_data" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "jq_error")
# Get agent name from environment (set by invoke-agent.sh)
agent_name="${CCONDUCTOR_AGENT_NAME:-unknown}"
debug_log "hook_context tool=$tool_name agent=$agent_name"

# Validate file access and tool usage for orchestrator
if [[ "$agent_name" == "mission-orchestrator" ]]; then
    case "$tool_name" in
        Read|Write|Edit|MultiEdit)
            file_path=$(echo "$hook_data" | jq -r '.tool_input.file_path // ""')
            if [[ -n "$file_path" ]]; then
                # Get absolute path
                abs_path=$(cd "$(dirname "$file_path")" 2>/dev/null && pwd)/$(basename "$file_path") || abs_path="$file_path"
                
                # Check if path is within session directory
                if [[ -n "$session_dir" ]]; then
                    abs_session=$(cd "$session_dir" 2>/dev/null && pwd)
                    # Allow session directory, config directory, and knowledge-base
                    if [[ "$abs_path" != "$abs_session"* ]] && \
                       [[ "$abs_path" != *"/config/"* ]] && \
                       [[ "$abs_path" != *"/knowledge-base/"* ]] && \
                       [[ "$abs_path" != *"/knowledge-base-custom/"* ]]; then
                        echo "ERROR: Orchestrator cannot access files outside session directory" >&2
                        echo "  Blocked: $file_path" >&2
                        echo "  Session: $session_dir" >&2
                        exit 1
                    fi
                fi
            fi
            ;;
        Bash)
            # Only allow whitelisted utility scripts
            command=$(echo "$hook_data" | jq -r '.tool_input.command // ""')
            
            # Whitelist of safe utility scripts
            if [[ "$command" =~ ^(src/utils/calculate\.sh|src/utils/kg-utils\.sh|src/utils/data-utils\.sh) ]]; then
                # Allow whitelisted utilities
                exit 0
            else
                echo "ERROR: Orchestrator can only use whitelisted utility scripts" >&2
                echo "  Blocked command: $command" >&2
                echo "" >&2
                echo "  Allowed utilities:" >&2
                echo "    - src/utils/calculate.sh (math operations)" >&2
                echo "    - src/utils/kg-utils.sh (knowledge graph queries)" >&2
                echo "    - src/utils/data-utils.sh (data transformation)" >&2
                exit 1
            fi
            ;;
    esac
fi

# Extract tool input (summary only, full data in events.jsonl)
tool_input_summary=""
tool_input_details=""
case "$tool_name" in
    WebSearch)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.query // "no query"')
        ;;
    WebFetch)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.url // "no url"')
        tool_input_details="$tool_input_summary"
        ;;
    Bash)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.command // "no command"')
        tool_input_details="$tool_input_summary"
        ;;
    Read)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.file_path // "no path"')
        ;;
    Write|Edit|MultiEdit)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.file_path // "no path"')
        ;;
    Glob)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.pattern // "no pattern"')
        ;;
    Grep)
        # Show search pattern (most relevant info for grep)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.pattern // "pattern"')
        ;;
    TodoWrite)
        # Extract high-priority or in-progress todos (most relevant)
        # Format: "content (status)" for up to 3 most important tasks
        tool_input_summary=$(echo "$hook_data" | jq -r '
            [.tool_input.todos[]? | 
             select(.priority == "high" or .status == "in_progress") | 
             .content] | 
            .[0:3] | 
            join("; ")' 2>/dev/null)
        # Fallback: if no high-priority tasks, show first 3 todos
        if [[ -z "$tool_input_summary" ]]; then
            tool_input_summary=$(echo "$hook_data" | jq -r '[.tool_input.todos[]?.content // empty] | .[0:3] | join("; ")' 2>/dev/null || echo "tasks")
        fi
        ;;
    *)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input | keys | join(", ")' 2>/dev/null || echo "...")
        ;;
esac

session_dir="${CCONDUCTOR_SESSION_DIR:-}"
if [[ -z "$session_dir" ]]; then
    transcript_path=$(echo "$hook_data" | jq -r '.transcript_path // ""')
    if [[ -n "$transcript_path" && "$transcript_path" != "null" ]]; then
        session_dir="$(dirname "$transcript_path")"
    elif [[ -f "events.jsonl" ]]; then
        session_dir=$(pwd)
    else
        session_dir=""
    fi
fi
if [[ -n "$session_dir" ]]; then
    HOOK_DEBUG_LOG="$session_dir/hook-debug.log"
    debug_log "hook_session_dir $session_dir"
else
    debug_log "hook_session_dir_unset"
fi

if [[ -n "$session_dir" && -d "$session_dir/library" ]]; then
    real_library_dir=$(cd "$session_dir/library" && pwd -P)
    debug_log "hook_real_library_dir ${real_library_dir:-none}"
    if [[ -n "$real_library_dir" ]]; then
        PROJECT_ROOT="$(cd "$real_library_dir/.." && pwd)"
        ROOT="$PROJECT_ROOT"
        export HOOK_DEBUG_LOG
        debug_log "hook_project_root_adjusted $PROJECT_ROOT"
    fi
fi

emit_event() {
    local event_type="$1"
    local event_data_json="$2"

    if [[ -z "${session_dir:-}" ]]; then
        return 0
    fi
    if [[ -z "$event_type" || -z "$event_data_json" ]]; then
        return 0
    fi

    local lock_file="$session_dir/.events.lock"
    local start_time
    start_time=$(get_epoch)
    local timeout=5

    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            jq -n -c \
                --arg ts "$(get_timestamp)" \
                --arg type "$event_type" \
                --argjson data "$event_data_json" \
                '{timestamp: $ts, type: $type, data: $data}' \
                >> "$session_dir/events.jsonl" 2>/dev/null
            rmdir "$lock_file" 2>/dev/null || true
            break
        fi

        local elapsed
        elapsed=$(($(get_epoch) - start_time))
        if [[ "$elapsed" -ge "$timeout" ]]; then
            debug_log "emit_event_timeout type=$event_type"
            break
        fi
        sleep 0.05
    done
}

# Source utilities after resolving project root
# shellcheck disable=SC1091
if source "$PROJECT_ROOT/src/utils/verbose.sh" 2>/dev/null; then
    :
else
    # Fallback stubs if verbose utilities unavailable
    # shellcheck disable=SC2329
    is_verbose_enabled() { [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; }
    # shellcheck disable=SC2329
    verbose_tool_use() { :; }
fi
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-cache.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-search-cache.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh" 2>/dev/null || true

# WebSearch cache guard (avoid redundant billed queries)
if [[ "$tool_name" == "WebSearch" ]]; then
    query=$(echo "$hook_data" | jq -r '.tool_input.query // empty')
    debug_log "web_search_guard_start query_length=${#query}"
    if [[ -n "$query" ]] && command -v web_search_cache_lookup >/dev/null 2>&1 && web_search_cache_enabled; then
        lookup_json=$(web_search_cache_lookup "$query")
        status=$(echo "$lookup_json" | jq -r '.status // "miss"')
        debug_log "web_search_guard_status $status"
        case "$status" in
            hit)
                display_query=$(web_search_cache_display_query "$query" 2>/dev/null || printf '%s' "$query")
                stored_iso=$(echo "$lookup_json" | jq -r '.metadata.stored_at_iso // ""')
                if [[ -z "$stored_iso" ]]; then
                    stored_iso=$(get_timestamp)
                fi
                materialized_path=""
                if [[ -n "$session_dir" ]]; then
                    materialized_path=$(web_search_cache_materialize_for_session "$session_dir" "$query" "$lookup_json" 2>/dev/null || echo "")
                fi
                result_count=$(echo "$lookup_json" | jq -r '.metadata.result_count // 0')
                if [[ -z "$result_count" || "$result_count" == "null" ]]; then
                    result_count=0
                fi
                match_ratio=$(echo "$lookup_json" | jq -r '.match_ratio // ""')
                match_base_query=$(echo "$lookup_json" | jq -r '.match_base_query // ""')
                # Cache hit detected - emit event for tailer to display
                # Note: Hook stderr is captured by Claude CLI, so we emit events instead
                # The event tailer reads events.jsonl and displays formatted output
                tool_block_reason="web_search_cache_hit"
                if [[ -n "$match_ratio" && "$match_ratio" != "null" ]]; then
                    tool_block_reason="web_search_cache_hit_overlap"
                fi

                if [[ -n "$session_dir" ]]; then
                    lock_file="$session_dir/.events.lock"
                    if mkdir "$lock_file" 2>/dev/null; then
                        jq -cn \
                            --arg ts "$(get_timestamp)" \
                            --arg type "web_search_cache_hit" \
                            --arg query "$display_query" \
                            --arg normalized "$(echo "$lookup_json" | jq -r '.normalized_query // ""')" \
                            --arg path "$materialized_path" \
                            --arg status "$status" \
                            --arg count "$result_count" \
                            --arg match "$match_ratio" \
                            --arg base "$match_base_query" \
                            '{
                                timestamp: $ts,
                                type: $type,
                                data: {
                                    query: $query,
                                    normalized_query: (if $normalized == "" then null else $normalized end),
                                    cache_path: (if $path == "" then null else $path end),
                                    status: $status,
                                    result_count: ($count | tonumber),
                                    match_ratio: (if $match == "" or $match == "null" then null else ($match | tonumber) end),
                                    match_base_query: (if $base == "" or $base == "null" then null else $base end)
                                }
                            }' >> "$session_dir/events.jsonl" 2>/dev/null

                        jq -cn \
                            --arg ts "$(get_timestamp)" \
                            --arg type "tool_use_blocked" \
                            --arg tool "$tool_name" \
                            --arg agent "$agent_name" \
                            --arg summary "$tool_input_summary" \
                            --arg reason "$tool_block_reason" \
                            --arg details "$display_query" \
                            '{
                                timestamp: $ts,
                                type: $type,
                                data: {
                                    tool: $tool,
                                    agent: $agent,
                                    input_summary: $summary,
                                    reason: $reason,
                                    details: (if $details == "" then null else $details end)
                                }
                            }' >> "$session_dir/events.jsonl" 2>/dev/null
                        rmdir "$lock_file" 2>/dev/null || true
                    fi
                fi

                debug_log "web_search_guard_hit path=${materialized_path:-none}"
                exit 2
                ;;
            stale)
                display_query=$(web_search_cache_display_query "$query" 2>/dev/null || printf '%s' "$query")
                echo "⚠️  Cached search results for '$display_query' are older than the configured TTL; proceeding with fresh search." >&2
                debug_log "web_search_guard_stale"
                ;;
            force_refresh)
                display_query=$(web_search_cache_display_query "$query" 2>/dev/null || printf '%s' "$query")
                echo "↻ Forcing fresh search for '$display_query' (fresh parameter detected)." >&2
                debug_log "web_search_guard_force_refresh"
                ;;
            disabled)
                debug_log "web_search_guard_disabled"
                ;;
            *)
                debug_log "web_search_guard_miss"
                ;;
        esac
    else
        debug_log "web_search_guard_unavailable"
    fi
fi

# LibraryMemory guard for WebFetch (enforce cache reuse)
guard_reason=""
guard_detail=""
guard_hash_script=""
guard_library_sources=""

# LibraryMemory guard for WebFetch (enforce cache reuse)
if [[ "$tool_name" == "WebFetch" ]]; then
    url=$(echo "$hook_data" | jq -r '.tool_input.url // empty')
    guard_detail="$url"
    guard_reason="allow:no_url"
    debug_log "guard_start tool=$tool_name url=$url session_dir=${session_dir:-}"
    if [[ -n "$url" ]]; then
        check_payload=$(jq -nc \
            --arg url "$url" \
            --arg agent "$agent_name" \
            '{url: $url, agent: $agent}')
        emit_event "library_digest_check" "$check_payload"

        guard_reason="allow:no_digest"
        # Respect explicit fresh fetch requests
        if [[ "$url" != *"fresh=1"* && "$url" != *"refresh=1"* ]]; then
            library_root="${LIBRARY_MEMORY_ROOT:-$ROOT/library}"
            library_sources_dir="$library_root/sources"
            hash_script="$ROOT/src/claude-runtime/skills/library-memory/hash-url.sh"
            ttl_days="${LIBRARY_MEMORY_TTL_DAYS:-7}"
            if [[ ! "$ttl_days" =~ ^-?[0-9]+$ ]]; then
                ttl_days=7
            fi
            debug_log "guard_paths lib_root=$library_root sources=$library_sources_dir hash_script=$hash_script ttl=$ttl_days"
            if [[ -x "$hash_script" ]]; then
                debug_log "guard_hash_script_exists yes"
            else
                debug_log "guard_hash_script_exists no"
            fi
            if [[ -d "$library_sources_dir" ]]; then
                debug_log "guard_library_dir_exists yes"
            else
                debug_log "guard_library_dir_exists no"
            fi

            if [[ -d "$library_sources_dir" && -x "$hash_script" ]]; then
                url_hash=$("$hash_script" "$url" 2>/dev/null || echo "")
                debug_log "guard_hash hash=$url_hash"
                if [[ -n "$url_hash" ]]; then
                    digest_path="$library_sources_dir/${url_hash}.json"
                    debug_log "guard_digest_path $digest_path"
                    if [[ -f "$digest_path" ]]; then
                        last_updated=$(jq -r '.last_updated // empty' "$digest_path" 2>/dev/null || echo "")
                        is_fresh=0
                        if [[ -n "$last_updated" ]]; then
                            if [[ "$ttl_days" -lt 0 ]]; then
                                is_fresh=1
                            elif [[ "$ttl_days" -gt 0 ]]; then
                                if command -v python3 >/dev/null 2>&1; then
                                    debug_log "guard_checking_ttl last_updated=$last_updated"
                                    if python3 - "$last_updated" "$ttl_days" <<'PY'
import sys
from datetime import datetime, timezone

last = sys.argv[1]
ttl_days = int(sys.argv[2])
try:
    if last.endswith("Z"):
        last_dt = datetime.fromisoformat(last.replace("Z", "+00:00"))
    else:
        last_dt = datetime.fromisoformat(last)
except ValueError:
    sys.exit(2)
age = (datetime.now(timezone.utc) - last_dt).total_seconds() / 86400.0
sys.exit(0 if age <= ttl_days else 1)
PY
                                    then
                                        is_fresh=1
                                    fi
                                    debug_log "guard_ttl_result fresh=$is_fresh"
                                fi
                            fi
                        fi

                        if [[ "$is_fresh" -eq 1 ]]; then
                            stored_timestamp="${last_updated:-unknown}"
                            
                            # Cache hit detected - emit event for tailer to display
                            # Note: Hook stderr is captured by Claude CLI, so we emit events instead
                            # The event tailer reads events.jsonl and displays formatted output

                            hit_event=$(jq -nc \
                                --arg url "$url" \
                                --arg hash "$url_hash" \
                                --arg path "$digest_path" \
                                --arg last "$stored_timestamp" \
                                --arg agent "$agent_name" \
                                --argjson ttl "$ttl_days" \
                                '{
                                    url: $url,
                                    agent: $agent,
                                    url_hash: $hash,
                                    digest_path: $path,
                                    last_updated: (if $last == "" or $last == "unknown" then null else $last end),
                                    ttl_days: $ttl
                                }')
                            emit_event "library_digest_hit" "$hit_event"

                            blocked_event=$(jq -nc \
                                --arg tool "$tool_name" \
                                --arg agent "$agent_name" \
                                --arg summary "$tool_input_summary" \
                                --arg reason "library_digest_fresh" \
                                --arg details "$tool_input_details" \
                                '{
                                    tool: $tool,
                                    agent: $agent,
                                    input_summary: $summary,
                                    reason: $reason,
                                    details: (if $details == "" then null else $details end)
                                }')
                            emit_event "tool_use_blocked" "$blocked_event"

                            debug_log "guard_digest_reused path=$digest_path"
                            exit 2
                        else
                            guard_reason="allow:digest_stale"
                        fi
                    else
                        guard_reason="allow:digest_missing"
                    fi
                else
                    guard_reason="allow:hash_failed"
                fi
            else
                guard_reason="allow:library_missing"
                guard_hash_script="$hash_script"
                guard_library_sources="$library_sources_dir"
            fi
        else
            guard_reason="allow:fresh_param"
            refresh_payload=$(jq -nc \
                --arg url "$url" \
                --arg agent "$agent_name" \
                '{url: $url, agent: $agent}')
            emit_event "library_digest_force_refresh" "$refresh_payload"
            # Event emitted - tailer will display "⟳ Fresh fetch requested for $url"
        fi
    fi

    if [[ -n "$session_dir" && -n "$guard_detail" && "$guard_reason" != "allow:no_url" ]]; then
        lock_file="$session_dir/.events.lock"
        if mkdir "$lock_file" 2>/dev/null; then
            jq -cn \
                --arg ts "$(get_timestamp)" \
                --arg type "library_digest_allow" \
                --arg url "$guard_detail" \
                --arg reason "$guard_reason" \
                --arg hash "${guard_hash_script:-}" \
                --arg libdir "${guard_library_sources:-}" \
                --arg agent "$agent_name" \
                '{
                    timestamp: $ts,
                    type: $type,
                    data: {
                        url: $url,
                        agent: $agent,
                        reason: $reason,
                        hash_script: (if $hash == "" then null else $hash end),
                        library_sources_dir: (if $libdir == "" then null else $libdir end)
                    }
                }' >> "$session_dir/events.jsonl" 2>/dev/null
            rmdir "$lock_file" 2>/dev/null || true
        fi
    fi
fi

# Backup existing files before Write tool executes (for JSON validation rollback)
if [[ "$tool_name" == "Write" ]]; then
    file_path=$(echo "$hook_data" | jq -r '.tool_input.file_path // empty')
    if [[ -n "$file_path" && -f "$file_path" ]]; then
        backup_root=""
        if [[ -n "$session_dir" ]]; then
            backup_root="$session_dir/.claude/write-backups"
        elif [[ -n "$CCONDUCTOR_SESSION_DIR" ]]; then
            backup_root="$CCONDUCTOR_SESSION_DIR/.claude/write-backups"
        fi
        if [[ -n "$backup_root" ]]; then
            mkdir -p "$backup_root"
            hash=$(printf '%s' "$file_path" | shasum -a 256 | awk '{print $1}')
            cp "$file_path" "$backup_root/$hash.bak" 2>/dev/null || true
        fi
    fi
fi

# Cache + knowledge graph advisory for WebFetch
if [[ "$tool_name" == "WebFetch" && -n "$session_dir" ]]; then
    if command -v web_cache_lookup >/dev/null 2>&1 && web_cache_enabled; then
        url=$(echo "$hook_data" | jq -r '.tool_input.url // empty')
        if [[ -n "$url" ]]; then
            force_fetch=0
            if command -v web_cache_load_config >/dev/null 2>&1; then
                config=$(web_cache_load_config)
                fresh_params=()
                fresh_list=$(echo "$config" | jq -r '.fresh_url_parameters[]?')
                if [[ -n "$fresh_list" ]]; then
                    while IFS= read -r param; do
                        [[ -z "$param" ]] && continue
                        fresh_params+=("$param")
                    done <<< "$fresh_list"
                fi
                for param in "${fresh_params[@]}"; do
                    if [[ "$url" == *"$param"* ]]; then
                        force_fetch=1
                        break
                    fi
                done
            fi

            if [ "$force_fetch" -eq 0 ]; then
                lookup_json=$(web_cache_lookup "$url")
                status=$(echo "$lookup_json" | jq -r '.status // "miss"')
                if [[ "$status" == "hit" ]]; then
                    materialized_path=$(web_cache_materialize_for_session "$session_dir" "$url" "$lookup_json" 2>/dev/null || echo "")
                    if [[ -n "$materialized_path" ]]; then
                        kg_summary=""
                        if command -v kg_find_source_by_url >/dev/null 2>&1; then
                            kg_summary=$(kg_find_source_by_url "$session_dir" "$url" 2>/dev/null || echo "")
                        fi
                        stored_iso=$(echo "$lookup_json" | jq -r 'if .metadata.stored_at then (.metadata.stored_at | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")) else "" end' 2>/dev/null || printf '')
                        if [[ -z "$stored_iso" ]]; then
                            stored_iso="unknown"
                        fi
                        message="⚡ Cached web content reused for:
  URL: $url
  Cached file: $materialized_path
  Stored: $stored_iso
Use the Read tool on the cached file. Append '?fresh=1' to the URL if you must force a fresh fetch."
                        echo "$message" >&2

                        if [[ -n "$session_dir" ]]; then
                            lock_file="$session_dir/.events.lock"
                            if mkdir "$lock_file" 2>/dev/null; then
                                jq -cn \
                                    --arg ts "$(get_timestamp)" \
                                    --arg type "web_cache_hit" \
                                    --arg url "$url" \
                                    --arg path "$materialized_path" \
                                    --arg status "$status" \
                                    --arg agent "$agent_name" \
                                    --arg summary "$kg_summary" \
                                    '{
                                        timestamp: $ts,
                                        type: $type,
                                        data: {
                                            url: $url,
                                            agent: $agent,
                                            cache_path: $path,
                                            status: $status,
                                            kg_summary: (if $summary == "" then null else $summary end)
                                        }
                                    }' >> "$session_dir/events.jsonl"
                                rmdir "$lock_file" 2>/dev/null || true
                            fi
                        fi
                        exit 2
                    fi
                elif [[ "$status" == "stale" ]]; then
                    echo "⚠️  Cached copy for $url is older than the configured TTL; proceeding with fresh fetch." >&2
                fi
            else
                echo "↻ Forcing fresh fetch for $url (fresh parameter detected)." >&2
            fi
        fi
    fi
fi

# Create event for logging
timestamp=$(get_timestamp)
event_data=$(jq -n \
    --arg tool "$tool_name" \
    --arg agent "$agent_name" \
    --arg summary "$tool_input_summary" \
    --arg details "$tool_input_details" \
    '{tool: $tool, agent: $agent, input_summary: $summary, details: (if $details == "" then null else $details end)}')

# Log to events.jsonl if session directory is available
if [ -n "$session_dir" ] && [ -d "$session_dir" ]; then
    # Use atomic mkdir for locking (portable, works on all platforms)
    lock_file="$session_dir/.events.lock"
    start_time=$(get_epoch)
    timeout=5
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write event
            echo "$hook_data" | jq -c \
                --arg ts "$timestamp" \
                --arg type "tool_use_start" \
                --argjson data "$event_data" \
                '{timestamp: $ts, type: $type, data: $data}' \
                >> "$session_dir/events.jsonl" 2>/dev/null
            
            # Release lock
            rmdir "$lock_file" 2>/dev/null || true
            break
        fi
        
        # Check timeout - but don't fail hook if lock times out
        elapsed=$(($(get_epoch) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            break
        fi
        
        sleep 0.05
    done
fi

# Architecture Note: Claude Code CLI captures hook stderr output
# This means any `echo ... >&2` in this hook will NOT appear in the terminal
# Instead, we emit events to events.jsonl which are displayed by event-tailer.sh
# The event tailer runs as a background process started by invoke-agent.sh
# See: src/utils/event-tailer.sh and memory-bank/systemPatterns.md

# Exit 0 to allow the tool to proceed
exit 0
