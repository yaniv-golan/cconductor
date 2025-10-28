#!/usr/bin/env bash
# Hook: PreToolUse - Logs and displays tool usage before execution
# Called by Claude Code before each tool use
# Receives JSON data via stdin

set -euo pipefail

# Find project root and session directory via shared bootstrap
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HOOK_DIR/hook-bootstrap.sh"

hook_resolve_roots "${BASH_SOURCE[0]}"
resolved_repo="${HOOK_REPO_ROOT:-}"
resolved_session="${HOOK_SESSION_DIR:-}"

if [[ -z "$resolved_repo" ]]; then
    resolved_repo="$(cd "$HOOK_DIR/../../.." && pwd)"
fi

PROJECT_ROOT="$resolved_repo"
SESSION_DIR="$resolved_session"
session_dir="$SESSION_DIR"
ROOT="$PROJECT_ROOT"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    # shellcheck disable=SC2329
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    # shellcheck disable=SC2329
    get_epoch() { date +%s; }
    # shellcheck disable=SC2329
    log_warn() { printf '[%s] WARN: %s\n' "$(get_timestamp)" "$*" >&2; }
}

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh" 2>/dev/null || true

# Source shared-state for atomic operations (with fallback)
# shellcheck disable=SC1091
if ! source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null; then
    if [[ -z "${PRE_HOOK_SHARED_STATE_WARNED:-}" ]]; then
        log_warn "Optional shared-state.sh failed to load in pre-tool-use hook (lock coordination disabled)"
        PRE_HOOK_SHARED_STATE_WARNED=1
    fi
fi

debug_log() {
    local msg="$1"
    local ts
    ts=$(get_timestamp)
    # Use session_dir if set, otherwise fall back to PROJECT_ROOT
        local log_file="${HOOK_DEBUG_LOG:-}"
        if [[ -z "$log_file" ]]; then
            if [[ -n "${session_dir:-}" && -d "${session_dir:-}" ]]; then
                log_file="$session_dir/logs/hook-debug.log"
            else
                # Skip logging when session_dir is not set to avoid root file
                return 0
            fi
        fi
    {
        printf '%s %s\n' "$ts" "$msg"
    } >> "$log_file" 2>/dev/null || true
}

safe_realpath() {
    local target="$1"

    if command -v realpath >/dev/null 2>&1; then
        realpath "$target" 2>/dev/null && return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$target" <<'PY' 2>/dev/null && return 0
import os
import sys

try:
    print(os.path.realpath(sys.argv[1]))
except Exception:
    sys.exit(1)
PY
    fi

    local dir_part
    dir_part=$(dirname -- "$target" 2>/dev/null || echo ".")
    local base_part
    base_part=$(basename -- "$target" 2>/dev/null || echo "$target")
    if resolved_dir=$(cd "$dir_part" 2>/dev/null && pwd -P); then
        printf '%s/%s\n' "$resolved_dir" "$base_part"
    else
        printf '%s\n' "$target"
    fi
}

