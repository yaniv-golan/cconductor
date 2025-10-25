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
# Note: SCRIPT_DIR may be set to src/ by parent, but we need core helpers from utils
UTILS_DIR_FOR_HELPERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$UTILS_DIR_FOR_HELPERS/core-helpers.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR_FOR_HELPERS/error-messages.sh"
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
# shellcheck disable=SC1091
source "$UTILS_DIR/web-cache.sh" 2>/dev/null || true

MISSION_ORCH_BASE_DIR="$(pwd)"

rel_path_for_display() {
    local raw_path="$1"
    local session_dir="$2"
    local base_dir="$3"
    if [[ -z "$raw_path" || "$raw_path" == "null" ]]; then
        echo "$raw_path"
        return 0
    fi
    if [[ "$raw_path" != /* ]]; then
        echo "$raw_path"
        return 0
    fi
    if [[ -n "$base_dir" && "$raw_path" == "$base_dir"* ]]; then
        local rel="${raw_path#"$base_dir"}"
        rel="${rel#/}"
        if [[ -z "$rel" ]]; then
            echo "."
        else
            echo "$rel"
        fi
        return 0
    fi
    if [[ -n "$session_dir" && "$raw_path" == "$session_dir"* ]]; then
        local rel="${raw_path#"$session_dir"}"
        rel="${rel#/}"
        if [[ -z "$rel" ]]; then
            echo "."
        else
            echo "$rel"
        fi
        return 0
    fi
    echo "$raw_path"
}

format_fetch_cache_lines() {
    local summary_json="$1"
    local session_dir="$2"
    local base_dir="$3"
    local output=""

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == "null" ]] && continue
        local url status stored content_type path display_path
        url=$(echo "$entry" | jq -r '.url // ""')
        status=$(echo "$entry" | jq -r '.status // ""')
        stored=$(echo "$entry" | jq -r '.stored_at_iso // (.stored_at // "")' 2>/dev/null || echo "")
        [[ -z "$stored" || "$stored" == "null" ]] && stored="unknown"
        content_type=$(echo "$entry" | jq -r '.content_type // ""' 2>/dev/null || echo "")
        path=$(echo "$entry" | jq -r '.path // ""' 2>/dev/null || echo "")
        display_path=$(rel_path_for_display "$path" "$session_dir" "$base_dir")

        local status_label="cached"
        [[ "$status" == "stale" ]] && status_label="stale"

        if [[ -n "$output" ]]; then
            output+=$'\n'
        fi
        output+="- [WebFetch] ${url} (${status_label})"$'\n'
        output+="    Stored: ${stored}"$'\n'
        if [[ -n "$content_type" && "$content_type" != "null" ]]; then
            output+="    Content-Type: ${content_type}"$'\n'
        fi
        output+="    Cached file: ${display_path}"
    done < <(echo "$summary_json" | jq -c '.[]')

    printf '%s' "$output"
}

format_search_cache_lines() {
    local summary_json="$1"
    local session_dir="$2"
    local base_dir="$3"
    local output=""

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == "null" ]] && continue
        local query stored status result_count canonical snippet path display_path
        query=$(echo "$entry" | jq -r '.query // ""')
        stored=$(echo "$entry" | jq -r '.stored_at_iso // (.stored_at // "")' 2>/dev/null || echo "")
        [[ -z "$stored" || "$stored" == "null" ]] && stored="unknown"
        status=$(echo "$entry" | jq -r '.status // ""')
        result_count=$(echo "$entry" | jq -r '.result_count // 0')
        canonical=$(echo "$entry" | jq -r '.canonical_query // ""')
        snippet=$(echo "$entry" | jq -r '.snippet_preview // ""')
        snippet=${snippet//$'\n'/ }
        path=$(echo "$entry" | jq -r '.path // ""' 2>/dev/null || echo "")
        display_path=$(rel_path_for_display "$path" "$session_dir" "$base_dir")

        local status_label="cached"
        [[ "$status" == "stale" ]] && status_label="stale"

        if [[ -n "$output" ]]; then
            output+=$'\n'
        fi
        output+="- [WebSearch] \"${query}\" (stored ${stored}, ${result_count} results, status: ${status_label})"$'\n'
        if [[ -n "$canonical" && "$canonical" != "null" ]]; then
            output+="    Canonical: ${canonical}"$'\n'
        fi
        if [[ -n "$snippet" && "$snippet" != "null" ]]; then
            output+="    Snippet: ${snippet}"$'\n'
        fi
        output+="    Cached file: ${display_path}"
    done < <(echo "$summary_json" | jq -c '.[]')

    printf '%s' "$output"
}

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
    
    # Extract coverage summary from knowledge graph
    local coverage_summary
    coverage_summary=$(echo "$kg_json" | jq -r '
        .claims // [] | group_by(.topic // "general") | 
        map({
            topic: (.[0].topic // "general"),
            claim_count: length,
            avg_confidence: (if length > 0 then (map(.confidence // 0) | add / length) else 0 end),
            unique_domains: (
                [.[] | .sources[]? | .url // "" | 
                    sub("^https?://"; "") | sub("/.*$"; "") | sub("^www\\."; "")] 
                | unique | length
            )
        })
    ' 2>/dev/null || echo "[]")
    
    # Extract high-priority gaps (≥8)
    local high_priority_gaps_count
    high_priority_gaps_count=$(echo "$kg_json" | jq -r '
        [.gaps[]? | select(.priority >= 8)] | length
    ' 2>/dev/null || echo "0")
    
    # Get list of high-priority gaps for context
    local high_priority_gaps_list
    high_priority_gaps_list=$(echo "$kg_json" | jq -c '
        [.gaps[]? | select(.priority >= 8) | {
            description: .description,
            priority: .priority,
            status: (.status // "unresolved")
        }]
    ' 2>/dev/null || echo "[]")
    
    # Check if quality gate has run
    local quality_gate_status="not_run"
    local quality_gate_summary="{}"
    local quality_gate_mode="advisory"
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        quality_gate_status=$(jq -r '.status // "unknown"' \
            "$session_dir/artifacts/quality-gate-summary.json" 2>/dev/null || echo "unknown")
        quality_gate_summary=$(cat "$session_dir/artifacts/quality-gate-summary.json" 2>/dev/null || echo "{}")
    fi
    
    # Load quality gate mode from config
    if command -v load_config &>/dev/null; then
        quality_gate_mode=$(load_config "quality-gate" 2>/dev/null | jq -r '.mode // "advisory"')
    fi
    
    # Check if research plan exists
    local research_plan_exists="false"
    local research_plan="{}"
    if [[ -f "$session_dir/artifacts/research-plan.json" ]]; then
        research_plan_exists="true"
        research_plan=$(cat "$session_dir/artifacts/research-plan.json" 2>/dev/null || echo "{}")
    fi
    
    # Check for recent agent timeouts
    local recent_timeouts
    local timeout_lines
    timeout_lines=$(grep -E '"agent_timeout"|"agent_invocation_failure"' "$session_dir/logs/orchestration.jsonl" 2>/dev/null | tail -10 || true)
    if [[ -n "$timeout_lines" ]]; then
        recent_timeouts=$(echo "$timeout_lines" | jq -s 'map(select(.type == "agent_timeout" or (.type == "agent_invocation_failure" and (.decision.failure_reason // "") | contains("timeout")))) | map({agent: (.decision.failed_agent // .decision.agent // "unknown"), reason: (.decision.timeout_reason // .decision.failure_reason // "unknown")})' 2>/dev/null || echo "[]")
    else
        recent_timeouts="[]"
    fi
    
    # Build context JSON with enhanced diagnostics
    jq -n \
        --argjson mission "$mission_profile" \
        --argjson agents "$agents_json" \
        --argjson kg "$kg_json" \
        --argjson budget "$budget_json" \
        --argjson decisions "$decisions_json" \
        --argjson iteration "$iteration" \
        --argjson coverage "$coverage_summary" \
        --arg gaps_count "$high_priority_gaps_count" \
        --argjson gaps_list "$high_priority_gaps_list" \
        --arg qg_status "$quality_gate_status" \
        --arg qg_mode "$quality_gate_mode" \
        --argjson qg_summary "$quality_gate_summary" \
        --arg plan_exists "$research_plan_exists" \
        --argjson plan "$research_plan" \
        --argjson timeouts "$recent_timeouts" \
        '{
            mission: $mission,
            agents: $agents,
            knowledge_graph: $kg,
            budget: $budget,
            previous_decisions: $decisions,
            iteration: $iteration,
            coverage_metrics: $coverage,
            high_priority_gaps: {
                count: ($gaps_count | tonumber),
                gaps: $gaps_list
            },
            quality_gate: {
                status: $qg_status,
                mode: $qg_mode,
                summary: $qg_summary
            },
            research_plan: {
                exists: ($plan_exists == "true"),
                plan: $plan
            },
            recent_timeouts: $timeouts
        }'
}

# Invoke mission orchestrator agent
invoke_mission_orchestrator() {
    local session_dir="$1"
    local context_json="$2"
    
    # Write context to temp file
    local context_file="$session_dir/meta/orchestrator-context.json"
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

## Coverage Metrics
$(echo "$context_json" | jq -r '.coverage_metrics | tojson')

## High-Priority Gaps (≥8)
Count: $(echo "$context_json" | jq -r '.high_priority_gaps.count')
Gaps: $(echo "$context_json" | jq -r '.high_priority_gaps.gaps | tojson')

## Quality Gate Status
Status: $(echo "$context_json" | jq -r '.quality_gate.status')
Summary: $(echo "$context_json" | jq -r '.quality_gate.summary | tojson')

## Research Plan
Exists: $(echo "$context_json" | jq -r '.research_plan.exists')
Plan: $(echo "$context_json" | jq -r '.research_plan.plan | tojson')

## Budget Status
$(echo "$context_json" | jq -r '.budget | tojson')

## Previous Decisions
$(echo "$context_json" | jq -r '.previous_decisions | tojson')

## Current Iteration
$(echo "$context_json" | jq -r '.iteration')

---

Based on this context, decide your next action(s). Use the decision schema to structure your outputs. Think step-by-step:

1. **Reflect** on the current state and what has been accomplished
2. **Assess** progress toward success criteria and coverage completeness
3. **Review** high-priority gaps and quality gate status
4. **Plan** the next action(s) needed
5. **Decide** which agent to invoke, with what task and context

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
    local input_file="$session_dir/meta/orchestrator-input.txt"
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
    local output_file="$session_dir/meta/orchestrator-output.json"
    
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
        output_spec=$(jq -r '.output_specification // ""' "$session_dir/meta/session.json" 2>/dev/null)
        if [[ -n "$output_spec" && "$output_spec" != "null" ]]; then
            output_spec_section=$(cat <<SPEC_EOF

## User's Output Format Requirements
$output_spec
SPEC_EOF
)
        fi
    fi
    
    # Build instructions based on agent type
    local instructions_section
    
    if [[ "$agent_name" == "web-researcher" ]]; then
        # Web-researcher: Manifest-only output (findings go to files)
        instructions_section=$(cat <<'INSTRUCTIONS_EOF'
## Instructions
Complete this task and write findings to separate JSON files in work/web-researcher/ directory.

Return ONLY this JSON manifest (no markdown, no explanations):

{
  "status": "completed",
  "tasks_completed": <number>,
  "findings_files": [
    "work/<agent>/findings-<task_id>.json",
    ...
  ]
}

CRITICAL REQUIREMENTS:
- Response must be ONLY the JSON manifest above
- Start with { and end with }
- NO markdown formatting (no ```json blocks)
- NO explanatory text
- If any task failed, set status to "partial" and add "errors" array

Example CORRECT: {"status":"completed","tasks_completed":2,"findings_files":["work/web-researcher/findings-t0.json","work/web-researcher/findings-t1.json"]}
Example WRONG: Here's the manifest: ```json {"status":"completed"} ```
INSTRUCTIONS_EOF
)
    elif [[ "$agent_name" =~ ^(academic-researcher|pdf-analyzer|code-analyzer|fact-checker|market-analyzer)$ ]]; then
        # Other research agents: Full JSON schema output
        instructions_section=$(cat <<'INSTRUCTIONS_EOF'
## Instructions
Return ONLY valid JSON matching this exact schema:

{
  "task_id": "string",
  "status": "completed|failed",
  "entities_discovered": [
    {"name": "string", "type": "string", "description": "string", 
     "confidence": 0.0-1.0, "sources": ["url"]}
  ],
  "claims": [
    {"statement": "string", "confidence": 0.0-1.0, "evidence_quality": "high|medium|low",
     "sources": [{"url": "string", "title": "string", "relevant_quote": "string"}]}
  ],
  "relationships_discovered": [...],
  "gaps_identified": [{"question": "string", "priority": 1-10}]
}

CRITICAL REQUIREMENTS:
- Return ONLY the JSON object above IN YOUR RESPONSE
- The orchestration system will automatically integrate your findings into the knowledge graph
- Do NOT use the Write tool to create knowledge/knowledge-graph.json or findings files
- Do NOT attempt to write to any data files - all findings go in your JSON response
- Start with { and end with }
- NO markdown formatting (no ```json blocks)
- NO explanatory text before or after the JSON
- Validate all JSON is properly escaped

Example CORRECT: {"task_id":"t0","status":"completed","entities_discovered":[...],"claims":[...]}
Example WRONG: Here are my findings: ```json {"entities_discovered": [...]} ```
Example WRONG: I will write the findings to knowledge/knowledge-graph.json using the Write tool.
Example WRONG: Let me create a findings file...

If you must explain something, put it in a "notes" field within the JSON.
INSTRUCTIONS_EOF
)
    else
        # Non-research agents: generic instructions
        instructions_section=$(cat <<'INSTRUCTIONS_EOF'
## Instructions
Please complete this task and provide your findings in a structured format.
Include any artifacts you create and cite all sources.
INSTRUCTIONS_EOF
)
    fi
    
    local cache_section=""
    local cache_lines=""
    if command -v web_cache_format_summary >/dev/null 2>&1; then
        local fetch_summary_json fetch_lines
        fetch_summary_json=$(web_cache_format_summary "$session_dir" 2>/dev/null || echo "[]")
        if [[ -n "$fetch_summary_json" && "$fetch_summary_json" != "[]" ]]; then
            fetch_lines=$(format_fetch_cache_lines "$fetch_summary_json" "$session_dir" "$MISSION_ORCH_BASE_DIR")
            if [[ -n "$fetch_lines" ]]; then
                cache_lines="$fetch_lines"
            fi
        fi
    fi
    if command -v web_search_cache_format_summary >/dev/null 2>&1; then
        local search_summary_json search_lines
        search_summary_json=$(web_search_cache_format_summary "$session_dir" 2>/dev/null || echo "[]")
        if [[ -n "$search_summary_json" && "$search_summary_json" != "[]" ]]; then
            search_lines=$(format_search_cache_lines "$search_summary_json" "$session_dir" "$MISSION_ORCH_BASE_DIR")
            if [[ -n "$search_lines" ]]; then
                if [[ -n "$cache_lines" ]]; then
                    cache_lines+=$'\n'
                fi
                cache_lines+="$search_lines"
            fi
        fi
    fi
    if [[ -n "$cache_lines" ]]; then
        cache_section=$'\n''## Cached Sources Available\n'"$cache_lines"$'\n'
    fi

    local agent_input
    agent_input=$(cat <<EOF
$task

## Context
$context

## Input Artifacts
$artifacts_section${output_spec_section}${cache_section}

$instructions_section
EOF
)
    
    # Write input to agent-specific work directory
    mkdir -p "$session_dir/work/$agent_name"
    local agent_input_file="$session_dir/work/$agent_name/input.txt"
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
    
    # Invoke agent - output to agent-specific work directory
    local agent_output_file="$session_dir/work/$agent_name/output.json"
    
    # Source invoke-agent utility
    # shellcheck disable=SC1091
    source "$UTILS_DIR/invoke-agent.sh"
    
    local start_time
    start_time=$(get_epoch)
    
    if invoke_agent_v2 "$agent_name" "$agent_input_file" "$agent_output_file" 600 "$session_dir"; then
        local end_time
        end_time=$(get_epoch)
        local duration=$((end_time - start_time))
        
        echo "  ✓ $agent_name completed ($duration seconds)"
        
        # Extract cost from agent output
        local cost
        cost=$(extract_cost_from_output "$agent_output_file")
        
        # Extract result
        local result
        result=$(jq -r '.result // empty' "$agent_output_file" 2>/dev/null)
        
        # Register output as artifact
        local artifact_file=""
        if [[ -n "$result" ]]; then
            mkdir -p "$session_dir/artifacts/$agent_name"
            artifact_file="$session_dir/artifacts/$agent_name/output.md"
            echo "$result" > "$artifact_file"
            
            # Register artifact (capture ID but don't display it)
            local artifact_id
            # shellcheck disable=SC2034
            artifact_id=$(artifact_register "$session_dir" "$artifact_file" "agent_output" "$agent_name")
        fi
        
        # Record budget with real cost
        budget_record_invocation "$session_dir" "$agent_name" "$cost" "$duration"
        
        return 0
    else
        local exit_code=$?
        echo "  ✗ $agent_name invocation failed" >&2
        return $exit_code
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
# Ensures report/mission-report.md is created
validate_synthesis_outputs() {
    local session_dir="$1"
    local agent="$2"
    
    # Only validate for synthesis-agent
    if [ "$agent" != "synthesis-agent" ]; then
        return 0
    fi
    
    local mission_report="$session_dir/report/mission-report.md"
    
    # Check mission report exists
    if [ ! -f "$mission_report" ]; then
        echo "  ⚠️  Warning: synthesis-agent did not create report/mission-report.md" >&2
        return 1
    fi
    
    echo "  ✓ Synthesis outputs validated (report/mission-report.md)" >&2
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
            
            # For synthesis-agent, run quality gate first
            if [[ "$agent_name" == "synthesis-agent" ]]; then
                echo "→ Running quality gate before synthesis..."
                if ! run_quality_assurance_cycle "$session_dir"; then
                    # Get mode to display appropriate message
                    local gate_mode
                    if command -v load_config &>/dev/null; then
                        gate_mode=$(load_config "quality-gate" 2>/dev/null | jq -r '.mode // "advisory"')
                    else
                        gate_mode="advisory"
                    fi
                    
                    if [[ "$gate_mode" == "advisory" ]]; then
                        echo "⚠ Quality gate flagged some claims (advisory mode - remediation attempted)" >&2
                    else
                        echo "⚠ Quality gate flagged some claims, synthesis blocked (enforce mode)" >&2
                    fi
                    
                    # Provide gate results to orchestrator for remediation decision
                    local gate_results
                    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
                        gate_results=$(cat "$session_dir/artifacts/quality-gate-summary.json")
                    else
                        gate_results='{"status": "failed", "message": "Quality gate failed but no summary available"}'
                    fi
                    
                    # Log decision with gate results
                    log_decision "$session_dir" "synthesis_blocked_quality_gate" \
                        "$(echo "$orchestrator_output" | jq --argjson gate "$gate_results" \
                        '. + {quality_gate_failed: $gate}')"
                    
                    # Return without invoking synthesis - orchestrator will adapt
                    return 0
                fi
                echo "  ✓ Quality gate passed, proceeding with synthesis"
            fi
            
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
                local exit_code=$?
                
                # Check for timeout (exit code 124)
                if [[ $exit_code -eq 124 ]]; then
                    echo "  ⚠ Agent $agent_name timed out (no activity) - orchestrator will adapt" >&2
                    log_decision "$session_dir" "agent_timeout" \
                        "$(echo "$orchestrator_output" | jq \
                        --arg agent "$agent_name" \
                        --arg reason "inactivity_timeout" \
                        '. + {timeout: true, failed_agent: $agent, timeout_reason: $reason}')"
                else
                    echo "  ⚠ Agent $agent_name failed - orchestrator will adapt" >&2
                    log_decision "$session_dir" "agent_invocation_failure" \
                        "$(echo "$orchestrator_output" | jq --arg reason "Agent failed" '. + {failure_reason: $reason}')"
                fi
            fi
            ;;
            
        reinvoke)
            local agent_name
            agent_name=$(echo "$decision_json" | jq -r '.agent')
            local reason
            reason=$(echo "$decision_json" | jq -r '.reason')
            local refinements
            refinements=$(echo "$decision_json" | jq -r '.refinements // "Please provide more detail"')
            
            # Validate refinements don't contain file-writing instructions
            # These confuse research agents since they're designed to return JSON, not write files
            if echo "$refinements" | grep -Eqi "write.*(knowledge-graph|file|findings)|write tool|create.*file|save to"; then
                log_warn "⚠️  Orchestrator refinements contain file-writing instructions"
                log_warn "Research agents return JSON responses - they don't write data files"
                log_warn "This may cause agents to ask for clarification instead of researching"
                log_warn "Refinements: ${refinements:0:200}..."
                # Continue anyway - let orchestrator learn from the response
            fi
            
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

# Run quality gate on knowledge graph
run_quality_gate() {
    local session_dir="$1"
    
    # Check if quality gate script exists
    if [[ ! -f "$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh" ]]; then
        log_warn "Quality gate script not found, skipping quality check"
        return 0  # Don't block if gate doesn't exist
    fi
    
    # Run quality gate (always succeeds in advisory mode, so check JSON output)
    bash "$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh" "$session_dir" > /dev/null 2>&1
    
    # Check actual status from the summary file
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        local status
        status=$(jq -r '.status // "unknown"' "$session_dir/artifacts/quality-gate-summary.json")
        if [[ "$status" == "passed" ]]; then
            return 0  # Passed
        else
            return 1  # Failed
        fi
    else
        log_warn "Quality gate summary not found after execution"
        return 1  # Treat as failure if no output
    fi
}

log_quality_gate_event() {
    local session_dir="$1"
    local event_type="$2"
    local attempt_value="${3:-0}"
    local mode_value="${4:-advisory}"
    local status_value="${5:-}"
    local summary_file="${6:-}"
    local report_file="${7:-}"

    # Ensure attempt is numeric for jq --argjson
    if ! [[ "$attempt_value" =~ ^[0-9]+$ ]]; then
        attempt_value=0
    fi

    if command -v log_event &>/dev/null; then
        local event_payload
        event_payload=$(jq -n \
            --argjson attempt "$attempt_value" \
            --arg mode "$mode_value" \
            --arg status "$status_value" \
            --arg summary "$summary_file" \
            --arg report "$report_file" \
            '{
                attempt: $attempt,
                mode: $mode,
                status: $status,
                summary_file: ($summary | select(. != "")),
                report_file: ($report | select(. != ""))
            }')

        log_event "$session_dir" "$event_type" "$event_payload"
    fi
}

# Run quality assurance cycle (gate + remediation if needed)
run_quality_assurance_cycle() {
    local session_dir="$1"
    
    # Load quality gate config
    local quality_config
    if ! quality_config=$(load_config "quality-gate" 2>/dev/null); then
        log_warn "Quality gate config not found, skipping quality assurance"
        return 0
    fi
    
    # Check if remediation is enabled
    local remediation_enabled
    remediation_enabled=$(echo "$quality_config" | jq -r '.remediation.enabled // false')

    local gate_mode
    gate_mode=$(echo "$quality_config" | jq -r '.mode // "advisory"')
    
    local max_attempts
    max_attempts=$(echo "$quality_config" | jq -r '.remediation.max_attempts // 2')
    
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_quality_gate_event "$session_dir" "quality_gate_started" "$attempt" "$gate_mode" "running"
        # Run quality gate
        if run_quality_gate "$session_dir"; then
            verbose "✓ Quality gate passed"
            log_quality_gate_event "$session_dir" "quality_gate_completed" "$attempt" "$gate_mode" "passed" "artifacts/quality-gate-summary.json" "artifacts/quality-gate.json"
            return 0
        fi
        log_quality_gate_event "$session_dir" "quality_gate_completed" "$attempt" "$gate_mode" "failed" "artifacts/quality-gate-summary.json" "artifacts/quality-gate.json"

        # Gate failed
        if [[ "$remediation_enabled" != "true" ]] || [[ $attempt -eq $max_attempts ]]; then
            verbose "Quality gate still flagging claims after remediation attempts"
            
            # Check mode before deciding to block
            if [[ "$gate_mode" == "advisory" ]]; then
                # Advisory mode: log issues but don't block
                verbose "Quality gate in advisory mode - issues logged but not blocking"
                return 0  # Allow synthesis to proceed
            else
                # Enforce mode: block synthesis
                verbose "Quality gate in enforce mode - blocking synthesis"
                return 1
            fi
        fi
        
        # Check if quality-remediator agent exists
        if [[ ! -d "$PROJECT_ROOT/src/claude-runtime/agents/quality-remediator" ]]; then
            log_warn "Quality remediator agent not found, cannot auto-remediate"
            return 1
        fi
        
        # Invoke quality remediator
        echo "→ Invoking quality remediator (attempt $attempt/$max_attempts)..."
        
        # Create remediation task
        local gate_summary
        if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
            gate_summary=$(cat "$session_dir/artifacts/quality-gate-summary.json")
        else
            gate_summary="{}"
        fi
        
        local remediation_task="Review the quality gate flagged claims and gather additional evidence to address the identified issues."
        local remediation_context="Quality gate summary: $gate_summary"
        
        # Invoke remediator
        if _invoke_delegated_agent "$session_dir" "quality-remediator" "$remediation_task" "$remediation_context" "[]"; then
            # Process any KG artifacts from remediation
            process_agent_kg_artifacts "$session_dir" "quality-remediator"
            verbose "  ✓ Remediation attempt $attempt completed"
        else
            log_warn "Quality remediator invocation failed"
            return 1
        fi
        
        attempt=$((attempt + 1))
    done

    return 1
}

# Check if mission is complete
check_mission_complete() {
    local session_dir="$1"
    local mission_profile="$2"
    local orchestrator_output="$3"
    
    # Initialize completion checklist
    local planning_done=false
    local quality_gate_passed=false
    local high_priority_gaps_resolved=false
    local required_outputs_present=false
    
    # 1. Check planning done (if research plan exists)
    if [[ -f "$session_dir/artifacts/research-plan.json" ]]; then
        planning_done=true
    else
        # Planning is optional - not all missions need explicit planning
        planning_done=true
    fi
    
    # 2. Check quality gate
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        local gate_status
        gate_status=$(jq -r '.status // "unknown"' "$session_dir/artifacts/quality-gate-summary.json" 2>/dev/null || echo "unknown")
        if [[ "$gate_status" == "passed" ]]; then
            quality_gate_passed=true
        fi
    else
        # Quality gate hasn't run yet - not a failure
        quality_gate_passed=true
    fi
    
    # 3. Check high-priority gaps (≥8)
    local unresolved_gaps
    unresolved_gaps=$(jq -r '[.gaps[]? | select(.priority >= 8 and (.status // "unresolved") != "resolved")] | length' \
        "$session_dir/knowledge/knowledge-graph.json" 2>/dev/null || echo "0")
    if [[ "$unresolved_gaps" -eq 0 ]]; then
        high_priority_gaps_resolved=true
    fi
    
    # 4. Check required outputs exist in artifacts
    local required_outputs
    required_outputs=$(echo "$mission_profile" | jq -r '.success_criteria.required_outputs[]?' 2>/dev/null)
    
    if [[ -z "$required_outputs" ]]; then
        # No required outputs specified
        required_outputs_present=true
    else
        # Get all artifacts
        local artifacts
        artifacts=$(artifact_list_all "$session_dir" 2>/dev/null || echo "[]")
        
        # Check each required output
        local all_found=true
        while IFS= read -r required_output; do
            [[ -z "$required_output" ]] && continue
            
            # Check if any artifact has this output type
            local found
            found=$(echo "$artifacts" | jq -r --arg type "$required_output" '.[]? | select(.type == $type) | .type' | head -1)
            
            if [[ -z "$found" ]]; then
                all_found=false
                break
            fi
        done <<< "$required_outputs"
        
        if [[ "$all_found" == "true" ]]; then
            required_outputs_present=true
        fi
    fi
    
    # 5. Check for orchestrator early_exit decision
    local decision_json
    if decision_json=$(extract_orchestrator_decision "$orchestrator_output" 2>/dev/null); then
        local decision_action
        decision_action=$(echo "$decision_json" | jq -r '.action // ""')
        
        if [[ "$decision_action" == "early_exit" ]]; then
            # Orchestrator explicitly requested early exit
            # Log completion verification with current checklist state
            log_decision "$session_dir" "completion_verification" "$(jq -n \
                --argjson planning "$planning_done" \
                --argjson quality "$quality_gate_passed" \
                --argjson gaps "$high_priority_gaps_resolved" \
                --argjson outputs "$required_outputs_present" \
                --arg early_exit "true" \
                '{
                    planning_done: $planning,
                    quality_gate_passed: $quality,
                    gaps_resolved: $gaps,
                    outputs_present: $outputs,
                    early_exit_requested: $early_exit
                }')"
            return 0  # Complete (early exit)
        fi
    fi
    
    # Log completion verification
    log_decision "$session_dir" "completion_verification" "$(jq -n \
        --argjson planning "$planning_done" \
        --argjson quality "$quality_gate_passed" \
        --argjson gaps "$high_priority_gaps_resolved" \
        --argjson outputs "$required_outputs_present" \
        '{
            planning_done: $planning,
            quality_gate_passed: $quality,
            gaps_resolved: $gaps,
            outputs_present: $outputs
        }')"
    
    # Mission complete only if all checks pass
    if [[ "$planning_done" == "true" ]] && \
       [[ "$quality_gate_passed" == "true" ]] && \
       [[ "$high_priority_gaps_resolved" == "true" ]] && \
       [[ "$required_outputs_present" == "true" ]]; then
        return 0
    fi
    
    return 1
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
    objective=$(cat "$session_dir/meta/session.json" | jq -r '.objective // "Unknown"')
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
            echo "  ⚠ Dashboard viewer failed (check logs/system-errors.log)" >&2
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
        kg_current=$(jq -r '.iteration // 0' "$session_dir/knowledge/knowledge-graph.json" 2>/dev/null || echo "0")
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
        local orch_start_time
        orch_start_time=$(get_epoch)
        invoke_mission_orchestrator "$session_dir" "$context_json" > "$orchestrator_output_file"
        orchestrator_output=$(cat "$orchestrator_output_file")
        
        # Record orchestrator cost in budget
        local orchestrator_cost
        orchestrator_cost=$(extract_cost_from_output "$session_dir/meta/orchestrator-output.json")
        local orch_duration
        orch_duration=$(($(get_epoch) - orch_start_time))
        budget_record_invocation "$session_dir" "mission-orchestrator" "$orchestrator_cost" "$orch_duration"
        
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
    completed_at=$(get_timestamp)
    jq --arg completed "$completed_at" \
        '.completed_at = $completed | .status = "completed"' \
        "$session_dir/meta/session.json" > "$session_dir/meta/session.json.tmp" && \
        mv "$session_dir/meta/session.json.tmp" "$session_dir/meta/session.json"
    
    # Announce final report status from synthesis agent
    local final_report="$session_dir/report/mission-report.md"
    echo "→ Final report status..."
    if [ -f "$final_report" ]; then
        local final_report_display
        final_report_display=$(rel_path_for_display "$final_report" "$session_dir" "$MISSION_ORCH_BASE_DIR")
        echo "  ✓ Final report ready: $final_report_display"
    else
        local final_report_missing_display
        final_report_missing_display=$(rel_path_for_display "$final_report" "$session_dir" "$MISSION_ORCH_BASE_DIR")
        verbose "  (Final report not generated - synthesis may not have completed: $final_report_missing_display)"
    fi
    
    # Export research journal as markdown
    # shellcheck source=/dev/null
    if command -v export_journal &>/dev/null || source "$UTILS_DIR/export-journal.sh" 2>/dev/null; then
        echo "→ Generating research journal..."
        export_journal "$session_dir" "$session_dir/report/research-journal.md" 2>&1 || echo "  ⚠️  Warning: Could not generate research journal"
    fi
    
    # Log mission completion event for journal
    local report_relative=""
    if [ -f "$final_report" ]; then
        report_relative="report/mission-report.md"
    fi
    log_event "$session_dir" "mission_completed" "$(jq -n \
        --arg completed "$completed_at" \
        --arg report "$report_relative" \
        '{
            completed_at: $completed,
            report_file: $report,
            status: "success"
        }')"
    
    # Generate mission metrics file for easy analysis
    local started_at
    started_at=$(jq -r '.created_at' "$session_dir/meta/session.json")
    local total_cost
    total_cost=$(grep '"type":"agent_result"' "$session_dir/logs/events.jsonl" 2>/dev/null | \
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
        }' > "$session_dir/meta/mission-metrics.json"

    # Persist findings into the shared digital library
    if [ -x "$UTILS_DIR/digital-librarian.sh" ]; then
        "$UTILS_DIR/digital-librarian.sh" "$session_dir" 2>/dev/null || \
            echo "  ⚠️  Warning: Digital librarian update failed" >&2
    fi
    
    # Generate session manifests and user README
    if [ -x "$UTILS_DIR/meta-manifest-generator.sh" ]; then
        "$UTILS_DIR/meta-manifest-generator.sh" "$session_dir" >/dev/null 2>&1 || \
            echo "  ⚠️  Warning: Meta manifest generation failed" >&2
    fi
    if [ -x "$UTILS_DIR/session-readme-generator.sh" ]; then
        "$UTILS_DIR/session-readme-generator.sh" "$session_dir" >/dev/null 2>&1 || \
            echo "  ⚠️  Warning: Session README generation failed" >&2
    fi

    # Stop event tailer if running
    # shellcheck disable=SC1091
    if command -v stop_event_tailer &>/dev/null || source "$UTILS_DIR/event-tailer.sh" 2>/dev/null; then
        stop_event_tailer "$session_dir" 2>/dev/null || true
    fi
    
    local session_display
    session_display=$(rel_path_for_display "$session_dir" "" "$MISSION_ORCH_BASE_DIR")
    echo ""
    echo "Session saved at: $session_display"
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
    if [ -f "$session_dir/logs/orchestration.jsonl" ]; then
        # Try to get last iteration from decision entries
        current_iteration=$(awk 'NF{print}' "$session_dir/logs/orchestration.jsonl" | \
            jq -r 'select(.decision.iteration!=null) | .decision.iteration' 2>/dev/null | \
            tail -1)
        
        # Fallback to line count if no iteration found
        if [ -z "$current_iteration" ] || [ "$current_iteration" = "null" ]; then
            current_iteration=$(wc -l < "$session_dir/logs/orchestration.jsonl" | tr -d ' ')
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
        kg_current=$(jq -r '.iteration // 0' "$session_dir/knowledge/knowledge-graph.json" 2>/dev/null || echo "0")
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
        local orch_start_time
        orch_start_time=$(get_epoch)
        invoke_mission_orchestrator "$session_dir" "$context_json" > "$orchestrator_output_file"
        orchestrator_output=$(cat "$orchestrator_output_file")
        
        # Record orchestrator cost in budget
        local orchestrator_cost
        orchestrator_cost=$(extract_cost_from_output "$session_dir/meta/orchestrator-output.json")
        local orch_duration
        orch_duration=$(($(get_epoch) - orch_start_time))
        budget_record_invocation "$session_dir" "mission-orchestrator" "$orchestrator_cost" "$orch_duration"
        
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
    completed_at=$(get_timestamp)
    jq --arg completed "$completed_at" \
        '.completed_at = $completed | .status = "completed"' \
        "$session_dir/meta/session.json" > "$session_dir/meta/session.json.tmp" && \
        mv "$session_dir/meta/session.json.tmp" "$session_dir/meta/session.json"
    
    # Announce final report status from synthesis agent
    local final_report="$session_dir/report/mission-report.md"
    echo "→ Final report status..."
    if [ -f "$final_report" ]; then
        local final_report_display
        final_report_display=$(rel_path_for_display "$final_report" "$session_dir" "$MISSION_ORCH_BASE_DIR")
        echo "  ✓ Final report ready: $final_report_display"
    else
        local final_report_missing_display
        final_report_missing_display=$(rel_path_for_display "$final_report" "$session_dir" "$MISSION_ORCH_BASE_DIR")
        verbose "  (Final report not generated - synthesis may not have completed: $final_report_missing_display)"
    fi
    
    # Export research journal as markdown
    # shellcheck source=/dev/null
    if command -v export_journal &>/dev/null || source "$UTILS_DIR/export-journal.sh" 2>/dev/null; then
        echo "→ Generating research journal..."
        export_journal "$session_dir" "$session_dir/report/research-journal.md" 2>&1 || echo "  ⚠️  Warning: Could not generate research journal"
    fi
    
    # Log mission completion event for journal
    local report_relative=""
    if [ -f "$final_report" ]; then
        report_relative="report/mission-report.md"
    fi
    log_event "$session_dir" "mission_completed" "$(jq -n \
        --arg completed "$completed_at" \
        --arg report "$report_relative" \
        '{
            completed_at: $completed,
            report_file: $report,
            status: "success"
        }')"
    
    # Generate mission metrics file for easy analysis
    local started_at
    started_at=$(jq -r '.created_at' "$session_dir/meta/session.json")
    local total_cost
    total_cost=$(grep '"type":"agent_result"' "$session_dir/logs/events.jsonl" 2>/dev/null | \
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
        }' > "$session_dir/meta/mission-metrics.json"
    
    # Generate session manifests and user README
    if [ -x "$UTILS_DIR/meta-manifest-generator.sh" ]; then
        "$UTILS_DIR/meta-manifest-generator.sh" "$session_dir" >/dev/null 2>&1 || \
            echo "  ⚠️  Warning: Meta manifest generation failed" >&2
    fi
    if [ -x "$UTILS_DIR/session-readme-generator.sh" ]; then
        "$UTILS_DIR/session-readme-generator.sh" "$session_dir" >/dev/null 2>&1 || \
            echo "  ⚠️  Warning: Session README generation failed" >&2
    fi
    
    # Stop event tailer if running
    # shellcheck disable=SC1091
    if command -v stop_event_tailer &>/dev/null || source "$UTILS_DIR/event-tailer.sh" 2>/dev/null; then
        stop_event_tailer "$session_dir" 2>/dev/null || true
    fi
    
    local session_display
    session_display=$(rel_path_for_display "$session_dir" "" "$MISSION_ORCH_BASE_DIR")
    echo ""
    echo "Session saved at: $session_display"
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
    
    # Extract coverage summary from knowledge graph
    local coverage_summary
    coverage_summary=$(echo "$kg_json" | jq -r '
        .claims // [] | group_by(.topic // "general") | 
        map({
            topic: (.[0].topic // "general"),
            claim_count: length,
            avg_confidence: (if length > 0 then (map(.confidence // 0) | add / length) else 0 end),
            unique_domains: (
                [.[] | .sources[]? | .url // "" | 
                    sub("^https?://"; "") | sub("/.*$"; "") | sub("^www\\."; "")] 
                | unique | length
            )
        })
    ' 2>/dev/null || echo "[]")
    
    # Extract high-priority gaps (≥8)
    local high_priority_gaps_count
    high_priority_gaps_count=$(echo "$kg_json" | jq -r '
        [.gaps[]? | select(.priority >= 8)] | length
    ' 2>/dev/null || echo "0")
    
    # Get list of high-priority gaps for context
    local high_priority_gaps_list
    high_priority_gaps_list=$(echo "$kg_json" | jq -c '
        [.gaps[]? | select(.priority >= 8) | {
            description: .description,
            priority: .priority,
            status: (.status // "unresolved")
        }]
    ' 2>/dev/null || echo "[]")
    
    # Check if quality gate has run
    local quality_gate_status="not_run"
    local quality_gate_summary="{}"
    local quality_gate_mode="advisory"
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        quality_gate_status=$(jq -r '.status // "unknown"' \
            "$session_dir/artifacts/quality-gate-summary.json" 2>/dev/null || echo "unknown")
        quality_gate_summary=$(cat "$session_dir/artifacts/quality-gate-summary.json" 2>/dev/null || echo "{}")
    fi
    if command -v load_config &>/dev/null; then
        quality_gate_mode=$(load_config "quality-gate" 2>/dev/null | jq -r '.mode // "advisory"')
    fi
    
    # Check if research plan exists
    local research_plan_exists="false"
    local research_plan="{}"
    if [[ -f "$session_dir/artifacts/research-plan.json" ]]; then
        research_plan_exists="true"
        research_plan=$(cat "$session_dir/artifacts/research-plan.json" 2>/dev/null || echo "{}")
    fi
    
    # Build context with resume metadata and enhanced diagnostics
    jq -n \
        --argjson mission "$mission_profile" \
        --argjson agents "$agents_json" \
        --argjson kg "$kg_json" \
        --argjson budget "$budget_json" \
        --argjson decisions "$decisions_json" \
        --argjson iteration "$iteration" \
        --argjson is_resume true \
        --arg refinement "$refinement" \
        --argjson coverage "$coverage_summary" \
        --arg gaps_count "$high_priority_gaps_count" \
        --argjson gaps_list "$high_priority_gaps_list" \
        --arg qg_status "$quality_gate_status" \
        --arg qg_mode "$quality_gate_mode" \
        --argjson qg_summary "$quality_gate_summary" \
        --arg plan_exists "$research_plan_exists" \
        --argjson plan "$research_plan" \
        '{
            mission: $mission,
            agents: $agents,
            knowledge_graph: $kg,
            budget: $budget,
            previous_decisions: $decisions,
            iteration: $iteration,
            is_resume: $is_resume,
            refinement_guidance: (if $refinement != "" then $refinement else null end),
            coverage_metrics: $coverage,
            high_priority_gaps: {
                count: ($gaps_count | tonumber),
                gaps: $gaps_list
            },
            quality_gate: {
                status: $qg_status,
                mode: $qg_mode,
                summary: $qg_summary
            },
            research_plan: {
                exists: ($plan_exists == "true"),
                plan: $plan
            }
        }'
}
