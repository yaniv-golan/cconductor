#!/usr/bin/env bash
# Budget Tracker - Track and enforce mission budget constraints

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

# Load shared state utilities for atomic JSON updates
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../shared-state.sh"

# Initialize budget tracker
budget_init() {
  local session_dir="$1"
  local mission_profile="$2"
  
  local budget_file="$session_dir/meta/budget.json"
  
  # Extract constraints from mission profile
  local budget_usd
  budget_usd=$(echo "$mission_profile" | jq -r '.constraints.max_cost_usd // 0')
  
  local max_invocations
  max_invocations=$(echo "$mission_profile" | jq -r '.constraints.max_agent_invocations // 9999')
  
  local max_time_minutes
  max_time_minutes=$(echo "$mission_profile" | jq -r '.constraints.max_time_minutes // 9999')
  
  local start_time
  start_time=$(get_epoch)
  
  # Initialize budget tracking
  jq -n \
    --argjson budget_usd "$budget_usd" \
    --argjson max_invocations "$max_invocations" \
    --argjson max_time_minutes "$max_time_minutes" \
    --argjson start_time "$start_time" \
    '{
      limits: {
        budget_usd: $budget_usd,
        max_agent_invocations: $max_invocations,
        max_time_minutes: $max_time_minutes
      },
      spent: {
        cost_usd: 0,
        agent_invocations: 0,
        elapsed_minutes: 0
      },
      start_time: $start_time,
      invocations: []
    }' > "$budget_file"
}

# Record agent invocation
# Uses battle-tested atomic_json_update for thread-safe updates
budget_record_invocation() {
  local session_dir="$1"
  local agent_name="$2"
  local cost_usd="${3:-0}"
  local duration_seconds="${4:-0}"
  
  local budget_file="$session_dir/meta/budget.json"
  
  if [[ ! -f "$budget_file" ]]; then
    echo "Error: Budget file not found" >&2
    return 1
  fi
  
  local timestamp
  timestamp=$(get_timestamp)
  
  # Use battle-tested atomic update with file locking
  # Single quotes intentional - this is a jq expression
  # shellcheck disable=SC2016
  atomic_json_update "$budget_file" \
    --arg agent "$agent_name" \
    --argjson cost "$cost_usd" \
    --argjson duration "$duration_seconds" \
    --arg timestamp "$timestamp" \
    '
    .spent.cost_usd += $cost |
    .spent.agent_invocations += 1 |
    .invocations += [{
      agent: $agent,
      cost_usd: $cost,
      duration_seconds: $duration,
      timestamp: $timestamp
    }]
    '
}

