#!/bin/bash
# Adaptive Research Orchestrator
# Main control loop for adaptive research system

set -euo pipefail

# Save script directory before sourcing other files (which redefine SCRIPT_DIR)
DELVE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$DELVE_SCRIPT_DIR")"

# Use DELVE_SCRIPT_DIR for sourcing to avoid conflicts
# (sourced files may redefine SCRIPT_DIR for their own use)
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/knowledge-graph.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/task-queue.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/shared-state.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/utils/gap-analyzer.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/utils/contradiction-detector.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/utils/lead-evaluator.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/utils/confidence-scorer.sh"
# shellcheck disable=SC1091
source "$DELVE_SCRIPT_DIR/utils/config-loader.sh"

# Load configuration using overlay pattern
# This automatically merges user config (config/adaptive-config.json)
# over defaults (config/adaptive-config.default.json)
if ! ADAPTIVE_CONFIG=$(load_config "adaptive-config"); then
    echo "❌ Error: Failed to load adaptive configuration" >&2
    echo "" >&2
    echo "To create a custom configuration:" >&2
    echo "  $DELVE_SCRIPT_DIR/utils/config-loader.sh init adaptive-config" >&2
    echo "  vim $PROJECT_ROOT/config/adaptive-config.json" >&2
    echo "" >&2
    exit 1
fi

# Validate required fields exist and have correct types
# Using literal jq paths (not variables) because jq doesn't interpret dots in variables as path separators
# Note: Don't use 'jq -e' because it exits 1 for false/null values (by design)
validate_field_exists() {
    local field_desc="$1"
    local jq_expr="$2"
    
    local value
    value=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr" 2>/dev/null)
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "❌ Error: Required config field missing or null: $field_desc" >&2
        return 1
    fi
    return 0
}

validate_field_type() {
    local field_desc="$1"
    local jq_expr="$2"
    local expected_type="$3"
    
    local actual_type
    actual_type=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr | type" 2>/dev/null)
    if [ "$actual_type" != "$expected_type" ]; then
        local value
        value=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr" 2>/dev/null)
        echo "❌ Error: Config field $field_desc has wrong type" >&2
        echo "   Expected: $expected_type, got: $actual_type (value: $value)" >&2
        return 1
    fi
    return 0
}

# Validate each required field with literal jq expressions
validate_field_exists "termination.max_iterations" ".termination.max_iterations" || exit 1
validate_field_type "termination.max_iterations" ".termination.max_iterations" "number" || exit 1

validate_field_exists "termination.confidence_threshold" ".termination.confidence_threshold" || exit 1
validate_field_type "termination.confidence_threshold" ".termination.confidence_threshold" "number" || exit 1

validate_field_exists "termination.max_tasks" ".termination.max_tasks" || exit 1
validate_field_type "termination.max_tasks" ".termination.max_tasks" "number" || exit 1

validate_field_exists "termination.interactive_mode" ".termination.interactive_mode" || exit 1
validate_field_type "termination.interactive_mode" ".termination.interactive_mode" "boolean" || exit 1

validate_field_exists "task_generation.exploration_mode" ".task_generation.exploration_mode" || exit 1
validate_field_type "task_generation.exploration_mode" ".task_generation.exploration_mode" "string" || exit 1

validate_field_exists "task_generation.min_gap_priority" ".task_generation.min_gap_priority" || exit 1
validate_field_type "task_generation.min_gap_priority" ".task_generation.min_gap_priority" "number" || exit 1

validate_field_exists "task_generation.min_lead_priority" ".task_generation.min_lead_priority" || exit 1
validate_field_type "task_generation.min_lead_priority" ".task_generation.min_lead_priority" "number" || exit 1

# Extract config values
MAX_ITERATIONS=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.max_iterations')
CONFIDENCE_THRESHOLD=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.confidence_threshold')
INTERACTIVE_MODE=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.interactive_mode')
EXPLORATION_MODE=$(echo "$ADAPTIVE_CONFIG" | jq -r '.task_generation.exploration_mode')

