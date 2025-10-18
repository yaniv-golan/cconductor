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

# Start tailing events for tool use display
# Usage: start_event_tailer SESSION_DIR
start_event_tailer() {
    local session_dir="$1"
    local events_file="$session_dir/events.jsonl"
    
    # Run in both verbose and non-verbose modes
    # In verbose mode: show detailed messages
    # In non-verbose mode: show progress dots
    
    # Check if tailer already started in this shell session
    if [[ -n "${CCONDUCTOR_EVENT_TAILER_RUNNING:-}" ]]; then
        return 0
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
    
    # Start background tail process with inline display logic (no function exports)
    (
        # Wait a moment for file to be ready
        sleep 0.5
        
        # Tail new lines only
        tail -n +$((start_line + 1)) -f "$events_file" 2>/dev/null | while IFS= read -r line; do
            # Parse JSON event
            local event_type tool_name input_summary status duration_ms
            event_type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null)
            
            case "$event_type" in
                tool_use_start)
                    tool_name=$(echo "$line" | jq -r '.data.tool // empty' 2>/dev/null)
                    input_summary=$(echo "$line" | jq -r '.data.input_summary // empty' 2>/dev/null)
                    [[ -z "$tool_name" ]] && continue
                    
                    # Acquire lock and display
                    local lock_dir="$session_dir/.output.lock"
                    local start_time
                    start_time=$(date +%s)
                    while ! mkdir "$lock_dir" 2>/dev/null; do
                        [[ $(($(date +%s) - start_time)) -ge 5 ]] && continue 2
                        sleep 0.05
                    done
                    
                    # Check if verbose mode (get from parent environment)
                    if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
                        # Verbose mode: show detailed messages
                        case "$tool_name" in
                            WebSearch) echo "🔍 Searching the web for: $input_summary" >&2 ;;
                            WebFetch) echo "📄 Getting information from: $(echo "$input_summary" | sed -E 's|^https?://([^/]+).*|\1|')" >&2 ;;
                            Read) echo "📖 Opening: $input_summary" >&2 ;;
                            Write|Edit|MultiEdit)
                                [[ "$input_summary" =~ findings-|mission-report|research-|synthesis- ]] && echo "💾 Saving: $input_summary" >&2 ;;
                            Grep) echo "🔎 Looking for: $input_summary" >&2 ;;
                            Glob) echo "📁 Finding files: $input_summary" >&2 ;;
                            TodoWrite)
                                # Show todo content if available, otherwise hide
                                if [[ -n "$input_summary" && "$input_summary" != "tasks" ]]; then
                                    # Truncate if too long (show first task or two)
                                    if [[ ${#input_summary} -gt 100 ]]; then
                                        echo "📋 Planning: ${input_summary:0:100}..." >&2
                                    else
                                        echo "📋 Planning: $input_summary" >&2
                                    fi
                                fi
                                ;;
                            Bash) ;; # Hide bash (internal operation)
                            *) echo "🔧 Using $tool_name" >&2 ;;
                        esac
                    else
                        # Non-verbose mode: show progress dots (hide internal tools)
                        if [[ "$tool_name" != "Bash" && "$tool_name" != "TodoRead" ]]; then
                            printf "." >&2
                        fi
                    fi
                    rmdir "$lock_dir" 2>/dev/null || true
                    ;;
                    
                tool_use_complete)
                    # Skip completion messages - they're not very informative
                    # Only log failures if needed in the future
                    continue
                    ;;
            esac
        done
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
