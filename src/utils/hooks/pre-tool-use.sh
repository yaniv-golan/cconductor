#!/usr/bin/env bash
# Hook: PreToolUse - Logs and displays tool usage before execution
# Called by Claude Code before each tool use
# Receives JSON data via stdin

set -euo pipefail

# Source shared utilities for get_timestamp
# Hooks run in session directory, so we need to find the project root
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../../.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || {
    # Fallback: inline get_timestamp if shared-state.sh not found
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
}

# Source verbose utility
# shellcheck disable=SC1091
if source "$PROJECT_ROOT/src/utils/verbose.sh" 2>/dev/null; then
    # Successfully loaded verbose.sh
    :
else
    # Fallback: stub functions if verbose.sh not available
    # shellcheck disable=SC2329
    is_verbose_enabled() { [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; }
    # shellcheck disable=SC2329
    verbose_tool_use() { :; }
fi

# Read hook data from stdin
hook_data=$(cat)

# Extract tool information
tool_name=$(echo "$hook_data" | jq -r '.tool_name // "unknown"')
# Get agent name from environment (set by invoke-agent.sh)
agent_name="${CCONDUCTOR_AGENT_NAME:-unknown}"

# Extract tool input (summary only, full data in events.jsonl)
tool_input_summary=""
case "$tool_name" in
    WebSearch)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.query // "no query"')
        ;;
    WebFetch)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.url // "no url"')
        ;;
    Bash)
        tool_input_summary=$(echo "$hook_data" | jq -r '.tool_input.command // "no command"' | head -c 60)
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

# Get session directory from environment or derive it
session_dir="${CCONDUCTOR_SESSION_DIR:-}"
if [ -z "$session_dir" ]; then
    # Try to find it from current directory
    if [ -f "events.jsonl" ]; then
        session_dir=$(pwd)
    else
        # Fallback: don't log to file, just stdout
        session_dir=""
    fi
fi

# Create event for logging
timestamp=$(get_timestamp)
event_data=$(jq -n \
    --arg tool "$tool_name" \
    --arg agent "$agent_name" \
    --arg summary "$tool_input_summary" \
    '{tool: $tool, agent: $agent, input_summary: $summary}')

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
                --arg type "tool_use_start" \
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

# Print to stderr for real-time visibility
# Hooks only write to events.jsonl (event tailer displays both verbose and dots)
# Claude Code captures hook stderr, so tailer is needed to show output
# (no direct output from hooks)

# Exit 0 to allow the tool to proceed
exit 0

