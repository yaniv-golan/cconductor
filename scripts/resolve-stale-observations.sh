#!/usr/bin/env bash
# Manually resolve stale observations in existing sessions
# This is a one-time fix for sessions that have false-alarm observations

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source required utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/event-logger.sh"

resolve_observations_for_session() {
    local session_dir="$1"
    
    if [ ! -d "$session_dir" ]; then
        echo "Session directory not found: $session_dir"
        return 1
    fi
    
    local session_name
    session_name=$(basename "$session_dir")
    
    echo "Processing $session_name..."
    
    # Get all system observations
    local observations
    observations=$(grep '"type":"system_observation"' "$session_dir/events.jsonl" 2>/dev/null | jq -s '.' || echo '[]')
    
    if [ "$observations" = "[]" ]; then
        echo "  No observations found"
        return 0
    fi
    
    local resolved_count=0
    local temp_count_file="/tmp/resolved_count_$$"
    echo "0" > "$temp_count_file"
    
    # Check each observation
    while read -r event; do
        local obs
        obs=$(echo "$event" | jq '.data')
        
        local component
        component=$(echo "$obs" | jq -r '.component // "unknown"')
        local observation_text
        observation_text=$(echo "$obs" | jq -r '.observation // ""')
        
        local is_resolved=false
        local resolution_msg=""
        
        # Validate based on component type
        case "$component" in
            knowledge_graph)
                # Check if "empty" observation is now resolved
                if echo "$observation_text" | grep -qi "empty"; then
                    local kg_file="$session_dir/knowledge-graph.json"
                    if [ -f "$kg_file" ]; then
                        local entities
                        entities=$(jq '.stats.total_entities // 0' "$kg_file")
                        local claims
                        claims=$(jq '.stats.total_claims // 0' "$kg_file")
                        
                        if [ "$entities" -gt 0 ] || [ "$claims" -gt 0 ]; then
                            is_resolved=true
                            resolution_msg="Knowledge graph populated with $entities entities and $claims claims"
                        fi
                    fi
                fi
                ;;
            
            task_queue)
                # Check if task queue issues resolved
                if echo "$observation_text" | grep -qi "stuck\|not updating"; then
                    local tq_file="$session_dir/task-queue.json"
                    if [ -f "$tq_file" ]; then
                        local completed
                        completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "$tq_file")
                        
                        if [ "$completed" -gt 0 ]; then
                            is_resolved=true
                            resolution_msg="Task queue functioning: $completed completed tasks"
                        fi
                    fi
                fi
                ;;
        esac
        
        # Log resolution if issue is resolved
        if [ "$is_resolved" = true ]; then
            # Check if already resolved
            local already_resolved=0
            if grep -q '"type":"observation_resolved"' "$session_dir/events.jsonl" 2>/dev/null; then
                already_resolved=$(grep '"type":"observation_resolved"' "$session_dir/events.jsonl" | \
                    jq -s --arg comp "$component" --arg obs "$observation_text" \
                    'map(select(.data.original_observation.component == $comp and .data.original_observation.observation == $obs)) | length')
            fi
            
            if [ "$already_resolved" -eq 0 ]; then
                local resolution_data
                resolution_data=$(jq -n \
                    --argjson obs "$obs" \
                    --arg resolution "$resolution_msg" \
                    --arg resolved_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                    '{
                        original_observation: $obs,
                        resolution: $resolution,
                        resolved_at: $resolved_at
                    }')
                
                log_event "$session_dir" "observation_resolved" "$resolution_data" || true
                
                echo "  ✓ Resolved [$component]: $resolution_msg"
                
                # Increment count in temp file
                local current_count
                current_count=$(cat "$temp_count_file")
                echo "$((current_count + 1))" > "$temp_count_file"
            fi
        fi
    done < <(echo "$observations" | jq -c '.[]')
    
    # Read final count
    resolved_count=$(cat "$temp_count_file")
    rm -f "$temp_count_file"
    
    if [ "$resolved_count" -gt 0 ]; then
        echo "  → $resolved_count observation(s) resolved"
        
        # Regenerate dashboard metrics
        if [ -f "$PROJECT_ROOT/src/utils/dashboard-metrics.sh" ]; then
            # shellcheck disable=SC1091
            source "$PROJECT_ROOT/src/utils/dashboard-metrics.sh"
            generate_dashboard_metrics "$session_dir"
            echo "  → Dashboard metrics regenerated"
        fi
    else
        echo "  No observations to resolve"
    fi
}

# Main execution
if [ $# -eq 0 ]; then
    echo "Usage: $0 <session_dir> [session_dir2 ...]"
    echo "   or: $0 --all  (process all sessions)"
    exit 1
fi

if [ "$1" = "--all" ]; then
    echo "Processing all sessions..."
    echo ""
    
    for session_dir in "$PROJECT_ROOT"/research-sessions/session_*; do
        if [ -d "$session_dir" ]; then
            resolve_observations_for_session "$session_dir"
            echo ""
        fi
    done
else
    # Process specific sessions
    for session_arg in "$@"; do
        resolve_observations_for_session "$session_arg"
        echo ""
    done
fi

echo "✓ Done"
