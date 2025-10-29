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
source "$UTILS_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"
# shellcheck disable=SC1091
if ! source "$UTILS_DIR/quality-surface-sync.sh" 2>/dev/null; then
    if [[ -z "${MISSION_ORCH_QUALITY_SURFACE_SYNC_WARNED:-}" ]]; then
        log_warn "Optional quality-surface-sync.sh failed to load (quality surface metrics disabled)"
        MISSION_ORCH_QUALITY_SURFACE_SYNC_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$UTILS_DIR/verbose.sh" 2>/dev/null; then
    if [[ -z "${MISSION_ORCH_VERBOSE_WARNED:-}" ]]; then
        log_warn "Optional verbose.sh failed to load (enhanced iteration logging disabled)"
        MISSION_ORCH_VERBOSE_WARNED=1
    fi
fi
# shellcheck disable=SC1091
source "$UTILS_DIR/error-logger.sh"
# shellcheck disable=SC1091
source "$UTILS_DIR/debug.sh"
setup_error_trap
# shellcheck disable=SC1091
if ! source "$UTILS_DIR/web-cache.sh" 2>/dev/null; then
    if [[ -z "${MISSION_ORCH_WEB_CACHE_WARNED:-}" ]]; then
        log_warn "Optional web-cache.sh failed to load (web fetch cache disabled for this run)"
        MISSION_ORCH_WEB_CACHE_WARNED=1
    fi
fi
# shellcheck disable=SC1091
source "$UTILS_DIR/session-manager.sh"

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

    if ! jq_validate_json "$summary_json"; then
        log_system_warning "$session_dir" "jq_cache_summary_invalid" "format_fetch_cache_lines" "payload_snippet=${summary_json:0:120}"
        printf '%s' "$output"
        return 0
    fi

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == "null" ]] && continue
        local url status stored content_type path display_path
        url=$(safe_jq_from_json "$entry" '.url // ""' "" "$session_dir" "fetch_cache_entry.url")
        status=$(safe_jq_from_json "$entry" '.status // ""' "" "$session_dir" "fetch_cache_entry.status")
        stored=$(safe_jq_from_json "$entry" '.stored_at_iso // (.stored_at // "")' "" "$session_dir" "fetch_cache_entry.stored")
        [[ -z "$stored" || "$stored" == "null" ]] && stored="unknown"
        content_type=$(safe_jq_from_json "$entry" '.content_type // ""' "" "$session_dir" "fetch_cache_entry.content_type")
        path=$(safe_jq_from_json "$entry" '.path // ""' "" "$session_dir" "fetch_cache_entry.path")
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
    done < <(printf '%s' "$summary_json" | jq -c '.[]?')

    printf '%s' "$output"
}

format_search_cache_lines() {
    local summary_json="$1"
    local session_dir="$2"
    local base_dir="$3"
    local output=""

    if ! jq_validate_json "$summary_json"; then
        log_system_warning "$session_dir" "jq_cache_summary_invalid" "format_search_cache_lines" "payload_snippet=${summary_json:0:120}"
        printf '%s' "$output"
        return 0
    fi

    while IFS= read -r entry; do
        [[ -z "$entry" || "$entry" == "null" ]] && continue
        local query stored status result_count canonical snippet path display_path
        query=$(safe_jq_from_json "$entry" '.query // ""' "" "$session_dir" "search_cache_entry.query")
        stored=$(safe_jq_from_json "$entry" '.stored_at_iso // (.stored_at // "")' "" "$session_dir" "search_cache_entry.stored")
        [[ -z "$stored" || "$stored" == "null" ]] && stored="unknown"
        status=$(safe_jq_from_json "$entry" '.status // ""' "" "$session_dir" "search_cache_entry.status")
        result_count=$(safe_jq_from_json "$entry" '.result_count // 0' "0" "$session_dir" "search_cache_entry.result_count")
        canonical=$(safe_jq_from_json "$entry" '.canonical_query // ""' "" "$session_dir" "search_cache_entry.canonical")
        snippet=$(safe_jq_from_json "$entry" '.snippet_preview // ""' "" "$session_dir" "search_cache_entry.snippet")
        snippet=${snippet//$'\n'/ }
        path=$(safe_jq_from_json "$entry" '.path // ""' "" "$session_dir" "search_cache_entry.path")
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
    done < <(printf '%s' "$summary_json" | jq -c '.[]?')

    printf '%s' "$output"
}

get_search_quota_state() {
    local session_dir="$1"
    local budget_file="$session_dir/meta/budget.json"
    local used=0
    if [[ -f "$budget_file" ]]; then
        used=$(safe_jq_from_file "$budget_file" '.tool_usage.web_searches // 0' "0" "$session_dir" "search_quota.budget")
    else
        log_system_warning "$session_dir" "jq_file_missing" "search_quota.budget" "file=$budget_file"
    fi

    local max=999
    if command -v load_config >/dev/null 2>&1; then
        local config_json
        config_json=$(load_config "cconductor" 2>/dev/null || echo '{}')
        max=$(safe_jq_from_json "$config_json" '.research.max_web_searches // 999' "999" "$session_dir" "search_quota.config")
    fi

    if [[ -z "$max" || "$max" == "null" ]]; then
        max=999
    fi

    printf '%s %s' "$used" "$max"
}

# Prepare orchestrator context for invocation
prepare_orchestrator_context() {
    local session_dir="$1"
    local mission_profile="$2"
    local iteration="$3"
    trace_function "$@"
    
    # Get agent registry as JSON
    local agents_json
    if ! agents_json=$(agent_registry_export_json); then
        echo "✗ Error: Failed to export agent registry" >&2
        return 1
    fi
    
    local bash_runtime="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"
    if ! "$bash_runtime" "$PROJECT_ROOT/src/utils/mission-state-builder.sh" "$session_dir"; then
        echo "✗ Error: Failed to build mission state summary" >&2
        return 1
    fi

    local mission_state
    mission_state=$(cat "$session_dir/meta/mission_state.json" 2>/dev/null || echo '{}')

    jq -n \
        --argjson mission "$mission_profile" \
        --argjson agents "$agents_json" \
        --argjson iteration "$iteration" \
        --argjson state "$mission_state" \
        '{
            mission: $mission,
            agents: $agents,
            iteration: $iteration,
            state: $state,
            note: "For full knowledge graph or orchestration log, use the paths referenced in the state object."
        }'
}

