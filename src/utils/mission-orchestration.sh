#!/usr/bin/env bash
# Mission Orchestration - Core orchestration loop for mission-based research

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/agent-registry.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/mission-loader.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/orchestration-logger.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/budget-tracker.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/artifact-manager.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-parser.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../knowledge-graph.sh"

# Prepare orchestrator context for invocation
prepare_orchestrator_context() {
    local session_dir="$1"
    local mission_profile="$2"
    local iteration="$3"
    
    # Get agent registry as JSON
    local agents_json
    if ! agents_json=$(agent_registry_export_json); then
        echo "Error: Failed to export agent registry" >&2
        return 1
    fi
    
    # Get knowledge graph
    local kg_json
    if ! kg_json=$(kg_read "$session_dir"); then
        echo "Error: Could not read knowledge graph from $session_dir" >&2
        return 1
    fi
    
    # Get budget status
    local budget_json
    if ! budget_json=$(budget_status "$session_dir"); then
        echo "Error: Could not read budget status from $session_dir" >&2
        return 1
    fi
    
    # Get previous decisions
    local decisions_json
    if ! decisions_json=$(get_orchestration_log "$session_dir"); then
        echo "Error: Could not read orchestration log from $session_dir" >&2
        return 1
    fi
    
    # Build context JSON
    jq -n \
        --argjson mission "$mission_profile" \
        --argjson agents "$agents_json" \
        --argjson kg "$kg_json" \
        --argjson budget "$budget_json" \
        --argjson decisions "$decisions_json" \
        --argjson iteration "$iteration" \
        '{
            mission: $mission,
            agents: $agents,
            knowledge_graph: $kg,
            budget: $budget,
            previous_decisions: $decisions,
            iteration: $iteration
        }'
}

