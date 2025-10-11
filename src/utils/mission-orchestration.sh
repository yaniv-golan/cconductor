#!/usr/bin/env bash
# Mission Orchestration - Core orchestration loop for mission-based research

set -euo pipefail

# Use CCONDUCTOR_MISSION_SCRIPT_DIR if available (when sourced), otherwise detect
if [ -z "${CCONDUCTOR_MISSION_SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    SCRIPT_DIR="$CCONDUCTOR_MISSION_SCRIPT_DIR"
fi
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"

# Load dependencies from utils directory
# Note: SCRIPT_DIR may be set to src/ by parent (cconductor-mission.sh sets CCONDUCTOR_MISSION_SCRIPT_DIR)
# But mission-orchestration.sh is actually in src/utils/, so we need to detect where WE are
UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$UTILS_DIR/agent-registry.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/mission-loader.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/orchestration-logger.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/budget-tracker.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/artifact-manager.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/kg-artifact-processor.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/json-parser.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/verbose.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$UTILS_DIR/error-logger.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/debug.sh"

# Prepare orchestrator context for invocation
prepare_orchestrator_context() {
    local session_dir="$1"
    local mission_profile="$2"
    local iteration="$3"
    
    # Get agent registry as JSON
    local agents_json
    if ! agents_json=$(agent_registry_export_json); then
        echo "✗ Error: Failed to export agent registry" >&2
        return 1
    fi
    
    # Get knowledge graph
    local kg_json
    if ! kg_json=$(kg_read "$session_dir"); then
        echo "✗ Error: Could not read knowledge graph from $session_dir" >&2
        return 1
    fi
    
    # Get budget status
    local budget_json
    if ! budget_json=$(budget_status "$session_dir"); then
        echo "✗ Error: Could not read budget status from $session_dir" >&2
        return 1
    fi
    
    # Get previous decisions
    local decisions_json
    if ! decisions_json=$(get_orchestration_log "$session_dir"); then
        echo "✗ Error: Could not read orchestration log from $session_dir" >&2
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
        
        # Calculate orchestrator directory relative to this script
        # This script is in src/utils/, orchestrator is in src/claude-runtime/agents/mission-orchestrator
        local orchestrator_dir
        orchestrator_dir="$(cd "$UTILS_DIR/../claude-runtime/agents/mission-orchestrator" && pwd)"
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
    source "$UTILS_DIR/invoke-agent.sh"
    
        if invoke_agent_v2 "mission-orchestrator" "$input_file" "$output_file" 600 "$session_dir"; then
        # Extract result from agent output
        local result
        result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)
        
        if [[ -z "$result" ]]; then
            echo "✗ Error: Orchestrator returned empty result" >&2
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
            echo "✗ Error: Could not extract valid JSON from orchestrator" >&2
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
        return 0
    else
        echo "✗ Error: Agent invocation failed" >&2
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
    
    # Note: verbose_agent_start is called by invoke_agent_v2, no need to call here
    
    # Build agent input message
    # Process input_artifacts JSON array into readable format
    local artifacts_section
    if [[ "$input_artifacts" == "[]" || -z "$input_artifacts" ]]; then
        artifacts_section="None"
    else
        # Parse JSON array and format as list
        artifacts_section=$(echo "$input_artifacts" | jq -r '.[]' 2>/dev/null | while IFS= read -r artifact_path; do
            if [[ -f "$session_dir/$artifact_path" ]]; then
                echo "- $artifact_path (available - use Read tool to access)"
            else
                echo "- $artifact_path (ERROR: file not found)"
            fi
        done)
        
        # If parsing failed, show the raw value
        if [[ -z "$artifacts_section" ]]; then
            artifacts_section="$input_artifacts (format error - expected JSON array)"
        fi
    fi
    
    # Add output specification for synthesis-agent
    local output_spec_section=""
    if [[ "$agent_name" == "synthesis-agent" ]]; then
        local output_spec
        output_spec=$(jq -r '.output_specification // ""' "$session_dir/session.json" 2>/dev/null)
        if [[ -n "$output_spec" && "$output_spec" != "null" ]]; then
            output_spec_section=$(cat <<SPEC_EOF

## User's Output Format Requirements
$output_spec
SPEC_EOF
)
        fi
    fi
    
    local agent_input
    agent_input=$(cat <<EOF
$task

## Context
$context

## Input Artifacts
$artifacts_section${output_spec_section}

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
        # Check if agent exists in registry (already initialized by main script)
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
                echo "  ⚠️  Warning: Agent $agent_name system prompt not found" >&2
                return 1
            fi
        else
            echo "  ⚠️  Warning: Agent $agent_name not found in registry" >&2
            return 1
        fi
    fi
    
    # Invoke agent
    local agent_output_file="$session_dir/agent-output-${agent_name}.json"
    
    # Source invoke-agent utility
    # shellcheck disable=SC1091
    source "$UTILS_DIR/invoke-agent.sh"
    
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
            
            # Register artifact (capture ID but don't display it)
            local artifact_id
            # shellcheck disable=SC2034
            artifact_id=$(artifact_register "$session_dir" "$artifact_file" "agent_output" "$agent_name")
        fi
        
        # Record budget (invocation tracking is done via orchestration log)
        budget_record_invocation "$session_dir" "$agent_name" 0 "$duration"
        
        return 0
    else
        echo "  ✗ $agent_name invocation failed" >&2
        return 1
    fi
}

# Process knowledge graph artifacts for agent
# Processes artifacts if agent created a .kg.lock file
process_agent_kg_artifacts() {
    local session_dir="$1"
    local agent="$2"
    
    # Check if agent created a KG lock file
    local lock_file="$session_dir/${agent}.kg.lock"
    if [ ! -f "$lock_file" ]; then
        # No artifacts to process
        return 0
    fi
    
    verbose "Processing knowledge graph artifacts from $agent..."
    
    # Process artifacts using kg-artifact-processor
    if process_kg_artifacts "$session_dir" "$agent"; then
        verbose "  ✓ Successfully processed $agent artifacts"
        return 0
    else
        echo "  ⚠️  Warning: Failed to process $agent artifacts" >&2
        echo "  See ${agent}.retry-instructions.json for details" >&2
        return 1
    fi
}

# Validate synthesis agent outputs
# Ensures mission-report.md is created
validate_synthesis_outputs() {
    local session_dir="$1"
    local agent="$2"
    
    # Only validate for synthesis-agent
    if [ "$agent" != "synthesis-agent" ]; then
        return 0
    fi
    
    local mission_report="$session_dir/mission-report.md"
    
    # Check mission report exists
    if [ ! -f "$mission_report" ]; then
        echo "  ⚠️  Warning: synthesis-agent did not create mission-report.md" >&2
        return 1
    fi
    
    echo "  ✓ Synthesis outputs validated" >&2
    return 0
}

# Extract JSON decision from orchestrator output (may include text + JSON)
extract_orchestrator_decision() {
    local orchestrator_output="$1"
    
    # Use the battle-tested json-parser utilities
    local extracted_json
    if extracted_json=$(extract_json_from_text "$orchestrator_output" 2>/dev/null); then
        # Check if it has an action field
        local action
        action=$(echo "$extracted_json" | jq -r '.action // empty' 2>/dev/null)
        if [ -n "$action" ] && [ "$action" != "null" ]; then
            echo "$extracted_json"
            return 0
        fi
    fi
    
    # Could not extract valid decision JSON with action field
    return 1
}

# Helper: Get agent display name
get_agent_display_name() {
    local agent_name="$1"
    local session_dir="${2:-}"
    local friendly_name=""
    
    if [[ -n "$session_dir" ]]; then
        local metadata_file="$session_dir/.claude/agents/${agent_name}/metadata.json"
        if [[ -f "$metadata_file" ]]; then
            friendly_name=$(jq -r '.display_name // empty' "$metadata_file" 2>/dev/null)
        fi
    fi
    
    if [[ -z "$friendly_name" ]]; then
        # Fallback: convert hyphens to spaces
        friendly_name="${agent_name//-/ }"
    fi
    
    echo "$friendly_name"
}

# Process orchestrator decisions
process_orchestrator_decisions() {
    local session_dir="$1"
    local orchestrator_output="$2"
    
    # Extract decision JSON from output (may include prose)
    local decision_json
    if ! decision_json=$(extract_orchestrator_decision "$orchestrator_output"); then
        echo "⚠️  Warning: Orchestrator did not return valid decision JSON" >&2
        echo "   Output preview: $(echo "$orchestrator_output" | head -c 200)..." >&2
        log_decision "$session_dir" "invalid_output" "$(echo "$orchestrator_output" | head -c 500)"
        return 1
    fi
    
    # Parse decision from extracted JSON
    local decision_action
    decision_action=$(echo "$decision_json" | jq -r '.action')
    
    # Verbose: Show what the orchestrator decided
    if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
        case "$decision_action" in
            invoke)
                local agent_for_msg
                agent_for_msg=$(echo "$decision_json" | jq -r '.agent')
                echo "   → Delegating to $(get_agent_display_name "$agent_for_msg" "$session_dir")" >&2
                ;;
            reinvoke)
                echo "   → Re-invoking previous agent" >&2
                ;;
            synthesize)
                echo "   → Starting synthesis" >&2
                ;;
            handoff)
                echo "   → Handing off between agents" >&2
                ;;
        esac
    fi
    
    case "$decision_action" in
        invoke)
            local agent_name
            agent_name=$(echo "$decision_json" | jq -r '.agent')
            local task
            task=$(echo "$decision_json" | jq -r '.task')
            local context
            context=$(echo "$decision_json" | jq -r '.context // "No additional context"')
            local input_artifacts
            input_artifacts=$(echo "$decision_json" | jq -c '.input_artifacts // []')
            
            # Log the decision with proper format for journal export
            local rationale
            rationale=$(echo "$decision_json" | jq -r '.rationale // ""')
            local alternatives
            alternatives=$(echo "$decision_json" | jq -c '.alternatives_considered // []')
            local expected_impact
            expected_impact=$(echo "$decision_json" | jq -r '.expected_impact // ""')
            
            local decision_log_entry
            decision_log_entry=$(jq -n \
                --arg agent "$agent_name" \
                --arg task "$task" \
                --arg context "$context" \
                --arg rationale "$rationale" \
                --argjson alternatives "$alternatives" \
                --arg expected_impact "$expected_impact" \
                '{
                    decision: {
                        type: "agent_selection",
                        agent: $agent,
                        task: $task,
                        context: $context,
                        rationale: $rationale,
                        alternatives_considered: $alternatives,
                        expected_impact: $expected_impact
                    }
                }')
            log_decision "$session_dir" "agent_invocation" "$decision_log_entry"
            
            # Actually invoke the agent - handle failures gracefully
            if _invoke_delegated_agent "$session_dir" "$agent_name" "$task" "$context" "$input_artifacts"; then
                # Process KG artifacts if agent produced any
                process_agent_kg_artifacts "$session_dir" "$agent_name"
                
                # Validate synthesis outputs if applicable
                if validate_synthesis_outputs "$session_dir" "$agent_name"; then
                    log_decision "$session_dir" "agent_invocation_success" "$orchestrator_output"
                else
                    echo "  ⚠ Agent $agent_name succeeded but outputs incomplete" >&2
                    log_decision "$session_dir" "agent_invocation_failure" \
                        "$(echo "$orchestrator_output" | jq --arg reason "Outputs incomplete" '. + {failure_reason: $reason}')"
                fi
            else
                echo "  ⚠ Agent $agent_name failed - orchestrator will adapt" >&2
                log_decision "$session_dir" "agent_invocation_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Agent failed" '. + {failure_reason: $reason}')"
            fi
            ;;
            
        reinvoke)
            local agent_name
            agent_name=$(echo "$decision_json" | jq -r '.agent')
            local reason
            reason=$(echo "$decision_json" | jq -r '.reason')
            local refinements
            refinements=$(echo "$decision_json" | jq -r '.refinements // "Please provide more detail"')
            
            log_decision "$session_dir" "agent_reinvocation" "$orchestrator_output"
            
            # Re-invoke with refinements - handle failures
            if _invoke_delegated_agent "$session_dir" "$agent_name" "$refinements" "$reason" "[]"; then
                # Process KG artifacts if agent produced any
                process_agent_kg_artifacts "$session_dir" "$agent_name"
                
                log_decision "$session_dir" "agent_reinvocation_success" "$orchestrator_output"
            else
                echo "  ⚠ Agent $agent_name re-invocation failed" >&2
                log_decision "$session_dir" "agent_reinvocation_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Re-invocation failed" '. + {failure_reason: $reason}')"
            fi
            ;;
            
        handoff)
            local from_agent
            from_agent=$(echo "$decision_json" | jq -r '.from_agent')
            local to_agent
            to_agent=$(echo "$decision_json" | jq -r '.to_agent')
            local task
            task=$(echo "$decision_json" | jq -r '.task')
            local input_artifacts
            input_artifacts=$(echo "$decision_json" | jq -c '.input_artifacts // []')
            local rationale
            rationale=$(echo "$decision_json" | jq -r '.rationale // "Handoff requested"')
            
            # Log handoff decision (tracking is done via orchestration log)
            log_agent_handoff "$session_dir" "$from_agent" "$to_agent" "$orchestrator_output"
            
            # Invoke receiving agent - handle failures
            if _invoke_delegated_agent "$session_dir" "$to_agent" "$task" "$rationale" "$input_artifacts"; then
                # Process KG artifacts if agent produced any
                process_agent_kg_artifacts "$session_dir" "$to_agent"
                
                log_decision "$session_dir" "handoff_success" "$orchestrator_output"
            else
                echo "  ⚠ Handoff failed - agent $to_agent did not complete" >&2
                log_decision "$session_dir" "handoff_failure" \
                    "$(echo "$orchestrator_output" | jq --arg reason "Handoff target failed" '. + {failure_reason: $reason}')"
            fi
            ;;
            
        early_exit)
            local reason
            reason=$(echo "$decision_json" | jq -r '.reason')
            
            log_decision "$session_dir" "early_exit" "$orchestrator_output"
            return 2  # Signal early exit
            ;;
            
        *)
            echo "⚠️  Warning: Unknown decision action: $decision_action" >&2
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
    
    # Extract decision JSON from output
    local decision_json
    if decision_json=$(extract_orchestrator_decision "$orchestrator_output" 2>/dev/null); then
        # Check if orchestrator explicitly signaled completion
        local decision_action
        decision_action=$(echo "$decision_json" | jq -r '.action')
        
        if [[ "$decision_action" == "early_exit" ]]; then
            return 0  # Complete (early)
        fi
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