# Validate value ranges
if [ "$MAX_ITERATIONS" -lt 1 ] || [ "$MAX_ITERATIONS" -gt 100 ]; then
    echo "❌ Error: max_iterations must be between 1 and 100 (got: $MAX_ITERATIONS)" >&2
    exit 1
fi

if awk -v thresh="$CONFIDENCE_THRESHOLD" 'BEGIN { exit !(thresh < 0 || thresh > 1) }'; then
    echo "❌ Error: confidence_threshold must be between 0 and 1 (got: $CONFIDENCE_THRESHOLD)" >&2
    exit 1
fi

if [[ ! "$EXPLORATION_MODE" =~ ^(conservative|balanced|aggressive)$ ]]; then
    echo "❌ Error: exploration_mode must be one of: conservative, balanced, aggressive (got: $EXPLORATION_MODE)" >&2
    exit 1
fi

# Print banner
print_banner() {
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        ADAPTIVE RESEARCH ENGINE - Sonnet 4.5               ║"
    echo "║  Intelligent, self-improving research with dynamic goals   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Initialize session
initialize_session() {
    local research_question="$1"

    # Create session directory
    local timestamp
    timestamp=$(date +%s)
    local session_dir="$PROJECT_ROOT/research-sessions/session_${timestamp}"
    mkdir -p "$session_dir"
    mkdir -p "$session_dir/raw"
    mkdir -p "$session_dir/intermediate"
    mkdir -p "$session_dir/knowledge"

    # Source version checker
    # shellcheck disable=SC1091
    source "$DELVE_SCRIPT_DIR/utils/version-check.sh"

    # Get system version
    local system_version
    system_version=$(get_engine_version)

    # Capture config snapshot
    local exploration_mode
    exploration_mode=$(echo "$ADAPTIVE_CONFIG" | jq -r '.task_generation.exploration_mode // "balanced"')
    local security_profile
    security_profile=$(get_config_value "security-config" ".security_profile" "\"strict\"" | tr -d '"')

    # Create session metadata with version tracking
    jq -n \
        --arg version "$system_version" \
        --arg session "session_${timestamp}" \
        --arg question "$research_question" \
        --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg mode "$exploration_mode" \
        --arg profile "$security_profile" \
        '{
            session_id: $session,
            engine_version: $version,
            created_at: $date,
            last_opened: $date,
            research_question: $question,
            schemas: {
                knowledge_graph: "1.0",
                task_queue: "1.0",
                citations: "1.0"
            },
            status: "active",
            config_snapshot: {
                exploration_mode: $mode,
                security_profile: $profile
            }
        }' > "$session_dir/session.json"

    echo "$session_dir"
}

# Initial planning phase
initial_planning() {
    local session_dir="$1"
    local research_question="$2"

    echo "=== Phase 0: Initial Planning ==="
    echo "Research Question: $research_question"
    echo ""

    # Create planning input
    local planning_input="$session_dir/raw/planning-input.json"
    jq -n \
        --arg question "$research_question" \
        --arg mode "$EXPLORATION_MODE" \
        '{research_question: $question, exploration_mode: $mode}' \
        > "$planning_input"

    # Invoke research planner
    echo "⚡ Invoking research-planner agent..."
    local planning_output="$session_dir/raw/planning-output.json"

    # NOTE: In actual implementation, this would use Claude Code's Task tool
    # For now, provide manual invocation instructions
    cat <<EOF

Claude Code: Please invoke the research-planner agent:
  Agent: research-planner
  Input: $planning_input
  Output: $planning_output

The planner will:
1. Understand the question
2. Decompose into initial research tasks
3. Create task list with priorities

EOF

    # Wait for planning completion
    read -r -p "Press Enter when planning is complete..."

    if [ ! -f "$planning_output" ]; then
        echo "Error: Planning output not found" >&2
        return 1
    fi

    # Extract initial tasks
    local initial_tasks
    initial_tasks=$(cat "$planning_output" | jq '.tasks')
    echo "$initial_tasks"
}

