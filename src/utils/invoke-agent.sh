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

# Source event logger for Phase 2 metrics
# shellcheck disable=SC1091
source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/verbose.sh" 2>/dev/null || true


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

# Extract agent-specific metadata for research journal view
# Returns a JSON object with relevant metrics for each agent type
extract_agent_metadata() {
    local agent_name="$1"
    local output_file="$2"
    local session_dir="$3"
    
    # Default empty metadata
    local metadata="{}"
    
    # Helper function to extract JSON from markdown code blocks
    extract_json_from_result() {
        local file="$1"
        # shellcheck disable=SC2016
        # SC2016: Single quotes intentional - we want literal regex patterns, not variable expansion
        jq -r '.result // ""' "$file" 2>/dev/null | \
            sed -n '/^```json$/,/^```$/p' | \
            sed '1d;$d' | \
            jq -c '.' 2>/dev/null || echo ""
    }
    
    # OPTION 2: Self-Describing Agents
    # First, try to extract standardized .metadata field from agent output
    local result_json
    result_json=$(extract_json_from_result "$output_file")
    
    if [ -n "$result_json" ]; then
        local agent_metadata
        agent_metadata=$(echo "$result_json" | jq -c '.metadata // empty' 2>/dev/null)
        
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
                reasoning=$(echo "$result_json" | jq -c '.reasoning // empty' 2>/dev/null)
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
                tasks_count=$(echo "$result_json" | jq '.initial_tasks // [] | length' 2>/dev/null || echo "0")
                # Fallback: if initial_tasks doesn't exist, try direct array length
                if [ "$tasks_count" -eq 0 ]; then
                    tasks_count=$(echo "$result_json" | jq 'if type == "array" then length else 0 end' 2>/dev/null || echo "0")
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
            findings_files=$(echo "$result_json" | jq -r '.findings_files[]? // empty' 2>/dev/null || echo "")
            
            if [ -n "$findings_files" ]; then
                # Agent provided manifest - use it
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
            else
                # TIER 2: Filesystem fallback - look for findings files
                # Check raw/ directory (standard location)
                if [ -d "$session_dir/raw" ]; then
                    for findings_file in "$session_dir/raw"/findings-*.json "$session_dir/raw"/*findings*.json; do
                        [ -f "$findings_file" ] || continue
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    done
                fi
                
                # Also check session root for findings files (multiple patterns)
                # Patterns: *-findings.json, *findings*.json (catches all variations)
                for findings_file in "$session_dir"/*-findings.json "$session_dir"/*findings*.json; do
                    [ -f "$findings_file" ] || continue
                    local file_entities
                    file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                    entities=$((entities + file_entities))
                    
                    local file_claims
                    file_claims=$(jq '[.claims[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                    claims=$((claims + file_claims))
                done
            fi
            
            # TIER 3: KG validation - verify findings were actually integrated
            # (This provides observability - we can log if numbers don't match)
            if [ -f "$session_dir/knowledge-graph.json" ]; then
                local kg_entities
                kg_entities=$(jq '.entities | length' "$session_dir/knowledge-graph.json" 2>/dev/null || echo "0")
                
                # If we found findings but KG is still low, log warning
                if [ "$entities" -gt 5 ] && [ "$kg_entities" -lt 5 ]; then
                    echo "  ⚠ Warning: Found $entities entities in findings but only $kg_entities in KG - integration may have failed" >&2
                fi
            fi
            
            # Count WebSearch tool uses from events.jsonl
            if [ -f "$session_dir/events.jsonl" ]; then
                searches=$(grep '"academic-researcher"' "$session_dir/events.jsonl" | \
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
            findings_files=$(echo "$result_json" | jq -r '.findings_files[]? // empty' 2>/dev/null || echo "")
            
            if [ -n "$findings_files" ]; then
                # Agent provided manifest - use it
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
            else
                # TIER 2: Filesystem fallback - look for findings files
                # Check raw/ directory (standard location)
                if [ -d "$session_dir/raw" ]; then
                    for findings_file in "$session_dir/raw"/findings-*.json "$session_dir/raw"/*findings*.json; do
                        [ -f "$findings_file" ] || continue
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    done
                fi
                
                # Also check session root for findings files (multiple patterns)
                # Patterns: *-findings.json, *findings*.json (catches all variations like water_composition_research_findings.json)
                for findings_file in "$session_dir"/*-findings.json "$session_dir"/*findings*.json; do
                    [ -f "$findings_file" ] || continue
                    local file_entities
                    file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                    entities=$((entities + file_entities))
                    
                    local file_claims
                    file_claims=$(jq '[.claims[]? // empty] | length' "$findings_file" 2>/dev/null || echo "0")
                    claims=$((claims + file_claims))
                done
            fi
            
            # TIER 3: KG validation - verify findings were actually integrated
            # (This provides observability - we can log if numbers don't match)
            if [ -f "$session_dir/knowledge-graph.json" ]; then
                local kg_entities
                kg_entities=$(jq '.entities | length' "$session_dir/knowledge-graph.json" 2>/dev/null || echo "0")
                
                # If we found findings but KG is still low, log warning
                if [ "$entities" -gt 5 ] && [ "$kg_entities" -lt 5 ]; then
                    echo "  ⚠ Warning: Found $entities entities in findings but only $kg_entities in KG - integration may have failed" >&2
                fi
            fi
            
            # Count WebSearch tool uses from events.jsonl
            if [ -f "$session_dir/events.jsonl" ]; then
                searches=$(grep '"web-researcher"' "$session_dir/events.jsonl" | \
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
                claims=$(jq -r '.claims_analyzed // 0' "$session_dir/artifacts/synthesis-agent/completion.json" 2>/dev/null || echo "0")
            fi
            
            if [ -f "$session_dir/artifacts/synthesis-agent/coverage.json" ]; then
                gaps=$(jq -r '.aspects_not_covered // 0' "$session_dir/artifacts/synthesis-agent/coverage.json" 2>/dev/null || echo "0")
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
#   invoke_agent_v2 <agent_name> <input_file> <output_file> [timeout] <session_dir>
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

    # Load agent definition
    local agent_file="$session_dir/.claude/agents/${agent_name}.json"

    if [ ! -f "$agent_file" ]; then
        echo "Error: Agent definition not found: $agent_file" >&2
        return 1
    fi

    # Extract systemPrompt from agent definition
    # VALIDATED: Correct JSON path in diagnostic-json-structure.sh
    local system_prompt
    system_prompt=$(jq -r '.systemPrompt' "$agent_file" 2>/dev/null)

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
    agent_model=$(jq -r '.model // "sonnet"' "$agent_file" 2>/dev/null || echo "sonnet")
    
    # Build Claude command with validated flags
    # VALIDATED:
    # - --output-format json: test-01
    # - --append-system-prompt: test-append-system-prompt.sh
    # - --allowedTools: test-04
    # - --disallowedTools: test-05
    local claude_cmd=(
        claude
        --print
        --model "$agent_model"  # Now uses per-agent model
        --output-format json          # VALIDATED: test-01
        --append-system-prompt "$system_prompt"  # VALIDATED: test-append-system-prompt.sh
    )

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

    # Change to session directory for context
    local original_dir
    original_dir=$(pwd)
    cd "$session_dir" || return 1

    # Load agent timeout from config (before showing start message)
    load_agent_timeout() {
        local agent_name="$1"
        if [[ -f "$PROJECT_ROOT/src/utils/config-loader.sh" ]]; then
            # shellcheck disable=SC1091
            source "$PROJECT_ROOT/src/utils/config-loader.sh" 2>/dev/null || { echo "600"; return; }
            local config
            config=$(load_config "agent-timeouts" 2>/dev/null || echo "{}")
            echo "$config" | jq -r ".per_agent_timeouts.\"$agent_name\" // .default_timeout_seconds // 600"
        else
            echo "600"
        fi
    }

    local agent_timeout
    agent_timeout=$(load_agent_timeout "$agent_name")

    # Show friendly message in verbose mode, technical in normal/debug mode
    if is_verbose_enabled 2>/dev/null && [ "$(type -t verbose_agent_start)" = "function" ]; then
        # Verbose mode: user-friendly
        # Special message for orchestrator
        if [[ "$agent_name" == "mission-orchestrator" ]]; then
            if [ "$(type -t verbose)" = "function" ]; then
                verbose "🎯 Coordinating next research step... [mission-orchestrator with ${agent_timeout}s timeout]"
            else
                echo "🎯 Coordinating next research step... [mission-orchestrator with ${agent_timeout}s timeout]" >&2
            fi
        else
            # Regular agents: extract first line of input file as task description
            local task_desc=""
            if [ -f "$input_file" ]; then
                task_desc=$(head -n 1 "$input_file" 2>/dev/null || echo "")
            fi
            verbose_agent_start "$agent_name" "$task_desc"
            verbose "  [$agent_name with ${agent_timeout}s timeout]"
        fi
    else
        # Normal/debug mode: technical
        if [[ "$agent_name" == "mission-orchestrator" ]]; then
            echo "→ Invoking mission orchestrator... [${agent_timeout}s timeout]" >&2
        else
            echo "⚡ Invoking $agent_name with systemPrompt (tools: ${allowed_tools:-all}) [${agent_timeout}s timeout]" >&2
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
    local tailer_started=0
    local invoke_agent_dir
    invoke_agent_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # shellcheck disable=SC1091
    if source "$invoke_agent_dir/event-tailer.sh" 2>/dev/null; then
        start_event_tailer "$session_dir" || true
        tailer_started=1
    fi

    # Set agent name for hooks (enables heartbeat tracking)
    export CCONDUCTOR_AGENT_NAME="$agent_name"

    # Initialize heartbeat file
    echo "${agent_name}:$(get_epoch)" > "$session_dir/.agent-heartbeat" 2>/dev/null || true

    # Read task from input file
    local task
    task=$(cat "$input_file")

    # Start agent in background with watchdog monitoring
    # Output goes to $output_file in JSON format
    # Note: Don't redirect stderr (2>&1) - let hooks write to terminal in verbose mode
    printf '%s\n' "$task" | CLAUDE_PROJECT_DIR="$session_dir" "${claude_cmd[@]}" > "$output_file" &
    local agent_pid=$!

    # Start watchdog in background to monitor for inactivity
    local watchdog_pid=""
    if [[ -f "$PROJECT_ROOT/src/utils/agent-watchdog.sh" ]]; then
        bash "$PROJECT_ROOT/src/utils/agent-watchdog.sh" \
            "$session_dir" "$agent_pid" "$agent_timeout" "$agent_name" &
        watchdog_pid=$!
    fi

    # Wait for agent to complete
    wait "$agent_pid"
    local agent_exit_code=$?

    # Kill watchdog if it's still running
    if [[ -n "$watchdog_pid" ]]; then
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
    fi

    # Check if agent timed out (exit code 124 = timeout, 143 = SIGTERM)
    if [[ $agent_exit_code -eq 124 ]] || [[ $agent_exit_code -eq 143 ]]; then
        echo "✗ $agent_name timed out after ${agent_timeout}s (no activity detected)" >&2
        
        # Log timeout event for orchestrator awareness
        if command -v log_event &>/dev/null; then
            log_event "$session_dir" "agent_invocation_timeout" \
                "{\"agent\":\"$agent_name\",\"timeout_seconds\":$agent_timeout}" 2>/dev/null || true
        fi
        
        return 124
    fi

    # Continue with existing validation if agent succeeded
    if [[ $agent_exit_code -eq 0 ]]; then
        # Return to original directory
        cd "$original_dir" || true

        # Check if output file is empty (synthesis-agent may produce artifacts without JSON)
        if [ ! -s "$output_file" ]; then
            # For synthesis-agent, check if expected artifacts were created
            if [[ "$agent_name" == "synthesis-agent" ]] && [ -f "$session_dir/final/mission-report.md" ]; then
                # Create minimal success JSON for validation
                echo '{"type":"result","subtype":"success","result":"Mission report generated at final/mission-report.md"}' > "$output_file"
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
            if command -v log_error &>/dev/null; then
                log_error "$session_dir" "invalid_json" \
                    "Agent $agent_name returned invalid JSON" \
                    "Output sample: $error_sample"
            fi
            echo "✗ Agent $agent_name returned invalid JSON" >&2
            echo "Raw output:" >&2
            cat "$output_file" >&2
            return 1
        fi

        # Check for .result field
        local result
        result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)

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
                        result_preview=$(jq -r '.result // "no result"' "$output_file" 2>/dev/null | head -c 100)
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
        
        # Try to extract cost from Claude's response
        # Common paths: .usage.total_cost_usd, .total_cost_usd
        local cost
        cost=$(jq -r '.usage.total_cost_usd // .total_cost_usd // 0' "$output_file" 2>/dev/null || echo "0")
        
        # Extract agent-specific metadata for research journal view
        local metadata
        metadata=$(extract_agent_metadata "$agent_name" "$output_file" "$session_dir" 2>/dev/null || echo "{}")
        # Compact JSON to single line to avoid quoting issues
        metadata=$(echo "$metadata" | jq -c '.' 2>/dev/null || echo "{}")
        
        # Log agent result with metrics, metadata, and model
        if [ -n "${session_dir:-}" ] && command -v log_agent_result &>/dev/null; then
            log_agent_result "$session_dir" "$agent_name" "$cost" "$duration" "$metadata" "$agent_model" || true
        fi
        
        # Integrate findings into knowledge graph for research agents
        if [[ "$agent_name" =~ ^(web-researcher|academic-researcher|pdf-analyzer|code-analyzer|fact-checker|market-analyzer)$ ]]; then
            if [ -n "${session_dir:-}" ]; then
                local agent_output_file="$session_dir/agent-output-${agent_name}.json"
                if [ -f "$agent_output_file" ]; then
                    # Call standalone wrapper via subprocess (handles all dependencies internally)
                    # Use cconductor_root (not PROJECT_ROOT) - it's the reliable variable discovered earlier
                    local wrapper_script="$cconductor_root/src/utils/kg-integrate.sh"
                    if [ -f "$wrapper_script" ]; then
                        if bash "$wrapper_script" "$session_dir" "$agent_output_file" 2>&1; then
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
            # Try to extract reasoning from agent output (JSON format)
            local reasoning_json
            # shellcheck disable=SC2016
            reasoning_json=$(jq -r '.result' "$output_file" 2>/dev/null | \
                            sed -n '/^```json$/,/^```$/p' | sed '1d;$d' | \
                            jq -c '.reasoning // empty' 2>/dev/null || echo "")
            
            if [ -n "$reasoning_json" ] && [ "$reasoning_json" != "null" ]; then
                verbose_agent_reasoning "$reasoning_json"
            fi
        fi

        # Get friendly name for completion message
        local friendly_name=""
        if [[ -n "${session_dir:-}" ]]; then
            local metadata_file="$session_dir/.claude/agents/${agent_name}/metadata.json"
            if [[ -f "$metadata_file" ]]; then
                friendly_name=$(jq -r '.display_name // empty' "$metadata_file" 2>/dev/null)
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
            stop_event_tailer "$session_dir" || true
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
            stop_event_tailer "$session_dir" || true
        fi

        # Get friendly name for error message
        local friendly_name=""
        if [[ -n "${session_dir:-}" ]]; then
            local metadata_file="$session_dir/.claude/agents/${agent_name}/metadata.json"
            if [[ -f "$metadata_file" ]]; then
                friendly_name=$(jq -r '.display_name // empty' "$metadata_file" 2>/dev/null)
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
export -f invoke_agent_v2

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        invoke-v2)
            invoke_agent_v2 "$2" "$3" "$4" "${5:-600}" "$6"
            ;;
        check)
            check_claude_cli && echo "✓ Claude CLI is available"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args...]

Commands:
  invoke-v2 <agent> <input_file> <output_file> [timeout] <session_dir>
      Invoke agent with v2 implementation (validated patterns)
      - Injects systemPrompt via --append-system-prompt
      - Enforces tool restrictions via agent-tools.json
      - Returns clean JSON with .result field
      
  check
      Check if Claude CLI is available

Examples:
  $0 invoke-v2 web-researcher input.txt output.json 600 /path/to/session
  $0 check

Notes:
  - session_dir is REQUIRED and must contain .claude/agents/ directory
  - Timeout default is 600 seconds (10 minutes)
  - All patterns validated in validation_tests/

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