Report generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
    
    # Log mission start event for journal
    local objective
    objective=$(cat "$session_dir/session.json" | jq -r '.objective // "Unknown"')
    log_event "$session_dir" "mission_started" "$(jq -n \
        --arg mission "$mission_name" \
        --arg objective "$objective" \
        '{
            mission: $mission,
            objective: $objective,
            started_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }')"
    
    # Clean up stale dashboard servers from previous sessions
    # shellcheck disable=SC1091
    if source "$UTILS_DIR/dashboard.sh" 2>/dev/null; then
        dashboard_cleanup_orphans "$(dirname "$session_dir")" >/dev/null 2>&1 || true
    fi
    
    # Launch dashboard viewer
    echo "→ Launching Research Journal Viewer..."
    # shellcheck disable=SC1091
    if source "$UTILS_DIR/dashboard.sh"; then
        if dashboard_view "$session_dir"; then
            echo "  ✓ Dashboard viewer launched"
        else
            log_error "$session_dir" "dashboard_launch" "Dashboard viewer failed to launch"
            echo "  ⚠ Dashboard viewer failed (check system-errors.log)" >&2
        fi
    else
        log_error "$session_dir" "dashboard_source" "Failed to source dashboard.sh"
        echo "  ⚠ Dashboard utility not found" >&2
    fi
    
    echo ""
    
    # Mission orchestration loop
    local iteration=1
    local max_iterations
    max_iterations=$(echo "$mission_profile" | jq -r '.constraints.max_iterations')
    
    while [[ $iteration -le $max_iterations ]]; do
        # Sync KG iteration with mission iteration FIRST (before any work)
        # This ensures dashboard always shows the current iteration number
        local kg_current
        kg_current=$(jq -r '.iteration // 0' "$session_dir/knowledge-graph.json" 2>/dev/null || echo "0")
        if [[ "$kg_current" -lt "$iteration" ]]; then
            kg_increment_iteration "$session_dir"
            # Update dashboard metrics immediately so dashboard shows current iteration
            if command -v dashboard_update_metrics &>/dev/null; then
                dashboard_update_metrics "$session_dir" || true
            fi
        fi
        
        echo "═══ Mission Iteration $iteration/$max_iterations ═══"
        echo ""
        
        # Parse prompt on first iteration if not yet done
        if [[ $iteration -eq 1 ]]; then
            # shellcheck disable=SC1091
            source "$UTILS_DIR/prompt-parser-handler.sh" 2>/dev/null || true
            
            if command -v needs_prompt_parsing &>/dev/null && needs_prompt_parsing "$session_dir"; then
                if command -v parse_prompt &>/dev/null; then
                    parse_prompt "$session_dir" || true
                    echo ""
                fi
            fi
        fi
        
        # Check budget before proceeding
        if ! budget_check "$session_dir"; then
            log_warning "$session_dir" "budget_limit" "Budget limit reached at iteration $iteration"
            echo ""
            echo "⚠ Budget limit reached - generating partial results"
            break
        fi
        
        # Prepare orchestrator context
        echo "→ Preparing orchestrator context..."
        local context_json
        context_json=$(prepare_orchestrator_context "$session_dir" "$mission_profile" "$iteration")
        
        # Invoke mission orchestrator
        # (invoke_agent.sh handles the invocation message)
        local orchestrator_output
        local orchestrator_output_file="$session_dir/.orchestrator-output.tmp"
        invoke_mission_orchestrator "$session_dir" "$context_json" > "$orchestrator_output_file"
        orchestrator_output=$(cat "$orchestrator_output_file")
        rm -f "$orchestrator_output_file"
        
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
    
    # Mark session as completed
    local completed_at
    completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg completed "$completed_at" \
        '.completed_at = $completed | .status = "completed"' \
        "$session_dir/session.json" > "$session_dir/session.json.tmp" && \
        mv "$session_dir/session.json.tmp" "$session_dir/session.json"
    
    # Generate final report
    generate_mission_report "$session_dir" "$mission_profile"
    
    # Export research journal as markdown
    # shellcheck source=/dev/null
    if command -v export_journal &>/dev/null || source "$UTILS_DIR/export-journal.sh" 2>/dev/null; then
        echo "→ Generating research journal..."
        export_journal "$session_dir" "$session_dir/research-journal.md" 2>&1 || echo "  ⚠️  Warning: Could not generate research journal"
    fi
    
    # Log mission completion event for journal
    local report_path="$session_dir/mission-report.md"
    log_event "$session_dir" "mission_completed" "$(jq -n \
        --arg completed "$completed_at" \
        --arg report "$([ -f "$report_path" ] && echo "mission-report.md" || echo "")" \
        '{
            completed_at: $completed,
            report_file: $report,
            status: "success"
        }')"
    
    # Generate mission metrics file for easy analysis
    local started_at
    started_at=$(jq -r '.created_at' "$session_dir/session.json")
    local total_cost
    total_cost=$(grep '"type":"agent_result"' "$session_dir/events.jsonl" 2>/dev/null | \
                 jq -s 'map(.data.cost_usd) | add' 2>/dev/null || echo "0")
    
    jq -n \
        --arg status "completed" \
        --arg start "$started_at" \
        --arg end "$completed_at" \
        --arg cost "$total_cost" \
        '{
            status: $status,
            started_at: $start,
            completed_at: $end,
            duration_seconds: (($end | fromdateiso8601) - ($start | fromdateiso8601)),
            total_cost_usd: ($cost | tonumber)
        }' > "$session_dir/mission-metrics.json"
    
    # Stop event tailer if running
    # shellcheck disable=SC1091
    if command -v stop_event_tailer &>/dev/null || source "$UTILS_DIR/event-tailer.sh" 2>/dev/null; then
        stop_event_tailer "$session_dir" 2>/dev/null || true
    fi
    
    echo ""
    echo "Session saved at: $session_dir"
}

