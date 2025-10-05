#!/bin/bash
# Hook: PostToolUse - Logs and displays tool completion
# Called by Claude Code after each tool completes
# Receives JSON data via stdin

set -euo pipefail

# Read hook data from stdin
hook_data=$(cat)

# Extract tool information
tool_name=$(echo "$hook_data" | jq -r '.tool_name // "unknown"')
exit_code=$(echo "$hook_data" | jq -r '.exit_code // 0')
duration_ms=$(echo "$hook_data" | jq -r '.duration_ms // 0')

# Determine success/failure
if [ "$exit_code" = "0" ]; then
    status="✓"
    status_text="success"
else
    status="✗"
    status_text="failed"
fi

# Format duration
if [ "$duration_ms" -gt 1000 ]; then
    duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc 2>/dev/null || echo "?")
    duration_display="${duration_sec}s"
else
    duration_display="${duration_ms}ms"
fi

# Get session directory from environment or derive it
session_dir="${CCONDUCTOR_SESSION_DIR:-}"
if [ -z "$session_dir" ]; then
    if [ -f "events.jsonl" ]; then
        session_dir=$(pwd)
    else
        session_dir=""
    fi
fi

# Create event for logging
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
event_data=$(jq -n \
    --arg tool "$tool_name" \
    --arg status "$status_text" \
    --arg duration "$duration_ms" \
    --arg exit_code "$exit_code" \
    '{tool: $tool, status: $status, duration_ms: ($duration | tonumber), exit_code: ($exit_code | tonumber)}')

# Log to events.jsonl if session directory is available
if [ -n "$session_dir" ] && [ -d "$session_dir" ]; then
    # Use atomic mkdir for locking (portable, works on all platforms)
    lock_file="$session_dir/.events.lock"
    start_time=$(date +%s)
    timeout=5
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write event
            echo "$hook_data" | jq -c \
                --arg ts "$timestamp" \
                --arg type "tool_use_complete" \
                --argjson data "$event_data" \
                '{timestamp: $ts, type: $type, data: $data}' \
                >> "$session_dir/events.jsonl" 2>/dev/null
            
            # Release lock
            rmdir "$lock_file" 2>/dev/null || true
            break
        fi
        
        # Check timeout - but don't fail hook if lock times out
        elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            break
        fi
        
        sleep 0.05
    done
fi

# Print to stdout for real-time visibility
echo "    $status $tool_name ($duration_display)" >&2

# Exit 0 to continue
exit 0

