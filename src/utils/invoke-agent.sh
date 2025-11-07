#!/usr/bin/env bash
# Agent Invocation Helper (Phase 0 - Validated Implementation)
# Invokes Claude CLI agents with systemPrompt injection and tool restrictions
#
# VALIDATION: All patterns tested in validation_tests/
# - JSON output: test-01
# - System prompt injection: test-append-system-prompt.sh
# - Tool restrictions: test-04, test-05, test-06
# - JSON extraction: diagnostic-json-structure.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_record_provider_session_limit() {
    local session_dir="$1"
    local agent_name="${2:-unknown-agent}"
    local provider_message="${3:-Session limit reached.}"
    local streaming_flag="${4:-0}"

    local streaming_value
    streaming_value=$([[ "$streaming_flag" -eq 1 ]] && echo true || echo false)
    local display_message="Claude CLI session limit reached — provider response: ${provider_message}"

    if [[ -n "$session_dir" ]] && command -v log_system_error &>/dev/null; then
        log_system_error "$session_dir" "provider_session_limit" \
            "Claude session limit reached for agent $agent_name" \
            "message=$(printf '%s' "$provider_message" | tr $'\n' ' ') streaming=$streaming_value"
    fi

    if [[ -n "$session_dir" ]] && command -v log_event &>/dev/null; then
        local provider_event
        provider_event=$(jq -n \
            --arg agent "$agent_name" \
            --arg message "$provider_message" \
            --argjson streaming "$([[ "$streaming_value" == "true" ]] && echo true || echo false)" \
            '{agent:$agent, message:$message, streaming:$streaming}')
        log_event "$session_dir" "provider_session_limit" "$provider_event" || true
    fi

    if [[ -n "$session_dir" ]]; then
        local sentinel="$session_dir/meta/provider-session-limit.flag"
        mkdir -p "$(dirname "$sentinel")"
        printf '%s\n' "$display_message" > "$sentinel" 2>/dev/null || true
    fi

    echo "⚠ ${agent_name} aborted: $display_message" >&2
}

_notify_provider_session_limit() {
    local output_file="$1"
    local session_dir="${2:-}"
    local agent_name="${3:-unknown-agent}"
    local use_streaming_flag="${4:-0}"

    if [[ ! -f "$output_file" ]]; then
        return 1
    fi

    local result_is_error
    result_is_error=$(safe_jq_from_file "$output_file" '.is_error // false' "false" "$session_dir" "invoke_agent.provider.is_error")
    if [[ "$result_is_error" != "true" ]]; then
        return 1
    fi

    local provider_message
    provider_message=$(safe_jq_from_file "$output_file" '.result // "Session limit reached."' "Session limit reached." "$session_dir" "invoke_agent.provider.message")
    _record_provider_session_limit "$session_dir" "$agent_name" "$provider_message" "$use_streaming_flag"
    return 0
}

_detect_provider_session_limit_phrase() {
    local text="$1"
    if [[ -z "$text" ]]; then
        return 1
    fi
    local lower_text="${text,,}"
    if [[ "$lower_text" == *"session limit reached"* ]]; then
        return 0
    fi
    if [[ "$lower_text" == *"wait for the provider reset"* ]]; then
        return 0
    fi
    if [[ "$lower_text" == *"resets 1am"* ]]; then
        return 0
    fi
    return 1
}

_extract_provider_session_limit_message() {
    local text="$1"
    if [[ -z "$text" ]]; then
        echo "Session limit reached."
        return
    fi
    local line
    line=$(printf '%s\n' "$text" | grep -i 'session limit reached' | head -n1)
    if [[ -z "$line" ]]; then
        line=$(printf '%s\n' "$text" | grep -i 'resets' | head -n1)
    fi
    if [[ -z "$line" ]]; then
        line="Session limit reached."
    fi
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    printf '%s\n' "$line"
}

_artifact_first_handle_stream_fallback() {
    local session_dir="$1"
    local agent_label="$2"
    
    # Use existing artifact_contract_path helper (from artifact-manager.sh)
    local contract_path
    if ! contract_path=$(artifact_contract_path "$agent_label" 2>/dev/null); then
        return 1  # No contract, allow warning
    fi
    
    # Check if ANY required artifact exists
    local required_paths
    required_paths=$(jq -r '.artifacts[] | select(.required == true) | .relative_path // empty' \
        "$contract_path" 2>/dev/null || echo "")
    
    if [[ -z "$required_paths" ]]; then
        return 1  # No required artifacts in contract
    fi
    
    # Check if at least one required artifact is present
    local found_artifact=0
    while IFS= read -r rel_path; do
        [[ -z "$rel_path" ]] && continue
        if [[ -f "$session_dir/$rel_path" ]]; then
            found_artifact=1
            break
        fi
    done <<<"$required_paths"
    
    if [[ "$found_artifact" -eq 1 ]]; then
        # Artifact exists - suppress warning, emit telemetry
        if command -v log_event &>/dev/null; then
            local payload
            payload=$(jq -n \
                --arg agent "$agent_label" \
                --arg reason "stream_synthesized" \
                '{agent:$agent, reason:$reason}')
            log_event "$session_dir" "artifact_fallback.stream_synthesized" "$payload" || true
        fi
        return 0  # Suppress warning
    fi
    
    return 1  # No artifacts found, allow warning
}

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
if [[ -f "$SCRIPT_DIR/provider-helpers.sh" ]]; then
    source "$SCRIPT_DIR/provider-helpers.sh"
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/argument-writer.sh" 2>/dev/null; then
    if [[ -z "${INVOKE_AGENT_ARGUMENT_WARNED:-}" ]]; then
        log_warn "Optional argument-writer.sh failed to load (argument event capture disabled)"
        INVOKE_AGENT_ARGUMENT_WARNED=1
    fi
fi

# Source event logger for Phase 2 metrics
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null; then
    if [[ -z "${INVOKE_AGENT_EVENT_LOGGER_WARNED:-}" ]]; then
        log_warn "Optional event-logger.sh failed to load (agent event tracking disabled)"
        INVOKE_AGENT_EVENT_LOGGER_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null; then
    if [[ -z "${INVOKE_AGENT_ERROR_LOGGER_WARNED:-}" ]]; then
        log_warn "Optional error-logger.sh failed to load (structured agent errors disabled)"
        INVOKE_AGENT_ERROR_LOGGER_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/verbose.sh" 2>/dev/null; then
    if [[ -z "${INVOKE_AGENT_VERBOSE_WARNED:-}" ]]; then
        log_warn "Optional verbose.sh failed to load (agent verbose output disabled)"
        INVOKE_AGENT_VERBOSE_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/process-cleanup.sh" 2>/dev/null; then
    if [[ -z "${INVOKE_AGENT_PROC_CLEANUP_WARNED:-}" ]]; then
        log_warn "Optional process-cleanup.sh failed to load (orphan reaping disabled)"
        INVOKE_AGENT_PROC_CLEANUP_WARNED=1
    fi
fi
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/artifact-manager.sh" 2>/dev/null; then
    log_error "artifact-manager.sh failed to load; cannot enforce artifact contracts"
    exit 1
fi

ARTIFACT_VALIDATION_PHASE="${CCONDUCTOR_ARTIFACT_PHASE:-phase2}"
case "$ARTIFACT_VALIDATION_PHASE" in
    phase1|phase2|phase3) ;;
    *)
        ARTIFACT_VALIDATION_PHASE="phase2"
        ;;
esac

ARTIFACT_CONTRACT_BYPASS=0
case "${CCONDUCTOR_ALLOW_CONTRACT_BYPASS:-}" in
    1|true|TRUE|yes|YES)
        ARTIFACT_CONTRACT_BYPASS=1
        ;;
esac

_finalize_agent_output() {
    local session_dir="$1"
    local agent_name="$2"
    local wait_timeout="${3:-${CCONDUCTOR_ARTIFACT_WAIT_TIMEOUT:-15}}"
    local poll_interval="${CCONDUCTOR_ARTIFACT_POLL_INTERVAL:-0.25}"

    if [[ -z "$session_dir" || -z "$agent_name" ]]; then
        log_error "_finalize_agent_output requires session_dir and agent_name"
        return 2
    fi

    if ! command -v artifact_finalize_manifest >/dev/null 2>&1; then
        log_error "artifact_finalize_manifest unavailable; cannot validate artifacts"
        return 2
    fi

    if [[ -z "$wait_timeout" || "$wait_timeout" == "null" ]]; then
        wait_timeout=15
    fi
    if [[ -z "$poll_interval" || "$poll_interval" == "null" ]]; then
        poll_interval=0.25
    fi

    local start_epoch
    start_epoch=$(get_epoch)

    local manifest_json="{}"
    local manifest_status=1
    local missing_count=-1
    local schema_count=-1
    local checksum_count=-1
    local marker_enabled=1
    local marker_path="$session_dir/work/$agent_name/artifacts.ready"
    local manifest_path="$session_dir/work/$agent_name/manifest.actual.json"
    if [[ "${CCONDUCTOR_DISABLE_ARTIFACT_READY_WAIT:-0}" == "1" ]]; then
        marker_enabled=0
    fi

    while true; do
        if (( marker_enabled == 1 )) && [[ -f "$marker_path" && -f "$manifest_path" ]]; then
            manifest_json=$(cat "$manifest_path")
            missing_count=$(safe_jq_from_json "$manifest_json" '.summary.missing_slots | length' "0" "$session_dir" "invoke_agent.finalize.marker_missing" false)
            schema_count=$(safe_jq_from_json "$manifest_json" '.summary.schema_failures | length' "0" "$session_dir" "invoke_agent.finalize.marker_schema" false)
            checksum_count=$(safe_jq_from_json "$manifest_json" '.summary.checksum_failures | length' "0" "$session_dir" "invoke_agent.finalize.marker_checksum" false)
            if [[ "$missing_count" != "-1" && "$schema_count" != "-1" && "$checksum_count" != "-1" ]]; then
                if [[ "$missing_count" == "0" && "$schema_count" == "0" && "$checksum_count" == "0" ]]; then
                    if command -v log_event >/dev/null 2>&1; then
                        local marker_payload
                        if command -v jq >/dev/null 2>&1; then
                            marker_payload=$(printf '%s' "$manifest_json" | jq -c --arg agent "$agent_name" '. + {agent: $agent}' 2>/dev/null || echo "$manifest_json")
                        else
                            marker_payload="$manifest_json"
                        fi
                        log_event "$session_dir" "agent_result.artifact_ready" "$marker_payload" || true
                    fi
                    printf '%s\n' "$manifest_json"
                    return 0
                fi
            fi
        fi

        set +e
        manifest_json=$(artifact_finalize_manifest "$session_dir" "$agent_name" "$ARTIFACT_VALIDATION_PHASE" "$ARTIFACT_CONTRACT_BYPASS")
        manifest_status=$?
        set -e

        missing_count=$(safe_jq_from_json "$manifest_json" '.summary.missing_slots | length' "-1" "$session_dir" "invoke_agent.finalize.missing" false)
        schema_count=$(safe_jq_from_json "$manifest_json" '.summary.schema_failures | length' "-1" "$session_dir" "invoke_agent.finalize.schema" false)
        checksum_count=$(safe_jq_from_json "$manifest_json" '.summary.checksum_failures | length' "-1" "$session_dir" "invoke_agent.finalize.checksum" false)

        if [[ "$missing_count" == "-1" || "$schema_count" == "-1" || "$checksum_count" == "-1" ]]; then
            log_warn "artifact_finalize_manifest returned invalid payload for $agent_name"
            if [[ -z "$manifest_json" ]]; then
                printf '{}\n'
            else
                printf '%s\n' "$manifest_json"
            fi
            return 2
        fi

        if [[ $manifest_status -eq 0 ]]; then
            if command -v log_event >/dev/null 2>&1; then
                local event_payload
                if command -v jq >/dev/null 2>&1; then
                    event_payload=$(printf '%s' "$manifest_json" | jq -c --arg agent "$agent_name" '. + {agent: $agent}' 2>/dev/null || echo "$manifest_json")
                else
                    event_payload="$manifest_json"
                fi
                log_event "$session_dir" "agent_result.artifact_ready" "$event_payload" || true
            fi
            printf '%s\n' "$manifest_json"
            return 0
        fi

        if (( schema_count > 0 || checksum_count > 0 )); then
            local invalid_slots
            invalid_slots=$(safe_jq_from_json "$manifest_json" '.summary.schema_failures + .summary.checksum_failures | unique | join(", ")' "" "$session_dir" "invoke_agent.finalize.invalid_slots" false)
            if [[ -z "$invalid_slots" ]]; then
                invalid_slots="unknown"
            fi
            log_warn "Artifact validation failed for $agent_name (schema/checksum errors: $invalid_slots)"
            if command -v log_event >/dev/null 2>&1; then
                local invalid_payload
                if command -v jq >/dev/null 2>&1; then
                    invalid_payload=$(printf '%s' "$manifest_json" | jq -c --arg agent "$agent_name" '. + {agent: $agent}' 2>/dev/null || echo "$manifest_json")
                else
                    invalid_payload="$manifest_json"
                fi
                log_event "$session_dir" "agent_result.artifact_invalid" "$invalid_payload" || true
            fi
            printf '%s\n' "$manifest_json"
            return 2
        fi

        local elapsed=$(( $(get_epoch) - start_epoch ))
        if (( elapsed >= wait_timeout )); then
            local missing_slots
            missing_slots=$(safe_jq_from_json "$manifest_json" '.summary.missing_slots | join(", ")' "" "$session_dir" "invoke_agent.finalize.missing_slots" false)
            if [[ -z "$missing_slots" ]]; then
                missing_slots="unknown"
            fi
            log_warn "Timed out waiting for required artifacts for $agent_name (missing: $missing_slots)"
            if command -v log_event >/dev/null 2>&1; then
                local missing_payload
                if command -v jq >/dev/null 2>&1; then
                    missing_payload=$(printf '%s' "$manifest_json" | jq -c --arg agent "$agent_name" '. + {agent: $agent}' 2>/dev/null || echo "$manifest_json")
                else
                    missing_payload="$manifest_json"
                fi
                log_event "$session_dir" "agent_result.artifact_missing" "$missing_payload" || true
            fi
            printf '%s\n' "$manifest_json"
            return 1
        fi

        sleep "$poll_interval"
    done
}