# Resume mission orchestration
run_mission_orchestration_resume() {
    local mission_profile="$1"
    local session_dir="$2"
    local refinement="${3:-}"
    
    local mission_name
    mission_name=$(echo "$mission_profile" | jq -r '.name')
    
    echo "════════════════════════════════════════════════════════════"
    echo "Mission: $mission_name (Resume)"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    echo "→ Resuming orchestration..."
    
    # Get current iteration from orchestration log (robust method)
    local current_iteration=0
    if [ -f "$session_dir/orchestration-log.jsonl" ]; then
        # Try to get last iteration from decision entries
        current_iteration=$(awk 'NF{print}' "$session_dir/orchestration-log.jsonl" | \
            jq -r 'select(.decision.iteration!=null) | .decision.iteration' 2>/dev/null | \
            tail -1)
        
        # Fallback to line count if no iteration found
        if [ -z "$current_iteration" ] || [ "$current_iteration" = "null" ]; then
            current_iteration=$(wc -l < "$session_dir/orchestration-log.jsonl" | tr -d ' ')
        fi
    fi
    
    local max_iterations
    max_iterations=$(echo "$mission_profile" | jq -r '.constraints.max_iterations')
    local iteration=$((current_iteration + 1))
    
    echo "  Continuing from iteration $iteration/$max_iterations"
    
    # Launch dashboard if not already running
    if [ ! -f "$session_dir/.dashboard-server.pid" ]; then
        echo "→ Launching Research Journal Viewer..."
        # shellcheck disable=SC1091
        if source "$UTILS_DIR/dashboard.sh"; then
            if ! dashboard_view "$session_dir"; then
                log_error "$session_dir" "dashboard_refresh" "Dashboard refresh failed on resume"
            fi
        else
            log_error "$session_dir" "dashboard_source" "Failed to source dashboard.sh on resume"
        fi
    fi
    
    echo ""
    
    # Continue orchestration loop
    while [[ $iteration -le $max_iterations ]]; do
        # Sync KG iteration with mission iteration FIRST (before any work)
        # This ensures dashboard always shows the current iteration number
        local kg_current
        kg_current=$(jq -r '.iteration // 0' "$session_dir/knowledge-graph.json" 2>/dev/null || echo "0")
        if [[ "$kg_current" -lt "$iteration" ]]; then
            kg_increment_iteration "$session_dir"
            # Update dashboard metrics immediately so dashboard shows current iteration
            if command -v dashboard_update_metrics &>/dev/null; then
                dashboard_update_metrics "$session_dir" || true
            fi
        fi
        
        echo "═══ Mission Iteration $iteration/$max_iterations (Resume) ═══"
        echo ""
        
        # Check budget
        if ! budget_check "$session_dir"; then
            log_warning "$session_dir" "budget_limit" "Budget limit reached at iteration $iteration (resume)"
            echo ""
            echo "⚠ Budget limit reached"
            break
        fi
        
        # Prepare context with resume flag and refinement
        echo "→ Preparing orchestrator context..."
        local context_json
        context_json=$(prepare_orchestrator_context_resume \
            "$session_dir" "$mission_profile" "$iteration" "$refinement")
        
        # Invoke orchestrator
        # (invoke_agent.sh handles the invocation message)
        local orchestrator_output
        local orchestrator_output_file="$session_dir/.orchestrator-output.tmp"
        invoke_mission_orchestrator "$session_dir" "$context_json" > "$orchestrator_output_file"
        orchestrator_output=$(cat "$orchestrator_output_file")
        rm -f "$orchestrator_output_file"
        
        echo ""
        
        # Process decisions
        if ! process_orchestrator_decisions "$session_dir" "$orchestrator_output"; then
            local exit_code=$?
            if [[ $exit_code -eq 2 ]]; then
                echo ""
                echo "✓ Mission completed"
                break
            fi
        fi
        
        echo ""
        
        # Check completion
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
    
    # Mark session as completed
    local completed_at
    completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg completed "$completed_at" \
        '.completed_at = $completed | .status = "completed"' \
        "$session_dir/session.json" > "$session_dir/session.json.tmp" && \
        mv "$session_dir/session.json.tmp" "$session_dir/session.json"
    
    # Update final report
    generate_mission_report "$session_dir" "$mission_profile"
    
    # Export research journal as markdown
    # shellcheck source=/dev/null
    if command -v export_journal &>/dev/null || source "$UTILS_DIR/export-journal.sh" 2>/dev/null; then
        echo "→ Generating research journal..."
        export_journal "$session_dir" "$session_dir/research-journal.md" 2>&1 || echo "  ⚠️  Warning: Could not generate research journal"
    fi
    
    # Log mission completion event for journal
    local report_path="$session_dir/mission-report.md"
    log_event "$session_dir" "mission_completed" "$(jq -n \
        --arg completed "$completed_at" \
        --arg report "$([ -f "$report_path" ] && echo "mission-report.md" || echo "")" \
        '{
            completed_at: $completed,
            report_file: $report,
            status: "success"
        }')"
    
    # Generate mission metrics file for easy analysis
    local started_at
    started_at=$(jq -r '.created_at' "$session_dir/session.json")
    local total_cost
    total_cost=$(grep '"type":"agent_result"' "$session_dir/events.jsonl" 2>/dev/null | \
                 jq -s 'map(.data.cost_usd) | add' 2>/dev/null || echo "0")
    
    jq -n \
        --arg status "completed" \
        --arg start "$started_at" \
        --arg end "$completed_at" \
        --arg cost "$total_cost" \
        '{
            status: $status,
            started_at: $start,
            completed_at: $end,
            duration_seconds: (($end | fromdateiso8601) - ($start | fromdateiso8601)),
            total_cost_usd: ($cost | tonumber)
        }' > "$session_dir/mission-metrics.json"
    
    # Stop event tailer if running
    # shellcheck disable=SC1091
    if command -v stop_event_tailer &>/dev/null || source "$UTILS_DIR/event-tailer.sh" 2>/dev/null; then
        stop_event_tailer "$session_dir" 2>/dev/null || true
    fi
    
    echo ""
    echo "Session saved at: $session_dir"
}

