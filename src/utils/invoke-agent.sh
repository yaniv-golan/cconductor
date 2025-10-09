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

# Source event logger for Phase 2 metrics
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null || true

# Check if Claude CLI is available
check_claude_cli() {
    if ! command -v claude &> /dev/null; then
        echo "Error: Claude CLI not found in PATH" >&2
        echo "Install (native): curl -fsSL https://claude.ai/install.sh | bash" >&2
        echo "Or (npm): npm install -g @anthropic-ai/claude-code" >&2
        echo "Docs: https://docs.claude.com/en/docs/claude-code/overview" >&2
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
            # Count entities and claims from findings files
            # Count searches from events.jsonl
            local entities=0
            local claims=0
            local searches=0
            
            # Extract findings files from agent output (result_json already extracted above)
            local findings_files
            findings_files=$(echo "$result_json" | jq -r '.findings_files[]? // empty' 2>/dev/null || echo "")
            
            if [ -n "$findings_files" ]; then
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        # Count entities_discovered
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        # Count claims
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
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
            # Count entities and claims from findings files
            # Count searches from events.jsonl
            local entities=0
            local claims=0
            local searches=0
            
            # Extract findings files from agent output (result_json already extracted above)
            local findings_files
            findings_files=$(echo "$result_json" | jq -r '.findings_files[]? // empty' 2>/dev/null || echo "")
            
            if [ -n "$findings_files" ]; then
                while IFS= read -r findings_file; do
                    if [ -f "$session_dir/$findings_file" ]; then
                        # Count entities_discovered
                        local file_entities
                        file_entities=$(jq '[.entities_discovered[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        entities=$((entities + file_entities))
                        
                        # Count claims
                        local file_claims
                        file_claims=$(jq '[.claims[]? // empty] | length' "$session_dir/$findings_file" 2>/dev/null || echo "0")
                        claims=$((claims + file_claims))
                    fi
                done <<< "$findings_files"
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
            # Extract synthesis statistics from agent's output
            local claims=0
            local gaps=0
            
            # Extract from synthesis agent's output (result_json already extracted above)
            if [ -n "$result_json" ]; then
                # Try to count claims synthesized
                claims=$(echo "$result_json" | jq '[.claims_synthesized[]? // empty] | length' 2>/dev/null || echo "0")
                # If that doesn't work, try counting from synthesis object
                if [ "$claims" = "0" ]; then
                    claims=$(echo "$result_json" | jq '[.synthesis.claims[]? // empty] | length' 2>/dev/null || echo "0")
                fi
                
                # Count gaps found
                gaps=$(echo "$result_json" | jq '[.gaps_identified[]? // empty] | length' 2>/dev/null || echo "0")
                if [ "$gaps" = "0" ]; then
                    gaps=$(echo "$result_json" | jq '[.knowledge_gaps[]? // empty] | length' 2>/dev/null || echo "0")
                fi
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
    local timeout="${4:-600}"
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

    # Build Claude command with validated flags
    # VALIDATED:
    # - --output-format json: test-01
    # - --append-system-prompt: test-append-system-prompt.sh
    # - --allowedTools: test-04
    # - --disallowedTools: test-05
    local claude_cmd=(
        claude
        --print
        --model sonnet
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

    # Export session directory and agent name for hooks to use
    export CCONDUCTOR_SESSION_DIR="$session_dir"
    export CCONDUCTOR_AGENT_NAME="$agent_name"

    # Change to session directory for context
    local original_dir
    original_dir=$(pwd)
    cd "$session_dir" || return 1

    echo "⚡ Invoking $agent_name with systemPrompt (tools: ${allowed_tools:-all})" >&2

    # Phase 2: Track start time for metrics
    local start_time
    # macOS-compatible milliseconds (date +%s gives seconds, multiply by 1000)
    start_time=$(($(date +%s) * 1000))

    # Phase 2: Log agent invocation
    if [ -n "${session_dir:-}" ] && command -v log_agent_invocation &>/dev/null; then
        log_agent_invocation "$session_dir" "$agent_name" "${allowed_tools:-all}" "" || true
    fi

    # Read task from input file
    local task
    task=$(cat "$input_file")

    # Invoke Claude with validated patterns
    # Output goes to $output_file in JSON format
    # Note: timeout command not available on macOS by default, so we run without it
    # The claude CLI has its own timeout mechanisms
    if echo "$task" | "${claude_cmd[@]}" > "$output_file" 2>&1; then
        # Return to original directory
        cd "$original_dir" || true

        # Validate JSON output
        # VALIDATED: diagnostic-json-structure.sh confirmed .result path
        if ! jq empty "$output_file" 2>/dev/null; then
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

        # Phase 2: Extract metrics and log result
        local end_time
        end_time=$(($(date +%s) * 1000))
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
        
        # Log agent result with metrics and metadata
        if [ -n "${session_dir:-}" ] && command -v log_agent_result &>/dev/null; then
            log_agent_result "$session_dir" "$agent_name" "$cost" "$duration" "$metadata" || true
        fi

        echo "✓ Agent $agent_name completed successfully" >&2
        return 0
    else
        local exit_code=$?

        # Return to original directory
        cd "$original_dir" || true

        if [ $exit_code -eq 124 ]; then
            echo "✗ Agent $agent_name timed out after ${timeout}s" >&2
        else
            echo "✗ Agent $agent_name failed with code $exit_code" >&2
        fi
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