# Execute pending tasks (parallel)
execute_pending_tasks() {
    local session_dir="$1"

    local pending
    pending=$(tq_get_pending "$session_dir")
    local pending_count
    pending_count=$(echo "$pending" | jq 'length')

    if [ "$pending_count" -eq 0 ]; then
        echo "No pending tasks"
        return 0
    fi

    echo "Executing $pending_count pending tasks..."

    # Get tasks by agent type
    local agents
    agents=$(echo "$pending" | jq -r '.[].agent' | sort -u)

    # Execute each agent's tasks
    while IFS= read -r agent; do
        local agent_tasks
        agent_tasks=$(echo "$pending" | jq -c --arg agent "$agent" '[.[] | select(.agent == $agent)]')
        local task_count
        task_count=$(echo "$agent_tasks" | jq 'length')

        if [ "$task_count" -eq 0 ]; then
            continue
        fi

        echo "  → $agent: $task_count tasks"

        # Mark tasks as in progress
        echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
            tq_start_task "$session_dir" "$task_id"
        done

        # Create agent input
        local agent_input="$session_dir/raw/${agent}-input.json"
        echo "$agent_tasks" > "$agent_input"

        # Invoke agent
        cat <<EOF

Claude Code: Please invoke the $agent agent:
  Agent: $agent
  Input: $agent_input

For each task in the input, research and output findings in adaptive format.

EOF

        read -r -p "Press Enter when $agent is complete..."

        # Mark tasks as completed
        echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
            local findings_file="$session_dir/raw/${agent}-${task_id}-findings.json"
            if [ -f "$findings_file" ]; then
                tq_complete_task "$session_dir" "$task_id" "$findings_file"
            else
                echo "Warning: Findings file not found for $task_id" >&2
            fi
        done

    done <<< "$agents"
}

# Run coordinator analysis
run_coordinator() {
    local session_dir="$1"
    local iteration="$2"

    echo ""
    echo "=== Iteration $iteration: Coordinator Analysis ==="

    # Increment knowledge graph iteration
    kg_increment_iteration "$session_dir"

    # Prepare coordinator input
    local kg
    kg=$(kg_read "$session_dir")
    local queue
    queue=$(tq_read "$session_dir")
    local completed_tasks
    completed_tasks=$(tq_get_completed "$session_dir")

    # Get new findings since last coordinator run
    local new_findings='[]'
    while IFS= read -r task; do
        local findings_file
        findings_file=$(echo "$task" | jq -r '.findings_file // ""')
        if [ -n "$findings_file" ] && [ -f "$findings_file" ]; then
            local finding
            finding=$(cat "$findings_file")
            new_findings=$(echo "$new_findings" | jq --argjson f "$finding" '. += [$f]')
        fi
    done <<< "$(echo "$completed_tasks" | jq -c '.[]')"

    local coordinator_input="$session_dir/intermediate/coordinator-input-${iteration}.json"
    jq -n \
        --argjson kg "$kg" \
        --argjson queue "$queue" \
        --argjson findings "$new_findings" \
        --arg iteration "$iteration" \
        --argjson config "$ADAPTIVE_CONFIG" \
        '{
            knowledge_graph: $kg,
            task_queue: $queue,
            new_findings: $findings,
            iteration: ($iteration | tonumber),
            config: $config
        }' \
        > "$coordinator_input"

    # Invoke coordinator
    echo "⚡ Invoking research-coordinator agent..."
    local coordinator_output="$session_dir/intermediate/coordinator-output-${iteration}.json"

    cat <<EOF

Claude Code: Please invoke the research-coordinator agent:
  Agent: research-coordinator
  Input: $coordinator_input
  Output: $coordinator_output

The coordinator will:
1. Integrate new findings into knowledge graph
2. Detect gaps, contradictions, promising leads
3. Generate new research tasks
4. Update confidence scores
5. Decide if research is complete

EOF

    read -r -p "Press Enter when coordinator is complete..."

    if [ ! -f "$coordinator_output" ]; then
        echo "Error: Coordinator output not found" >&2
        return 1
    fi

    cat "$coordinator_output"
}