# Prepare orchestrator context for resume
prepare_orchestrator_context_resume() {
    local session_dir="$1"
    local mission_profile="$2"
    local iteration="$3"
    local refinement="${4:-}"
    
    # Get existing state
    local agents_json
    if ! agents_json=$(agent_registry_export_json); then
        echo "✗ Error: Failed to export agent registry" >&2
        return 1
    fi
    
    local kg_json
    if ! kg_json=$(kg_read "$session_dir"); then
        echo "✗ Error: Could not read knowledge graph" >&2
        return 1
    fi
    
    local budget_json
    if ! budget_json=$(budget_status "$session_dir"); then
        echo "✗ Error: Could not read budget status" >&2
        return 1
    fi
    
    local decisions_json
    if ! decisions_json=$(get_orchestration_log "$session_dir"); then
        echo "✗ Error: Could not read orchestration log" >&2
        return 1
    fi
    
    # Build context with resume metadata
    jq -n \
        --argjson mission "$mission_profile" \
        --argjson agents "$agents_json" \
        --argjson kg "$kg_json" \
        --argjson budget "$budget_json" \
        --argjson decisions "$decisions_json" \
        --argjson iteration "$iteration" \
        --argjson is_resume true \
        --arg refinement "$refinement" \
        '{
            mission: $mission,
            agents: $agents,
            knowledge_graph: $kg,
            budget: $budget,
            previous_decisions: $decisions,
            iteration: $iteration,
            is_resume: $is_resume,
            refinement_guidance: (if $refinement != "" then $refinement else null end)
        }'
}

