#!/usr/bin/env bash
# Event Tailer - Real-time verbose display of tool use from events.jsonl
# Tails events.jsonl and displays tool activity in user-friendly format

set -euo pipefail

# Source verbose utility for message formatting
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/verbose.sh" 2>/dev/null || {
    # Fallback if verbose.sh not available
    is_verbose_enabled() { [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; }
}

TAILER_CURRENT_AGENT=""
TAILER_CACHE_ACTIVITY=0
TAILER_TOTAL_HITS=0
TAILER_TOTAL_FETCHES=0
TAILER_TOTAL_FORCE_REFRESH=0
declare -A TAILER_CACHE_HIT_COUNTS=()
TAILER_LAST_LIBRARY_EVENT_TIME=0
TAILER_LAST_LIBRARY_URL=""
TAILER_SESSION_DIR=""
TAILER_PROJECT_ROOT=""

tailer_rel_path() {
    local raw_path="$1"
    if [[ -z "$raw_path" || "$raw_path" == "null" ]]; then
        echo "$raw_path"
        return 0
    fi

    # Only adjust absolute paths
    if [[ "$raw_path" != /* ]]; then
        echo "$raw_path"
        return 0
    fi

    if [[ -n "$TAILER_SESSION_DIR" && "$raw_path" == "$TAILER_SESSION_DIR"* ]]; then
        local rel="${raw_path#"$TAILER_SESSION_DIR"}"
        rel="${rel#/}"
        if [[ -z "$rel" ]]; then
            echo "."
        else
            echo "$rel"
        fi
        return 0
    fi

    if [[ -n "$TAILER_PROJECT_ROOT" && "$raw_path" == "$TAILER_PROJECT_ROOT"* ]]; then
        local rel="${raw_path#"$TAILER_PROJECT_ROOT"}"
        rel="${rel#/}"
        if [[ -z "$rel" ]]; then
            echo "."
        else
            echo "$rel"
        fi
        return 0
    fi

    echo "$raw_path"
}

tailer_format_timestamp() {
    local iso="$1"
    if [[ -z "$iso" || "$iso" == "null" ]]; then
        echo "unknown time"
        return 0
    fi
    python3 - "$iso" <<'PY'
import sys
from datetime import datetime, timezone

iso = sys.argv[1]
if not iso or iso == "null":
    print("unknown time")
    raise SystemExit

try:
    iso = iso.replace("Z", "+00:00")
    dt = datetime.fromisoformat(iso)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    local_dt = dt.astimezone()
    print(local_dt.strftime("%b %d %Y, %I:%M %p %Z"))
except Exception:
    print(sys.argv[1])
PY
}

tailer_reset_agent_state() {
    TAILER_CACHE_ACTIVITY=0
    TAILER_TOTAL_HITS=0
    TAILER_TOTAL_FETCHES=0
    TAILER_TOTAL_FORCE_REFRESH=0
    TAILER_CACHE_HIT_COUNTS=()
}

tailer_pluralize() {
    local count="$1"
    local singular="$2"
    local plural="$3"
    if [[ "$count" -eq 1 ]]; then
        echo "$singular"
    else
        echo "$plural"
    fi
}

tailer_emit_cache_summary() {
    if ! is_verbose_enabled; then
        return 0
    fi
    if [[ "$TAILER_CACHE_ACTIVITY" -eq 0 ]]; then
        return 0
    fi

    local hits="$TAILER_TOTAL_HITS"
    local fetches="$TAILER_TOTAL_FETCHES"
    local forced="$TAILER_TOTAL_FORCE_REFRESH"
    local hit_label
    hit_label=$(tailer_pluralize "$hits" "hit" "hits")
    local fetch_label
    fetch_label=$(tailer_pluralize "$fetches" "fetch" "fetches")
    local forced_label
    forced_label=$(tailer_pluralize "$forced" "forced refresh" "forced refreshes")

    echo "Cache usage: ♻️ $hits $hit_label · 🌐 $fetches $fetch_label · ⟳ $forced $forced_label" >&2
}

tailer_process_library_check() {
    local line="$1"
    local url
    url=$(echo "$line" | jq -r '.data.url // empty' 2>/dev/null || echo "")
    local event_agent
    event_agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
    if [[ -n "$TAILER_CURRENT_AGENT" && -n "$event_agent" && "$event_agent" != "$TAILER_CURRENT_AGENT" ]]; then
        return 0
    fi
    TAILER_CACHE_ACTIVITY=1
    # Removed verbose "Checking..." message - details logged to events.jsonl and hook-debug.log
    # Users only need to see results (hits/misses), not every check
}

tailer_process_library_force_refresh() {
    local line="$1"
    local url
    url=$(echo "$line" | jq -r '.data.url // empty' 2>/dev/null || echo "")
    local event_agent
    event_agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
    if [[ -n "$TAILER_CURRENT_AGENT" && -n "$event_agent" && "$event_agent" != "$TAILER_CURRENT_AGENT" ]]; then
        return 0
    fi
    TAILER_CACHE_ACTIVITY=1
    TAILER_TOTAL_FORCE_REFRESH=$((TAILER_TOTAL_FORCE_REFRESH + 1))
    if is_verbose_enabled; then
        echo "⟳ Fresh fetch requested for $url" >&2
    fi
    
    # Mark that we just displayed a library cache message
    # This will be checked by tool_use_start to avoid duplicate WebFetch message
    TAILER_LAST_LIBRARY_EVENT_TIME=$(date +%s)
    TAILER_LAST_LIBRARY_URL="$url"
}

tailer_process_library_hit() {
    local line="$1"
    local url
    url=$(echo "$line" | jq -r '.data.url // empty' 2>/dev/null || echo "")
    local event_agent
    event_agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
    if [[ -n "$TAILER_CURRENT_AGENT" && -n "$event_agent" && "$event_agent" != "$TAILER_CURRENT_AGENT" ]]; then
        return 0
    fi
    TAILER_CACHE_ACTIVITY=1
    TAILER_TOTAL_HITS=$((TAILER_TOTAL_HITS + 1))

    local current_count=0
    if [[ -n "${TAILER_CACHE_HIT_COUNTS[$url]+_}" ]]; then
        current_count="${TAILER_CACHE_HIT_COUNTS[$url]}"
    fi
    current_count=$((current_count + 1))
    TAILER_CACHE_HIT_COUNTS["$url"]=$current_count

    if ! is_verbose_enabled; then
        return 0
    fi

    # Display simplified one-line cache hit message (verbose mode only)
    # Architecture: Hooks emit events, tailer displays them (hook stderr is captured by Claude CLI)
    if [[ "$current_count" -eq 1 ]]; then
        local last_updated
        last_updated=$(echo "$line" | jq -r '.data.last_updated // empty' 2>/dev/null || echo "")
        if [[ "$last_updated" != "null" && -n "$last_updated" ]]; then
            local date_part="${last_updated:0:10}"
            echo "♻️ Cache hit: Reused digest for $url (from $date_part)" >&2
        else
            echo "♻️ Cache hit: Reused digest for $url" >&2
        fi
    fi
}

tailer_process_library_allow() {
    local line="$1"
    local url
    url=$(echo "$line" | jq -r '.data.url // empty' 2>/dev/null || echo "")
    local reason
    reason=$(echo "$line" | jq -r '.data.reason // empty' 2>/dev/null || echo "")
    local event_agent
    event_agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
    if [[ -n "$TAILER_CURRENT_AGENT" && -n "$event_agent" && "$event_agent" != "$TAILER_CURRENT_AGENT" ]]; then
        return 0
    fi
    TAILER_CACHE_ACTIVITY=1
    
    # Map technical reason to user-friendly message
    local cache_reason="was not cached"
    case "$reason" in
        allow:digest_stale) cache_reason="cache expired" ;;
        allow:digest_missing|allow:no_digest) cache_reason="was not cached" ;;
        allow:fresh_param) return 0 ;;  # Already handled by library_digest_force_refresh
        *) cache_reason="was not cached" ;;
    esac
    
    if is_verbose_enabled; then
        echo "🌐 $url ($cache_reason)" >&2
    fi
    
    # Mark that we just displayed a library cache message
    # This will be checked by tool_use_start to avoid duplicate WebFetch message
    TAILER_LAST_LIBRARY_EVENT_TIME=$(date +%s)
    TAILER_LAST_LIBRARY_URL="$url"
}

tailer_process_tool_start() {
    local line="$1"
    local session_dir="$2"

    local tool_name
    tool_name=$(echo "$line" | jq -r '.data.tool // empty' 2>/dev/null)
    [[ -z "$tool_name" ]] && return 0

    local input_summary
    input_summary=$(echo "$line" | jq -r '.data.input_summary // empty' 2>/dev/null)

    if [[ "$tool_name" == "WebFetch" ]]; then
        TAILER_TOTAL_FETCHES=$((TAILER_TOTAL_FETCHES + 1))
        TAILER_CACHE_ACTIVITY=1
        
        # Check if we just showed a library cache message (< 2 seconds ago)
        local now
        now=$(date +%s)
        local last_event_time="${TAILER_LAST_LIBRARY_EVENT_TIME:-0}"
        local time_diff=$((now - last_event_time))
        
        # If library event was recent AND URL matches, skip duplicate message
        if [[ $time_diff -lt 2 && "$input_summary" == "$TAILER_LAST_LIBRARY_URL" ]]; then
            return 0
        fi
    fi

    local lock_dir="$session_dir/.output.lock"
    local start_time
    start_time=$(date +%s)
    while ! mkdir "$lock_dir" 2>/dev/null; do
        if [[ $(($(date +%s) - start_time)) -ge 5 ]]; then
            return 0
        fi
        sleep 0.05
    done

    if is_verbose_enabled; then
        case "$tool_name" in
            WebSearch)
                echo "🔍 Searching the web for: $input_summary" >&2
                ;;
            WebFetch)
                local domain
                domain=$(echo "$input_summary" | sed -E 's|^https?://([^/]+).*|\1|')
                echo "📄 Getting information from: $domain" >&2
                ;;
            Read)
                echo "📖 Opening: $(tailer_rel_path "$input_summary")" >&2
                ;;
            Write|Edit|MultiEdit)
                if [[ "$input_summary" =~ findings-|mission-report|research-|synthesis- ]]; then
                    echo "💾 Saving: $(tailer_rel_path "$input_summary")" >&2
                fi
                ;;
            Grep)
                echo "🔎 Looking for: $input_summary" >&2
                ;;
            Glob)
                echo "📁 Finding files: $input_summary" >&2
                ;;
            TodoWrite)
                if [[ -n "$input_summary" && "$input_summary" != "tasks" ]]; then
                    if [[ ${#input_summary} -gt 100 ]]; then
                        echo "📋 Planning: ${input_summary:0:100}..." >&2
                    else
                        echo "📋 Planning: $input_summary" >&2
                    fi
                fi
                ;;
            Bash)
                ;;
            *)
                echo "🔧 Using $tool_name" >&2
                ;;
        esac
    else
        if [[ "$tool_name" != "Bash" && "$tool_name" != "TodoRead" ]]; then
            printf "." >&2
        fi
    fi

    rmdir "$lock_dir" 2>/dev/null || true
}

tailer_process_web_search_cache_hit() {
    local line="$1"
    if ! is_verbose_enabled; then
        return 0
    fi
    # Display simplified one-line cache hit message (verbose mode only)
    # Architecture: Hooks emit events, tailer displays them (hook stderr is captured by Claude CLI)
    local query
    query=$(echo "$line" | jq -r '.data.query // ""' 2>/dev/null)
    local match_ratio
    match_ratio=$(echo "$line" | jq -r '.data.match_ratio // ""' 2>/dev/null)
    local event_timestamp
    event_timestamp=$(echo "$line" | jq -r '.timestamp // ""' 2>/dev/null)
    
    # Extract date from event timestamp (format: 2025-10-23T08:28:06Z)
    local date_part="${event_timestamp:0:10}"

    if [[ -n "$match_ratio" && "$match_ratio" != "null" && "$match_ratio" != "" ]]; then
        local ratio_pct
        ratio_pct=$(printf '%.0f' "$(echo "$match_ratio * 100" | bc 2>/dev/null || echo "0")")
        echo "♻️ Cache hit: search \"$query\" (${ratio_pct}% match, from $date_part)" >&2
    else
        echo "♻️ Cache hit: search \"$query\" (from $date_part)" >&2
    fi
}
# Start tailing events for tool use display
# Usage: start_event_tailer SESSION_DIR
start_event_tailer() {
    local session_dir="$1"
    local events_file="$session_dir/events.jsonl"
    
    # Run in both verbose and non-verbose modes
    # In verbose mode: show detailed messages
    # In non-verbose mode: show progress dots
    
    # Check if tailer already started in this shell session and still running
    if [[ -n "${CCONDUCTOR_EVENT_TAILER_RUNNING:-}" ]]; then
        local existing_pid_file="${session_dir}/.event-tailer.pid"
        if [[ -f "$existing_pid_file" ]]; then
            local existing_pid
            existing_pid=$(cat "$existing_pid_file" 2>/dev/null || echo "")
            if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
                return 0
            fi
        fi
    fi
    
    # Check if tailer already running for this session (PID file check)
    local pid_file="$session_dir/.event-tailer.pid"
    if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            # Tailer already running
            export CCONDUCTOR_EVENT_TAILER_RUNNING=1
            return 0
        fi
    fi
    
    # Create events file if it doesn't exist
    touch "$events_file"
    
    # Get current line count to only show new events
    local start_line
    start_line=$(wc -l < "$events_file" 2>/dev/null || echo "0")
    
    TAILER_SESSION_DIR="$session_dir"
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        TAILER_PROJECT_ROOT="$(cd "${CLAUDE_PROJECT_DIR}" && pwd)"
    elif [[ -n "${PROJECT_ROOT:-}" ]]; then
        TAILER_PROJECT_ROOT="$(cd "${PROJECT_ROOT}" && pwd)"
    else
        TAILER_PROJECT_ROOT="$(cd "$session_dir/.." && pwd)"
    fi

    (
        sleep 0.5

        tailer_reset_agent_state
        TAILER_CURRENT_AGENT=""

        while IFS= read -r line; do
            event_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
            [[ -z "$event_type" ]] && continue

            case "$event_type" in
                agent_invocation)
                    agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
                    if [[ -n "$TAILER_CURRENT_AGENT" && "$TAILER_CURRENT_AGENT" != "$agent" ]]; then
                        tailer_emit_cache_summary
                        tailer_reset_agent_state
                    fi
                    TAILER_CURRENT_AGENT="$agent"
                    tailer_reset_agent_state
                    # Reset library event tracking on agent change
                    TAILER_LAST_LIBRARY_EVENT_TIME=0
                    TAILER_LAST_LIBRARY_URL=""
                    ;;
                agent_result)
                    agent=$(echo "$line" | jq -r '.data.agent // empty' 2>/dev/null || echo "")
                    if [[ -z "$TAILER_CURRENT_AGENT" ]] || [[ -z "$agent" ]] || [[ "$agent" == "$TAILER_CURRENT_AGENT" ]]; then
                        tailer_emit_cache_summary
                        tailer_reset_agent_state
                        TAILER_CURRENT_AGENT=""
                    fi
                    ;;
                library_digest_check)
                    tailer_process_library_check "$line"
                    ;;
                library_digest_force_refresh)
                    tailer_process_library_force_refresh "$line"
                    ;;
                library_digest_hit)
                    tailer_process_library_hit "$line"
                    ;;
                library_digest_allow)
                    tailer_process_library_allow "$line"
                    ;;
                tool_use_start)
                    tailer_process_tool_start "$line" "$session_dir"
                    ;;
                tool_use_complete)
                    continue
                    ;;
                web_search_cache_hit)
                    tailer_process_web_search_cache_hit "$line"
                    ;;
            esac
        done < <(tail -n +$((start_line + 1)) -f "$events_file" 2>/dev/null)
    ) &
    
    # Store tailer PID for cleanup
    local tailer_pid=$!
    echo "$tailer_pid" > "$session_dir/.event-tailer.pid"
    
    # Mark tailer as running in this shell session
    export CCONDUCTOR_EVENT_TAILER_RUNNING=1
}

# Stop the event tailer
# Usage: stop_event_tailer SESSION_DIR
stop_event_tailer() {
    local session_dir="$1"
    local pid_file="$session_dir/.event-tailer.pid"
    
    if [[ -f "$pid_file" ]]; then
        local tailer_pid
        tailer_pid=$(cat "$pid_file" 2>/dev/null || echo "")
        
        if [[ -n "$tailer_pid" ]] && kill -0 "$tailer_pid" 2>/dev/null; then
            kill "$tailer_pid" 2>/dev/null || true
            wait "$tailer_pid" 2>/dev/null || true
        fi
        
        rm -f "$pid_file"
    fi
    
    unset CCONDUCTOR_EVENT_TAILER_RUNNING
}

# Display tool start event
display_tool_start() {
    local event_json="$1"
    
    # Extract tool info from event
    local tool_name
    tool_name=$(echo "$event_json" | jq -r '.data.tool // empty' 2>/dev/null)
    
    local input_summary
    input_summary=$(echo "$event_json" | jq -r '.data.input_summary // empty' 2>/dev/null)
    
    # Skip if no tool name
    [[ -z "$tool_name" ]] && return 0
    
    # Use atomic mkdir for locking (portable, works on macOS)
    local lock_dir="${CCONDUCTOR_SESSION_DIR:-.}/.output.lock"
    local start_time
    start_time=$(date +%s)
    local timeout=5
    
    # Try to acquire lock
    while ! mkdir "$lock_dir" 2>/dev/null; do
        local elapsed
        elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            # Timeout - skip display to avoid hanging
            return 0
        fi
        sleep 0.05
    done
    
    # Lock acquired - display message
    case "$tool_name" in
        WebSearch)
            echo "🔍 Searching the web for: $input_summary" >&2
            ;;
        WebFetch)
            local domain
            domain=$(echo "$input_summary" | sed -E 's|^https?://([^/]+).*|\1|')
            echo "📄 Getting information from: $domain" >&2
            ;;
        Read)
            echo "📖 Opening: $input_summary" >&2
            ;;
        Write|Edit|MultiEdit)
            # Only show if it looks like a research file
            if [[ "$input_summary" =~ findings-|mission-report|research-|synthesis- ]]; then
                echo "💾 Saving: $input_summary" >&2
            fi
            ;;
        Grep)
            echo "🔎 Looking for: $input_summary" >&2
            ;;
        Bash)
            # Don't show bash in verbose mode
            ;;
        *)
            # Show generic message for unknown tools
            echo "🔧 Using $tool_name" >&2
            ;;
    esac
    
    # Release lock
    rmdir "$lock_dir" 2>/dev/null || true
}

# Display tool completion event
display_tool_complete() {
    local event_json="$1"
    
    # Extract completion info
    local tool_name
    tool_name=$(echo "$event_json" | jq -r '.data.tool // empty' 2>/dev/null)
    
    local status
    status=$(echo "$event_json" | jq -r '.data.status // empty' 2>/dev/null)
    
    local duration_ms
    duration_ms=$(echo "$event_json" | jq -r '.data.duration_ms // 0' 2>/dev/null)
    
    # Skip bash completions and empty events
    [[ -z "$tool_name" ]] && return 0
    [[ "$tool_name" == "Bash" ]] && return 0
    
    # Format duration
    local duration_display
    if [[ "$duration_ms" -gt 1000 ]]; then
        local duration_sec
        duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc 2>/dev/null || echo "?")
        duration_display="${duration_sec}s"
    else
        duration_display="${duration_ms}ms"
    fi
    
    # Use atomic mkdir for locking (portable, works on macOS)
    local lock_dir="${CCONDUCTOR_SESSION_DIR:-.}/.output.lock"
    local start_time
    start_time=$(date +%s)
    local timeout=5
    
    # Try to acquire lock
    while ! mkdir "$lock_dir" 2>/dev/null; do
        local elapsed
        elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            # Timeout - skip display to avoid hanging
            return 0
        fi
        sleep 0.05
    done
    
    # Lock acquired - display message
    if [[ "$status" == "success" ]]; then
        echo "✓ Done in $duration_display" >&2
    else
        echo "✗ Didn't work ($duration_display)" >&2
    fi
    
    # Release lock
    rmdir "$lock_dir" 2>/dev/null || true
}

# Export functions
export -f start_event_tailer
export -f stop_event_tailer
export -f display_tool_start
export -f display_tool_complete
