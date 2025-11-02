#!/usr/bin/env bash
# Prompt Parser Handler
# Handles prompt parsing through the orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-parser.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
if ! declare -F log_event >/dev/null; then
    source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null || true
fi

_prompt_parser_record_artifact_fallback() {
    local session_dir="$1"
    local reason="$2"

    if command -v log_warn >/dev/null 2>&1; then
        log_warn "Prompt parser artifact fallback: $reason"
    else
        echo "  ⚠ Prompt parser artifact fallback: $reason" >&2
    fi

    if command -v log_event >/dev/null 2>&1; then
        local payload
        payload=$(jq -n \
            --arg agent "prompt-parser" \
            --arg reason "$reason" \
            '{agent: $agent, reason: $reason}')
        log_event "$session_dir" "prompt_parser.artifact_fallbacks" "$payload" || true
    fi
}

_prompt_parser_update_session_state() {
    local session_dir="$1"
    local objective="$2"
    local output_spec="$3"

    local session_file="$session_dir/meta/session.json"
    local temp_session="${session_file}.tmp"

    jq --arg obj "$objective" \
       --arg spec "$output_spec" \
       '.objective = $obj |
        .output_specification = (
            if $spec == "__CCONDUCTOR_NULL__" or $spec == "" then null
            else $spec
            end
        ) |
        .prompt_parsed = true' \
       "$session_file" > "$temp_session"
    mv "$temp_session" "$session_file"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    if [[ -f "$kg_file" ]]; then
        local temp_kg="${kg_file}.tmp"
        jq --arg obj "$objective" \
           '.research_objective = $obj' \
           "$kg_file" > "$temp_kg"
        mv "$temp_kg" "$kg_file"
    fi
}