# Update knowledge graph from coordinator output
update_knowledge_graph() {
    local session_dir="$1"
    local coordinator_output_file="$2"

    echo "Updating knowledge graph..."

    # Bulk update
    kg_bulk_update "$session_dir" "$coordinator_output_file"

    # Update confidence
    local confidence
    confidence=$(cat "$coordinator_output_file" | jq '.knowledge_graph_updates.confidence_scores // null')
    if [ "$confidence" != "null" ]; then
        kg_update_confidence "$session_dir" "$confidence"
    fi

    # Update coverage
    local coverage
    coverage=$(cat "$coordinator_output_file" | jq '.knowledge_graph_updates.coverage // null')
    if [ "$coverage" != "null" ]; then
        kg_update_coverage "$session_dir" "$coverage"
    fi
}

# Add new tasks from coordinator
add_coordinator_tasks() {
    local session_dir="$1"
    local coordinator_output_file="$2"

    local new_tasks
    new_tasks=$(cat "$coordinator_output_file" | jq '.new_tasks // []')
    local task_count
    task_count=$(echo "$new_tasks" | jq 'length')

    if [ "$task_count" -gt 0 ]; then
        echo "Adding $task_count new tasks to queue..."
        tq_add_tasks "$session_dir" "$new_tasks" >/dev/null
    else
        echo "No new tasks generated"
    fi
}

# Check termination
should_terminate() {
    local coordinator_output_file="$1"

    local should_stop
    should_stop=$(cat "$coordinator_output_file" | jq -r '.termination_recommendation')
    [ "$should_stop" = "true" ]
}

# Interactive prompt
interactive_prompt() {
    local session_dir="$1"
    local iteration="$2"
    local coordinator_output="$3"

    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    local confidence
    confidence=$(echo "$kg_summary" | jq -r '.confidence')
    local entities
    entities=$(echo "$kg_summary" | jq -r '.entities')
    local claims
    claims=$(echo "$kg_summary" | jq -r '.claims')
    local gaps
    gaps=$(echo "$kg_summary" | jq -r '.unresolved_gaps')
    local contradictions
    contradictions=$(echo "$kg_summary" | jq -r '.unresolved_contradictions')
    local pending
    pending=$(tq_get_stats "$session_dir" | jq -r '.pending')

    local recommendations
    recommendations=$(echo "$coordinator_output" | jq -r '.recommendations | join("\n  - ")')

    cat <<EOF

╔════════════════════════════════════════════════════════════╗
║  Iteration $iteration Complete                                      ║
╚════════════════════════════════════════════════════════════╝

Summary:
  - Confidence: ${confidence}
  - Entities: $entities
  - Claims: $claims
  - Unresolved Gaps: $gaps
  - Contradictions: $contradictions
  - Pending Tasks: $pending

Recommendations:
  - $recommendations

Options:
  [c] Continue
  [s] Stop and synthesize now
  [d] Show detailed knowledge graph
  [r] Show recommendations
  [q] Quit

EOF

    read -r -p "Your choice: " choice

    case "$choice" in
        c|C|"")
            return 0  # Continue
            ;;
        s|S)
            return 1  # Stop
            ;;
        d|D)
            kg_read "$session_dir" | jq '.'
            interactive_prompt "$session_dir" "$iteration" "$coordinator_output"
            ;;
        r|R)
            echo "$coordinator_output" | jq -r '.recommendations | join("\n")'
            interactive_prompt "$session_dir" "$iteration" "$coordinator_output"
            ;;
        q|Q)
            exit 0
            ;;
        *)
            echo "Invalid option"
            interactive_prompt "$session_dir" "$iteration" "$coordinator_output"
            ;;
    esac
}

# Final synthesis
final_synthesis() {
    local session_dir="$1"

    echo ""
    echo "=== Final Synthesis ==="

    local kg
    kg=$(kg_read "$session_dir")
    local synthesis_input="$session_dir/intermediate/synthesis-input.json"
    echo "$kg" > "$synthesis_input"

    cat <<EOF

Claude Code: Please invoke the synthesis-agent:
  Agent: synthesis-agent
  Input: $synthesis_input
  Output: $session_dir/research-report.json

Generate comprehensive final report from knowledge graph.

EOF

    read -r -p "Press Enter when synthesis is complete..."

    echo "Research complete! Output at: $session_dir/research-report.md"
}

