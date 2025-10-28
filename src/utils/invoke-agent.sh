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

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

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

# Extract cost from Claude CLI output.json
# Returns numeric cost or 0 if missing
# Usage: extract_cost_from_output "$output_file"
extract_cost_from_output() {
    local output_file="$1"
    
    if [[ ! -f "$output_file" ]]; then
        echo "0"
        return 0
    fi
    
    # Try common paths: .usage.total_cost_usd, .total_cost_usd
    local cost
    cost=$(safe_jq_from_file "$output_file" '.usage.total_cost_usd // .total_cost_usd // 0 | tonumber? // 0' "0" "$session_dir" "invoke_agent.cost")
    
    # Optional: Log warning if file exists but has no cost field (verbose mode only)
    if is_verbose_enabled 2>/dev/null && [[ "$cost" == "0" ]] && [[ -s "$output_file" ]]; then
        if ! jq -e '.usage.total_cost_usd // .total_cost_usd' "$output_file" >/dev/null 2>&1; then
            echo "  ⚠ No cost field found in $output_file" >&2
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
            if [[ -n "${original_dir:-}" ]]; then
                cd "$original_dir" >/dev/null 2>&1 || true
            fi
            cleanup_performed=1
        fi
        return $status
    }
    trap 'cleanup_invoke_agent' EXIT INT TERM HUP

    process_stream_events() {
        local pipe_path="$1"
        local log_file="$2"
        local output_target="$3"
        local heartbeat_path="$4"
        local agent_label="$5"
        local debug_log="${CCONDUCTOR_STREAM_DEBUG_LOG:-}"

        : > "$log_file"
        if [[ -n "$debug_log" ]]; then
            : > "$debug_log"
        fi

        local final_result=""
        local line=""
        local aggregated_text=""
        local last_assistant_text=""

        while IFS= read -r line; do
            printf '%s\n' "$line" >> "$log_file"
            if [[ -n "$debug_log" ]]; then
                printf '%s\n' "$line" >> "$debug_log"
            fi
            [[ -z "$line" ]] && continue

            local event_type
            event_type=$(safe_jq_from_json "$line" '.type // empty' "" "$session_dir" "invoke_agent.stream.event_type")

            case "$event_type" in
                stream_event)
                    local inner_type
                    inner_type=$(safe_jq_from_json "$line" '.event.type // empty' "" "$session_dir" "invoke_agent.stream.inner_type")
                    case "$inner_type" in
                        message_start|message_delta|content_block_start|content_block_delta|content_block_stop|tool_use_start|tool_use_delta|tool_use_stop)
                            echo "${agent_label}:$(get_epoch)" > "$heartbeat_path" 2>/dev/null || true
                            ;;
                    esac
                    if [[ "$inner_type" == "content_block_delta" || "$inner_type" == "message_delta" ]]; then
                        local delta_text
                        delta_text=$(safe_jq_from_json "$line" '.event.delta.text? // empty' "" "$session_dir" "invoke_agent.stream.delta")
                        if [[ -n "$delta_text" && "$delta_text" != "null" ]]; then
                            aggregated_text+="$delta_text"
                        fi
                    fi
                    ;;
                assistant|message)
                    echo "${agent_label}:$(get_epoch)" > "$heartbeat_path" 2>/dev/null || true
                    local assistant_text
                    assistant_text=$(safe_jq_from_json "$line" '[.message.content[]? | select(.type=="text") | .text] | join("")' "" "$session_dir" "invoke_agent.stream.assistant")
                    if [[ -n "$assistant_text" && "$assistant_text" != "null" ]]; then
                        last_assistant_text="$assistant_text"
                    fi
                    ;;
                result)
                    final_result="$line"
                    if [[ -n "$debug_log" ]]; then
                        printf 'final_result_set\n' >> "$debug_log"
                    fi
                    ;;
                *)
                    ;;
            esac
        done < "$pipe_path"

        if [[ -n "$final_result" ]]; then
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
            local synthetic_result
            synthetic_result=$(jq -n --arg text "$synthesized_text" --arg subtype "stream_synthesized" \
                '{type:"result",subtype:$subtype,result:$text}')
            printf '%s\n' "$synthetic_result" > "$output_target"
            if [[ -n "$debug_log" ]]; then
                printf 'wrote_synthetic_result\n' >> "$debug_log"
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
    echo "${agent_name}:$(get_epoch)" > "$heartbeat_file" 2>/dev/null || true

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
            process_stream_events "$stream_pipe" "$stream_log" "$output_file" "$heartbeat_file" "$agent_name" &
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
                        
                        # For web-researcher, verify manifest structure
                        if [[ "$agent_name" == "web-researcher" ]]; then
                            if echo "$extracted_json" | jq -e 'has("status") and has("findings_files")' >/dev/null 2>&1; then
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
        local cost
        cost=$(extract_cost_from_output "$output_file")
        
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
        
        # Log agent result with metrics, metadata, and model
        if [ -n "${session_dir:-}" ] && command -v log_agent_result &>/dev/null; then
            log_agent_result "$session_dir" "$agent_name" "$cost" "$duration" "$metadata" "$agent_model" || true
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
        
        # In non-verbose mode, add newline before message (to end progress dots line)
        if [[ "${CCONDUCTOR_VERBOSE:-0}" != "1" ]]; then
            echo "" >&2
        fi
        
        # Note: Exit code 124/143 (timeout) is handled earlier, so this handles other failures
        echo "✗ $friendly_name failed with code $exit_code" >&2
        return 1
    fi
}

# Export functions
export -f check_claude_cli
export -f extract_agent_metadata
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
            cat <<EOF
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
            ;;
    esac
fi