_prompt_parser_apply_json_artifact() {
    local session_dir="$1"
    local artifact_path="$session_dir/artifacts/prompt-parser/output.json"

    if [[ ! -f "$artifact_path" ]]; then
        return 1
    fi

    local extracted
    extracted=$(jq -c '
        if type != "object" then empty else
        {
            objective: (.objective // empty),
            output_specification: (if has("output_specification") then .output_specification else null end),
            research_question: (.research_question // empty)
        }
    ' "$artifact_path" 2>/dev/null || echo "")

    if [[ -z "$extracted" ]]; then
        return 1
    fi

    local objective
    objective=$(echo "$extracted" | jq -r '.objective // empty')
    local output_spec_raw
    output_spec_raw=$(echo "$extracted" | jq -r '
        if (.output_specification | type) == "null" then "__CCONDUCTOR_NULL__"
        else (.output_specification // empty)
        end
    ')
    local research_question
    research_question=$(echo "$extracted" | jq -r '.research_question // empty')

    if [[ -z "$objective" || -z "$research_question" ]]; then
        return 1
    fi

    _prompt_parser_update_session_state "$session_dir" "$objective" "$output_spec_raw"
    return 0
}

_prompt_parser_apply_legacy_result() {
    local session_dir="$1"
    local agent_output="$session_dir/work/prompt-parser/output.json"

    if [[ ! -f "$agent_output" ]]; then
        return 1
    fi

    local result
    if ! result=$(safe_jq_from_file "$agent_output" '.result // empty' "" "$session_dir" "prompt_parser.agent_result" "true"); then
        result=""
    fi

    if [[ -z "$result" ]]; then
        return 1
    fi

    local parsed_json=""
    if command -v extract_json_from_text &>/dev/null; then
        parsed_json=$(extract_json_from_text "$result" 2>/dev/null || echo "")
    else
        parsed_json="$result"
    fi

    if [[ -z "$parsed_json" ]]; then
        return 1
    fi

    if ! echo "$parsed_json" | jq empty >/dev/null 2>&1; then
        return 1
    fi

    local objective
    objective=$(echo "$parsed_json" | jq -r '.objective // empty' 2>/dev/null)
    local output_spec_raw
    output_spec_raw=$(echo "$parsed_json" | jq -r '
        if (.output_specification // empty) == "" then "__CCONDUCTOR_NULL__"
        elif .output_specification == null then "__CCONDUCTOR_NULL__"
        else .output_specification
        end
    ' 2>/dev/null)

    if [[ -z "$objective" ]]; then
        return 1
    fi

    _prompt_parser_update_session_state "$session_dir" "$objective" "$output_spec_raw"
    return 0
}

# Check if prompt needs parsing
needs_prompt_parsing() {
    local session_dir="$1"
    local session_file="$session_dir/meta/session.json"
    
    if [ ! -f "$session_file" ]; then
        return 1
    fi
    
    local prompt_parsed
    if prompt_parsed=$(safe_jq_from_file "$session_file" '.prompt_parsed // false' "false" "$session_dir" "prompt_parser.prompt_parsed" "true"); then
        :
    else
        prompt_parsed="false"
    fi
    
    if [ "$prompt_parsed" = "false" ]; then
        return 0  # Needs parsing
    fi
    
    return 1  # Already parsed
}

# Parse the prompt and update session
parse_prompt() {
    local session_dir="$1"
    local session_file="$session_dir/meta/session.json"
    local sentinel_file="$session_dir/meta/provider-session-limit.flag"
    
    echo "→ Parsing research prompt..." >&2
    
    # Get current objective
    local raw_prompt
    raw_prompt=$(jq -r '.objective' "$session_file" 2>/dev/null)
    
    if [ -z "$raw_prompt" ] || [ "$raw_prompt" = "null" ]; then
        echo "  ⚠ Warning: No objective found to parse" >&2
        return 1
    fi
    
    # Write prompt to file for agent to read
    echo "$raw_prompt" > "$session_dir/user-prompt.txt"
    
    # Create task for prompt-parser agent
    local task="Parse the user prompt in user-prompt.txt and extract the clean objective, output specification, and full prompt as specified in your system prompt."
    
    # Invoke prompt-parser through the orchestration system
    local UTILS_DIR="$SCRIPT_DIR"
    if ! declare -F _invoke_delegated_agent >/dev/null; then
        # shellcheck disable=SC1091
        source "$UTILS_DIR/mission-orchestration.sh"
        # Ensure agent registry is populated if we had to source orchestration helpers here
        if declare -F agent_registry_init >/dev/null; then
            agent_registry_init
        fi
    fi
    
    if _invoke_delegated_agent "$session_dir" "prompt-parser" "$task" "Extract clean research objective from user prompt" "[]"; then
        echo "  ✓ Prompt parsed successfully" >&2

        local parsed_success=0
        if _prompt_parser_apply_json_artifact "$session_dir"; then
            parsed_success=1
        else
            _prompt_parser_record_artifact_fallback "$session_dir" "json_artifact_unavailable"
            if _prompt_parser_apply_legacy_result "$session_dir"; then
                parsed_success=1
            fi
        fi

        if (( parsed_success == 1 )); then
            local clean_objective
            clean_objective=$(jq -r '.objective // empty' "$session_file" 2>/dev/null)
            local output_spec
            output_spec=$(jq -r '
                if (.output_specification // empty) == "" then "__CCONDUCTOR_NULL__"
                elif .output_specification == null then "__CCONDUCTOR_NULL__"
                else .output_specification
                end
            ' "$session_file" 2>/dev/null)

            if [[ -n "$clean_objective" ]]; then
                echo "  ✓ Session and knowledge graph updated with clean objective" >&2

                if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
                    echo "" >&2
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                    echo "📝 Prompt Parser Results" >&2
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                    echo "" >&2
                    echo "Core Objective (for research agents):" >&2
                    echo "  $clean_objective" >&2
                    echo "" >&2
                    if [[ "$output_spec" != "__CCONDUCTOR_NULL__" ]]; then
                        echo "Output Format Specification (for synthesis):" >&2
                        echo "  $output_spec" >&2
                        echo "" >&2
                    else
                        echo "Output Format: Using standard domain format" >&2
                        echo "" >&2
                    fi
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                    echo "" >&2
                fi

                rm -f "$session_dir/user-prompt.txt"
                return 0
            fi
        else
            _prompt_parser_record_artifact_fallback "$session_dir" "legacy_result_missing"
        fi

        if command -v log_warn >/dev/null 2>&1; then
            log_warn "Prompt parser results were unavailable; falling back to original prompt"
        fi
        echo "  ⚠ Warning: Could not extract parsed results, using original prompt" >&2
    else
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "Prompt parsing failed, using original prompt"
        fi
        echo "  ⚠ Warning: Prompt parsing failed, using original prompt" >&2
    fi

    rm -f "$session_dir/user-prompt.txt"

    if [[ -f "$sentinel_file" ]]; then
        return 2
    fi
    
    # Mark as parsed even if it failed (to avoid retrying)
    local temp_session="${session_file}.tmp"
    jq '.prompt_parsed = true' "$session_file" > "$temp_session"
    mv "$temp_session" "$session_file"
    
    return 1
}

# Export functions
export -f needs_prompt_parsing
export -f parse_prompt