is_path_allowed_for_orchestrator() {
    local abs_target="$1"
    local session_path="$2"

    local abs_session=""
    if [[ -n "$session_path" ]]; then
        abs_session=$(safe_realpath "$session_path")
    fi

    local -a allowlist=()
    if [[ -n "$abs_session" ]]; then
        allowlist+=("$abs_session")
    fi

    local candidate
    for candidate in \
        "$PROJECT_ROOT/config" \
        "$PROJECT_ROOT/knowledge-base" \
        "$PROJECT_ROOT/knowledge-base-custom"; do
        if [[ -n "$candidate" ]]; then
            allowlist+=("$(safe_realpath "$candidate")")
        fi
    done

    local allowed_dir
    for allowed_dir in "${allowlist[@]}"; do
        if [[ -z "$allowed_dir" ]]; then
            continue
        fi
        if [[ "$abs_target" == "$allowed_dir" ]] || [[ "$abs_target" == "$allowed_dir"/* ]]; then
            return 0
        fi
    done

    return 1
}

debug_log "hook_project_root_init $PROJECT_ROOT"

# Read hook data from stdin
hook_raw_input=$(cat)
hook_data="$hook_raw_input"
session_dir="${SESSION_DIR:-${CCONDUCTOR_SESSION_DIR:-}}"

hook_field() {
    local filter="$1"
    local fallback="$2"
    local context="$3"
    safe_jq_from_json "$hook_data" "$filter" "$fallback" "$session_dir" "pre_tool.$context"
}

lookup_field() {
    local payload="$1"
    local filter="$2"
    local fallback="$3"
    local context="$4"
    local raw="${5:-true}"
    safe_jq_from_json "$payload" "$filter" "$fallback" "$session_dir" "pre_tool.$context" "$raw"
}
debug_log "hook_invoked raw_len=${#hook_raw_input}"

# Extract tool information
tool_name=$(hook_field '.tool_name // "unknown"' 'unknown' 'tool_name')
# Get agent name from environment (set by invoke-agent.sh)
agent_name="${CCONDUCTOR_AGENT_NAME:-unknown}"
debug_log "hook_context tool=$tool_name agent=$agent_name"

# Validate file access and tool usage for orchestrator
if [[ "$agent_name" == "mission-orchestrator" ]]; then
    case "$tool_name" in
        Read|Write|Edit|MultiEdit)
            file_path=$(hook_field '.tool_input.file_path // ""' '' 'tool_input.file_path')
            if [[ -n "$file_path" ]]; then
                # Get absolute path
                abs_path=$(safe_realpath "$file_path")

                # Check if path is within the allowlist
                if [[ -n "$session_dir" ]]; then
                    if ! is_path_allowed_for_orchestrator "$abs_path" "$session_dir"; then
                        echo "ERROR: Orchestrator cannot access files outside allowed directories" >&2
                        echo "  Blocked: $file_path" >&2
                        echo "  Resolved to: $abs_path" >&2
                        exit 1
                    fi
                fi
            fi
            ;;
        Bash)
            # Only allow whitelisted utility scripts
            command=$(hook_field '.tool_input.command // ""' '' 'tool_input.command')
            
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

# Extract tool input (summary only, full data lives in logs/events.jsonl)
tool_input_summary=""
tool_input_details=""
case "$tool_name" in
    WebSearch)
        tool_input_summary=$(hook_field '.tool_input.query // "no query"' 'no query' 'tool_input.query')
        ;;
    WebFetch)
        tool_input_summary=$(hook_field '.tool_input.url // "no url"' 'no url' 'tool_input.url')
        tool_input_details="$tool_input_summary"
        ;;
    Bash)
        tool_input_summary=$(hook_field '.tool_input.command // "no command"' 'no command' 'tool_input.command_summary')
        tool_input_details="$tool_input_summary"
        ;;
    Read)
        tool_input_summary=$(hook_field '.tool_input.file_path // "no path"' 'no path' 'tool_input.file_path_read')
        ;;
    Write|Edit|MultiEdit)
        tool_input_summary=$(hook_field '.tool_input.file_path // "no path"' 'no path' 'tool_input.file_path_edit')
        ;;
    Glob)
        tool_input_summary=$(hook_field '.tool_input.pattern // "no pattern"' 'no pattern' 'tool_input.pattern_glob')
        ;;
    Grep)
        # Show search pattern (most relevant info for grep)
        tool_input_summary=$(hook_field '.tool_input.pattern // "pattern"' 'pattern' 'tool_input.pattern_grep')
        ;;
    TodoWrite)
        # Extract high-priority or in-progress todos (most relevant)
        # Format: "content (status)" for up to 3 most important tasks
        tool_input_summary=$(hook_field '[.tool_input.todos[]? | select(.priority == "high" or .status == "in_progress") | .content] | .[0:3] | join("; ")' '' 'tool_input.todo_high')
        # Fallback: if no high-priority tasks, show first 3 todos
        if [[ -z "$tool_input_summary" ]]; then
            tool_input_summary=$(hook_field '[.tool_input.todos[]?.content // empty] | .[0:3] | join("; ")' 'tasks' 'tool_input.todo_any')
        fi
        ;;
    *)
        tool_input_summary=$(hook_field '.tool_input | keys | join(", ")' '...' 'tool_input.generic')
        ;;
esac

if [[ -z "${session_dir:-}" ]]; then
    session_dir="${SESSION_DIR:-${CCONDUCTOR_SESSION_DIR:-}}"
fi
if [[ -z "$session_dir" ]]; then
    transcript_path=$(hook_field '.transcript_path // ""' '' 'transcript_path')
    if [[ -n "$transcript_path" && "$transcript_path" != "null" ]]; then
        session_dir="$(dirname "$transcript_path")"
    elif [[ -f "logs/events.jsonl" ]]; then
        session_dir=$(pwd)
    else
        session_dir=""
    fi
fi
if [[ -n "$session_dir" ]]; then
    HOOK_DEBUG_LOG="$session_dir/logs/hook-debug.log"
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

    local lock_file="$session_dir/logs/.events.lock"
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
                >> "$session_dir/logs/events.jsonl" 2>/dev/null
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
if ! source "$PROJECT_ROOT/src/utils/web-cache.sh" 2>/dev/null; then
    if [[ -z "${PRE_HOOK_WEB_CACHE_WARNED:-}" ]]; then
        log_warn "Optional web-cache.sh failed to load in pre-tool-use hook (web fetch cache summaries unavailable)"
        PRE_HOOK_WEB_CACHE_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$PROJECT_ROOT/src/utils/web-search-cache.sh" 2>/dev/null; then
    if [[ -z "${PRE_HOOK_SEARCH_CACHE_WARNED:-}" ]]; then
        log_warn "Optional web-search-cache.sh failed to load in pre-tool-use hook (search cache summaries unavailable)"
        PRE_HOOK_SEARCH_CACHE_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$PROJECT_ROOT/src/knowledge-graph.sh" 2>/dev/null; then
    if [[ -z "${PRE_HOOK_KG_WARNED:-}" ]]; then
        log_warn "Optional knowledge-graph.sh failed to load in pre-tool-use hook (KG helpers unavailable)"
        PRE_HOOK_KG_WARNED=1
    fi
fi

# WebSearch cache guard (avoid redundant billed queries)
if [[ "$tool_name" == "WebSearch" ]]; then
query=$(hook_field '.tool_input.query // empty' '' 'web_search.query')
    debug_log "web_search_guard_start query_length=${#query}"
    if [[ -n "$query" ]] && command -v web_search_cache_lookup >/dev/null 2>&1 && web_search_cache_enabled; then
        lookup_json=$(web_search_cache_lookup "$query")
        status=$(lookup_field "$lookup_json" '.status // "miss"' 'miss' 'search_cache.status')
        debug_log "web_search_guard_status $status"
        case "$status" in
            hit)
                display_query=$(web_search_cache_display_query "$query" 2>/dev/null || printf '%s' "$query")
                stored_iso=$(lookup_field "$lookup_json" '.metadata.stored_at_iso // ""' '' 'search_cache.stored_at_iso')
                if [[ -z "$stored_iso" ]]; then
                    stored_iso=$(get_timestamp)
                fi
                materialized_path=""
                if [[ -n "$session_dir" ]]; then
                    materialized_path=$(web_search_cache_materialize_for_session "$session_dir" "$query" "$lookup_json" 2>/dev/null || echo "")
                fi
                result_count=$(lookup_field "$lookup_json" '.metadata.result_count // 0' '0' 'search_cache.result_count')
                if [[ -z "$result_count" || "$result_count" == "null" ]]; then
                    result_count=0
                fi
                match_ratio=$(lookup_field "$lookup_json" '.match_ratio // ""' '' 'search_cache.match_ratio')
                match_base_query=$(lookup_field "$lookup_json" '.match_base_query // ""' '' 'search_cache.match_base')
                # Cache hit detected - emit event for tailer to display
                # Note: Hook stderr is captured by Claude CLI, so we emit events instead
                # The event tailer reads logs/events.jsonl and displays formatted output
                tool_block_reason="web_search_cache_hit"
                if [[ -n "$match_ratio" && "$match_ratio" != "null" ]]; then
                    tool_block_reason="web_search_cache_hit_overlap"
                fi

                if [[ -n "$session_dir" ]]; then
                    lock_file="$session_dir/logs/.events.lock"
                    if mkdir "$lock_file" 2>/dev/null; then
                        jq -cn \
                            --arg ts "$(get_timestamp)" \
                            --arg type "web_search_cache_hit" \
                            --arg query "$display_query" \
                            --arg normalized "$(lookup_field "$lookup_json" '.normalized_query // ""' '' 'search_cache.normalized_query')" \
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
                            }' >> "$session_dir/logs/events.jsonl" 2>/dev/null

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
                            }' >> "$session_dir/logs/events.jsonl" 2>/dev/null
                        rmdir "$lock_file" 2>/dev/null || true
                    fi
                fi

                debug_log "web_search_guard_hit path=${materialized_path:-none}"
                payload_file="$materialized_path"
                if [[ -z "$payload_file" ]]; then
                    payload_file=$(lookup_field "$lookup_json" '.object_path // empty' '' 'search_cache.object_path')
                fi
                if [[ -n "$payload_file" && -f "$payload_file" ]]; then
                    jq -n \
                        --arg status "$status" \
                        --arg stored "$stored_iso" \
                        --slurpfile payload "$payload_file" \
                        '{
                            cache_hit: true,
                            cache_status: $status,
                            stored_at: (if $stored == "" then null else $stored end),
                            tool_output: ($payload[0] // null)
                        }'
                    exit 0
                fi
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
url=$(hook_field '.tool_input.url // empty' '' 'web_fetch.url')
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
                        last_updated=$(safe_jq_from_file "$digest_path" '.last_updated // empty' '' "$session_dir" "digest.last_updated")
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
        lock_file="$session_dir/logs/.events.lock"
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
                }' >> "$session_dir/logs/events.jsonl" 2>/dev/null
            rmdir "$lock_file" 2>/dev/null || true
        fi
    fi
fi

# Backup existing files before Write tool executes (for JSON validation rollback)
if [[ "$tool_name" == "Write" ]]; then
file_path=$(hook_field '.tool_input.file_path // empty' '' 'file_watch.file_path')
    if [[ -n "$file_path" && -f "$file_path" ]]; then
        backup_root=""
        if [[ -n "$session_dir" ]]; then
            backup_root="$session_dir/.claude/write-backups"
        elif [[ -n "$CCONDUCTOR_SESSION_DIR" ]]; then
            backup_root="$CCONDUCTOR_SESSION_DIR/.claude/write-backups"
        fi
        if [[ -n "$backup_root" ]]; then
            mkdir -p "$backup_root"
            hash=$("$PROJECT_ROOT/src/utils/hash-string.sh" "$file_path")
            cp "$file_path" "$backup_root/$hash.bak" 2>/dev/null || true
        fi
    fi
fi

# Cache + knowledge graph advisory for WebFetch
if [[ "$tool_name" == "WebFetch" && -n "$session_dir" ]]; then
    if command -v web_cache_lookup >/dev/null 2>&1 && web_cache_enabled; then
        url=$(hook_field '.tool_input.url // empty' '' 'library.url_check')
        if [[ -n "$url" ]]; then
            force_fetch=0
            if command -v web_cache_load_config >/dev/null 2>&1; then
                config=$(web_cache_load_config)
                fresh_params=()
                fresh_params_json=$(safe_jq_from_json "$config" '.fresh_url_parameters // []' '[]' "$session_dir" "web_cache.fresh_params" "false")
                if [[ -n "$fresh_params_json" ]]; then
                    while IFS= read -r param; do
                        [[ -z "$param" ]] && continue
                        fresh_params+=("$param")
                    done < <(jq -r '.[]?' <<< "$fresh_params_json")
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
                status=$(lookup_field "$lookup_json" '.status // "miss"' 'miss' 'web_cache.status')
                if [[ "$status" == "hit" ]]; then
                    materialized_path=$(web_cache_materialize_for_session "$session_dir" "$url" "$lookup_json" 2>/dev/null || echo "")
                    if [[ -n "$materialized_path" ]]; then
                        kg_summary=""
                        if command -v kg_find_source_by_url >/dev/null 2>&1; then
                            kg_summary=$(kg_find_source_by_url "$session_dir" "$url" 2>/dev/null || echo "")
                        fi
                stored_iso=$(lookup_field "$lookup_json" 'if .metadata.stored_at then (.metadata.stored_at | gmtime | strftime("%Y-%m-%dT%H:%M:%SZ")) else "" end' '' 'web_cache.stored_at' )
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
                            lock_file="$session_dir/logs/.events.lock"
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
                                    }' -c >> "$session_dir/logs/events.jsonl"
                                rmdir "$lock_file" 2>/dev/null || true
                            fi
                        fi
                        status_code=$(lookup_field "$lookup_json" '.metadata.status_code // 200' '200' 'web_cache.status_code')
                        content_type=$(lookup_field "$lookup_json" '.metadata.content_type // ""' '' 'web_cache.content_type')
                        headers_json=$(lookup_field "$lookup_json" '.metadata.headers // {}' '{}' 'web_cache.headers' 'false')
                        jq -n \
                            --arg path "$materialized_path" \
                            --arg status "$status_code" \
                            --arg content_type "$content_type" \
                            --argjson headers "$headers_json" \
                            '{
                                cache_hit: true,
                                tool_output: {
                                    body: null,
                                    body_file: $path,
                                    content_type: (if $content_type == "" then null else $content_type end),
                                    status_code: ($status | tonumber),
                                    headers: $headers
                                }
                            }'
                        exit 0
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

# Log to logs/events.jsonl if session directory is available
if [ -n "$session_dir" ] && [ -d "$session_dir" ]; then
    # Use atomic mkdir for locking (portable, works on all platforms)
    lock_file="$session_dir/logs/.events.lock"
    start_time=$(get_epoch)
    timeout=5
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write event
            jq -n -c --arg ts "$timestamp" --arg type "tool_use_start" --argjson data "$event_data" \
                '{timestamp: $ts, type: $type, data: $data}' >> "$session_dir/logs/events.jsonl" 2>/dev/null
            
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
# Instead, we emit events to logs/events.jsonl which are displayed by event-tailer.sh
# The event tailer runs as a background process started by invoke-agent.sh
# See: src/utils/event-tailer.sh and memory-bank/systemPatterns.md

# Exit 0 to allow the tool to proceed
exit 0