# Invoke mission orchestrator agent
invoke_mission_orchestrator() {
    local session_dir="$1"
    local context_json="$2"
    
    # Write context to temp file
    local context_file="$session_dir/orchestrator-context.json"
    echo "$context_json" > "$context_file"
    
    # Create user message with context
    local user_message
    user_message=$(cat <<EOF
I am providing you with the mission context for this orchestration iteration.

## Mission Profile
$(echo "$context_json" | jq -r '.mission | tojson')

## Available Agents
$(echo "$context_json" | jq -r '.agents | tojson')

## Current Knowledge Graph State
$(echo "$context_json" | jq -r '.knowledge_graph | tojson')

## Budget Status
$(echo "$context_json" | jq -r '.budget | tojson')

## Previous Decisions
$(echo "$context_json" | jq -r '.previous_decisions | tojson')

## Current Iteration
$(echo "$context_json" | jq -r '.iteration')

---

Based on this context, decide your next action(s). Use the decision schema to structure your outputs. Think step-by-step:

1. **Reflect** on the current state and what has been accomplished
2. **Assess** progress toward success criteria
3. **Plan** the next action(s) needed
4. **Decide** which agent to invoke, with what task and context

Respond with a JSON object following the orchestrator decision schema:

For invoke:
\`\`\`json
{
  "action": "invoke",
  "agent": "agent-name",
  "task": "Specific task description",
  "context": "Why this agent and what they should know",
  "input_artifacts": ["path/to/file"],
  "expected_outputs": ["output_type"],
  "constraints": {"max_time_minutes": 30}
}
\`\`\`

For early_exit:
\`\`\`json
{
  "action": "early_exit",
  "reason": "Why exiting early",
  "achieved_outputs": ["output_type"],
  "missing_outputs": ["output_type"],
  "partial_results_useful": true
}
\`\`\`

Log your decision and explain your reasoning.
EOF
)
    
    # Write user message to input file
    local input_file="$session_dir/orchestrator-input.txt"
    echo "$user_message" > "$input_file"
    
    # Setup orchestrator agent in session if not already there
    local orchestrator_agent_file="$session_dir/.claude/agents/mission-orchestrator.json"
    if [[ ! -f "$orchestrator_agent_file" ]]; then
        mkdir -p "$session_dir/.claude/agents"
        
        local orchestrator_dir="$PROJECT_ROOT/src/claude-runtime/agents/mission-orchestrator"
        local system_prompt
        system_prompt=$(cat "$orchestrator_dir/system-prompt.md")
        
            # Get model from metadata or use default
            local model
            model=$(jq -r '.model // "claude-sonnet-4-5"' "$orchestrator_dir/metadata.json" 2>/dev/null || echo "claude-sonnet-4-5")
            
            # Create agent definition
            jq -n \
                --arg prompt "$system_prompt" \
                --arg model "$model" \
                '{
                    "systemPrompt": $prompt,
                    "model": $model
                }' > "$orchestrator_agent_file"
    fi
    
    # Invoke agent
    local output_file="$session_dir/orchestrator-output.json"
    
    # Source invoke-agent utility
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/invoke-agent.sh"
    
        if invoke_agent_v2 "mission-orchestrator" "$input_file" "$output_file" 600 "$session_dir"; then
        # Extract result from agent output
        local result
        result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)
        
        if [[ -z "$result" ]]; then
            echo "Error: Orchestrator returned empty result" >&2
            echo "  Output file: $output_file" >&2
            if [[ -f "$output_file" ]]; then
                echo "  Output preview: $(head -c 200 "$output_file")" >&2
            fi
            # Return early exit on error
            jq -n '{
                "action": "early_exit",
                "reason": "Orchestrator returned empty result",
                "achieved_outputs": [],
                "missing_outputs": [],
                "partial_results_useful": false
            }'
            return 1
        fi
        
        # Extract JSON decision using battle-tested brace-balanced extraction
        local decision_json
        decision_json=$(extract_json_from_text "$result")
        
        # Validate extraction succeeded
        if [[ -z "$decision_json" ]]; then
            echo "Error: Could not extract valid JSON from orchestrator" >&2
            echo "Result preview: ${result:0:300}" >&2
            # Return early exit on parse error
            jq -n '{
                "action": "early_exit",
                "reason": "Orchestrator returned invalid or unparseable JSON",
                "achieved_outputs": [],
                "missing_outputs": [],
                "partial_results_useful": false
            }'
            return 1
        fi
        
        echo "$decision_json"
    else
        echo "Error: Agent invocation failed" >&2
        # Return early exit on invocation failure
        jq -n '{
            "action": "early_exit",
            "reason": "Orchestrator agent invocation failed",
            "achieved_outputs": [],
            "missing_outputs": [],
            "partial_results_useful": false
        }'
        return 1
    fi
}

# Invoke a specific agent based on orchestrator decision
_invoke_delegated_agent() {
    local session_dir="$1"
    local agent_name="$2"
    local task="$3"
    local context="$4"
    local input_artifacts="$5"  # JSON array
    
    # Validate inputs
    if [[ -z "$session_dir" || -z "$agent_name" || -z "$task" ]]; then
        echo "  ✗ Invalid arguments to _invoke_delegated_agent" >&2
        return 1
    fi
    
    if [[ ! -d "$session_dir" ]]; then
        echo "  ✗ Session directory does not exist: $session_dir" >&2
        return 1
    fi
    
    echo "  → Invoking $agent_name..."
    
    # Build agent input message
    local agent_input
    agent_input=$(cat <<EOF
$task

## Context
$context

## Input Artifacts
$input_artifacts

## Instructions
Please complete this task and provide your findings in a structured format.
Include any artifacts you create and cite all sources.
EOF
)
    
    # Write input
    local agent_input_file="$session_dir/agent-input-${agent_name}.txt"
    echo "$agent_input" > "$agent_input_file"
    
    # Setup agent in session if not already there
    local agent_file="$session_dir/.claude/agents/${agent_name}.json"
    if [[ ! -f "$agent_file" ]]; then
        # Try to find agent in registry
        agent_registry_init 2>/dev/null || true
        
        if agent_registry_exists "$agent_name"; then
            local agent_metadata
            agent_metadata=$(agent_registry_get "$agent_name")
            
            # Load system prompt
            local agent_dir
            agent_dir=$(dirname "$agent_metadata")
            local system_prompt
            system_prompt=$(cat "$agent_dir/system-prompt.md" 2>/dev/null || echo "")
            
            if [[ -n "$system_prompt" ]]; then
                # Get model from agent metadata or use default
                local agent_model
                agent_model=$(jq -r '.model // "claude-sonnet-4-5"' "$agent_metadata" 2>/dev/null || echo "claude-sonnet-4-5")
                
                # Create agent definition
                mkdir -p "$session_dir/.claude/agents"
                jq -n \
                    --arg prompt "$system_prompt" \
                    --arg model "$agent_model" \
                    '{
                        "systemPrompt": $prompt,
                        "model": $model
                    }' > "$agent_file"
            else
                echo "  ⚠ Warning: Agent $agent_name system prompt not found" >&2
                return 1
            fi
        else
            echo "  ⚠ Warning: Agent $agent_name not found in registry" >&2
            return 1
        fi
    fi
    
    # Invoke agent
    local agent_output_file="$session_dir/agent-output-${agent_name}.json"
    
    # Source invoke-agent utility
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/invoke-agent.sh"
    
    local start_time
    start_time=$(date +%s)
    
    if invoke_agent_v2 "$agent_name" "$agent_input_file" "$agent_output_file" 600 "$session_dir"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo "  ✓ $agent_name completed ($duration seconds)"
        
        # Extract result
        local result
        result=$(jq -r '.result // empty' "$agent_output_file" 2>/dev/null)
        
        # Register output as artifact
        local artifact_file=""
        if [[ -n "$result" ]]; then
            artifact_file="$session_dir/artifacts/${agent_name}-output.md"
            mkdir -p "$session_dir/artifacts"
            echo "$result" > "$artifact_file"
            
            # Register artifact (5th parameter is optional content_hash, not needed here)
            artifact_register "$session_dir" "$artifact_file" "agent_output" "$agent_name"
        fi
        
        # Record invocation in KG
        local artifact_json
        if [[ -n "$artifact_file" ]]; then
            artifact_json="[\"$artifact_file\"]"
        else
            artifact_json="[]"
        fi
        kg_add_invocation "$session_dir" "$agent_name" "$task" "$input_artifacts" \
            "$artifact_json" 0 "$duration"
        
        # Record budget
        budget_record_invocation "$session_dir" "$agent_name" 0 "$duration"
        
        return 0
    else
        echo "  ✗ $agent_name invocation failed" >&2
        return 1
    fi
}

# Process orchestrator decisions
process_orchestrator_decisions() {
    local session_dir="$1"
    local orchestrator_output="$2"
    
    # Parse decision from output
    local decision_action
    decision_action=$(echo "$orchestrator_output" | jq -r '.action')
    
    case "$decision_action" in
        invoke)
            local agent_name
            agent_name=$(echo "$orchestrator_output" | jq -r '.agent')
            local task
            task=$(echo "$orchestrator_output" | jq -r '.task')
            local context
            context=$(echo "$orchestrator_output" | jq -r '.context // "No additional context"')
            local input_artifacts
            input_artifacts=$(echo "$orchestrator_output" | jq -c '.input_artifacts // []')
            
            echo "→ Invoking agent: $agent_name"
            echo "  Task: $task"
            
            # Log the decision
            log_decision "$session_dir" "agent_invocation" "$orchestrator_output"
            
            # Actually invoke the agent - handle failures gracefully
            if _invoke_delegated_agent "$session_dir" "$agent_name" "$task" "$context" "$input_artifacts"; then
                log_decision "$session_dir" "agent_invocation_success" "$orchestrator_output"
            else
                echo "  ⚠ Agent $agent_name failed - orchestrator will adapt" >&2
                log_decision "$session_dir" "agent_invocation_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Agent failed" '. + {failure_reason: $reason}')"
                # Record failed invocation in KG with empty outputs
                kg_add_invocation "$session_dir" "$agent_name" "$task" "$input_artifacts" "[]" 0 0
            fi
            ;;
            
        reinvoke)
            local agent_name
            agent_name=$(echo "$orchestrator_output" | jq -r '.agent')
            local reason
            reason=$(echo "$orchestrator_output" | jq -r '.reason')
            local refinements
            refinements=$(echo "$orchestrator_output" | jq -r '.refinements // "Please provide more detail"')
            
            echo "→ Re-invoking agent: $agent_name"
            echo "  Reason: $reason"
            
            log_decision "$session_dir" "agent_reinvocation" "$orchestrator_output"
            
            # Re-invoke with refinements - handle failures
            if _invoke_delegated_agent "$session_dir" "$agent_name" "$refinements" "$reason" "[]"; then
                log_decision "$session_dir" "agent_reinvocation_success" "$orchestrator_output"
            else
                echo "  ⚠ Agent $agent_name re-invocation failed" >&2
                log_decision "$session_dir" "agent_reinvocation_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Re-invocation failed" '. + {failure_reason: $reason}')"
                kg_add_invocation "$session_dir" "$agent_name" "$refinements" "[]" "[]" 0 0
            fi
            ;;
            
        handoff)
            local from_agent
            from_agent=$(echo "$orchestrator_output" | jq -r '.from_agent')
            local to_agent
            to_agent=$(echo "$orchestrator_output" | jq -r '.to_agent')
            local task
            task=$(echo "$orchestrator_output" | jq -r '.task')
            local input_artifacts
            input_artifacts=$(echo "$orchestrator_output" | jq -c '.input_artifacts // []')
            local rationale
            rationale=$(echo "$orchestrator_output" | jq -r '.rationale // "Handoff requested"')
            
            echo "→ Agent handoff: $from_agent → $to_agent"
            
            # Record handoff in KG
            local handoff_id
            # Record handoff in knowledge graph (ID not currently used but may be needed later)
            # shellcheck disable=SC2034
            handoff_id=$(kg_add_handoff "$session_dir" "$from_agent" "$to_agent" "$task" "$input_artifacts" "{}")
            
            log_agent_handoff "$session_dir" "$from_agent" "$to_agent" "$orchestrator_output"
            
            # Invoke receiving agent - handle failures
            if _invoke_delegated_agent "$session_dir" "$to_agent" "$task" "$rationale" "$input_artifacts"; then
                log_decision "$session_dir" "handoff_success" "$orchestrator_output"
            else
                echo "  ⚠ Handoff failed - agent $to_agent did not complete" >&2
                log_decision "$session_dir" "handoff_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Handoff target failed" '. + {failure_reason: $reason}')"
            fi
            ;;
            
        early_exit)
            local reason
            reason=$(echo "$orchestrator_output" | jq -r '.reason')
            
            echo "→ Early exit: $reason"
            
            log_decision "$session_dir" "early_exit" "$orchestrator_output"
            return 2  # Signal early exit
            ;;
            
        *)
            echo "Warning: Unknown decision action: $decision_action" >&2
            log_decision "$session_dir" "unknown_action" "$orchestrator_output"
            ;;
    esac
    
    return 0
}

# Check if mission is complete
check_mission_complete() {
    local session_dir="$1"
    local mission_profile="$2"
    local orchestrator_output="$3"
    
    # Check if orchestrator explicitly signaled completion
    local decision_action
    decision_action=$(echo "$orchestrator_output" | jq -r '.action')
    
    if [[ "$decision_action" == "early_exit" ]]; then
        return 0  # Complete (early)
    fi
    
    # Check success criteria - verify required outputs exist in artifacts
    local required_outputs
    required_outputs=$(echo "$mission_profile" | jq -r '.success_criteria.required_outputs[]?')
    
    # If no required outputs specified, mission is complete
    if [[ -z "$required_outputs" ]]; then
        return 0
    fi
    
    # Get all artifacts
    local artifacts
    artifacts=$(artifact_list_all "$session_dir")
    
    # Check each required output
    while IFS= read -r required_output; do
        [[ -z "$required_output" ]] && continue
        
        # Check if any artifact has this output type
        local found
        found=$(echo "$artifacts" | jq -r --arg type "$required_output" '.[] | select(.type == $type) | .type' | head -1)
        
        if [[ -z "$found" ]]; then
            # Required output not found
            return 1
        fi
    done <<< "$required_outputs"
    
    # All required outputs found
    return 0
}

# Generate final mission report
generate_mission_report() {
    local session_dir="$1"
    local mission_profile="$2"
    
    local mission_name
    mission_name=$(echo "$mission_profile" | jq -r '.name')
    
    echo "→ Generating mission report..."
    
    local report_file="$session_dir/final/mission-report.md"
    mkdir -p "$session_dir/final"
    
    # Get orchestration summary
    local orchestration_summary
    orchestration_summary=$(get_orchestration_summary "$session_dir")
    
    # Get budget report
    local budget_report
    budget_report=$(budget_report "$session_dir")
    
    # Extract KG findings
    local kg_file
    kg_file=$(kg_get_path "$session_dir")
    
    local kg_findings=""
    if [[ -f "$kg_file" ]]; then
        local entity_count
        entity_count=$(jq '.entities | length' "$kg_file" 2>/dev/null || echo "0")
        local claim_count
        claim_count=$(jq '.claims | length' "$kg_file" 2>/dev/null || echo "0")
        local citation_count
        citation_count=$(jq '.citations | length' "$kg_file" 2>/dev/null || echo "0")
        
        kg_findings="### Knowledge Graph Summary

- **Entities discovered**: $entity_count
- **Claims validated**: $claim_count
- **Citations collected**: $citation_count

### Key Entities

$(jq -r '.entities[:10] | .[] | "- \(.name) (\(.type))"' "$kg_file" 2>/dev/null || echo "None")

### Key Claims

$(jq -r '.claims[:10] | .[] | "- \(.claim_text) (confidence: \(.confidence))"' "$kg_file" 2>/dev/null || echo "None")
"
    else
        kg_findings="Knowledge graph not available."
    fi
    
    # Generate report
    cat > "$report_file" <<EOF
# Mission Report: $mission_name

## Mission Objective

$(echo "$mission_profile" | jq -r '.objective')

## Execution Summary

$orchestration_summary

## Budget Summary

$budget_report

## Findings

$kg_findings

## Artifacts Produced

$(artifact_list_all "$session_dir" | jq -r '.[] | "- \(.path) (\(.type), produced by \(.produced_by))"')

---

Report generated at: 20 20 12 61 79 80 81 33 98 100 204 250 395 398 399 400 701 702get_timestamp)
EOF
    
    echo "  ✓ Report generated: $report_file"
}

# Main mission orchestration loop
run_mission_orchestration() {
    local mission_profile="$1"
    local session_dir="$2"
    
    local mission_name
    mission_name=$(echo "$mission_profile" | jq -r '.name')
    
    echo "════════════════════════════════════════════════════════════"
    echo "Mission: $mission_name"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Initialize mission state
    echo "→ Initializing mission state..."
    init_orchestration_log "$session_dir"
    artifact_init "$session_dir"
    budget_init "$session_dir" "$mission_profile"
    
    # Initialize agent registry
    echo "→ Loading agent registry..."
    agent_registry_init
    
    echo ""
    
    # Mission orchestration loop
    local iteration=1
    local max_iterations
    max_iterations=$(echo "$mission_profile" | jq -r '.constraints.max_iterations')
    
    while [[ $iteration -le $max_iterations ]]; do
        echo "═══ Mission Iteration $iteration/$max_iterations ═══"
        echo ""
        
        # Check budget before proceeding
        if ! budget_check "$session_dir" 2>/dev/null; then
            echo ""
            echo "⚠ Budget limit reached - generating partial results"
            break
        fi
        
        # Prepare orchestrator context
        echo "→ Preparing orchestrator context..."
        local context_json
        context_json=$(prepare_orchestrator_context "$session_dir" "$mission_profile" "$iteration")
        
        # Invoke mission orchestrator
        echo "→ Invoking mission orchestrator..."
        local orchestrator_output
        orchestrator_output=$(invoke_mission_orchestrator "$session_dir" "$context_json")
        
        echo ""
        
        # Process orchestrator decisions
        if ! process_orchestrator_decisions "$session_dir" "$orchestrator_output"; then
            local exit_code=$?
            if [[ $exit_code -eq 2 ]]; then
                # Early exit requested
                echo ""
                echo "✓ Mission completed early"
                break
            fi
        fi
        
        echo ""
        
        # Check mission completion
        if check_mission_complete "$session_dir" "$mission_profile" "$orchestrator_output"; then
            echo "✓ Mission complete - all success criteria met"
            break
        fi
        
        iteration=$((iteration + 1))
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Mission Completed"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Generate final report
    generate_mission_report "$session_dir" "$mission_profile"
    
    echo ""
    echo "Session saved at: $session_dir"
}