# Check if Claude CLI is available
check_claude_cli() {
    if ! require_command "claude" "curl -fsSL https://claude.ai/install.sh | bash" "npm install -g @anthropic-ai/claude-code"; then
        log_error "Claude CLI not found in PATH"
        log_error "Install (native): curl -fsSL https://claude.ai/install.sh | bash"
        log_error "Or (npm): npm install -g @anthropic-ai/claude-code"
        log_error "Docs: https://docs.claude.com/en/docs/claude-code/overview"
        return 1
    fi
    
    # Try to verify authentication (optional check, doesn't block)
    if ! claude --version &> /dev/null; then
        echo "Warning: Claude CLI may not be authenticated or properly installed" >&2
        echo "If you encounter auth errors, run: claude login" >&2
        # Don't fail - let it try anyway, claude --version might fail for other reasons
    fi
    
    return 0
}

supports_claude_streaming() {
    if [[ -n "${CLAUDE_STREAMING_CHECKED:-}" ]]; then
        [[ "${CLAUDE_STREAMING_SUPPORTED:-0}" -eq 1 ]]
        return
    fi

    if claude --help 2>&1 | grep -q 'stream-json'; then
        CLAUDE_STREAMING_SUPPORTED=1
    else
        CLAUDE_STREAMING_SUPPORTED=0
    fi
    CLAUDE_STREAMING_CHECKED=1

    [[ "${CLAUDE_STREAMING_SUPPORTED:-0}" -eq 1 ]]
}

# Extract JSON payload from an agent result file (looks for ```json fences)
extract_json_from_result_output() {
    local file="$1"
    local log_session="${CCONDUCTOR_SESSION_DIR:-}"
    local raw_result
    raw_result=$(safe_jq_from_file "$file" '.result // ""' "" "$log_session" "invoke_agent.extract_result")
    local extracted_block
    # shellcheck disable=SC2016
    extracted_block=$(printf '%s' "$raw_result" | sed -n '/^```json$/,/^```$/p' | sed '1d;$d')
    if [[ -z "$extracted_block" ]]; then
        echo ""
        return 0
    fi
    local parsed_json
    if parsed_json=$(printf '%s' "$extracted_block" | jq -c '.' 2>/dev/null); then
        printf '%s\n' "$parsed_json"
        return 0
    fi

    echo ""
    return 0
}

# Backwards compatibility helper (legacy name)
extract_json_from_result() {
    extract_json_from_result_output "$@"
}