# Run a single research iteration
# Returns: 0 to continue, 1 to stop
run_single_iteration() {
    local session_dir="$1"
    local iteration="$2"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  ITERATION $iteration / $MAX_ITERATIONS"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # Show pending tasks count
    local pending
    pending=$(jq '.stats.pending' "$session_dir/task-queue.json" 2>/dev/null || echo "0")
    echo "📋 Tasks: $pending pending"
    echo ""

    # Execute pending tasks
    echo "→ Executing tasks..."
    execute_pending_tasks "$session_dir"
    echo "  ✓ Tasks complete"
    echo ""

    # Run coordinator analysis
    echo "→ Running coordinator analysis..."
    local coordinator_output
    coordinator_output=$(run_coordinator "$session_dir" "$iteration")
    local coordinator_file="$session_dir/intermediate/coordinator-output-${iteration}.json"
    echo "  ✓ Coordinator analysis complete"
    echo ""

    # Update knowledge graph with coordinator findings
    echo "→ Updating knowledge graph..."
    update_knowledge_graph "$session_dir" "$coordinator_file"

    # Show knowledge graph statistics
    local kg_file="$session_dir/knowledge-graph.json"
    if [ -f "$kg_file" ]; then
        local claims
        claims=$(jq '.stats.total_claims' "$kg_file" 2>/dev/null || echo "0")
        local entities
        entities=$(jq '.stats.total_entities' "$kg_file" 2>/dev/null || echo "0")
        local citations
        citations=$(jq '.stats.total_citations' "$kg_file" 2>/dev/null || echo "0")
        local confidence
        confidence=$(jq '.confidence_scores.overall' "$kg_file" 2>/dev/null || echo "0")
        local gaps
        gaps=$(jq '.stats.unresolved_gaps' "$kg_file" 2>/dev/null || echo "0")

        echo "  ✓ Knowledge graph updated"
        echo ""
        echo "  Knowledge Graph:"
        echo "    • Claims: $claims"
        echo "    • Entities: $entities"
        echo "    • Citations: $citations"
        echo "    • Confidence: $confidence"
        echo "    • Unresolved gaps: $gaps"
        echo ""
    fi

    # Generate new tasks based on coordinator analysis
    echo "→ Generating new tasks..."
    add_coordinator_tasks "$session_dir" "$coordinator_file"
    local new_pending
    new_pending=$(jq '.stats.pending' "$session_dir/task-queue.json" 2>/dev/null || echo "0")
    echo "  ✓ Generated tasks (now $new_pending pending)"
    echo ""

    # Check termination conditions
    if should_terminate "$coordinator_file"; then
        local reason
        reason=$(cat "$coordinator_file" | jq -r '.termination_reason')
        echo ""
        echo "✓ Research Complete: $reason"
        return 1  # Signal termination
    fi

    # Check if no pending tasks remain
    if ! tq_has_pending "$session_dir"; then
        echo ""
        echo "✓ No pending tasks remaining"
        echo "✓ Research appears complete"
        return 1  # Signal termination
    fi

    # Interactive prompt if enabled
    if [ "$INTERACTIVE_MODE" = "true" ]; then
        if ! interactive_prompt "$session_dir" "$iteration" "$coordinator_output"; then
            echo "User requested stop"
            return 1  # Signal termination
        fi
    fi

    # Show progress estimate
    if [ "$iteration" -lt "$MAX_ITERATIONS" ]; then
        echo "Next: Iteration $((iteration + 1))/$MAX_ITERATIONS"
    fi

    return 0  # Continue iterations
}