# Check if budget allows operation
budget_check() {
  local session_dir="$1"
  local budget_file="$session_dir/meta/budget.json"
  
  if [[ ! -f "$budget_file" ]]; then
    echo "Error: Budget file not found" >&2
    return 1
  fi
  
  local current_time
  current_time=$(get_epoch)
  
  local start_time
  start_time=$(jq -r '.start_time' "$budget_file")
  
  local elapsed_seconds=$((current_time - start_time))
  local elapsed_minutes=$((elapsed_seconds / 60))
  
  # Update elapsed time
  jq \
    --argjson elapsed "$elapsed_minutes" \
    '.spent.elapsed_minutes = $elapsed' \
    "$budget_file" > "$budget_file.tmp"
  mv "$budget_file.tmp" "$budget_file"
  
  # Check limits
  local cost_spent
  cost_spent=$(jq -r '.spent.cost_usd' "$budget_file")
  local budget_limit
  budget_limit=$(jq -r '.limits.budget_usd' "$budget_file")
  
  local invocations_spent
  invocations_spent=$(jq -r '.spent.agent_invocations' "$budget_file")
  local invocations_limit
  invocations_limit=$(jq -r '.limits.max_agent_invocations' "$budget_file")
  
  local time_limit
  time_limit=$(jq -r '.limits.max_time_minutes' "$budget_file")
  
  # Calculate elapsed time
  local start_time
  start_time=$(jq -r '.start_time' "$budget_file")
  local current_time
  current_time=$(get_epoch)
  local elapsed_seconds
  elapsed_seconds=$((current_time - start_time))
  local elapsed_minutes
  elapsed_minutes=$((elapsed_seconds / 60))
  
  # Check if any limit exceeded (using awk for float comparison, portable)
  if awk -v limit="$budget_limit" -v spent="$cost_spent" 'BEGIN { exit !(limit > 0 && spent >= limit) }'; then
    echo "Budget limit exceeded: \$$cost_spent / \$$budget_limit" >&2
    return 1
  fi
  
  if [[ $invocations_limit -ne 9999 ]] && [[ $invocations_spent -ge $invocations_limit ]]; then
    echo "Invocation limit exceeded: $invocations_spent / $invocations_limit" >&2
    return 1
  fi
  
  if [[ $time_limit -ne 9999 ]] && [[ $elapsed_minutes -ge $time_limit ]]; then
    echo "Time limit exceeded: $elapsed_minutes / $time_limit minutes" >&2
    return 1
  fi
  
  # Check for soft warnings (75%, 90%) using awk
  if awk -v limit="$budget_limit" 'BEGIN { exit !(limit > 0) }'; then
    # Calculate percentage using awk
    local budget_percent
    budget_percent=$(awk -v spent="$cost_spent" -v limit="$budget_limit" 'BEGIN { printf "%.0f", (spent / limit) * 100 }')
    
    if [[ $budget_percent -ge 90 ]]; then
      echo "Warning: 90% of budget spent" >&2
    elif [[ $budget_percent -ge 75 ]]; then
      echo "Warning: 75% of budget spent" >&2
    fi
  fi
  
  return 0
}

# Get budget report
budget_report() {
  local session_dir="$1"
  local budget_file="$session_dir/meta/budget.json"
  
  if [[ ! -f "$budget_file" ]]; then
    echo "No budget data available"
    return 0
  fi
  
  local budget_data
  budget_data=$(cat "$budget_file")
  
  echo "Budget Report:"
  echo ""
  echo "Limits:"
  echo "$budget_data" | jq -r '.limits | to_entries | .[] | "  \(.key): \(.value)"'
  echo ""
  echo "Spent:"
  echo "$budget_data" | jq -r '.spent | to_entries | .[] | "  \(.key): \(.value)"'
  echo ""
  
  local invocation_count
  invocation_count=$(echo "$budget_data" | jq '.invocations | length')
  
  if [[ $invocation_count -gt 0 ]]; then
    echo "Invocations ($invocation_count):"
    echo "$budget_data" | jq -r '.invocations[] | "  \(.timestamp) - \(.agent): $\(.cost_usd) (\(.duration_seconds)s)"'
  fi
}

# Get budget status as JSON
budget_status() {
  local session_dir="$1"
  local budget_file="$session_dir/meta/budget.json"
  
  if [[ ! -f "$budget_file" ]]; then
    echo "{}"
    return 0
  fi
  
  cat "$budget_file"
}

# Update budget limits (for session extension)
budget_extend_limits() {
  local session_dir="$1"
  local extend_iterations="${2:-0}"
  local extend_time="${3:-0}"
  
  local budget_file="$session_dir/meta/budget.json"
  
  if [[ ! -f "$budget_file" ]]; then
    echo "Error: Budget file not found" >&2
    return 1
  fi
  
  # Validate inputs are numbers
  if ! [[ "$extend_iterations" =~ ^[0-9]+$ ]]; then
    extend_iterations=0
  fi
  if ! [[ "$extend_time" =~ ^[0-9]+$ ]]; then
    extend_time=0
  fi
  
  # Update limits atomically
  # shellcheck disable=SC2016
  atomic_json_update "$budget_file" \
    --argjson extend_invocations "$extend_iterations" \
    --argjson extend_time "$extend_time" \
    '
    .limits.max_agent_invocations = (
      if .limits.max_agent_invocations == 9999 then 9999
      else .limits.max_agent_invocations + $extend_invocations
      end
    ) |
    .limits.max_time_minutes = (
      if .limits.max_time_minutes == 9999 then 9999
      else .limits.max_time_minutes + $extend_time
      end
    )
    '
}