# Extract agent-specific metadata for research journal view
# Returns a JSON object with relevant metrics for each agent type
extract_agent_metadata() {
    local agent_name="$1"
    local output_file="$2"
    local session_dir="$3"
    
    # Default empty metadata
    local metadata="{}"
    
    # Helper function to extract JSON from markdown code blocks
    # (global function extract_json_from_result_output handles this)
    
    # OPTION 2: Self-Describing Agents
    # First, try to extract standardized .metadata field from agent output
    local result_json
    result_json=$(extract_json_from_result_output "$output_file")
    
    if [ -n "$result_json" ]; then
        local agent_metadata
        agent_metadata=$(safe_jq_from_json "$result_json" '.metadata // empty' "" "$session_dir" "invoke_agent.metadata" false)
        
        if [ -n "$agent_metadata" ] && [ "$agent_metadata" != "null" ]; then
            # Agent provided self-describing metadata - use it directly
            echo "$agent_metadata"
            return 0
        fi
    fi
    
    # FALLBACK: Legacy extraction for agents not yet updated to self-describing format
    case "$agent_name" in
        mission-orchestrator)
            # Extract reasoning from orchestrator output
            if [ -n "$result_json" ]; then
                local reasoning
                reasoning=$(safe_jq_from_json "$result_json" '.reasoning // empty' "" "$session_dir" "invoke_agent.reasoning" false)
                if [ -n "$reasoning" ] && [ "$reasoning" != "null" ]; then
                    metadata=$(jq -n --argjson reasoning "$reasoning" '{reasoning: $reasoning}')
                fi
            fi
            ;;
            
        research-planner)
            # Count tasks generated from planner output
            local tasks_count=0
            # result_json already extracted above
            if [ -n "$result_json" ]; then
                # Try to count from .initial_tasks array
                tasks_count=$(safe_jq_from_json "$result_json" '.initial_tasks // [] | length' "0" "$session_dir" "invoke_agent.initial_tasks_count")
                # Fallback: if initial_tasks doesn't exist, try direct array length
                if [ "$tasks_count" -eq 0 ]; then
                    tasks_count=$(safe_jq_from_json "$result_json" 'if type == "array" then length else 0 end' "0" "$session_dir" "invoke_agent.tasks_array_length")
                fi
            fi
            metadata=$(jq -n --argjson count "$tasks_count" '{tasks_generated: $count}')
            ;;
            
        academic-researcher)
            # Count entities and claims from findings files with three-tier fallback
            local entities=0
            local claims=0
            local searches=0
            
            # TIER 1: Try agent's self-reported manifest
            local findings_files
            findings_files=$(safe_jq_from_json "$result_json" '.findings_files[]? // empty' "" "$session_dir" "invoke_agent.findings_manifest")
            
            if [ -n "$findings_files" ]; then
                # Agent provided manifest - use it
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        local file_entities
                        file_entities=$(safe_jq_from_file "$session_dir/$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.findings.entities")
                        entities=$((entities + file_entities))

                        local file_claims
                        file_claims=$(safe_jq_from_file "$session_dir/$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.findings.claims")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
            else
                # TIER 2: Filesystem fallback - look for findings files
                # Check work/ directory (standard location)
                if [ -d "$session_dir/work" ]; then
                    for findings_file in "$session_dir/work"/*/findings-*.json "$session_dir/work"/*/findings*.json; do
                        [ -f "$findings_file" ] || continue
                        local file_entities
                        file_entities=$(safe_jq_from_file "$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.fs.entities")
                        entities=$((entities + file_entities))

                        local file_claims
                        file_claims=$(safe_jq_from_file "$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.fs.claims")
                        claims=$((claims + file_claims))
                    done
                fi
                
                # Also check session root for findings files (multiple patterns)
                # Patterns: *-findings.json, *findings*.json (catches all variations)
                for findings_file in "$session_dir"/*-findings.json "$session_dir"/*findings*.json; do
                    [ -f "$findings_file" ] || continue
                    local file_entities
                    file_entities=$(safe_jq_from_file "$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.tier3.entities")
                    entities=$((entities + file_entities))
                    
                    local file_claims
                    file_claims=$(safe_jq_from_file "$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.tier3.claims")
                    claims=$((claims + file_claims))
                done
            fi
            
            # TIER 3: KG validation - verify findings were actually integrated
            # (This provides observability - we can log if numbers don't match)
            if [ -f "$session_dir/knowledge/knowledge-graph.json" ]; then
                local kg_entities
                kg_entities=$(safe_jq_from_file "$session_dir/knowledge/knowledge-graph.json" '.entities | length' "0" "$session_dir" "invoke_agent.kg_entities")
                
                # If we found findings but KG is still low, log warning
                if [ "$entities" -gt 5 ] && [ "$kg_entities" -lt 5 ]; then
                    echo "  ⚠ Warning: Found $entities entities in findings but only $kg_entities in KG - integration may have failed" >&2
                fi
            fi
            
            # Count WebSearch tool uses from logs/events.jsonl
            if [ -f "$session_dir/logs/events.jsonl" ]; then
                searches=$(grep '"academic-researcher"' "$session_dir/logs/events.jsonl" | \
                          grep '"type":"tool_use_start"' | \
                          grep -c '"tool":"WebSearch"' 2>/dev/null || echo "0")
            fi
            
            metadata=$(jq -n --argjson entities "$entities" --argjson claims "$claims" --argjson searches "$searches" \
                       '{papers_found: $entities, claims_found: $claims, searches_performed: $searches}')
            ;;
            
        web-researcher)
            # Count entities and claims from findings files with three-tier fallback
            local entities=0
            local claims=0
            local searches=0
            
            # TIER 1: Try agent's self-reported manifest
            local findings_files
            findings_files=$(safe_jq_from_json "$result_json" '.findings_files[]? // empty' "" "$session_dir" "invoke_agent.parallel_manifest")
            
            if [ -n "$findings_files" ]; then
                # Agent provided manifest - use it
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        local file_entities
                        file_entities=$(safe_jq_from_file "$session_dir/$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel.entities")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(safe_jq_from_file "$session_dir/$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel.claims")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
            else
                # TIER 2: Filesystem fallback - look for findings files
                # Check work/ directory (standard location)
                if [ -d "$session_dir/work" ]; then
                    for findings_file in "$session_dir/work"/*/findings-*.json "$session_dir/work"/*/findings*.json; do
                        [ -f "$findings_file" ] || continue
                        local file_entities
                        file_entities=$(safe_jq_from_file "$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel_fs.entities")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(safe_jq_from_file "$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel_fs.claims")
                        claims=$((claims + file_claims))
                    done
                fi
                
                # Also check session root for findings files (multiple patterns)
                # Patterns: *-findings.json, *findings*.json (catches all variations like water_composition_research_findings.json)
                for findings_file in "$session_dir"/*-findings.json "$session_dir"/*findings*.json; do
                    [ -f "$findings_file" ] || continue
                    local file_entities
                    file_entities=$(safe_jq_from_file "$findings_file" '[.entities_discovered[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel_tier3.entities")
                    entities=$((entities + file_entities))
                    
                    local file_claims
                    file_claims=$(safe_jq_from_file "$findings_file" '[.claims[]? // empty] | length' "0" "$session_dir" "invoke_agent.parallel_tier3.claims")
                    claims=$((claims + file_claims))
                done
            fi
            
            # TIER 3: KG validation - verify findings were actually integrated
            # (This provides observability - we can log if numbers don't match)
            if [ -f "$session_dir/knowledge/knowledge-graph.json" ]; then
                local kg_entities
                kg_entities=$(safe_jq_from_file "$session_dir/knowledge/knowledge-graph.json" '.entities | length' "0" "$session_dir" "invoke_agent.parallel_kg_entities")
                
                # If we found findings but KG is still low, log warning
                if [ "$entities" -gt 5 ] && [ "$kg_entities" -lt 5 ]; then
                    echo "  ⚠ Warning: Found $entities entities in findings but only $kg_entities in KG - integration may have failed" >&2
                fi
            fi
            
            # Count WebSearch tool uses from logs/events.jsonl
            if [ -f "$session_dir/logs/events.jsonl" ]; then
                searches=$(grep '"web-researcher"' "$session_dir/logs/events.jsonl" | \
                          grep '"type":"tool_use_start"' | \
                          grep -c '"tool":"WebSearch"' 2>/dev/null || echo "0")
            fi
            
            metadata=$(jq -n --argjson entities "$entities" --argjson claims "$claims" --argjson searches "$searches" \
                       '{sources_found: $entities, claims_found: $claims, searches_performed: $searches}')
            ;;
            
        synthesis-agent)
            # Extract synthesis statistics from artifact files (v0.2.1 artifact pattern)
            local claims=0
            local gaps=0
            
            # Read from artifact files
            if [ -f "$session_dir/artifacts/synthesis-agent/completion.json" ]; then
                claims=$(safe_jq_from_file "$session_dir/artifacts/synthesis-agent/completion.json" '.claims_analyzed // 0' "0" "$session_dir" "invoke_agent.synthesis.claims")
            fi
            
            if [ -f "$session_dir/artifacts/synthesis-agent/coverage.json" ]; then
                gaps=$(safe_jq_from_file "$session_dir/artifacts/synthesis-agent/coverage.json" '.aspects_not_covered // 0' "0" "$session_dir" "invoke_agent.synthesis.gaps")
            fi
            
            metadata=$(jq -n \
                       --argjson claims "$claims" \
                       --argjson gaps "$gaps" \
                       '{claims_synthesized: $claims, gaps_found: $gaps}')
            ;;
    esac
    
    # Validate metadata is valid JSON before returning
    if echo "$metadata" | jq empty 2>/dev/null; then
        echo "$metadata"
    else
        # Return empty object if metadata is invalid
        echo "{}"
    fi
}

# Extract cost from events.jsonl for a specific agent
# Returns numeric cost or 0 if missing
# Usage: extract_cost_from_events "$session_dir" "$agent_name"
extract_cost_from_events() {
    local session_dir="$1"
    local agent_name="$2"
    
    if [[ -z "$session_dir" || -z "$agent_name" ]]; then
        echo "0"
        return 0
    fi
    
    local events_file="$session_dir/logs/events.jsonl"
    
    # Handle missing or empty events.jsonl file (first agent invocation)
    if [[ ! -f "$events_file" ]] || [[ ! -s "$events_file" ]]; then
        echo "0"
        return 0
    fi
    
    # Read events.jsonl using existing helper pattern
    local events_payload
    events_payload=$(json_slurp_array "$events_file" '[]')
    
    if [[ -z "$events_payload" || "$events_payload" == "[]" ]]; then
        echo "0"
        return 0
    fi
    
    # Query most recent agent_result entry for this agent
    # Events structure: {type: "agent_result", data: {agent: "...", cost_usd: X}}
    local cost
    # shellcheck disable=SC2016
    cost=$(safe_jq_from_json "$events_payload" \
        'map(select(.type == "agent_result" and .data.agent == $agent)) | last? // empty | .data.cost_usd // 0' \
        "0" "$session_dir" "invoke_agent.events_cost" false false \
        --arg agent "$agent_name")
    
    [[ -z "$cost" || "$cost" == "null" ]] && cost="0"
    echo "$cost"
}

# Extract cost from Claude CLI output.json
# Returns numeric cost or 0 if missing
# Priority order:
#   1. output.json → .total_cost_usd (root level, preferred)
#   2. output.json → .usage.total_cost_usd (legacy path)
#   3. .stream.jsonl → result type with total_cost_usd (streaming fallback)
#   4. events.jsonl → agent_result entries (validation/audit only, checked after log_agent_result writes)
#
# Note: events.jsonl is written AFTER extraction, so it cannot be used for real-time extraction
# of the current invocation. It's used for validation and historical lookups.
#
# Usage: extract_cost_from_output "$output_file" [agent_name] [session_dir]
extract_cost_from_output() {
    local output_file="$1"
    local agent_name="${2:-}"
    local session_dir="${3:-${session_dir:-}}"
    local session_ref="$session_dir"
    
    if [[ ! -f "$output_file" ]]; then
        echo "0"
        return 0
    fi
    
    # Try common paths: .usage.total_cost_usd, .total_cost_usd
    local cost
    cost=$(safe_jq_from_file "$output_file" '.usage.total_cost_usd // .total_cost_usd // 0 | tonumber? // 0' "0" "$session_ref" "invoke_agent.cost")
    
    # Short-circuit: if cost is already present and non-zero, return immediately
    if [[ -n "$cost" && "$cost" != "0" && "$cost" != "0.0" ]]; then
        echo "$cost"
        return 0
    fi
    
    if [[ "$cost" == "0" || "$cost" == "0.0" ]]; then
        local stream_log="${output_file}.stream.jsonl"
        if [[ -f "$stream_log" ]]; then
            local stream_payload
            stream_payload=$(json_slurp_array "$stream_log" '[]')
            if [[ -n "$stream_payload" && "$stream_payload" != "[]" ]]; then
                local stream_cost
                stream_cost=$(safe_jq_from_json "$stream_payload" '[
                    .[] |
                    select(.type == "stream_event") |
                    (
                        .event.usage.total_cost_usd? //
                        .event.response.usage.total_cost_usd? //
                        .event.response.usage.cost.usd? //
                        .event.usage.cost.usd? //
                        empty
                    )
                ] | last? // 0' "0" "$session_ref" "invoke_agent.stream_cost")
                if [[ -n "$stream_cost" && "$stream_cost" != "null" ]]; then
                    cost="$stream_cost"
                fi
            fi
        fi
    fi
    
    # Improved warning logic: Only warn when ALL sources show 0
    # This reduces false positives for legitimately zero-cost operations
    if is_verbose_enabled 2>/dev/null && [[ "$cost" == "0" ]] && [[ -s "$output_file" ]]; then
        # Check if output.json has cost field
        local has_output_cost=0
        if jq -e '.usage.total_cost_usd // .total_cost_usd' "$output_file" >/dev/null 2>&1; then
            has_output_cost=1
        fi
        
        # Check stream.jsonl if cost is still 0
        local has_stream_cost=0
        if [[ "$has_output_cost" -eq 0 ]]; then
            local stream_log="${output_file}.stream.jsonl"
            if [[ -f "$stream_log" ]]; then
                local stream_payload
                stream_payload=$(json_slurp_array "$stream_log" '[]')
                if [[ -n "$stream_payload" && "$stream_payload" != "[]" ]]; then
                    local stream_cost_check
                    stream_cost_check=$(safe_jq_from_json "$stream_payload" '[
                        .[] |
                        select(.type == "result") |
                        (.total_cost_usd // .usage.total_cost_usd // 0)
                    ] | last? // 0' "0" "$session_ref" "invoke_agent.warning_check.stream" "false")
                    if [[ -n "$stream_cost_check" && "$stream_cost_check" != "null" && "$stream_cost_check" != "0" ]]; then
                        has_stream_cost=1
                    fi
                fi
            fi
        fi
        
        # Check events.jsonl if agent_name and session_dir provided
        local has_events_cost=0
        if [[ "$has_output_cost" -eq 0 && "$has_stream_cost" -eq 0 ]] && [[ -n "$agent_name" && -n "$session_dir" ]]; then
            local events_cost_check
            events_cost_check=$(extract_cost_from_events "$session_dir" "$agent_name")
            if [[ -n "$events_cost_check" && "$events_cost_check" != "0" ]]; then
                has_events_cost=1
            fi
        fi
        
        local skip_warning=0
        if [[ "$agent_name" == "prompt-parser" && "${PROMPT_PARSER_STREAM_FALLBACK:-0}" == "1" ]]; then
            skip_warning=1
        fi
        
        # Check if this is a fallback invocation (file has stream_synthesized subtype)
        # Fallback path already logs structured warning, so skip duplicate console warning
        if [[ "$skip_warning" -eq 0 ]]; then
            if jq -e '.subtype == "stream_synthesized"' "$output_file" >/dev/null 2>&1; then
                skip_warning=1
            fi
        fi

        # Only warn if ALL sources show 0 and we are not in a known prompt-parser fallback or stream_synthesized fallback
        if [[ "$skip_warning" -eq 0 && "$has_output_cost" -eq 0 && "$has_stream_cost" -eq 0 && "$has_events_cost" -eq 0 ]]; then
            local display_path="$output_file"
            if [[ -n "$session_ref" ]]; then
                local session_abs
                if session_abs=$(cd "$session_ref" 2>/dev/null && pwd); then
                    if [[ "$display_path" == "$session_abs" ]]; then
                        display_path="."
                    elif [[ "$display_path" == "$session_abs/"* ]]; then
                        display_path="${display_path#"$session_abs"/}"
                    fi
                fi
            fi
            echo "  ⚠ No cost field found in $display_path (checked output.json, stream.jsonl, and events.jsonl)" >&2
        fi
    fi
    
    echo "$cost"
}

cleanup_stale_invoke_pid() {
    local pid_file="$1"
    local label="$2"

    if [[ ! -f "$pid_file" ]]; then
        return 0
    fi

    local stale_pid
    stale_pid=$(cat "$pid_file" 2>/dev/null || echo "")
    if [[ -z "$stale_pid" ]]; then
        rm -f "$pid_file"
        return 0
    fi

    if kill -0 "$stale_pid" 2>/dev/null; then
        local parent_pid
        parent_pid=$(ps -o ppid= -p "$stale_pid" 2>/dev/null | tr -d '[:space:]')
        if [[ -z "$parent_pid" || "$parent_pid" == "1" ]]; then
            echo "[cleanup] Terminating orphaned invoke-agent process $stale_pid for $label" >&2
            kill "$stale_pid" 2>/dev/null || true
            sleep 1
            if kill -0 "$stale_pid" 2>/dev/null; then
                kill -KILL "$stale_pid" 2>/dev/null || true
            fi
        fi
    fi

    rm -f "$pid_file"
}

# Invoke agent with v2 implementation (uses validated patterns)
# VALIDATED: All patterns tested in validation_tests/
# 
# This function implements the Phase 0 improvements:
# - Injects systemPrompt via --append-system-prompt
# - Enforces tool restrictions via --allowedTools/--disallowedTools
# - Returns clean JSON output via --output-format json
# - Extracts .result field (not .content[0].text)
#
# Usage:
#   invoke_agent_v2 <agent_name> <input_file> <output_file> [timeout] <session_dir> [resume_session_id]
#
# Args:
#   agent_name: Name of agent (must exist in session_dir/.claude/agents/)
#   input_file: File containing the task/query for the agent
#   output_file: File to write JSON output to
#   timeout: Optional timeout in seconds (default: 600)
#   session_dir: REQUIRED - Session directory containing .claude/agents/
#
# Returns:
#   0 on success, 1 on failure
#
# Output file format (JSON):
#   {
#     "type": "result",
#     "result": "the agent's response",
#     "session_id": "...",
#     "usage": {...}
#   }
#
# Wrapper for invoke_agent_v2 with retry logic for transient errors
invoke_agent_with_retry() {
    local agent_name="$1"
    local input_file="$2"
    local output_file="$3"
    local timeout="${4:-600}"
    local session_dir="${5:-}"
    local resume_session_id="${6:-}"
    
    local max_attempts=3
    local base_delay=2
    local attempt=1
    
    while (( attempt <= max_attempts )); do
        # Check budget before retry (skip for first attempt)
        if (( attempt > 1 )); then
            if [[ -n "$session_dir" ]] && [[ -f "$SCRIPT_DIR/budget-tracker.sh" ]]; then
                local remaining_budget
                remaining_budget=$("$SCRIPT_DIR/budget-tracker.sh" remaining "$session_dir" 2>/dev/null || echo "0")
                if [[ "$remaining_budget" == "0" || "$remaining_budget" == "0.0" ]]; then
                    log_warn "Budget exhausted, cannot retry agent invocation for $agent_name"
                    return 1
                fi
            fi
        fi
        
        # Attempt invocation
        if invoke_agent_v2 "$agent_name" "$input_file" "$output_file" "$timeout" "$session_dir" "$resume_session_id"; then
            return 0
        fi
        
        # Check if error is retryable
        local error_output="$session_dir/meta/orchestrator-output.json"
        if [[ -f "$error_output" ]] && command -v provider_is_retryable_error &>/dev/null; then
            local error_json
            error_json=$(jq -c '.' "$error_output" 2>/dev/null || echo "{}")
            if provider_is_retryable_error "$error_json"; then
                if (( attempt < max_attempts )); then
                    local delay=$((base_delay ** attempt + RANDOM % 2))
                    if command -v log_event &>/dev/null; then
                        log_event "$session_dir" "agent_retry" \
                            "$(jq -n --arg agent "$agent_name" --argjson attempt "$attempt" --argjson delay "$delay" \
                                '{agent: $agent, attempt: $attempt, delay: $delay}')" || true
                    fi
                    log_warn "Retryable error detected for $agent_name, attempt $attempt failed, retrying in ${delay}s..."
                    sleep "$delay"
                fi
            else
                # Non-retryable error, fail immediately
                return 1
            fi
        else
            # Cannot determine retryability, fail immediately
            return 1
        fi
        
        ((attempt++))
    done
    
    log_error "Agent invocation for $agent_name failed after $max_attempts attempts"
    return 1
}

invoke_agent_v2() {
    local agent_name="$1"
    local input_file="$2"
    local output_file="$3"
    # shellcheck disable=SC2034
    local timeout="${4:-600}"  # Legacy parameter, kept for backward compatibility
    local session_dir="${5:-}"
    local resume_session_id="${6:-}"
    local bash_runtime="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"

    # Validate inputs
    if [ -z "$agent_name" ]; then
        echo "Error: Agent name required" >&2
        return 1
    fi

    if [ ! -f "$input_file" ]; then
        echo "Error: Input file not found: $input_file" >&2
        return 1
    fi

    if [ -z "$session_dir" ]; then
        echo "Error: Session directory required" >&2
        return 1
    fi

    if [ ! -d "$session_dir/.claude" ]; then
        echo "Error: Session directory missing .claude/ context: $session_dir" >&2
        return 1
    fi

    if command -v artifact_prepare_directories >/dev/null 2>&1; then
        if ! artifact_prepare_directories "$session_dir" "$agent_name"; then
            log_warn "Failed to prepare artifact directories for $agent_name (session: $session_dir)"
        fi
    fi

    # Check Claude CLI
    check_claude_cli || return 1

    # Discover CCONDUCTOR_ROOT by walking up from session_dir
    local cconductor_root
    if [ -n "${CCONDUCTOR_ROOT:-}" ]; then
        cconductor_root="$CCONDUCTOR_ROOT"
    else
        # Walk up from session_dir to find root
        local search_dir="$session_dir"
        while [ "$search_dir" != "/" ]; do
            if [ -f "$search_dir/VERSION" ] && [ -d "$search_dir/src" ]; then
                cconductor_root="$search_dir"
                break
            fi
            search_dir="$(dirname "$search_dir")"
        done

        if [ -z "${cconductor_root:-}" ] && [ -f "$session_dir/.cconductor-root" ]; then
            local stored_root
            stored_root=$(cat "$session_dir/.cconductor-root" 2>/dev/null || echo "")
            if [ -n "$stored_root" ] && [ -d "$stored_root/src" ] && [ -f "$stored_root/VERSION" ]; then
                cconductor_root="$stored_root"
            fi
        fi

        if [ -z "${cconductor_root:-}" ]; then
            echo "Error: Could not find CCONDUCTOR_ROOT from session_dir: $session_dir" >&2
            return 1
        fi
    fi

    if [[ -z "${CCONDUCTOR_WEB_FETCH_STRICT_MODE:-}" ]]; then
        export CCONDUCTOR_WEB_FETCH_STRICT_MODE=0
    fi
    if [[ "${CCONDUCTOR_WEB_FETCH_STRICT_MODE:-0}" != "0" && -z "${CCONDUCTOR_WEB_FETCH_POLICY_FILE:-}" ]]; then
        local primary_policy="$cconductor_root/config/web-fetch-limits.json"
        local default_policy="$cconductor_root/config/web-fetch-limits.default.json"
        if [[ -f "$primary_policy" ]]; then
            export CCONDUCTOR_WEB_FETCH_POLICY_FILE="$primary_policy"
        elif [[ -f "$default_policy" ]]; then
            export CCONDUCTOR_WEB_FETCH_POLICY_FILE="$default_policy"
        fi
    fi

    local agent_runtime_config_json="{}"
    local agent_runtime_config_loaded=0

    load_agent_runtime_config() {
        if [[ "$agent_runtime_config_loaded" -eq 1 ]]; then
            return
        fi
        agent_runtime_config_loaded=1
        local config_loader="$cconductor_root/src/utils/config-loader.sh"
        agent_runtime_config_json="{}"
        if [[ -f "$config_loader" ]]; then
            # shellcheck disable=SC1090
            source "$config_loader" 2>/dev/null || true
            if command -v load_config >/dev/null 2>&1; then
                agent_runtime_config_json=$(load_config "agent-timeouts" 2>/dev/null || echo "{}")
            fi
        fi
    }

    agent_runtime_config_lookup() {
        local jq_filter="$1"
        local fallback="${2:-}"
        local context="${3:-invoke_agent.runtime_config}"
        local session_ctx="${session_dir:-}"

        load_agent_runtime_config

        if [[ -z "$agent_runtime_config_json" ]]; then
            printf '%s' "$fallback"
            return 0
        fi

        safe_jq_from_json "$agent_runtime_config_json" "$jq_filter" "$fallback" "$session_ctx" "$context"
    }

    resolve_toggle_mode() {
        local mode_env="$1"
        local legacy_enable_env="$2"
        local legacy_disable_env="$3"
        local config_key="$4"
        local default_value="$5"

        local env_mode_raw="${!mode_env:-}"
        local env_mode="${env_mode_raw,,}"
        if [[ -n "$env_mode" ]]; then
            case "$env_mode" in
                enabled|true|1)
                    echo "enabled"
                    return
                    ;;
                disabled|false|0)
                    echo "disabled"
                    return
                    ;;
                *)
                    log_warn "Invalid value for $mode_env: $env_mode_raw (expected enabled|disabled)"
                    ;;
            esac
        fi

        local legacy_enable="${!legacy_enable_env:-}"
        local legacy_disable="${!legacy_disable_env:-}"
        if [[ -n "$legacy_enable" ]] && [[ -n "$legacy_disable" ]]; then
            log_warn "Both $legacy_enable_env and $legacy_disable_env set; defaulting to disabled"
            echo "disabled"
            return
        fi
        if [[ -n "$legacy_enable" ]]; then
            echo "enabled"
            return
        fi
        if [[ -n "$legacy_disable" ]]; then
            echo "disabled"
            return
        fi

        load_agent_runtime_config
        local config_value
        config_value=$(agent_runtime_config_lookup ".${config_key} // empty" "" "invoke_agent.toggle.${config_key}")
        case "$config_value" in
            true|1|enabled)
                echo "enabled"
                return
                ;;
            false|0|disabled)
                echo "disabled"
                return
                ;;
        esac

        echo "$default_value"
    }

    local watchdog_mode
    watchdog_mode=$(resolve_toggle_mode "CCONDUCTOR_WATCHDOG_MODE" "CCONDUCTOR_ENABLE_WATCHDOG" "CCONDUCTOR_DISABLE_WATCHDOG" "watchdog_enabled" "enabled")
    local agent_timeouts_mode
    agent_timeouts_mode=$(resolve_toggle_mode "CCONDUCTOR_AGENT_TIMEOUT_MODE" "CCONDUCTOR_ENABLE_AGENT_TIMEOUTS" "CCONDUCTOR_DISABLE_AGENT_TIMEOUTS" "timeouts_enabled" "enabled")

    local watchdog_enabled=0
    if [[ "$watchdog_mode" == "enabled" ]]; then
        watchdog_enabled=1
    fi
    local agent_timeouts_enabled=0
    if [[ "$agent_timeouts_mode" == "enabled" ]]; then
        agent_timeouts_enabled=1
    fi

    # Track if fallback path already logged to avoid double-logging (use file since process_stream_events runs in background)
    local fallback_logged_flag="$session_dir/.agent-fallback-logged.${agent_name}.flag"
    rm -f "$fallback_logged_flag" 2>/dev/null || true

    export CCONDUCTOR_WATCHDOG_MODE="$watchdog_mode"
    export CCONDUCTOR_AGENT_TIMEOUT_MODE="$agent_timeouts_mode"
    export CCONDUCTOR_WATCHDOG_ENABLED="$watchdog_enabled"
    export CCONDUCTOR_AGENT_TIMEOUTS_ENABLED="$agent_timeouts_enabled"

    # Load agent definition
    local agent_file="$session_dir/.claude/agents/${agent_name}.json"

    if [ ! -f "$agent_file" ]; then
        echo "Error: Agent definition not found: $agent_file" >&2
        return 1
    fi

    # Extract systemPrompt from agent definition
    # VALIDATED: Correct JSON path in diagnostic-json-structure.sh
    local system_prompt
    system_prompt=$(safe_jq_from_file "$agent_file" '.systemPrompt' "" "$session_dir" "invoke_agent.system_prompt")

    if [ -z "$system_prompt" ] || [ "$system_prompt" = "null" ]; then
        echo "Error: Agent $agent_name missing systemPrompt in $agent_file" >&2
        return 1
    fi

    # Load tool restrictions from agent-tools.json
    # Format: {"agent-name": {"allowed": ["Tool1", "Tool2"], "disallowed": ["Tool3"]}}
    local allowed_tools=""
    local disallowed_tools=""
    local agent_tools_file="$cconductor_root/src/utils/agent-tools.json"

    if [ -f "$agent_tools_file" ]; then
        allowed_tools=$(jq -r \
            --arg agent "$agent_name" \
            '.[$agent].allowed // [] | join(",")' \
            "$agent_tools_file" 2>/dev/null)

        disallowed_tools=$(jq -r \
            --arg agent "$agent_name" \
            '.[$agent].disallowed // [] | join(",")' \
            "$agent_tools_file" 2>/dev/null)
    fi

    # Validate tool restrictions are defined (security warning)
    if [ -z "$allowed_tools" ] && [ -z "$disallowed_tools" ]; then
        echo "⚠️  Warning: No tool restrictions found for agent $agent_name" >&2
        echo "    Agent will run with ALL tools enabled (potential security risk)" >&2
        echo "    Consider adding tool restrictions in agent-tools.json" >&2
    fi

    # Extract model from agent definition (written by mission-orchestration.sh from agent metadata)
    # This supports per-agent models - each agent can specify its own model in metadata.json
    local agent_model
    agent_model=$(safe_jq_from_file "$agent_file" '.model // "sonnet"' "sonnet" "$session_dir" "invoke_agent.agent_model")
    
    # Determine streaming preference (enabled by default) and CLI support
    local enable_streaming="${CCONDUCTOR_ENABLE_STREAMING:-1}"
    local use_streaming=0
    if [[ "$enable_streaming" == "1" ]]; then
        if supports_claude_streaming; then
            use_streaming=1
        else
            log_warn "Claude CLI does not support stream-json output; falling back to legacy JSON mode"
        fi
    fi

    if [[ "$agent_name" == "prompt-parser" && "$use_streaming" -eq 1 ]]; then
        # Streaming occasionally fails to emit a final result frame on claude-sonnet-4-20250514,
        # which drops both the structured payload and cost metadata. Run prompt-parser in legacy
        # JSON mode so we always capture complete output until the upstream issue is resolved.
        use_streaming=0
    fi

    # Build Claude command with validated flags
    local claude_cmd=(
        claude
        --print
        --model "$agent_model"
        --append-system-prompt "$system_prompt"
    )

    if [[ "$use_streaming" -eq 1 ]]; then
        claude_cmd+=(--verbose --output-format stream-json --include-partial-messages)
    else
        claude_cmd+=(--output-format json)
    fi

    if [ -n "$resume_session_id" ]; then
        claude_cmd+=(--resume "$resume_session_id")
    fi

    # Add session-specific settings (hooks, etc.) if present
    # This ensures Claude uses the session's .claude/settings.json
    # rather than walking up to find the git root's settings
    if [ -f "$session_dir/.claude/settings.json" ]; then
        claude_cmd+=(--settings "$session_dir/.claude/settings.json")
    fi

    # Add MCP config if present
    if [ -f "$session_dir/.mcp.json" ]; then
        claude_cmd+=(--mcp-config "$session_dir/.mcp.json")
    fi

    # Add tool restrictions
    # VALIDATED: test-04 (allowed), test-05 (disallowed), test-06 (domains)
    if [ -n "$allowed_tools" ]; then
        claude_cmd+=(--allowedTools "$allowed_tools")
    fi
    if [ -n "$disallowed_tools" ]; then
        claude_cmd+=(--disallowedTools "$disallowed_tools")
    fi

    # Create output directory
    mkdir -p "$(dirname "$output_file")"

    # Export session directory, agent name, and verbose mode for hooks to use
    export CCONDUCTOR_SESSION_DIR="$session_dir"
    export CCONDUCTOR_AGENT_NAME="$agent_name"
    export CCONDUCTOR_VERBOSE="${CCONDUCTOR_VERBOSE:-0}"
    local tool_usage_file=""
    if [[ "${CCONDUCTOR_WEB_FETCH_STRICT_MODE:-0}" != "0" ]]; then
        tool_usage_file="$session_dir/meta/tool-usage.json"
        mkdir -p "$(dirname "$tool_usage_file")"
        jq -n '{}' > "$tool_usage_file"
        export CCONDUCTOR_TOOL_USAGE_FILE="$tool_usage_file"
    fi

    # Reap any orphaned agent processes from previous runs to avoid buildup
    if declare -F cleanup_orphan_agent_processes >/dev/null 2>&1; then
        cleanup_orphan_agent_processes || true
    fi

    # Track runtime resources for cleanup
    local original_dir
    original_dir=$(pwd)
    tailer_started=0
    local watchdog_pid=""
    local heartbeat_file=""
    local cleanup_performed=0
    local stderr_file=""
    local pid_file=""
    local stream_pipe=""
    local stream_processor_pid=""
    local stream_log=""

    cleanup_invoke_agent() {
        local status=$?
        if [[ ${cleanup_performed:-0} -eq 0 ]]; then
            if [[ -n "${watchdog_pid:-}" ]]; then
                kill "$watchdog_pid" 2>/dev/null || true
                wait "$watchdog_pid" 2>/dev/null || true
            fi
            if [[ -n "${stream_processor_pid:-}" ]]; then
                kill "$stream_processor_pid" 2>/dev/null || true
                wait "$stream_processor_pid" 2>/dev/null || true
            fi
            if [[ "$tailer_started" == "1" ]] && declare -F stop_event_tailer >/dev/null 2>&1; then
                stop_event_tailer "${session_dir:-}" || true
            fi
            if [[ -n "${heartbeat_file:-}" ]]; then
                rm -f "$heartbeat_file" "${heartbeat_file}.tmp" 2>/dev/null || true
            fi
            if [[ -n "${stream_pipe:-}" ]]; then
                rm -f "$stream_pipe" 2>/dev/null || true
            fi
            if [[ -n "${pid_file:-}" ]]; then
                rm -f "$pid_file" 2>/dev/null || true
            fi
            if [[ -n "${tool_usage_file:-}" ]]; then
                rm -f "$tool_usage_file" 2>/dev/null || true
            fi
            if [[ -n "${original_dir:-}" ]]; then
                cd "$original_dir" >/dev/null 2>&1 || true
            fi
            cleanup_performed=1
        fi
        return $status
    }
    trap 'cleanup_invoke_agent' EXIT INT TERM HUP

    dispatch_argument_events() {
        local session_dir="$1"
        local agent_label="$2"
        local line="$3"

        if ! command -v argument_writer_append_events >/dev/null 2>&1; then
            return 0
        fi
        if ! argument_writer_enabled; then
            return 0
        fi

        local payload
        payload=$(printf '%s\n' "$line" | jq -c '
            if (.type == "stream_event")
               and (.event.type == "custom_event")
               and ((.event.name // "") | test("argument_event"))
            then
                if (.event.payload.events? // empty) != empty then
                    {events: .event.payload.events}
                else
                    .event.payload
                end
            elif (.type == "argument_event") then
                if (.event.events? // empty) != empty then
                    {events: .event.events}
                else
                    .event
                end
            else
                empty
            end
        ' 2>/dev/null || true)

        if [[ -z "$payload" || "$payload" == "null" ]]; then
            return 0
        fi

        argument_writer_append_events "$session_dir" "$payload" "$agent_label" ""
    }

    process_stream_events() {
        local pipe_path="$1"
        local log_file="$2"
        local output_target="$3"
        local heartbeat_path="$4"
        local agent_label="$5"
        local session_dir_param="${6:-}"
        local debug_log="${CCONDUCTOR_STREAM_DEBUG_LOG:-}"

        : > "$log_file"
        if [[ -n "$debug_log" ]]; then
            : > "$debug_log"
        fi

        local final_result=""
        local session_id_cache=""
        local usage_cache=""
        local line=""
        local aggregated_text=""
        local last_assistant_text=""

        update_heartbeat() {
            local timestamp
            timestamp=$(get_epoch)
            printf '%s:%s\n' "$agent_label" "$timestamp" > "${heartbeat_path}.tmp" 2>/dev/null || true
            mv "${heartbeat_path}.tmp" "$heartbeat_path" 2>/dev/null || true
        }

        while IFS= read -r line; do
            printf '%s\n' "$line" >> "$log_file"
            if [[ -n "$debug_log" ]]; then
                printf '%s\n' "$line" >> "$debug_log"
            fi
            [[ -z "$line" ]] && continue

            local event_type
            event_type=$(safe_jq_from_json "$line" '.type // empty' "" "$session_dir" "invoke_agent.stream.event_type")

            dispatch_argument_events "$session_dir" "$agent_label" "$line" || true

            if [[ "$event_type" == "system" ]]; then
                local sys_session_id
                sys_session_id=$(printf '%s\n' "$line" | jq -r '.session_id // empty' 2>/dev/null || echo "")
                if [[ -n "$sys_session_id" ]]; then
                    session_id_cache="$sys_session_id"
                fi
            fi

            case "$event_type" in
                stream_event)
                    local inner_type
                    inner_type=$(safe_jq_from_json "$line" '.event.type // empty' "" "$session_dir" "invoke_agent.stream.inner_type")
                    case "$inner_type" in
                        message_start|message_delta|content_block_start|content_block_delta|content_block_stop|tool_use_start|tool_use_delta|tool_use_stop)
                            update_heartbeat
                            ;;
                    esac
                    if [[ "$inner_type" == "content_block_delta" || "$inner_type" == "message_delta" ]]; then
                        local delta_chunk
                        delta_chunk=$(safe_jq_from_json "$line" '
                            if (.event.delta? | type == "object") then
                                [
                                    (.event.delta.partial_json? // empty),
                                    (.event.delta.partial_output_json? // empty),
                                    (.event.delta.partial_markdown? // empty),
                                    (.event.delta.partial_text? // empty),
                                    (.event.delta.partial_tool_response? // empty),
                                    (.event.delta.text? // empty)
                                ]
                                | map(select(. != "" and . != "null"))
                                | join("")
                            else
                                ""
                            end
                        ' "" "$session_dir" "invoke_agent.stream.delta_chunk")
                        if [[ -n "$delta_chunk" ]]; then
                            aggregated_text+="$delta_chunk"
                        fi
                    elif [[ "$inner_type" == "content_block_stop" || "$inner_type" == "message_stop" ]]; then
                        aggregated_text+=$'\n'
                    fi
                    ;;
                assistant|message)
                    update_heartbeat
                    local assistant_text
                    assistant_text=$(safe_jq_from_json "$line" '[.message.content[]? | select(.type=="text") | .text] | join("")' "" "$session_dir" "invoke_agent.stream.assistant")
                    if [[ -n "$assistant_text" && "$assistant_text" != "null" ]]; then
                        last_assistant_text="$assistant_text"
                    fi
                    if [[ -z "$session_id_cache" ]]; then
                        local msg_session_id
                        msg_session_id=$(printf '%s\n' "$line" | jq -r '.session_id // empty' 2>/dev/null || echo "")
                        if [[ -n "$msg_session_id" ]]; then
                            session_id_cache="$msg_session_id"
                        fi
                    fi
                    ;;
                result)
                    final_result="$line"
                    if [[ -z "$session_id_cache" ]]; then
                        local result_session_id
                        result_session_id=$(printf '%s\n' "$line" | jq -r '.session_id // empty' 2>/dev/null || echo "")
                        if [[ -n "$result_session_id" ]]; then
                            session_id_cache="$result_session_id"
                        fi
                    fi
                    if [[ -z "$usage_cache" ]]; then
                        local result_usage
                        result_usage=$(printf '%s\n' "$line" | jq -c '.usage // empty' 2>/dev/null || echo "")
                        if [[ -n "$result_usage" && "$result_usage" != "null" ]]; then
                            usage_cache="$result_usage"
                        fi
                    fi
                    if [[ -n "$debug_log" ]]; then
                        printf 'final_result_set\n' >> "$debug_log"
                    fi
                    ;;
                *)
                    ;;
            esac

            if [[ "$event_type" == "stream_event" ]]; then
                local usage_candidate
                usage_candidate=$(printf '%s\n' "$line" | jq -c '(.event.usage // .event.response.usage // empty)' 2>/dev/null || echo "")
                if [[ -n "$usage_candidate" && "$usage_candidate" != "null" ]]; then
                    usage_cache="$usage_candidate"
                fi
                if [[ -z "$session_id_cache" ]]; then
                    local stream_session
                    stream_session=$(printf '%s\n' "$line" | jq -r '.event.session_id // empty' 2>/dev/null || echo "")
                    if [[ -n "$stream_session" ]]; then
                        session_id_cache="$stream_session"
                    fi
                fi
            fi
        done < "$pipe_path"

        if [[ -n "$final_result" ]]; then
            if [[ -n "$session_id_cache" ]]; then
                local patched_result
                patched_result=$(printf '%s\n' "$final_result" | jq --arg sid "$session_id_cache" '
                    if (.session_id // "" | length) == 0 then . + {session_id: $sid} else . end
                ' 2>/dev/null || echo "")
                if [[ -n "$patched_result" ]]; then
                    final_result="$patched_result"
                fi
            fi
            if [[ -n "$usage_cache" ]]; then
                local patched_usage_result
                patched_usage_result=$(printf '%s\n' "$final_result" | jq --argjson usage "$usage_cache" '
                    if (.usage // empty) == empty then . + {usage: $usage} else . end
                ' 2>/dev/null || echo "")
                if [[ -n "$patched_usage_result" ]]; then
                    final_result="$patched_usage_result"
                fi
            fi
            printf '%s\n' "$final_result" > "$output_target"
            if [[ -n "$debug_log" ]]; then
                printf 'wrote_final_result\n' >> "$debug_log"
            fi
            return 0
        fi

        local synthesized_text="$aggregated_text"
        if [[ -z "$synthesized_text" && -n "$last_assistant_text" ]]; then
            synthesized_text="$last_assistant_text"
        fi

        if [[ -n "$synthesized_text" ]]; then
            update_heartbeat
            local handled_stream_warning=0
            if _artifact_first_handle_stream_fallback "$session_dir" "$agent_label"; then
                handled_stream_warning=1
            fi
            if (( handled_stream_warning == 0 )); then
                if command -v log_system_warning &>/dev/null; then
                    log_system_warning "$session_dir" "claude_stream_missing_result" \
                        "Claude stream ended without final result event; using synthesized output" \
                        "agent=$agent_label"
                fi
            fi
            local synthetic_result
            synthetic_result=$(jq -n --arg text "$synthesized_text" --arg subtype "stream_synthesized" \
                '{type:"result",subtype:$subtype,result:$text}')
            if [[ -n "$session_id_cache" ]]; then
                synthetic_result=$(printf '%s\n' "$synthetic_result" | jq --arg sid "$session_id_cache" '. + {session_id: $sid}')
            fi
            local usage_json
            if [[ -n "$usage_cache" ]]; then
                usage_json="$usage_cache"
            else
                # Attempt to extract cost from stream.jsonl file before defaulting to zero
                local stream_cost="0"
                if [[ -f "$log_file" ]] && [[ -s "$log_file" ]]; then
                    local stream_payload
                    stream_payload=$(json_slurp_array "$log_file" '[]')
                    if [[ -n "$stream_payload" && "$stream_payload" != "[]" ]]; then
                        local extracted_cost
                        extracted_cost=$(safe_jq_from_json "$stream_payload" '[
                            .[] |
                            select(.type == "stream_event") |
                            (
                                .event.usage.total_cost_usd? //
                                .event.response.usage.total_cost_usd? //
                                .event.usage.cost.usd? //
                                empty
                            )
                        ] | last? // 0' "0" "$session_dir" "invoke_agent.stream_fallback_cost")
                        if [[ -n "$extracted_cost" && "$extracted_cost" != "null" && "$extracted_cost" != "0" ]]; then
                            stream_cost="$extracted_cost"
                            # Log successful cost extraction for diagnosis
                            if command -v log_event &>/dev/null && [[ -n "$session_dir" ]]; then
                                log_event "$session_dir" "cost_extraction_success" \
                                    "{\"agent\":\"$agent_label\",\"cost\":$stream_cost,\"source\":\"stream.jsonl\"}"
                            fi
                        fi
                    fi
                fi
                # Create usage JSON with extracted cost or zero
                usage_json=$(jq -n --argjson cost "$stream_cost" '{total_cost_usd: $cost}')
                
                # Add structured warning if cost extraction failed
                if [[ "$stream_cost" == "0" ]]; then
                    if command -v log_system_warning &>/dev/null; then
                        log_system_warning "$session_dir" "cost_extraction_failed" \
                            "Could not extract cost from stream.jsonl" \
                            "agent=$agent_label"
                    fi
                fi
            fi
            synthetic_result=$(printf '%s\n' "$synthetic_result" | jq --argjson usage "$usage_json" '. + {usage: $usage}')
            printf '%s\n' "$synthetic_result" > "$output_target"
            if [[ -n "$debug_log" ]]; then
                printf 'wrote_synthetic_result\n' >> "$debug_log"
            fi
            # Mark that fallback path was used (metrics will be logged later, but we need to skip duplicate logging)
            if [[ -n "$session_dir_param" ]]; then
                local fallback_flag="$session_dir_param/.agent-fallback-logged.${agent_label}.flag"
                touch "$fallback_flag" 2>/dev/null || true
            fi
            return 0
        fi

        # Fallback: try to salvage last JSON line if result missing
        local fallback_line=""
        if fallback_line=$(tail -n 1 "$log_file" 2>/dev/null); then
            if [[ -n "$fallback_line" ]]; then
                printf '%s\n' "$fallback_line" > "$output_target"
                if [[ -n "$debug_log" ]]; then
                    printf 'wrote_fallback\n' >> "$debug_log"
                fi
            fi
        fi
        return 1
    }

    # Change to session directory for context
    cd "$session_dir" || return 1
    local current_cwd
    current_cwd=$(pwd)
    if [[ "$current_cwd" != "$session_dir" ]]; then
        log_system_warning "$session_dir" "invoke_agent_cwd_mismatch" \
            "Working directory mismatch before agent invocation" \
            "expected=$session_dir actual=$current_cwd"
        cd "$session_dir" || return 1
    fi

    # Load agent timeout from config (before showing start message)
    load_agent_timeout() {
        local agent_name="$1"
        local fallback="${2:-600}"
        load_agent_runtime_config
        local resolved
        resolved=$(agent_runtime_config_lookup ".per_agent_timeouts.\"$agent_name\" // .default_timeout_seconds // empty" "" "invoke_agent.agent_timeout")
        if [[ -z "$resolved" || "$resolved" == "null" ]]; then
            echo "$fallback"
        else
            echo "$resolved"
        fi
    }

    local agent_timeout
    agent_timeout=$(load_agent_timeout "$agent_name")

    local timeout_description="timeouts disabled"
    if [[ "$agent_timeouts_enabled" -eq 1 ]]; then
        timeout_description="${agent_timeout}s timeout"
    fi

    local -a mode_annotations=("$timeout_description")
    if [[ "$watchdog_enabled" -eq 0 ]]; then
        mode_annotations+=("watchdog disabled")
    fi
    local mode_summary="${mode_annotations[0]}"
    if [[ ${#mode_annotations[@]} -gt 1 ]]; then
        for annotation in "${mode_annotations[@]:1}"; do
            mode_summary="${mode_summary}; ${annotation}"
        done
    fi

    if [[ "$watchdog_enabled" -eq 0 && "$agent_timeouts_enabled" -eq 1 ]]; then
        log_warn "Watchdog disabled; $agent_name timeout (${agent_timeout}s) will not be enforced."
    fi

    # Show friendly message in verbose mode, technical in normal/debug mode
    if is_verbose_enabled 2>/dev/null && [ "$(type -t verbose_agent_start)" = "function" ]; then
        # Verbose mode: user-friendly
        # Special message for orchestrator
        if [[ "$agent_name" == "mission-orchestrator" ]]; then
            if [ "$(type -t verbose)" = "function" ]; then
                verbose "🚦 Coordinating next research step... [mission-orchestrator with ${mode_summary}]"
            else
                echo "🚦 Coordinating next research step... [mission-orchestrator with ${mode_summary}]" >&2
            fi
        else
            # Regular agents: use sanitized task from environment if available, otherwise extract from file
            local task_desc=""
            if [[ -n "${CCONDUCTOR_TASK_DESC:-}" ]]; then
                task_desc="$CCONDUCTOR_TASK_DESC"
            elif [[ -f "$input_file" ]]; then
                # Fallback: extract first non-header, non-empty line from input file
                task_desc=$(grep -v '^##' "$input_file" 2>/dev/null | \
                            grep -v '^[[:space:]]*$' | \
                            head -n 1 | \
                            cut -c1-150)
            fi
            verbose_agent_start "$agent_name" "$task_desc"
            verbose "  [$agent_name with ${mode_summary}]"
        fi
    else
        # Normal/debug mode: technical
        if [[ "$agent_name" == "mission-orchestrator" ]]; then
            echo "→ Invoking mission orchestrator... [${mode_summary}]" >&2
        else
            echo "⚡ Invoking $agent_name with systemPrompt (tools: ${allowed_tools:-all}) [${mode_summary}]" >&2
        fi
    fi

    # Phase 2: Track start time for metrics
    local start_time
    # macOS-compatible milliseconds (epoch gives seconds, multiply by 1000)
    start_time=$(($(get_epoch) * 1000))

    # Phase 2: Log agent invocation with model
    if [ -n "${session_dir:-}" ] && command -v log_agent_invocation &>/dev/null; then
        log_agent_invocation "$session_dir" "$agent_name" "${allowed_tools:-all}" "" "$agent_model" || true
    fi

    # Start event tailer for real-time tool display
    # In verbose mode: shows detailed messages
    # In non-verbose mode: shows progress dots
    # Tailer prevents duplicates by checking if already running
    local invoke_agent_dir="$SCRIPT_DIR"
    
    if [[ "${CCONDUCTOR_SKIP_EVENT_TAILER:-0}" != "1" ]]; then
        # shellcheck disable=SC1091
        if source "$invoke_agent_dir/event-tailer.sh" 2>/dev/null; then
            start_event_tailer "$session_dir" || true
            tailer_started=1
        fi
    fi

    # Set agent name for hooks (enables heartbeat tracking)
    export CCONDUCTOR_AGENT_NAME="$agent_name"

    local heartbeat_file="$session_dir/.agent-heartbeat"

    # Initialize heartbeat file
    {
        local timestamp
        timestamp=$(get_epoch)
        printf '%s:%s\n' "$agent_name" "$timestamp"
    } > "${heartbeat_file}.tmp" 2>/dev/null || true
    mv "${heartbeat_file}.tmp" "$heartbeat_file" 2>/dev/null || true

    # Read task from input file
    local task
    task=$(cat "$input_file")

    # Prepare diagnostic paths
    stderr_file="${output_file}.stderr"
    : > "$stderr_file"
    if [[ "$use_streaming" -eq 1 ]]; then
        stream_log="${output_file}.stream.jsonl"
        : > "$stream_log"
        stream_pipe=$(mktemp "$session_dir/.agent-stream.XXXXXX")
        rm -f "$stream_pipe"
        if mkfifo "$stream_pipe"; then
            process_stream_events "$stream_pipe" "$stream_log" "$output_file" "$heartbeat_file" "$agent_name" "$session_dir" &
            stream_processor_pid=$!
            printf '%s\n' "$task" | CLAUDE_PROJECT_DIR="$session_dir" "${claude_cmd[@]}" > "$stream_pipe" 2> "$stderr_file" &
        else
            log_warn "Failed to initialize streaming FIFO; reverting to legacy JSON output"
            rm -f "$stream_pipe" 2>/dev/null || true
            stream_pipe=""
            use_streaming=0
            rm -f "$stream_log" 2>/dev/null || true
            stream_log=""
            local -a fallback_cmd=()
            local skip_next_value=0
            for arg in "${claude_cmd[@]}"; do
                if [[ "$arg" == "--verbose" || "$arg" == "--include-partial-messages" ]]; then
                    continue
                fi
                if [[ "$arg" == "--output-format" ]]; then
                    fallback_cmd+=("$arg")
                    fallback_cmd+=("json")
                    skip_next_value=1
                    continue
                fi
                if [[ "$skip_next_value" -eq 1 ]]; then
                    skip_next_value=0
                    continue
                fi
                fallback_cmd+=("$arg")
            done
            claude_cmd=("${fallback_cmd[@]}")
            printf '%s\n' "$task" | CLAUDE_PROJECT_DIR="$session_dir" "${fallback_cmd[@]}" > "$output_file" 2> "$stderr_file" &
        fi
    else
        printf '%s\n' "$task" | CLAUDE_PROJECT_DIR="$session_dir" "${claude_cmd[@]}" > "$output_file" 2> "$stderr_file" &
    fi
    local agent_pid=$!

    # Start watchdog in background to monitor for inactivity
    local watchdog_pid=""
    if [[ "$watchdog_enabled" -eq 1 && -f "$cconductor_root/src/utils/agent-watchdog.sh" ]]; then
        "$bash_runtime" "$cconductor_root/src/utils/agent-watchdog.sh" \
            "$session_dir" "$agent_pid" "$agent_timeout" "$agent_name" &
        watchdog_pid=$!
    fi

    # Wait for agent to complete
    wait "$agent_pid"
    local agent_exit_code=$?

    if [[ "$use_streaming" -eq 1 ]]; then
        if [[ -n "$stream_processor_pid" ]]; then
            wait "$stream_processor_pid" || true
            stream_processor_pid=""
        fi
        if [[ -f "$stream_log" ]] && { [[ ! -s "$output_file" ]] || ! jq empty "$output_file" 2>/dev/null; }; then
            local extracted_stream_result=""
            local stream_payload
            stream_payload=$(json_slurp_array "$stream_log" '[]')
            extracted_stream_result=$(safe_jq_from_json "$stream_payload" 'map(select(.type == "result")) | last // empty' "" "$session_dir" "invoke_agent.stream_extracted" "false")
            if [[ -n "$extracted_stream_result" ]]; then
                printf '%s\n' "$extracted_stream_result" > "$output_file"
            fi
        fi
        rm -f "$stream_pipe" 2>/dev/null || true
        stream_pipe=""
    fi

    # Kill watchdog if it's still running
    if [[ -n "$watchdog_pid" ]]; then
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
    fi

    # Clean up heartbeat file (no stale state between agents)
    rm -f "$heartbeat_file" 2>/dev/null || true

    # Check if agent timed out (exit code 124 = timeout, 143 = SIGTERM)
    if [[ $agent_exit_code -eq 124 ]] || [[ $agent_exit_code -eq 143 ]]; then
        if [[ "$watchdog_enabled" -eq 1 && "$agent_timeouts_enabled" -eq 1 ]]; then
            echo "✗ $agent_name timed out after ${agent_timeout}s (no activity detected)" >&2

            # Log timeout event for orchestrator awareness
            if command -v log_event &>/dev/null; then
                log_event "$session_dir" "agent_invocation_timeout" \
                    "{\"agent\":\"$agent_name\",\"timeout_seconds\":$agent_timeout}" 2>/dev/null || true
            fi

            return 124
        else
            echo "⚠️  $agent_name exited with code $agent_exit_code while watchdog/timeouts disabled; continuing." >&2
            agent_exit_code=0
        fi
    fi

    # Continue with existing validation if agent succeeded
    if [[ $agent_exit_code -eq 0 ]]; then
        # Return to original directory
        cd "$original_dir" || true

        # Check if output file is empty (synthesis-agent may produce artifacts without JSON)
        if [ ! -s "$output_file" ]; then
            # For synthesis-agent, check if expected artifacts were created
            if [[ "$agent_name" == "synthesis-agent" ]] && [ -f "$session_dir/report/mission-report.md" ]; then
                # Create minimal success JSON for validation
                echo '{"type":"result","subtype":"success","result":"Mission report generated at report/mission-report.md"}' > "$output_file"
            else
                # Empty output is a failure for other agents
                echo "✗ Agent $agent_name produced no output" >&2
                return 1
            fi
        fi

        # Validate JSON output
        # VALIDATED: diagnostic-json-structure.sh confirmed .result path
        if ! jq empty "$output_file" 2>/dev/null; then
            local error_sample
            error_sample=$(head -c 500 "$output_file" 2>/dev/null || echo "Unable to read output")
            log_system_error "$session_dir" "invalid_json" \
                "Agent $agent_name returned invalid JSON" \
                "Output sample: $error_sample"
            echo "✗ Agent $agent_name returned invalid JSON" >&2
            echo "Raw output:" >&2
            cat "$output_file" >&2
            return 1
        fi

        # Check for .result field
        local result
        result=$(safe_jq_from_file "$output_file" '.result // empty' "" "$session_dir" "invoke_agent.result")

        if [ -z "$result" ]; then
            echo "✗ Agent $agent_name returned empty .result field" >&2
            echo "Response structure:" >&2
            jq 'keys' "$output_file" >&2
            return 1
        fi
        if _detect_provider_session_limit_phrase "$result"; then
            local limit_message
            limit_message=$(_extract_provider_session_limit_message "$result")
            _record_provider_session_limit "$session_dir" "$agent_name" "$limit_message" "$use_streaming"
            return 1
        fi
        if _notify_provider_session_limit "$output_file" "$session_dir" "$agent_name" "$use_streaming"; then
            return 1
        fi
        
        # NEW: Validate .result field is extractable JSON for research agents (Tier 0 requirement)
        if [[ "$agent_name" =~ ^(web-researcher|academic-researcher|pdf-analyzer|code-analyzer|fact-checker|market-analyzer)$ ]]; then
            # Source the battle-tested JSON parser
            local parser_script="$cconductor_root/src/utils/json-parser.sh"
            if [[ -f "$parser_script" ]]; then
                # shellcheck disable=SC1090
                source "$parser_script"
                
                # Attempt to extract JSON from agent output
                local extracted_json
                if extracted_json=$(extract_json_from_agent_output "$output_file" false 2>/dev/null); then
                    # Success - validate it's not empty
                    if [[ -n "$extracted_json" ]] && echo "$extracted_json" | jq empty 2>/dev/null; then
                        echo "  ✓ Agent $agent_name output validated as JSON" >&2
                        # For web-researcher, enrich JSON with findings_files if missing
                        if [[ "$agent_name" == "web-researcher" ]]; then
                            findings_field_present=false
                            if echo "$extracted_json" | jq -e 'has("status") and has("findings_files")' >/dev/null 2>&1; then
                                findings_field_present=true
                            fi

                            if [[ "$findings_field_present" != "true" ]]; then
                                local manifest_file="$session_dir/work/web-researcher/manifest.actual.json"
                                if [[ -f "$manifest_file" ]]; then
                                    local findings_paths
                                    findings_paths=$(jq -r '[.artifacts[] | select(.slot == "web_research_findings") | .relative_path] | unique' "$manifest_file" 2>/dev/null)
                                    if [[ -n "$findings_paths" && "$findings_paths" != "null" && "$findings_paths" != "[]" ]]; then
                                        local enriched_json
                                        enriched_json=$(echo "$extracted_json" | jq --argjson files "$findings_paths" '
                                            if (has("status") | not) then .status = "completed" else . end |
                                            .findings_files = $files
                                        ' 2>/dev/null || echo '')
                                        if [[ -n "$enriched_json" ]]; then
                                            local tmp_json
                                            tmp_json=$(mktemp "${TMPDIR:-/tmp}/web-researcher-result.XXXXXX.json")
                                            if echo "$enriched_json" | jq . > "$tmp_json" 2>/dev/null; then
                                                mv "$tmp_json" "$output_file"
                                                extracted_json="$enriched_json"
                                                echo "  ✓ Injected findings_files from manifest (web-researcher)" >&2
                                                findings_field_present=true
                                            else
                                                rm -f "$tmp_json"
                                            fi
                                        fi
                                    fi
                                fi
                            fi

                            if [[ "$findings_field_present" == "true" ]]; then
                                echo "  ✓ Manifest structure valid" >&2
                            else
                                echo "  ⚠️  Warning: Manifest missing required fields (status, findings_files)" >&2
                            fi
                        fi
                    else
                        echo "⚠️  Warning: Agent $agent_name extracted JSON is empty or invalid" >&2
                        echo "   Tier 0 extraction will fail. Falling back to Tier 1/2." >&2
                    fi
                else
                    local fallback_used=0
                    if [[ "$agent_name" == "academic-researcher" ]]; then
                        local manifest_file="$session_dir/work/academic-researcher/manifest.json"
                        if [[ -f "$manifest_file" ]]; then
                            local manifest_json
                            manifest_json=$(cat "$manifest_file")
                            if [[ -n "$manifest_json" ]] && echo "$manifest_json" | jq empty >/dev/null 2>&1; then
                                local tmp_output
                                tmp_output=$(mktemp "${TMPDIR:-/tmp}/agent-output.XXXXXX.json")
                                if jq --argjson manifest "$manifest_json" '.result = $manifest' "$output_file" > "$tmp_output" 2>/dev/null; then
                                    mv "$tmp_output" "$output_file"
                                    extracted_json="$manifest_json"
                                    fallback_used=1
                                    echo "  ✓ Academic researcher manifest parsed via fallback (Tier 0)" >&2
                                else
                                    rm -f "$tmp_output"
                                fi
                            fi
                        fi
                    fi

                    if [[ "$fallback_used" -eq 0 ]]; then
                    echo "⚠️  Warning: Agent $agent_name output could not be parsed as JSON" >&2
                    echo "   Tier 0 extraction will fail. Falling back to Tier 1/2." >&2
                    
                    # Log for monitoring
                    if command -v log_event &>/dev/null; then
                        local result_preview
                        local preview_raw
                        preview_raw=$(safe_jq_from_file "$output_file" '.result // "no result"' "no result" "$session_dir" "invoke_agent.result_preview")
                        result_preview=$(printf '%s' "$preview_raw" | head -c 100)
                        log_event "$session_dir" "tier0_format_mismatch" \
                            "Agent $agent_name returned non-parseable result" \
                            "{\"agent\": \"$agent_name\", \"result_preview\": \"$result_preview\"}" || true
                    fi
                    else
                        if [[ -n "$extracted_json" ]] && echo "$extracted_json" | jq empty 2>/dev/null; then
                            echo "  ✓ Agent $agent_name output validated as JSON" >&2
                            if echo "$extracted_json" | jq -e 'has("status") and has("findings_files")' >/dev/null 2>&1; then
                                echo "  ✓ Manifest structure valid" >&2
                            else
                                echo "  ⚠️  Warning: Manifest missing required fields (status, findings_files)" >&2
                            fi
                        fi
                    fi
                fi
            else
                echo "⚠️  Warning: json-parser.sh not found, skipping enhanced validation" >&2
            fi
        fi

        # Phase 2: Extract metrics and log result
        local end_time
        end_time=$(($(get_epoch) * 1000))
        local duration=$((end_time - start_time))
        
        # Extract cost from Claude's response using shared helper
        # Pass agent_name and session_dir for improved warning logic
        local cost
        cost=$(extract_cost_from_output "$output_file" "$agent_name" "$session_dir")
        
        # Extract agent-specific metadata for research journal view
        local metadata
        metadata=$(extract_agent_metadata "$agent_name" "$output_file" "$session_dir" 2>/dev/null || echo "{}")
        # Compact JSON to single line to avoid quoting issues
        local metadata_trimmed="${metadata//[[:space:]]/}"
        if [[ -z "$metadata_trimmed" || "$metadata_trimmed" == "{}" ]]; then
            metadata="{}"
        else
            metadata=$(safe_jq_from_json "$metadata" '.' '{}' "$session_dir" "invoke_agent.metadata.normalize" false)
        fi
        
        local manifest_result="{}"
        local finalize_status=0
        if [ -n "${session_dir:-}" ] && command -v artifact_finalize_manifest &>/dev/null; then
            set +e
            manifest_result=$(_finalize_agent_output "$session_dir" "$agent_name")
            finalize_status=$?
            set -e
            if [[ -z "$manifest_result" ]]; then
                manifest_result="{}"
            fi
        fi

        local bypass_active_flag
        if [[ "$ARTIFACT_VALIDATION_PHASE" == "phase1" || "$ARTIFACT_CONTRACT_BYPASS" -eq 1 ]]; then
            bypass_active_flag=true
        else
            bypass_active_flag=false
        fi

        local contract_pass_flag="false"
        if [[ $finalize_status -eq 0 ]]; then
            echo "  ✓ Artifact contract validated ($ARTIFACT_VALIDATION_PHASE)" >&2
            contract_pass_flag="true"
        else
            if [[ "$ARTIFACT_CONTRACT_BYPASS" -eq 1 || "$ARTIFACT_VALIDATION_PHASE" == "phase1" ]]; then
                echo "  ⚠ Artifact contract violations bypassed for $agent_name" >&2
                contract_pass_flag="true"
            else
                echo "✗ Artifact contract validation failed for $agent_name" >&2
            fi
        fi

        if [[ -n "$manifest_result" ]]; then
            local contract_metrics
            contract_metrics=$(echo "$manifest_result" | jq -c \
                --arg phase "$ARTIFACT_VALIDATION_PHASE" \
                --arg pass_flag "$contract_pass_flag" \
                --arg bypass_active "$bypass_active_flag" \
                '{
                    artifact_contract: {
                        pass: ($pass_flag == "true"),
                        validation_phase: $phase,
                        bypass_active: ($bypass_active == "true"),
                        validation_duration_ms: (.validation_duration_ms // 0),
                        required_total: (.summary?.required_total // 0),
                        required_present: (.summary?.required_present // 0),
                        optional_present: (.summary?.optional_present // 0),
                        total_artifacts: (.summary?.total_artifacts // 0),
                        missing_slots: (.summary?.missing_slots // []),
                        checksum_failures: (.summary?.checksum_failures // []),
                        schema_failures: (.summary?.schema_failures // [])
                    }
                }' 2>/dev/null || echo '{}')

            if [[ -n "$contract_metrics" && "$contract_metrics" != "{}" ]]; then
                metadata=$(echo "$metadata" | jq -c --argjson contract "$contract_metrics" '. * $contract' 2>/dev/null || echo "$metadata")
            fi
        fi

        # Log agent result with metrics, metadata, and model
        # Skip if fallback path already handled logging (to avoid double-logging)
        if [ -n "${session_dir:-}" ] && command -v log_agent_result &>/dev/null && [ ! -f "$fallback_logged_flag" ]; then
            log_agent_result "$session_dir" "$agent_name" "$cost" "$duration" "$metadata" "$agent_model" || true
        fi
        
        # Clean up fallback flag
        rm -f "$fallback_logged_flag" 2>/dev/null || true
        
        # Validate extracted cost matches logged cost (cost extraction bug detection)
        # events.jsonl is written AFTER extraction, so we can now verify they match
        if [[ -n "${session_dir:-}" ]]; then
            local logged_cost
            logged_cost=$(extract_cost_from_events "$session_dir" "$agent_name")
            
            # Compare extracted cost vs logged cost (with small tolerance for floating point)
            # Use bc for floating point arithmetic (required by AGENTS.md)
            local cost_diff
            cost_diff=$(echo "scale=10; if ($cost > $logged_cost) then ($cost - $logged_cost) else ($logged_cost - $cost) fi" | bc 2>/dev/null || echo "0")
            
            # Flag discrepancies > 0.0001 (detect real bugs, ignore floating point noise)
            if (( $(echo "$cost_diff > 0.0001" | bc -l 2>/dev/null || echo 0) )); then
                if command -v log_system_warning &>/dev/null; then
                    log_system_warning "$session_dir" "cost_extraction_mismatch" \
                        "Cost extraction mismatch for $agent_name" \
                        "extracted=$cost logged=$logged_cost diff=$cost_diff"
                fi
            fi
        fi
        if [[ $finalize_status -ne 0 && "$ARTIFACT_VALIDATION_PHASE" != "phase1" && "$ARTIFACT_CONTRACT_BYPASS" -eq 0 ]]; then
            return "$finalize_status"
        fi

        # Integrate findings into knowledge graph for research agents
        if [[ "$agent_name" =~ ^(web-researcher|academic-researcher|pdf-analyzer|code-analyzer|fact-checker|market-analyzer)$ ]]; then
            if [ -n "${session_dir:-}" ]; then
                local agent_output_file="$session_dir/work/${agent_name}/output.json"
                if [ -f "$agent_output_file" ]; then
                    # Call standalone wrapper via subprocess (handles all dependencies internally)
                    # Use cconductor_root (not PROJECT_ROOT) - it's the reliable variable discovered earlier
                    local wrapper_script="$cconductor_root/src/utils/kg-integrate.sh"
                    if [ -f "$wrapper_script" ]; then
                        if "$bash_runtime" "$wrapper_script" "$session_dir" "$agent_output_file" 2>&1; then
                            echo "  ✓ Integrated findings into knowledge graph" >&2
                        else
                            echo "  ⚠ Warning: Could not integrate findings (knowledge graph may be incomplete)" >&2
                        fi
                    else
                        echo "  ⚠ Warning: KG integration wrapper not found at $wrapper_script" >&2
                    fi
                fi
            fi
        fi
        
        # Regenerate dashboard metrics after each agent completes (for live updates)
        if [ -n "${session_dir:-}" ] && command -v dashboard_update_metrics &>/dev/null; then
            dashboard_update_metrics "$session_dir" || true
        fi

        if [[ "$agent_name" == "synthesis-agent" ]]; then
            local report_renderer_sh="$cconductor_root/src/utils/render_mission_report.sh"
            if [[ -f "$report_renderer_sh" ]]; then
                local renderer_cmd=()
                if [[ -n "${CCONDUCTOR_BASH_RUNTIME:-}" ]]; then
                    renderer_cmd=("${CCONDUCTOR_BASH_RUNTIME}" "$report_renderer_sh")
                elif [[ -n "${BASH_RUNTIME:-}" ]]; then
                    renderer_cmd=("${BASH_RUNTIME}" "$report_renderer_sh")
                else
                    renderer_cmd=("$report_renderer_sh")
                fi
                if ! "${renderer_cmd[@]}" "$session_dir"; then
                    echo "  ⚠ Warning: Mission report evidence rendering failed" >&2
                fi
            fi
        fi

        # Show agent reasoning in verbose mode
        if is_verbose_enabled 2>/dev/null && [ "$(type -t verbose_agent_reasoning)" = "function" ]; then
            local reasoning_payload
            reasoning_payload=$(extract_json_from_result_output "$output_file")
            if [[ -n "$reasoning_payload" ]]; then
                local reasoning_json
                reasoning_json=$(safe_jq_from_json "$reasoning_payload" '.reasoning // empty' "" "$session_dir" "invoke_agent.verbose_reasoning" false)
                if [ -n "$reasoning_json" ] && [ "$reasoning_json" != "null" ]; then
                    verbose_agent_reasoning "$reasoning_json"
                fi
            fi
        fi

        # Get friendly name for completion message
        local friendly_name=""
        if [[ -n "${session_dir:-}" ]]; then
            local metadata_file="$session_dir/.claude/agents/${agent_name}/metadata.json"
            if [[ -f "$metadata_file" ]]; then
                friendly_name=$(safe_jq_from_file "$metadata_file" '.display_name // empty' "" "$session_dir" "invoke_agent.friendly_name")
            fi
        fi
        if [[ -z "$friendly_name" ]]; then
            friendly_name="${agent_name//-/ }"
        fi
        
        # In non-verbose mode, add newline before message (to end progress dots line)
        if [[ "${CCONDUCTOR_VERBOSE:-0}" != "1" ]]; then
            echo "" >&2
        fi
        echo "✓ $friendly_name completed successfully" >&2
        
        # Stop event tailer if it was started
        if [[ "$tailer_started" == "1" ]] && declare -F stop_event_tailer >/dev/null 2>&1; then
            # Give tailer time to catch up with final events
            sleep 1
            stop_event_tailer "${session_dir:-}" || true
        fi
        
        return 0
    else
        # Capture exit code from agent invocation
        # shellcheck disable=SC2319
        local exit_code=$?

        # Return to original directory
        cd "$original_dir" || true
        
        # Stop event tailer if it was started
        if [[ "$tailer_started" == "1" ]] && declare -F stop_event_tailer >/dev/null 2>&1; then
            sleep 0.5
            stop_event_tailer "${session_dir:-}" || true
        fi

        # Get friendly name for error message
        local friendly_name=""
        if [[ -n "${session_dir:-}" ]]; then
            local metadata_file="$session_dir/.claude/agents/${agent_name}/metadata.json"
            if [[ -f "$metadata_file" ]]; then
                friendly_name=$(safe_jq_from_file "$metadata_file" '.display_name // empty' "" "$session_dir" "invoke_agent.final_friendly_name")
            fi
        fi
        if [[ -z "$friendly_name" ]]; then
            friendly_name="${agent_name//-/ }"
        fi
        
        if _notify_provider_session_limit "$output_file" "$session_dir" "$agent_name" "$use_streaming"; then
            return 1
        fi

        if [[ "${CCONDUCTOR_VERBOSE:-0}" != "1" ]]; then
            echo "" >&2
        fi
        echo "✗ $friendly_name failed with code $exit_code" >&2
        return 1
    fi
}

# Export functions
export -f check_claude_cli
export -f extract_agent_metadata
export -f extract_cost_from_events
export -f extract_cost_from_output
export -f invoke_agent_v2

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        invoke-v2)
            invoke_agent_v2 "$2" "$3" "$4" "${5:-600}" "$6" "${7:-}"
            ;;
        check)
            check_claude_cli && echo "✓ Claude CLI is available"
            ;;
        *)
            {
                cat <<'EOF'
Usage: $0 <command> [args...]

Commands:
  invoke-v2 <agent> <input_file> <output_file> [timeout] <session_dir> [resume_session_id]
      Invoke agent with v2 implementation (validated patterns)
      - Injects systemPrompt via --append-system-prompt
      - Enforces tool restrictions via agent-tools.json
      - Returns clean JSON with .result field
      
  check
      Check if Claude CLI is available

Examples:
  $0 invoke-v2 web-researcher input.txt output.json 600 /path/to/session session_abc123
  $0 check

Notes:
  - session_dir is REQUIRED and must contain .claude/agents/ directory
  - Timeout default is 600 seconds (10 minutes)
  - All patterns validated in validation_tests/
  - Optional resume_session_id enables Claude's --resume flow for multi-turn agents

Input File Format:
  The input_file should contain the task/query and explicit JSON formatting instructions:
  
  "Your task here. Return ONLY valid JSON with these fields:
  - field1: description
  - field2: description
  
  NO explanatory text, just the JSON object starting with {."

Output File Format (JSON):
  {
    "type": "result",
    "result": "the agent's response (JSON if requested in prompt)",
    "session_id": "...",
    "usage": {...}
  }

Tool Restrictions:
  Tool access is controlled by src/utils/agent-tools.json
  Format: {"agent-name": {"allowed": ["Tool1"], "disallowed": ["Tool2"]}}
  Domain restrictions: "WebFetch(*.edu)" or "WebFetch(arxiv.org)"

Validation:
  All patterns tested in validation_tests/:
  - JSON output: test-01
  - System prompts: test-append-system-prompt.sh  
  - Tool restrictions: test-04, test-05, test-06
  - JSON extraction: diagnostic-json-structure.sh
EOF
            } >&2
            exit 1
            ;;
    esac
fi