# Resume existing session
resume_session() {
    local session_id="$1"
    
    # Try to find session directory
    local session_dir=""
    
    # Check if it's a full path
    if [ -d "$session_id" ]; then
        session_dir="$session_id"
    # Check if it's just the session name
    elif [ -d "$PROJECT_ROOT/research-sessions/$session_id" ]; then
        session_dir="$PROJECT_ROOT/research-sessions/$session_id"
    else
        echo "❌ Error: Session not found: $session_id" >&2
        echo "" >&2
        echo "Available sessions:" >&2
        # shellcheck disable=SC2012
        ls -1t "$PROJECT_ROOT/research-sessions/" 2>/dev/null | head -10 >&2
        echo "" >&2
        echo "Usage: ./delve resume <session_id>" >&2
        return 1
    fi
    
    # Validate session structure
    if [ ! -f "$session_dir/session.json" ]; then
        echo "❌ Error: Invalid session (missing session.json): $session_dir" >&2
        return 1
    fi
    
    if [ ! -f "$session_dir/knowledge-graph.json" ]; then
        echo "❌ Error: Invalid session (missing knowledge-graph.json): $session_dir" >&2
        return 1
    fi
    
    if [ ! -f "$session_dir/task-queue.json" ]; then
        echo "❌ Error: Invalid session (missing task-queue.json): $session_dir" >&2
        return 1
    fi
    
    # Verify session compatibility
    # shellcheck disable=SC1091
    source "$DELVE_SCRIPT_DIR/utils/version-check.sh"
    if ! validate_session_compatibility "$session_dir" 2>/dev/null; then
        echo "" >&2
        echo "⚠️  Warning: Session may be incompatible with current engine version" >&2
        echo "   You can try to continue, but results may be unexpected." >&2
        echo "" >&2
        read -r -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Update last_opened timestamp
    local tmp_file="$session_dir/session.json.tmp"
    jq --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.last_opened = $date | .status = "resumed"' \
       "$session_dir/session.json" > "$tmp_file"
    mv "$tmp_file" "$session_dir/session.json"
    
    # Update .latest marker
    basename "$session_dir" > "$PROJECT_ROOT/research-sessions/.latest"
    
    echo "$session_dir"
}

