#!/bin/bash
# Event Logger - Structured event stream for observability
set -euo pipefail

# Log an event to session's event stream
log_event() {
    local session_dir="$1"
    local event_type="$2"
    local event_data="$3"  # JSON string
    
    local events_file="$session_dir/events.jsonl"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    jq -n -c \
        --arg ts "$timestamp" \
        --arg type "$event_type" \
        --argjson data "$event_data" \
        '{timestamp: $ts, type: $type, data: $data}' \
        >> "$events_file"
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
    log_event "$session_dir" "task_started" \
        "{\"task_id\": \"$task_id\", \"agent\": \"$agent\"}"
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
    log_event "$session_dir" "agent_result" \
        "{\"agent\": \"$agent_name\", \"cost_usd\": $cost, \"duration_ms\": $duration}"
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

