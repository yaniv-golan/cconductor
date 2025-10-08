#!/usr/bin/env bash
# Event Logger - Structured event stream for observability
# Note: Don't set -euo pipefail here - this is sourced by other scripts
# that already have it set, and re-setting can cause issues

# Load debug utility if available
if declare -F debug >/dev/null 2>&1; then
    debug "event-logger.sh: Starting to load"
fi

# Global monotonic sequence counter for timestamp uniqueness
# Persisted per session to ensure uniqueness across rapid events
# Note: Don't use -g flag (Bash 4.2+ only), top-level declares are global anyway
EVENT_SEQUENCE_COUNTER=0

if declare -F debug >/dev/null 2>&1; then
    debug "event-logger.sh: EVENT_SEQUENCE_COUNTER declared"
fi

# Log an event to session's event stream
log_event() {
    local session_dir="$1"
    local event_type="$2"
    local event_data="$3"  # JSON string
    
    local events_file="$session_dir/events.jsonl"
    local lock_file="$session_dir/.events.lock"
    local timestamp
    
    # Use microseconds for precision (avoids ID collisions)
    # Try %N (nanoseconds) if supported (GNU date), otherwise use monotonic counter
    if date +%N &>/dev/null 2>&1 && [[ "$(date +%N 2>/dev/null)" =~ ^[0-9]+$ ]]; then
        # GNU date (Linux) - has nanosecond precision
        local nanos
        nanos=$(date +%N)
        # Remove leading zeros to avoid octal interpretation
        nanos=${nanos#"${nanos%%[!0]*}"}
        local micros=$(( ${nanos:-0} / 1000 ))
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S").${micros}Z
    else
        # BSD date (macOS) - use monotonic counter for guaranteed uniqueness
        # Increment counter for each event to prevent collisions
        EVENT_SEQUENCE_COUNTER=$((EVENT_SEQUENCE_COUNTER + 1))
        local sequence
        sequence=$(printf "%06d" "$EVENT_SEQUENCE_COUNTER")
        timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S").${sequence}Z
    fi
    
    # Use atomic mkdir for locking (portable, works on all platforms)
    # Wait up to 5 seconds for lock
    local start_time
    start_time=$(date +%s)
    local timeout=5
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write event
            jq -n -c \
                --arg ts "$timestamp" \
                --arg type "$event_type" \
                --argjson data "$event_data" \
                '{timestamp: $ts, type: $type, data: $data}' \
                >> "$events_file"
            
            # Release lock
            rmdir "$lock_file" 2>/dev/null || true
            return 0
        fi
        
        # Check timeout
        local elapsed
        elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Warning: Failed to acquire lock for event logging after ${timeout}s" >&2
            return 1
        fi
        
        sleep 0.05
    done
}

# Convenience wrappers for common events
log_iteration_start() {
    local session_dir="$1"
    local iteration="$2"
    log_event "$session_dir" "iteration_start" "{\"iteration\": $iteration}"
}

log_iteration_complete() {
    local session_dir="$1"
    local iteration="$2"
    local stats_json="$3"  # Pre-formed JSON object
    log_event "$session_dir" "iteration_complete" \
        "{\"iteration\": $iteration, \"stats\": $stats_json}"
}

log_task_started() {
    local session_dir="$1"
    local task_id="$2"
    local agent="$3"
    local query="${4:-}"
    
    # Escape and encode query for JSON
    local query_json
    query_json=$(jq -n --arg q "$query" '$q')
    
    log_event "$session_dir" "task_started" \
        "{\"task_id\": \"$task_id\", \"agent\": \"$agent\", \"query\": $query_json}"
}

log_task_completed() {
    local session_dir="$1"
    local task_id="$2"
    local agent="$3"
    local duration="$4"
    local cost="${5:-0}"
    log_event "$session_dir" "task_completed" \
        "{\"task_id\": \"$task_id\", \"agent\": \"$agent\", \"duration\": $duration, \"cost_usd\": $cost}"
}

log_task_failed() {
    local session_dir="$1"
    local task_id="$2"
    local agent="$3"
    local error="${4:-Unknown error}"
    local recoverable="${5:-false}"
    
    # Escape error message for JSON
    local error_json
    error_json=$(jq -n --arg e "$error" '$e')
    
    log_event "$session_dir" "task_failed" \
        "{\"task_id\": \"$task_id\", \"agent\": \"$agent\", \"error\": $error_json, \"recoverable\": $recoverable}"
}

log_entity_added() {
    local session_dir="$1"
    local entity_id="$2"
    local entity_name="$3"
    log_event "$session_dir" "entity_added" \
        "{\"entity_id\": \"$entity_id\", \"name\": \"$entity_name\"}"
}

log_claim_added() {
    local session_dir="$1"
    local claim_id="$2"
    local confidence="$3"
    log_event "$session_dir" "claim_added" \
        "{\"claim_id\": \"$claim_id\", \"confidence\": $confidence}"
}

log_gap_detected() {
    local session_dir="$1"
    local gap_id="$2"
    local priority="$3"
    log_event "$session_dir" "gap_detected" \
        "{\"gap_id\": \"$gap_id\", \"priority\": \"$priority\"}"
}

log_gap_resolved() {
    local session_dir="$1"
    local gap_id="$2"
    log_event "$session_dir" "gap_resolved" "{\"gap_id\": \"$gap_id\"}"
}

log_agent_invocation() {
    local session_dir="$1"
    local agent_name="$2"
    local allowed_tools="$3"
    local session_id="${4:-}"
    log_event "$session_dir" "agent_invocation" \
        "{\"agent\": \"$agent_name\", \"tools\": \"$allowed_tools\", \"session_id\": \"$session_id\"}"
}

log_agent_result() {
    local session_dir="$1"
    local agent_name="$2"
    local cost="${3:-0}"
    local duration="${4:-0}"
    local metadata="${5}"  # Optional JSON metadata object
    # Set default if empty
    if [ -z "$metadata" ]; then
        metadata="{}"
    fi
    
    # Merge base data with optional metadata
    local base_data
    base_data=$(jq -n \
        --arg agent "$agent_name" \
        --argjson cost "$cost" \
        --argjson duration "$duration" \
        '{agent: $agent, cost_usd: $cost, duration_ms: $duration}')
    
    # Merge with metadata if provided
    local final_data
    if [ "$metadata" = "{}" ] || [ -z "$metadata" ]; then
        final_data="$base_data"
    else
        # Validate metadata is valid JSON before merging
        if echo "$metadata" | jq empty 2>/dev/null; then
            final_data=$(echo "$base_data" | jq --argjson meta "$metadata" '. + $meta' 2>/dev/null)
            # If merge failed, fall back to base data
            if [ -z "$final_data" ]; then
                final_data="$base_data"
            fi
        else
            # Invalid JSON, use base data without metadata
            final_data="$base_data"
        fi
    fi
    
    log_event "$session_dir" "agent_result" "$final_data"
}

# Initialize events file for new session
init_events() {
    local session_dir="$1"
    touch "$session_dir/events.jsonl"
}

# Get recent events
get_recent_events() {
    local session_dir="$1"
    local count="${2:-10}"
    
    if [ ! -f "$session_dir/events.jsonl" ]; then
        echo "[]"
        return
    fi
    
    tail -n "$count" "$session_dir/events.jsonl" | jq -s '.'
}

# Export functions for use in subprocesses
export -f log_event
export -f log_iteration_start
export -f log_iteration_complete
export -f log_task_started
export -f log_task_completed
export -f log_task_failed
export -f log_agent_invocation
export -f log_agent_result
export -f init_events
export -f get_recent_events