# Invoke mission orchestrator agent
invoke_mission_orchestrator() {
    local session_dir="$1"
    local context_json="$2"
    if ! jq_validate_json "$context_json"; then
        log_system_error "$session_dir" "orchestrator_context_invalid" \
            "Invalid JSON context provided to mission orchestrator" \
            "payload_snippet=${context_json:0:200}"
        return 1
    fi
    
    # Write context to temp file
    local context_file="$session_dir/meta/orchestrator-context.json"
    echo "$context_json" > "$context_file"
    
    # Build domain compliance block for orchestrator context
    local domain_compliance_section
    domain_compliance_section=$(
        _dc_status=$(safe_jq_from_json "$context_json" '.state.domain_compliance.compliance_summary // .state.domain_compliance.status // "none"' "none" "$session_dir" "orchestrator.domain_compliance.status")
        if [[ -z "$_dc_status" || "$_dc_status" == "null" || "$_dc_status" == "none" ]]; then
            echo "No domain compliance data available."
        else
            echo "Compliance Status: $_dc_status"
            _dc_level=$(safe_jq_from_json "$context_json" '.state.domain_compliance.domain_drift.level // "none"' "none" "$session_dir" "orchestrator.domain_compliance.drift_level")
            _dc_score=$(safe_jq_from_json "$context_json" '.state.domain_compliance.domain_drift.score // ""' "" "$session_dir" "orchestrator.domain_compliance.drift_score")
            if [[ "$_dc_level" == "high" ]]; then
                echo ""
                echo "**⚠ HIGH DOMAIN DRIFT DETECTED** (score: ${_dc_score:-unknown})"
                echo "Factors:"
                _dc_factors=$(safe_jq_from_json "$context_json" '.state.domain_compliance.domain_drift.factors[]?' "" "$session_dir" "orchestrator.domain_compliance.drift_factors")
                if [[ -n "$_dc_factors" ]]; then
                    while IFS= read -r _dc_factor_line; do
                        echo "  - $_dc_factor_line"
                    done <<< "$_dc_factors"
                else
                    echo "  - (no drift factors reported)"
                fi
                _dc_recommendation=$(safe_jq_from_json "$context_json" '.state.domain_compliance.domain_drift.recommendation // "Consider re-running domain heuristics with refined scope."' "Consider re-running domain heuristics with refined scope." "$session_dir" "orchestrator.domain_compliance.recommendation")
                echo ""
                echo "Recommendation: $_dc_recommendation"
            elif [[ "$_dc_level" == "moderate" ]]; then
                echo "Note: Moderate domain drift detected (score: ${_dc_score:-unknown}). Monitor for continued expansion."
            else
                echo "Domain drift: none"
            fi
            _dc_missing_stakeholders=$(safe_jq_from_json "$context_json" '.state.domain_compliance.missing_stakeholders // [] | select(length>0) | join(", ")' "" "$session_dir" "orchestrator.domain_compliance.missing_stakeholders")
            _dc_missing_milestones=$(safe_jq_from_json "$context_json" '.state.domain_compliance.missing_milestones // [] | select(length>0) | join(", ")' "" "$session_dir" "orchestrator.domain_compliance.missing_milestones")
            if [[ -n "$_dc_missing_stakeholders" || -n "$_dc_missing_milestones" ]]; then
                echo "Gaps detected:"
                if [[ -n "$_dc_missing_stakeholders" ]]; then
                    echo "  - Missing stakeholders: $_dc_missing_stakeholders"
                fi
                if [[ -n "$_dc_missing_milestones" ]]; then
                    echo "  - Missing milestones: $_dc_missing_milestones"
                fi
            fi
        fi
    )

    # Create user message with context
    local user_message
    user_message=$(cat <<EOF
I am providing you with the mission context for this orchestration iteration.

## Mission Profile
$(safe_jq_from_json "$context_json" '.mission | tojson' '{}' "$session_dir" "orchestrator.context.mission")

## Available Agents
$(safe_jq_from_json "$context_json" '.agents | tojson' '[]' "$session_dir" "orchestrator.context.agents")

## Mission State Summary
Coverage Metrics: $(safe_jq_from_json "$context_json" '.state.coverage | tojson' '{}' "$session_dir" "orchestrator.context.coverage")
Budget Summary:
- Cost: \$$(safe_jq_from_json "$context_json" '.state.budget_summary.spent_usd' '0' "$session_dir" "orchestrator.context.budget.spent") of \$$(safe_jq_from_json "$context_json" '.state.budget_summary.budget_usd' '0' "$session_dir" "orchestrator.context.budget.limit")
- Agent invocations: $(safe_jq_from_json "$context_json" '.state.budget_summary.spent_invocations' '0' "$session_dir" "orchestrator.context.budget.invocations") of $(safe_jq_from_json "$context_json" '.state.budget_summary.max_agent_invocations' '9999' "$session_dir" "orchestrator.context.budget.invocation_limit")
- Elapsed time: $(safe_jq_from_json "$context_json" '.state.budget_summary.elapsed_minutes' '0' "$session_dir" "orchestrator.context.budget.elapsed") of $(safe_jq_from_json "$context_json" '.state.budget_summary.max_time_minutes' '9999' "$session_dir" "orchestrator.context.budget.time_limit") minutes
Quality Gate Status: $(safe_jq_from_json "$context_json" '.state.quality_gate_status' 'unknown' "$session_dir" "orchestrator.context.quality_gate")
## Domain Compliance & Drift
$(printf '%s\n' "$domain_compliance_section")
Recent Decisions (last 5): $(safe_jq_from_json "$context_json" '.state.last_5_decisions | tojson' '[]' "$session_dir" "orchestrator.context.decisions")

Important Paths (use the Read tool if you need the raw data):
- Knowledge Graph: $(safe_jq_from_json "$context_json" '.state.kg_path' 'unknown' "$session_dir" "orchestrator.context.kg_path")
- Orchestration Log: $(safe_jq_from_json "$context_json" '.state.full_log_path' 'unknown' "$session_dir" "orchestrator.context.log_path")

## Current Iteration
$(safe_jq_from_json "$context_json" '.iteration' '0' "$session_dir" "orchestrator.context.iteration")

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
            model=$(safe_jq_from_file "$orchestrator_dir/metadata.json" '.model // "claude-sonnet-4-5"' "claude-sonnet-4-5" "$session_dir" "orchestrator.metadata.model")
            
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
        local result=""
        if [[ -f "$output_file" ]] && jq empty "$output_file" >/dev/null 2>&1; then
            result=$(jq -r '.result // empty' "$output_file")
        else
            log_system_warning "$session_dir" "jq_file_parse_failure" "mission_orchestrator_output" "file=$output_file"
        fi
        
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

    local supports_sessions=false
    case "$agent_name" in
        web-researcher|academic-researcher|fact-checker|quality-remediator)
            supports_sessions=true
            ;;
    esac

    if [[ "$agent_name" == "web-researcher" ]]; then
        local used_searches max_searches
        read -r used_searches max_searches < <(get_search_quota_state "$session_dir")
        if [[ -z "$max_searches" ]]; then
            max_searches=999
        fi
        if (( used_searches >= max_searches )); then
            echo "  ⚠ Web search quota exhausted (${used_searches}/${max_searches}) - skipping $agent_name" >&2
            local quota_log
            quota_log=$(jq -n \
                --arg agent "$agent_name" \
                --argjson used "$used_searches" \
                --argjson max "$max_searches" \
                '{tool: "WebSearch", skipped_agent: $agent, used: $used, max: $max}')
            log_decision "$session_dir" "web_search_quota_exhausted" "$quota_log"
            return 0
        fi
    fi

    # Note: verbose_agent_start is called by invoke_agent_v2, no need to call here

    if [[ "$agent_name" == "synthesis-agent" && -f "$session_dir/meta/domain-heuristics.json" ]]; then
        if [[ -z "$input_artifacts" || "$input_artifacts" == "[]" ]]; then
            input_artifacts='["meta/domain-heuristics.json"]'
        else
            input_artifacts=$(safe_jq_from_json "$input_artifacts" 'if (map(. == "meta/domain-heuristics.json") | any) then . else . + ["meta/domain-heuristics.json"] end' '["meta/domain-heuristics.json"]' "$session_dir" "agent_input.input_artifacts" false)
        fi
    fi

    # Sanitize task for safe export and display
    # This is for verbose output only - the full task still goes to the input file
    local task_display
    task_display=$(printf '%s' "$task" | tr '\n' ' ' | cut -c1-150 | sed 's/[`$"\\]/\\&/g')
    export CCONDUCTOR_TASK_DESC="$task_display"
    
    # Normalize artifact paths (convert absolute session paths to relative)
    if [[ -n "$input_artifacts" && "$input_artifacts" != "[]" ]] && jq_validate_json "$input_artifacts"; then
        local normalized_artifacts
        normalized_artifacts=$(printf '%s' "$input_artifacts" | jq \
            --arg base "$session_dir/" \
            'map(
                if type == "string" then
                    (if startswith($base) then sub($base; "")
                     elif startswith("./") then sub("^\\./"; "")
                     else .
                    end)
                else .
                end
            )')
        if [[ -n "$normalized_artifacts" ]]; then
            input_artifacts="$normalized_artifacts"
        fi
    fi

    # Build agent input message
    # Process input_artifacts JSON array into readable format
    local artifacts_section
    if [[ "$input_artifacts" == "[]" || -z "$input_artifacts" ]]; then
        artifacts_section="None"
    else
        # Parse JSON array and format as list
        if jq_validate_json "$input_artifacts"; then
            artifacts_section=$(printf '%s' "$input_artifacts" | jq -r '.[]?' | while IFS= read -r artifact_path; do
                local display_path="$artifact_path"
                if [[ "$display_path" == /* ]]; then
                    if [[ "$display_path" == "$session_dir/"* ]]; then
                        display_path="${display_path#"$session_dir"/}"
                    fi
                fi
                local session_path="$session_dir/$display_path"
                if [[ -f "$session_path" ]]; then
                    echo "- $display_path (available - use Read tool to access)"
                elif [[ -f "$artifact_path" ]]; then
                    echo "- $artifact_path (available - use Read tool to access)"
                else
                    echo "- $artifact_path (ERROR: file not found)"
                fi
            done)
        else
            log_system_warning "$session_dir" "jq_json_parse_failure" "agent_input.artifacts" "payload_snippet=${input_artifacts:0:200}"
            artifacts_section=""
        fi

        # If parsing failed, show the raw value
        if [[ -z "$artifacts_section" ]]; then
            artifacts_section="$input_artifacts (format error - expected JSON array)"
        fi
    fi
    
    # Add output specification for synthesis-agent
    local output_spec_section=""
    if [[ "$agent_name" == "synthesis-agent" ]]; then
        local output_spec
        output_spec=$(safe_jq_from_file "$session_dir/meta/session.json" '.output_specification // ""' "" "$session_dir" "agent_input.output_spec")
        if [[ -n "$output_spec" && "$output_spec" != "null" ]]; then
            output_spec_section=$(cat <<SPEC_EOF

## User's Output Format Requirements
$output_spec
SPEC_EOF
)
        fi
    fi
    
    local context_section=""
    if [[ -n "$context" && "$context" != "null" ]]; then
        context_section=$'\n''## Context\n'"$context"$'\n'
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
## Task
$task${context_section}
## Input Artifacts
$artifacts_section${output_spec_section}${cache_section}
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
                agent_model=$(safe_jq_from_file "$agent_metadata" '.model // "claude-sonnet-4-5"' "claude-sonnet-4-5" "$session_dir" "agent_registry.model")
                
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
    
    local invocation_status=0
    if [[ "$supports_sessions" == "true" ]]; then
        if has_agent_session "$agent_name" "$session_dir"; then
            if continue_agent_session "$agent_name" "$session_dir" "$agent_input" "$agent_output_file"; then
                invocation_status=0
            else
                invocation_status=$?
            fi
        else
            if start_agent_session "$agent_name" "$session_dir" "$agent_input" "$agent_output_file"; then
                invocation_status=0
            else
                invocation_status=$?
            fi
        fi
    else
        if invoke_agent_v2 "$agent_name" "$agent_input_file" "$agent_output_file" 600 "$session_dir"; then
            invocation_status=0
        else
            invocation_status=$?
        fi
    fi

    if [[ $invocation_status -eq 0 ]]; then
        local end_time
        end_time=$(get_epoch)
        local duration=$((end_time - start_time))
        
        echo "  ✓ $agent_name completed ($duration seconds)"
        
        # Extract cost from agent output
        local cost
        cost=$(extract_cost_from_output "$agent_output_file")
        
        # Extract result
        local result=""
        if [[ -f "$agent_output_file" ]] && jq empty "$agent_output_file" >/dev/null 2>&1; then
            result=$(jq -r '.result // empty' "$agent_output_file")
        else
            log_system_warning "$session_dir" "jq_file_parse_failure" "agent_output.result" "file=$agent_output_file"
        fi
        
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
        local exit_code=$invocation_status
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
# Ensures report/mission-report.md is created and checks for incremental workflow artifacts
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
    
    # Check if incremental sections were created (indicates tool calls were made)
    local sections_dir="$session_dir/report/sections"
    local section_plan="$session_dir/work/synthesis-agent/section-plan.json"
    
    if [[ -f "$section_plan" ]]; then
        echo "  ✓ Synthesis used incremental workflow (section plan found)" >&2
    fi
    
    if [[ -d "$sections_dir" ]]; then
        local section_count
        section_count=$(find "$sections_dir" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ $section_count -gt 0 ]]; then
            echo "  ✓ Synthesis outputs validated (report + $section_count section files)" >&2
        else
            echo "  ✓ Synthesis outputs validated (report/mission-report.md)" >&2
        fi
    else
        echo "  ✓ Synthesis outputs validated (report/mission-report.md)" >&2
    fi
    
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
        action=$(safe_jq_from_json "$extracted_json" '.action // empty' "" "" "orchestrator.extract_decision")
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
            friendly_name=$(safe_jq_from_file "$metadata_file" '.display_name // empty' "" "$session_dir" "agent_metadata.display_name")
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
    decision_action=$(safe_jq_from_json "$decision_json" '.action // ""' "" "$session_dir" "orchestrator.decision.action")
    
    # Verbose: Show what the orchestrator decided
    if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
        case "$decision_action" in
            invoke)
                local agent_for_msg
                agent_for_msg=$(safe_jq_from_json "$decision_json" '.agent // ""' "" "$session_dir" "orchestrator.decision.agent_display")
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
            agent_name=$(safe_jq_from_json "$decision_json" '.agent // ""' "" "$session_dir" "orchestrator.decision.agent")
            local task
            task=$(safe_jq_from_json "$decision_json" '.task // ""' "" "$session_dir" "orchestrator.decision.task")
            local context
            context=$(safe_jq_from_json "$decision_json" '.context // "No additional context"' "No additional context" "$session_dir" "orchestrator.decision.context")
            local input_artifacts
            input_artifacts=$(safe_jq_from_json "$decision_json" '.input_artifacts // []' '[]' "$session_dir" "orchestrator.decision.input_artifacts" false)

            local attempt_num
            attempt_num=$(safe_jq_from_json "$decision_json" '.attempt // 1' "1" "$session_dir" "orchestrator.decision.attempt")
            local needs_synthesis="false"
            if [[ "$agent_name" == "synthesis-agent" ]]; then
                needs_synthesis="true"
            fi
            debug "Invoking agent $agent_name (attempt $attempt_num)"
            debug "Synthesis evaluation: needs_synthesis=$needs_synthesis"
            
            # Log the decision with proper format for journal export
            local rationale
            rationale=$(safe_jq_from_json "$decision_json" '.rationale // ""' "" "$session_dir" "orchestrator.decision.rationale")
            local alternatives
            alternatives=$(safe_jq_from_json "$decision_json" '.alternatives_considered // []' '[]' "$session_dir" "orchestrator.decision.alternatives" false)
            local expected_impact
            expected_impact=$(safe_jq_from_json "$decision_json" '.expected_impact // ""' "" "$session_dir" "orchestrator.decision.expected_impact")
            
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
                local gate_iteration="${iteration:-unknown}"
                debug "Checking quality gate: iteration=$gate_iteration"
                echo "→ Running quality gate before synthesis..."
                if ! run_quality_assurance_cycle "$session_dir"; then
                    # Get mode to display appropriate message
                    local gate_mode
                    if command -v load_config &>/dev/null; then
                        local gate_config_json
                        gate_config_json=$(load_config "quality-gate" 2>/dev/null || echo '{}')
                        gate_mode=$(safe_jq_from_json "$gate_config_json" '.mode // "advisory"' "advisory" "$session_dir" "quality_gate.config_mode")
                    else
                        gate_mode="advisory"
                    fi
                    
                    if [[ "$gate_mode" == "advisory" ]]; then
                        echo "⚠ Quality gate flagged claims (advisory mode - proceeding with synthesis)" >&2
                        # Log but don't block
                        log_decision "$session_dir" "synthesis_proceeding_despite_gate" \
                            "$(echo "$orchestrator_output" | jq --arg mode "$gate_mode" \
                            '. + {quality_gate_status: "failed", mode: $mode, proceeding: true}')"
                    else
                        echo "⚠ Quality gate blocked synthesis (enforce mode)" >&2
                        log_decision "$session_dir" "synthesis_blocked_quality_gate" \
                            "$(echo "$orchestrator_output" | jq '. + {quality_gate_status: "failed", mode: "enforce"}')"
                        # Return without invoking synthesis in enforce mode
                        return 0
                    fi
                else
                    echo "  ✓ Quality gate passed, proceeding with synthesis"
                fi
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
            debug "Agent reinvocation: agent=$agent_name, reason=$reason"
            
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
            from_agent=$(safe_jq_from_json "$decision_json" '.from_agent // ""' "" "$session_dir" "orchestrator.decision.from_agent")
            local to_agent
            to_agent=$(safe_jq_from_json "$decision_json" '.to_agent // ""' "" "$session_dir" "orchestrator.decision.to_agent")
            local task
            task=$(safe_jq_from_json "$decision_json" '.task // ""' "" "$session_dir" "orchestrator.decision.handoff_task")
            local input_artifacts
            input_artifacts=$(safe_jq_from_json "$decision_json" '.input_artifacts // []' '[]' "$session_dir" "orchestrator.decision.handoff_artifacts" false)
            local rationale
            rationale=$(safe_jq_from_json "$decision_json" '.rationale // "Handoff requested"' "Handoff requested" "$session_dir" "orchestrator.decision.handoff_rationale")
            
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
            reason=$(safe_jq_from_json "$decision_json" '.reason // ""' "" "$session_dir" "orchestrator.decision.early_exit_reason")
            
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
    local bash_runtime="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"
    "$bash_runtime" "$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh" "$session_dir" > /dev/null 2>&1
    
    # Check actual status from the summary file
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        local status
        status=$(safe_jq_from_file "$session_dir/artifacts/quality-gate-summary.json" '.status // "unknown"' "unknown" "$session_dir" "quality_gate.run_status")
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

announce_uncategorized_sources() {
    local session_dir="$1"
    local summary_file="$session_dir/artifacts/quality-gate-summary.json"
    if [[ ! -f "$summary_file" ]]; then
        return 0
    fi

    local uncategorized_count
    uncategorized_count=$(safe_jq_from_file "$summary_file" '.uncategorized_sources.count // 0' "0" "$session_dir" "quality_gate.uncategorized_count")
    if [[ "$uncategorized_count" -gt 0 ]]; then
        echo "  ⚠ Note: $uncategorized_count uncategorized sources detected"
        echo "     Review: artifacts/quality-gate-summary.json"
        echo "     Action: Add patterns to ~/.config/cconductor/stakeholder-patterns.json if needed"
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
            --arg attempt "$attempt_value" \
            --arg mode "$mode_value" \
            --arg status "$status_value" \
            --arg summary "$summary_file" \
            --arg report "$report_file" \
            '{
                attempt: ($attempt | tonumber? // 0),
                mode: $mode,
                status: $status,
                summary_file: (if $summary == "" then null else $summary end),
                report_file: (if $report == "" then null else $report end)
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
    local remediation_config
    remediation_config=$(echo "$quality_config" | jq '.remediation // {}')
    
    local gate_mode
    gate_mode=$(echo "$quality_config" | jq -r '.mode // "advisory"')
    
    local max_attempts
    max_attempts=$(echo "$quality_config" | jq -r '.remediation.max_attempts // 2')
    
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_quality_gate_event "$session_dir" "quality_gate_started" "$attempt" "$gate_mode" "running"
        # Run quality gate
        if run_quality_gate "$session_dir"; then
            announce_uncategorized_sources "$session_dir"
            verbose "✓ Quality gate passed"
            log_quality_gate_event "$session_dir" "quality_gate_completed" "$attempt" "$gate_mode" "passed" "artifacts/quality-gate-summary.json" "artifacts/quality-gate.json"
            
            # Sync gate results to KG (optional, fails gracefully)
            if command -v sync_quality_surfaces_to_kg &>/dev/null; then
                local kg_file="$session_dir/knowledge/knowledge-graph.json"
                local claims_count=0
                if [[ -f "$kg_file" ]]; then
                    claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' "0" "$session_dir" "quality_gate.claims_count")
                fi
                sync_quality_surfaces_to_kg "$session_dir" "artifacts/quality-gate.json" || true
                record_quality_gate_run "$session_dir" "$(get_timestamp)" "$claims_count" "artifacts/quality-gate.json" || true
            fi
            
            return 0
        fi
        announce_uncategorized_sources "$session_dir"
        log_quality_gate_event "$session_dir" "quality_gate_completed" "$attempt" "$gate_mode" "failed" "artifacts/quality-gate-summary.json" "artifacts/quality-gate.json"
        
        # Sync gate results to KG even on failure (partial results useful)
        if command -v sync_quality_surfaces_to_kg &>/dev/null; then
            local kg_file="$session_dir/knowledge/knowledge-graph.json"
            local claims_count=0
            if [[ -f "$kg_file" ]]; then
                claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' "0" "$session_dir" "quality_gate.claims_count")
            fi
            sync_quality_surfaces_to_kg "$session_dir" "artifacts/quality-gate.json" || true
            record_quality_gate_run "$session_dir" "$(get_timestamp)" "$claims_count" "artifacts/quality-gate.json" || true
        fi

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

        local min_budget
        min_budget=$(echo "$remediation_config" | jq -r '.min_remaining_budget_usd // 0')
        local min_invocations
        min_invocations=$(echo "$remediation_config" | jq -r '.min_remaining_invocations // 0')
        local min_minutes
        min_minutes=$(echo "$remediation_config" | jq -r '.min_remaining_minutes // 0')

        local budget_state
        if ! budget_state=$(budget_status "$session_dir"); then
            log_warn "Unable to read budget state for remediation"
            return 1
        fi

        local remaining_budget
        remaining_budget=$(echo "$budget_state" | jq -r '((.limits.budget_usd // 0) - (.spent.cost_usd // 0))')
        local remaining_invocations
        remaining_invocations=$(echo "$budget_state" | jq -r '((.limits.max_agent_invocations // 0) - (.spent.agent_invocations // 0))')
        local remaining_minutes
        remaining_minutes=$(echo "$budget_state" | jq -r '((.limits.max_time_minutes // 0) - (.spent.elapsed_minutes // 0))')

        if awk -v rem="$remaining_budget" -v min="$min_budget" 'BEGIN { if (min > 0 && rem < min) exit 0; exit 1 }'; then
            log_warn "Insufficient budget for remediation (need $min_budget USD, have $remaining_budget USD)"
            return 1
        fi

        if [[ ${min_invocations:-0} -gt 0 ]] && [[ ${remaining_invocations:-0} -lt ${min_invocations:-0} ]]; then
            log_warn "Insufficient agent invocations left for remediation (need $min_invocations, have $remaining_invocations)"
            return 1
        fi

        if [[ ${min_minutes:-0} -gt 0 ]] && [[ ${remaining_minutes:-0} -lt ${min_minutes:-0} ]]; then
            log_warn "Insufficient time remaining for remediation (need $min_minutes minutes, have $remaining_minutes minutes)"
            return 1
        fi

        local failure_reason=""
        if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
            failure_reason=$(safe_jq_from_file "$session_dir/artifacts/quality-gate-summary.json" '.primary_issue // ""' "" "$session_dir" "quality_gate.failure_reason")
            local failure_reason_lower
            failure_reason_lower=$(echo "$failure_reason" | tr '[:upper:]' '[:lower:]')
            case "$failure_reason_lower" in
                *"peer-reviewed sources"*|*"no sources available"*)
                    log_warn "Quality gate failure is non-actionable: $failure_reason"
                    return 1
                    ;;
            esac
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
            local remediator_exit_code=$?
            
            # Distinguish timeout from other failures
            if [[ $remediator_exit_code -eq 124 ]]; then
                log_warn "Quality remediator timed out (no activity detected) - continuing to next attempt"
                # Don't return 1 for timeout - allow retry on next attempt
            else
                log_warn "Quality remediator invocation failed (exit code: $remediator_exit_code)"
                return 1
            fi
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
    
    # 2. Check quality gate with mode awareness
    if [[ -f "$session_dir/artifacts/quality-gate-summary.json" ]]; then
        local gate_status gate_mode
        gate_status=$(safe_jq_from_file "$session_dir/artifacts/quality-gate-summary.json" '.status // "unknown"' "unknown" "$session_dir" "quality_gate.summary_status")
        gate_mode=$(safe_jq_from_file "$session_dir/artifacts/quality-gate-summary.json" '.mode // "advisory"' "advisory" "$session_dir" "quality_gate.summary_mode")
        
        if [[ "$gate_status" == "passed" ]]; then
            quality_gate_passed=true
        elif [[ "$gate_mode" == "advisory" ]]; then
            # Advisory mode: don't block completion
            quality_gate_passed=true
        fi
    else
        # Quality gate hasn't run yet - not a failure
        quality_gate_passed=true
    fi
    
    # 3. Check high-priority gaps (≥8)
    local unresolved_gaps
    unresolved_gaps=$(safe_jq_from_file "$session_dir/knowledge/knowledge-graph.json" '[.gaps[]? | select(.priority >= 8 and (.status // "unresolved") != "resolved")] | length' "0" "$session_dir" "mission_completion.unresolved_gaps")
    if [[ "$unresolved_gaps" -eq 0 ]]; then
        high_priority_gaps_resolved=true
    fi
    
    # 4. Check required outputs exist in artifacts
    local required_outputs
    required_outputs=$(safe_jq_from_json "$mission_profile" '.success_criteria.required_outputs[]?' "" "$session_dir" "mission_completion.required_outputs")
    
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
                --arg planning "$planning_done" \
                --arg quality "$quality_gate_passed" \
                --arg gaps "$high_priority_gaps_resolved" \
                --arg outputs "$required_outputs_present" \
                --arg early_exit "true" \
                '{
                    planning_done: ($planning == "true"),
                    quality_gate_passed: ($quality == "true"),
                    gaps_resolved: ($gaps == "true"),
                    outputs_present: ($outputs == "true"),
                    early_exit_requested: $early_exit
                }')"
            return 0  # Complete (early exit)
        fi
    fi
    
    # Log completion verification
    log_decision "$session_dir" "completion_verification" "$(jq -n \
        --arg planning "$planning_done" \
        --arg quality "$quality_gate_passed" \
        --arg gaps "$high_priority_gaps_resolved" \
        --arg outputs "$required_outputs_present" \
        '{
            planning_done: ($planning == "true"),
            quality_gate_passed: ($quality == "true"),
            gaps_resolved: ($gaps == "true"),
            outputs_present: ($outputs == "true")
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

    # Mission objective cached for logging + heuristics agent
    local objective
    objective=$(safe_jq_from_file "$session_dir/meta/session.json" '.objective // "Unknown"' "Unknown" "$session_dir" "mission_summary.objective")

    echo "→ Analyzing domain requirements..."
    if [[ -f "$session_dir/meta/domain-heuristics.json" ]]; then
        echo "  ✓ Domain heuristics already available (resume)"
    elif agent_registry_exists "domain-heuristics"; then
        local heuristics_task heuristics_context mission_summary
    mission_summary=$(safe_jq_from_json "$mission_profile" '{name: .name, success_criteria: .success_criteria, constraints: .constraints} | tojson' '{}' "$session_dir" "mission_summary.profile")
        heuristics_task=$(cat <<EOF
Analyze the mission objective below and produce domain-heuristics.json plus domain-heuristics.kg.lock inside artifacts/domain-heuristics/.
Focus on stakeholder taxonomy, freshness requirements, mandatory watch items, and synthesis guidance using the documented schema.

Mission Objective: $objective
EOF
)
        heuristics_context=$(cat <<EOF
Mission profile snapshot:
$mission_summary
EOF
)

        if _invoke_delegated_agent "$session_dir" "domain-heuristics" "$heuristics_task" "$heuristics_context" "[]"; then
            process_agent_kg_artifacts "$session_dir" "domain-heuristics" >/dev/null 2>&1 || true
            if [[ -f "$session_dir/artifacts/domain-heuristics/domain-heuristics.json" ]]; then
                mkdir -p "$session_dir/meta"
                cp "$session_dir/artifacts/domain-heuristics/domain-heuristics.json" "$session_dir/meta/domain-heuristics.json"
                echo "  ✓ Domain requirements established"
            else
                echo "  ⚠ Domain heuristics agent did not produce expected output"
            fi
        else
            echo "  ⚠ Domain heuristics agent failed, using defaults"
        fi
    else
        echo "  ⚠ Domain heuristics agent not found, using defaults"
    fi
    echo ""
    
    # Log mission start event for journal
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
                log_system_error "$session_dir" "dashboard_launch" "Dashboard viewer failed to launch"
                echo "  ⚠ Dashboard viewer failed (check logs/system-errors.log)" >&2
            fi
        else
            log_system_error "$session_dir" "dashboard_source" "Failed to source dashboard.sh"
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
        kg_current=$(safe_jq_from_file "$session_dir/knowledge/knowledge-graph.json" '.iteration // 0' "0" "$session_dir" "dashboard.kg_iteration")
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
            if ! source "$UTILS_DIR/prompt-parser-handler.sh" 2>/dev/null; then
                if [[ -z "${MISSION_ORCH_PROMPT_PARSER_WARNED:-}" ]]; then
                    log_warn "Optional prompt-parser-handler.sh failed to load (prompt parsing disabled)"
                    MISSION_ORCH_PROMPT_PARSER_WARNED=1
                fi
            fi
            
            if command -v needs_prompt_parsing &>/dev/null && needs_prompt_parsing "$session_dir"; then
                if command -v parse_prompt &>/dev/null; then
                    parse_prompt "$session_dir" || true
                    echo ""
                fi
            fi
        fi

        if [[ -f "$UTILS_DIR/domain-compliance-check.sh" && -f "$session_dir/meta/domain-heuristics.json" && $iteration -gt 1 ]]; then
            echo "→ Checking domain requirements compliance..."
            local compliance_report compliance_status
            local bash_runtime="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"
            if compliance_report=$("$bash_runtime" "$UTILS_DIR/domain-compliance-check.sh" "$session_dir" 2>/dev/null); then
                compliance_status=$(safe_jq_from_json "$compliance_report" '.compliance_summary // "unknown"' "unknown" "$session_dir" "domain_compliance.report_status")
                if [[ "$compliance_status" == "gaps_detected" ]]; then
                    if command -v log_event &>/dev/null; then
                        log_event "$session_dir" "domain_compliance_gap" "$compliance_report"
                    fi
                    echo "  ⚠ Domain compliance gaps detected (orchestrator will address)"
                else
                    echo "  ✓ Domain requirements on track"
                fi
            else
                echo "  ⚠ Compliance check failed, skipping"
            fi
            echo ""
        fi

        # Check budget before proceeding
        if ! budget_check "$session_dir"; then
            log_system_warning "$session_dir" "budget_limit" "Budget limit reached at iteration $iteration"
            echo ""
            echo "⚠ Budget limit reached - generating partial results"
            break
        fi
        debug "Budget check passed for iteration $iteration"
        
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
        export_journal "$session_dir" "$session_dir/report/research-journal.md" >/dev/null || echo "  ⚠️  Warning: Could not generate research journal"
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
    local cost_events
    cost_events=$(grep '"type":"agent_result"' "$session_dir/logs/events.jsonl" 2>/dev/null || true)
    if [[ -n "$cost_events" ]]; then
        if ! total_cost=$(printf '%s\n' "$cost_events" | jq -s 'map(.data.cost_usd // 0) | add' 2>/dev/null); then
            log_system_warning "$session_dir" "jq_stream_parse_failure" "mission_metrics.total_cost" "file=$session_dir/logs/events.jsonl"
            total_cost="0"
        fi
    else
        total_cost="0"
    fi
    
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

    local latest_marker_path
    latest_marker_path="$(dirname "$session_dir")/.latest"
    if ! printf '%s\n' "$(basename "$session_dir")" > "$latest_marker_path" 2>/dev/null; then
        log_warn "Failed to update latest session marker at $latest_marker_path"
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
    local extend_iterations="${4:-}"
    local extend_time="${5:-}"
    
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
        local orchestration_lines
        orchestration_lines=$(awk 'NF{print}' "$session_dir/logs/orchestration.jsonl" 2>/dev/null || true)
        if [[ -n "$orchestration_lines" ]]; then
            local parsed_iterations
            if parsed_iterations=$(printf '%s\n' "$orchestration_lines" | jq -r 'select(.decision.iteration!=null) | .decision.iteration' 2>/dev/null); then
                current_iteration=$(printf '%s\n' "$parsed_iterations" | tail -1)
            else
                log_system_warning "$session_dir" "jq_stream_parse_failure" "resume.iteration_extract" "file=$session_dir/logs/orchestration.jsonl"
                current_iteration=""
            fi
        fi
        
        # Fallback to line count if no iteration found
        if [ -z "$current_iteration" ] || [ "$current_iteration" = "null" ]; then
            current_iteration=$(wc -l < "$session_dir/logs/orchestration.jsonl" | tr -d ' ')
        fi
    fi
    
    local max_iterations
    max_iterations=$(echo "$mission_profile" | jq -r '.constraints.max_iterations')
    
    local max_time_minutes
    max_time_minutes=$(echo "$mission_profile" | jq -r '.constraints.max_time_minutes')
    
    # Apply extensions if provided
    local extensions_applied=false
    if [ -n "$extend_iterations" ] && [ "$extend_iterations" -gt 0 ]; then
        max_iterations=$((max_iterations + extend_iterations))
        echo "  Extended max iterations to $max_iterations (added $extend_iterations)"
        extensions_applied=true
    fi
    
    if [ -n "$extend_time" ] && [ "$extend_time" -gt 0 ]; then
        max_time_minutes=$((max_time_minutes + extend_time))
        echo "  Extended max time to $max_time_minutes minutes (added $extend_time)"
        extensions_applied=true
    fi
    
    # Update mission profile with extended constraints for budget_check
    if [ "$extensions_applied" = true ]; then
        mission_profile=$(echo "$mission_profile" | jq \
            --argjson max_iter "$max_iterations" \
            --argjson max_time "$max_time_minutes" \
            '.constraints.max_iterations = $max_iter | .constraints.max_time_minutes = $max_time')
        
        # Update budget limits in the persisted budget file
        if command -v budget_extend_limits &>/dev/null; then
            budget_extend_limits "$session_dir" "$extend_iterations" "$extend_time" || \
                log_warn "Failed to update budget limits - budget checks may be incorrect"
        fi
    fi
    
    local iteration=$((current_iteration + 1))
    
    echo "  Continuing from iteration $iteration/$max_iterations"
    
    # Check if iterations already exhausted
    if [[ $iteration -gt $max_iterations ]]; then
        echo ""
        echo "⚠ Session has already completed all iterations ($current_iteration original limit)"
        echo ""
        echo "This session cannot be resumed without extending the iteration limit."
        echo ""
        echo "Options:"
        echo "  1. Resume with additional iterations/time:"
        echo "     ./cconductor sessions resume $(basename "$session_dir") --extend-iterations 5"
        echo "     ./cconductor sessions resume $(basename "$session_dir") --extend-time 30"
        echo ""
        echo "  2. Start a new session with the same query:"
        local restart_objective
        restart_objective=$(safe_jq_from_file "$session_dir/meta/session.json" '.objective // ""' "" "$session_dir" "resume_hint.objective")
        echo "     ./cconductor \"$restart_objective\""
        echo ""
        echo "  3. View the existing research:"
        echo "     ./cconductor sessions viewer $(basename "$session_dir")"
        echo ""
        return 0
    fi
    
    # Launch dashboard if not already running
    if [ ! -f "$session_dir/.dashboard-server.pid" ]; then
        echo "→ Launching Research Journal Viewer..."
        # shellcheck disable=SC1091
        if source "$UTILS_DIR/dashboard.sh"; then
            if ! dashboard_view "$session_dir"; then
                log_system_error "$session_dir" "dashboard_refresh" "Dashboard refresh failed on resume"
            fi
        else
            log_system_error "$session_dir" "dashboard_source" "Failed to source dashboard.sh on resume"
        fi
    fi
    
    echo ""
    
    # Continue orchestration loop
    while [[ $iteration -le $max_iterations ]]; do
        # Sync KG iteration with mission iteration FIRST (before any work)
        # This ensures dashboard always shows the current iteration number
        local kg_current
        kg_current=$(safe_jq_from_file "$session_dir/knowledge/knowledge-graph.json" '.iteration // 0' "0" "$session_dir" "resume_dashboard.kg_iteration")
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
            log_system_warning "$session_dir" "budget_limit" "Budget limit reached at iteration $iteration (resume)"
            echo ""
            echo "⚠ Budget limit reached"
            break
        fi
        debug "Budget check passed for iteration $iteration"
        
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
        export_journal "$session_dir" "$session_dir/report/research-journal.md" >/dev/null || echo "  ⚠️  Warning: Could not generate research journal"
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
    local cost_events
    cost_events=$(grep '"type":"agent_result"' "$session_dir/logs/events.jsonl" 2>/dev/null || true)
    if [[ -n "$cost_events" ]]; then
        if ! total_cost=$(printf '%s\n' "$cost_events" | jq -s 'map(.data.cost_usd // 0) | add' 2>/dev/null); then
            log_system_warning "$session_dir" "jq_stream_parse_failure" "mission_metrics.total_cost" "file=$session_dir/logs/events.jsonl"
            total_cost="0"
        fi
    else
        total_cost="0"
    fi
    
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

    local latest_marker_path
    latest_marker_path="$(dirname "$session_dir")/.latest"
    if ! printf '%s\n' "$(basename "$session_dir")" > "$latest_marker_path" 2>/dev/null; then
        log_warn "Failed to update latest session marker at $latest_marker_path"
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
    trace_function "$@"
    
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
    if ! jq_validate_json "$kg_json"; then
        log_system_warning "$session_dir" "jq_json_parse_failure" "dashboard.kg_read" "payload_snippet=${kg_json:0:200}"
        kg_json='{}'
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
    coverage_summary=$(safe_jq_from_json "$kg_json" '
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
    ' '[]' "$session_dir" "dashboard.kg.coverage" false)
    
    # Extract high-priority gaps (≥8)
    local high_priority_gaps_count
    high_priority_gaps_count=$(safe_jq_from_json "$kg_json" '[.gaps[]? | select(.priority >= 8)] | length' "0" "$session_dir" "dashboard.kg.high_priority_gaps")
    
    # Get list of high-priority gaps for context
    local high_priority_gaps_list
    high_priority_gaps_list=$(safe_jq_from_json "$kg_json" '
        [.gaps[]? | select(.priority >= 8) | {
            description: .description,
            priority: .priority,
            status: (.status // "unresolved")
        }]
    ' '[]' "$session_dir" "dashboard.kg.high_priority_gaps_list" false)
    
    # Check if quality gate has run
    local quality_gate_status="not_run"
    local quality_gate_summary="{}"
    local quality_gate_mode="advisory"
    local summary_path="$session_dir/artifacts/quality-gate-summary.json"
    if [[ -f "$summary_path" ]]; then
        quality_gate_status=$(safe_jq_from_file "$summary_path" '.status // "unknown"' "unknown" "$session_dir" "dashboard.quality_gate_status")
        # Ensure we get valid JSON, default to empty object if file is invalid
        if jq empty "$summary_path" >/dev/null 2>&1; then
            quality_gate_summary=$(jq -c '.' "$summary_path")
        else
            log_system_warning "$session_dir" "jq_file_parse_failure" "dashboard.quality_gate_summary" "file=$summary_path"
        fi
    fi
    if command -v load_config &>/dev/null; then
        local gate_config_json
        gate_config_json=$(load_config "quality-gate" 2>/dev/null || echo '{}')
        quality_gate_mode=$(safe_jq_from_json "$gate_config_json" '.mode // "advisory"' "advisory" "$session_dir" "dashboard.quality_gate_mode")
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
