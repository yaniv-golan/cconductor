#!/usr/bin/env bash
# Orchestration Logger - Log mission orchestrator decisions
# Tracks plan/reflect/act cycles and agent handoffs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core helpers first
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

# Check for jq dependency using helper
require_command "jq" "brew install jq" "apt install jq" || exit 1

# Load error logger for validation failures
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null || true

# Source shared-state for locking
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Log orchestrator decision
log_decision() {
    local session_dir="$1"
    local decision_type="$2"
    local decision_data="$3"
    
    local log_file="$session_dir/orchestration-log.jsonl"
    local timestamp
    timestamp=$(get_timestamp)
    
    # Validate decision_data is valid JSON, if not wrap it
    local validated_data
    if echo "$decision_data" | jq empty 2>/dev/null; then
        validated_data="$decision_data"
    else
        # Not valid JSON - wrap as string and always warn
        log_warn "Decision data is not valid JSON, wrapping as string"
        if command -v log_warning &>/dev/null; then
            log_warning "$session_dir" "invalid_json" "Decision data is not valid JSON, wrapping as string"
        fi
        validated_data=$(jq -cn --arg text "$decision_data" '{raw_text: $text}')
    fi
    
    local entry
    entry=$(jq -cn \
        --arg timestamp "$timestamp" \
        --arg type "$decision_type" \
        --argjson data "$validated_data" \
        '{
            timestamp: $timestamp,
            type: $type,
            decision: $data
        }')
    
    # Use with_lock for thread-safe JSONL append
    # Use printf to safely handle JSON with special characters
    # shellcheck disable=SC2016
    with_lock "$log_file" bash -c 'printf "%s\n" "$0" >> "$1"' "$entry" "$log_file"
}

# Log agent handoff
log_agent_handoff() {
    local session_dir="$1"
    local from_agent="$2"
    local to_agent="$3"
    local handoff_data="$4"
    
    local handoff_json
    handoff_json=$(jq -cn \
        --arg from "$from_agent" \
        --arg to "$to_agent" \
        --argjson data "$handoff_data" \
        '{
            from_agent: $from,
            to_agent: $to,
            handoff: $data
        }')
    
    log_decision "$session_dir" "agent_handoff" "$handoff_json"
}

# Log reflection after agent invocation
log_reflection() {
    local session_dir="$1"
    local agent="$2"
    local reflection_text="$3"
    
    local reflection_json
    reflection_json=$(jq -cn \
        --arg agent "$agent" \
        --arg reflection "$reflection_text" \
        '{
            agent: $agent,
            reflection: $reflection
        }')
    
    log_decision "$session_dir" "orchestrator_reflection" "$reflection_json"
}

# Log plan or strategy change
log_plan_change() {
    local session_dir="$1"
    local change_description="$2"
    local reason="$3"
    
    local plan_json
    plan_json=$(jq -cn \
        --arg change "$change_description" \
        --arg reason "$reason" \
        '{
            change: $change,
            reason: $reason
        }')
    
    log_decision "$session_dir" "plan_change" "$plan_json"
}

# Get orchestration log
get_orchestration_log() {
    local session_dir="$1"
    local log_file="$session_dir/orchestration-log.jsonl"
    
    if [[ ! -f "$log_file" ]] || [[ ! -s "$log_file" ]]; then
        # File doesn't exist or is empty
        echo "[]"
        return 0
    fi
    
    # Convert JSONL to JSON array
    jq -s '.' "$log_file"
}

# Get orchestration log summary
get_orchestration_summary() {
    local session_dir="$1"
    local log_file="$session_dir/orchestration-log.jsonl"
    
    if [[ ! -f "$log_file" ]]; then
        echo "No orchestration log found"
        return 0
    fi
    
    local total_decisions
    total_decisions=$(wc -l < "$log_file" | tr -d ' ')
    
    local decision_counts
    decision_counts=$(jq -s 'map(select(.type != null or .decision.type != null)) | map(select(.type != null) // {type: .decision.type}) | group_by(.type) | map({type: .[0].type, count: length}) | from_entries' "$log_file" 2>/dev/null || echo '{}')
    
    echo "Orchestration Summary:"
    echo "  Total decisions: $total_decisions"
    echo "  By type:"
    echo "$decision_counts" | jq -r 'to_entries | .[] | "    \(.key): \(.value)"'
}

# Initialize orchestration log
init_orchestration_log() {
    local session_dir="$1"
    local log_file="$session_dir/orchestration-log.jsonl"
    
    # Create empty file
    touch "$log_file"
}
