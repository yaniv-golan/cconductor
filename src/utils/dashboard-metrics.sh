#!/usr/bin/env bash
# Dashboard Metrics - Pre-computed metrics for dashboard
set -euo pipefail

# Get script directory for sourcing shared-state
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../shared-state.sh"

# Generate dashboard metrics
generate_dashboard_metrics() {
    local session_dir="$1"
    local metrics_file="$session_dir/dashboard-metrics.json"
    
    # Read current state from files with locking to prevent partial reads
    local kg
    if [ -f "$session_dir/knowledge-graph.json" ]; then
        kg=$(atomic_read "$session_dir/knowledge-graph.json" 2>/dev/null || echo '{}')
    else
        kg='{}'
    fi
    
    local tq
    if [ -f "$session_dir/task-queue.json" ]; then
        tq=$(atomic_read "$session_dir/task-queue.json" 2>/dev/null || echo '{}')
    else
        tq='{}'
    fi
    
    local session
    if [ -f "$session_dir/session.json" ]; then
        session=$(atomic_read "$session_dir/session.json" 2>/dev/null || echo '{}')
    else
        session='{}'
    fi
    
    # Extract stats
    local iteration
    iteration=$(echo "$kg" | jq '.iteration // 0')
    local confidence
    confidence=$(echo "$kg" | jq '.confidence_scores.overall // 0')
    
    local total_tasks
    total_tasks=$(echo "$tq" | jq '.stats.total_tasks // 0')
    local completed
    completed=$(echo "$tq" | jq '.stats.completed // 0')
    local in_progress
    in_progress=$(echo "$tq" | jq '.stats.in_progress // 0')
    local pending
    pending=$(echo "$tq" | jq '.stats.pending // 0')
    local failed
    failed=$(echo "$tq" | jq '.stats.failed // 0')
    
    local entities
    entities=$(echo "$kg" | jq '.stats.total_entities // 0')
    local claims
    claims=$(echo "$kg" | jq '.stats.total_claims // 0')
    local citations
    citations=$(echo "$kg" | jq '.stats.total_citations // 0')
    local gaps
    gaps=$(echo "$kg" | jq '.stats.unresolved_gaps // 0')
    local contradictions
    contradictions=$(echo "$kg" | jq '.stats.unresolved_contradictions // 0')
    
    # Calculate costs from events
    local total_cost
    total_cost=$(calculate_total_cost "$session_dir")
    
    # Calculate duration
    local created_at
    created_at=$(echo "$session" | jq -r '.created_at // ""')
    local elapsed_seconds
    elapsed_seconds=$(calculate_elapsed_seconds "$created_at")
    
    # Extract session info
    local session_status
    session_status=$(echo "$session" | jq -r '.status // "unknown"')
    local completed_at
    completed_at=$(echo "$session" | jq -r '.completed_at // ""')
    local research_question
    research_question=$(echo "$session" | jq -r '.research_question // ""')
    
    # Get active agents (from task queue)
    local active_agents
    active_agents=$(echo "$tq" | jq -c '[.tasks[]? | select(.status == "in_progress") | .agent] | unique')
    
    # Get system observations (last 20, most recent first)
    local observations
    observations=$(cat "$session_dir/events.jsonl" 2>/dev/null | \
        jq -s 'map(select(.type == "system_observation")) | .[-20:] | reverse' 2>/dev/null || echo '[]')
    
    # Build metrics JSON
    # Use atomic write pattern: write to temp file, then atomic rename
    # This prevents corruption during concurrent access or interruptions
    local temp_metrics_file="${metrics_file}.tmp.$$"
    
    jq -n \
        --arg updated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson iter "$iteration" \
        --argjson confidence "$confidence" \
        --argjson total "$total_tasks" \
        --argjson completed "$completed" \
        --argjson in_progress "$in_progress" \
        --argjson pending "$pending" \
        --argjson failed "$failed" \
        --argjson entities "$entities" \
        --argjson claims "$claims" \
        --argjson citations "$citations" \
        --argjson gaps "$gaps" \
        --argjson contradictions "$contradictions" \
        --argjson total_cost "$total_cost" \
        --argjson elapsed "$elapsed_seconds" \
        --argjson agents "$active_agents" \
        --argjson observations "$observations" \
        --arg session_status "$session_status" \
        --arg session_created "$created_at" \
        --arg session_completed "$completed_at" \
        --arg research_question "$research_question" \
        '{
            last_updated: $updated,
            iteration: $iter,
            confidence: $confidence,
            session: {
                status: $session_status,
                created_at: $session_created,
                completed_at: $session_completed,
                research_question: $research_question
            },
            tasks: {
                total: $total,
                completed: $completed,
                in_progress: $in_progress,
                pending: $pending,
                failed: $failed
            },
            knowledge: {
                entities: $entities,
                claims: $claims,
                citations: $citations
            },
            issues: {
                gaps: $gaps,
                contradictions: $contradictions
            },
            costs: {
                total_usd: $total_cost,
                per_iteration: ($total_cost / ($iter + 0.001))
            },
            runtime: {
                elapsed_seconds: $elapsed,
                active_agents: $agents
            },
            system_health: {
                observations: $observations
            }
        }' > "$temp_metrics_file"
    
    # Atomic rename (POSIX guarantees atomicity)
    mv "$temp_metrics_file" "$metrics_file"
}

# Calculate total cost from events
calculate_total_cost() {
    local session_dir="$1"
    local events_file="$session_dir/events.jsonl"
    
    if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
        echo "0"
        return
    fi
    
    # Sum cost_usd from all agent_result events
    # Events have structure: {type: "agent_result", data: {cost_usd: X}}
    local cost
    cost=$(cat "$events_file" 2>/dev/null | \
        jq -s 'map(select(.type == "agent_result") | .data.cost_usd // 0) | add // 0' 2>/dev/null)
    
    if [ -z "$cost" ] || [ "$cost" = "null" ]; then
        echo "0"
    else
        echo "$cost"
    fi
}

# Calculate elapsed seconds
calculate_elapsed_seconds() {
    local start_time="$1"
    
    if [ -z "$start_time" ]; then
        echo "0"
        return
    fi
    
    # Platform-agnostic approach to parse ISO 8601 UTC timestamp
    local start_epoch
    local now_epoch
    
    # Detect OS type
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS (BSD date) - use -j flag to not set system time
        start_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null || echo "0")
        now_epoch=$(date -ju +%s)
    else
        # Linux (GNU date) - use -d flag for date parsing
        start_epoch=$(date -u -d "$start_time" +%s 2>/dev/null || echo "0")
        now_epoch=$(date -u +%s)
    fi
    
    echo $((now_epoch - start_epoch))
}

# Update metrics (call after state changes)
update_metrics() {
    local session_dir="$1"
    generate_dashboard_metrics "$session_dir" 2>/dev/null || true
}