# List available sessions
list_sessions() {
    local sessions_dir="$PROJECT_ROOT/research-sessions"
    
    if [ ! -d "$sessions_dir" ]; then
        echo "No sessions found (directory doesn't exist)" >&2
        return 1
    fi
    
    # Find all session directories with valid session.json
    local found_sessions=0
    
    echo "Available research sessions:"
    echo ""
    printf "%-25s %-50s %-20s\n" "SESSION ID" "QUESTION" "STATUS"
    printf "%-25s %-50s %-20s\n" "----------" "--------" "------"
    
    # shellcheck disable=SC2045
    for session_path in $(ls -1dt "$sessions_dir"/session_* 2>/dev/null); do
        if [ -f "$session_path/session.json" ]; then
            local session_id
            session_id=$(basename "$session_path")
            local question
            question=$(jq -r '.research_question // "N/A"' "$session_path/session.json" 2>/dev/null)
            local status
            status=$(jq -r '.status // "unknown"' "$session_path/session.json" 2>/dev/null)
            
            # Truncate question if too long
            if [ ${#question} -gt 47 ]; then
                question="${question:0:44}..."
            fi
            
            printf "%-25s %-50s %-20s\n" "$session_id" "$question" "$status"
            ((found_sessions++))
            
            # Limit output
            if [ $found_sessions -ge 10 ]; then
                break
            fi
        fi
    done
    
    if [ $found_sessions -eq 0 ]; then
        echo "No sessions found"
        return 1
    fi
    
    echo ""
    echo "To resume: ./delve resume <session_id>"
}

# Main adaptive research loop
main() {
    local research_question="$1"

    print_banner

    echo "════════════════════════════════════════════════════════════"
    echo "Starting Research"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Question: $research_question"
    echo ""

    # Initialize session
    echo "→ Initializing research session..."
    local session_dir
    session_dir=$(initialize_session "$research_question")
    echo "  ✓ Session created: $(basename "$session_dir")"
    echo ""

    # Verify session compatibility (for existing sessions, if resume added later)
    # For new sessions, this validates the metadata was created correctly
    # shellcheck disable=SC1091
    source "$DELVE_SCRIPT_DIR/utils/version-check.sh"
    if ! validate_session_compatibility "$session_dir" 2>/dev/null; then
        echo "⚠️  Warning: Session version mismatch (this shouldn't happen for new sessions)"
        echo "   Continuing anyway..."
    fi

    # Initialize knowledge graph and task queue
    echo "→ Setting up knowledge graph and task queue..."
    kg_init "$session_dir" "$research_question" >/dev/null
    tq_init "$session_dir" >/dev/null
    echo "  ✓ Data structures initialized"
    echo ""

    # Initial planning
    echo "→ Creating initial research plan..."
    local initial_tasks
    initial_tasks=$(initial_planning "$session_dir" "$research_question")
    tq_add_tasks "$session_dir" "$initial_tasks" >/dev/null
    local task_count
    task_count=$(echo "$initial_tasks" | jq 'length' 2>/dev/null || echo "0")
    echo "  ✓ Generated $task_count initial tasks"
    echo ""

    # Update .latest marker
    basename "$session_dir" > "$PROJECT_ROOT/research-sessions/.latest"

    echo "════════════════════════════════════════════════════════════"
    echo "Max Iterations: $MAX_ITERATIONS"
    echo "Interactive Mode: $INTERACTIVE_MODE"
    echo "════════════════════════════════════════════════════════════"

    # Main adaptive loop
    local iteration=0
    while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
        ((iteration++))

        # Run single iteration (returns 1 to stop, 0 to continue)
        if ! run_single_iteration "$session_dir" "$iteration"; then
            break
        fi
    done

    # Final synthesis
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Generating Final Report"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    final_synthesis "$session_dir"

    # Finalize research (copy report, update metadata)
    finalize_research "$session_dir" "$research_question"

    # Print summary
    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Research Complete                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Final Statistics:"
    echo "$kg_summary" | jq '.'
    echo ""
    echo "Session: $session_dir"
}

# Resume adaptive research loop
main_resume() {
    local session_id="$1"
    
    print_banner
    
    echo "════════════════════════════════════════════════════════════"
    echo "Resuming Research Session"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Load existing session
    echo "→ Loading session..."
    local session_dir
    if ! session_dir=$(resume_session "$session_id"); then
        exit 1
    fi
    echo "  ✓ Session loaded: $(basename "$session_dir")"
    echo ""
    
    # Load session metadata
    local research_question
    research_question=$(jq -r '.research_question' "$session_dir/session.json")
    local created_at
    created_at=$(jq -r '.created_at' "$session_dir/session.json")
    
    echo "Question: $research_question"
    echo "Originally created: $created_at"
    echo ""
    
    # Show current state
    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    local current_iteration
    current_iteration=$(echo "$kg_summary" | jq -r '.iteration')
    local confidence
    confidence=$(echo "$kg_summary" | jq -r '.confidence')
    local pending_tasks
    pending_tasks=$(jq '.stats.pending' "$session_dir/task-queue.json")
    local completed_tasks
    completed_tasks=$(jq '.stats.completed' "$session_dir/task-queue.json")
    
    echo "Current State:"
    echo "  • Iteration: $current_iteration"
    echo "  • Confidence: $confidence"
    echo "  • Tasks: $completed_tasks completed, $pending_tasks pending"
    echo "  • Entities: $(echo "$kg_summary" | jq -r '.entities')"
    echo "  • Claims: $(echo "$kg_summary" | jq -r '.claims')"
    echo "  • Unresolved gaps: $(echo "$kg_summary" | jq -r '.unresolved_gaps')"
    echo ""
    
    # Check if there are pending tasks
    if [ "$pending_tasks" -eq 0 ]; then
        echo "⚠️  No pending tasks found in session."
        echo ""
        read -r -p "Generate new tasks and continue? [Y/n] " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo ""
            echo "→ Running coordinator to generate new tasks..."
            local next_iteration
            next_iteration=$((current_iteration + 1))
            run_coordinator "$session_dir" "$next_iteration" >/dev/null 2>&1 || true
            local coordinator_file="$session_dir/intermediate/coordinator-output-${next_iteration}.json"
            if [ -f "$coordinator_file" ]; then
                add_coordinator_tasks "$session_dir" "$coordinator_file"
            fi
            pending_tasks=$(jq '.stats.pending' "$session_dir/task-queue.json")
            echo "  ✓ Generated new tasks (now $pending_tasks pending)"
            echo ""
        else
            echo ""
            echo "No new tasks generated. Proceeding to final synthesis..."
            final_synthesis "$session_dir"
            finalize_research "$session_dir" "$research_question"
            return 0
        fi
    fi
    
    echo "════════════════════════════════════════════════════════════"
    echo "Max Iterations: $MAX_ITERATIONS"
    echo "Interactive Mode: $INTERACTIVE_MODE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Continue iteration loop from last iteration
    local iteration=$current_iteration
    while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
        ((iteration++))
        
        # Run single iteration (returns 1 to stop, 0 to continue)
        if ! run_single_iteration "$session_dir" "$iteration"; then
            break
        fi
    done
    
    # Final synthesis
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Generating Final Report"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    final_synthesis "$session_dir"
    
    # Finalize research (copy report, update metadata)
    finalize_research "$session_dir" "$research_question"
    
    # Print summary
    kg_summary=$(kg_get_summary "$session_dir")
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Research Resumed and Complete                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Final Statistics:"
    echo "$kg_summary" | jq '.'
    echo ""
    echo "Session: $session_dir"
}

# Finalize research session
finalize_research() {
    local session_dir="$1"
    local question="$2"

    local report="$session_dir/research-report.md"

    if [ ! -f "$report" ]; then
        echo "⚠️  Warning: No research report found"

        # Update metadata to reflect completion (even without report)
        if [ -f "$session_dir/session.json" ]; then
            local tmp_file="$session_dir/session.json.tmp"
            jq --arg status "completed_no_report" \
               --arg completed "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
               '.status = $status | .completed_at = $completed' \
               "$session_dir/session.json" > "$tmp_file"
            mv "$tmp_file" "$session_dir/session.json"
        fi

        return 1
    fi

    # Create reports directory
    mkdir -p "$PROJECT_ROOT/reports"

    # Generate filename
    local date
    date=$(date +%Y-%m-%d)
    local slug
    slug=$(echo "$question" | \
        tr '[:upper:]' '[:lower:]' | \
        tr -cs '[:alnum:]' '-' | \
        sed 's/^-*//' | sed 's/-*$//' | \
        cut -c1-40)

    local report_copy="$PROJECT_ROOT/reports/${slug}-${date}.md"

    # Copy report
    cp "$report" "$report_copy"

    # Update metadata to completed
    if [ -f "$session_dir/session.json" ]; then
        local tmp_file="$session_dir/session.json.tmp"
        jq --arg status "completed" \
           --arg completed "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           --arg report "$report_copy" \
           '.status = $status | .completed_at = $completed | .report_path = $report' \
           "$session_dir/session.json" > "$tmp_file"
        mv "$tmp_file" "$session_dir/session.json"
    fi

    # Print completion message
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "✅ Research Complete!"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "📄 Report saved to:"
    echo "   • $report"
    echo "   • $report_copy"
    echo ""
    echo "View with:"
    echo "   cat $report_copy"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   open $report_copy"
    elif command -v xdg-open &> /dev/null; then
        echo "   xdg-open $report_copy"
    fi
    echo ""
    echo "Resume this session:"
    echo "   ./research resume $(basename "$session_dir")"
    echo ""
}

# CLI
if [ $# -lt 1 ]; then
    echo "Usage:"
    echo "  $0 \"<research question>\"           # Start new research"
    echo "  $0 --resume <session_id>            # Resume existing session"
    echo "  $0 --list                           # List available sessions"
    echo ""
    echo "Examples:"
    echo "  $0 \"How does PostgreSQL implement MVCC?\""
    echo "  $0 --resume session_1234567890"
    echo "  $0 --list"
    exit 1
fi

# Parse command-line arguments
case "${1:-}" in
    --resume)
        if [ $# -lt 2 ]; then
            echo "Error: --resume requires a session ID" >&2
            echo "" >&2
            echo "Usage: $0 --resume <session_id>" >&2
            echo "" >&2
            list_sessions
            exit 1
        fi
        main_resume "$2"
        ;;
    --list)
        list_sessions
        ;;
    *)
        # Regular research question
        main "$1"
        ;;
esac
