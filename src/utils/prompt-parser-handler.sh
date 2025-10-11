#!/usr/bin/env bash
# Prompt Parser Handler
# Handles prompt parsing through the orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-parser.sh" 2>/dev/null || true

# Check if prompt needs parsing
needs_prompt_parsing() {
    local session_dir="$1"
    local session_file="$session_dir/session.json"
    
    if [ ! -f "$session_file" ]; then
        return 1
    fi
    
    local prompt_parsed
    prompt_parsed=$(jq -r '.prompt_parsed // false' "$session_file" 2>/dev/null || echo "false")
    
    if [ "$prompt_parsed" = "false" ]; then
        return 0  # Needs parsing
    fi
    
    return 1  # Already parsed
}

# Parse the prompt and update session
parse_prompt() {
    local session_dir="$1"
    local session_file="$session_dir/session.json"
    
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
    # shellcheck disable=SC1091
    source "$UTILS_DIR/mission-orchestration.sh"
    
    if _invoke_delegated_agent "$session_dir" "prompt-parser" "$task" "Extract clean research objective from user prompt" "[]"; then
        echo "  ✓ Prompt parsed successfully" >&2
        
        # Extract parsed results from agent output
        local agent_output="$session_dir/agent-output-prompt-parser.json"
        if [ -f "$agent_output" ]; then
            local result
            result=$(jq -r '.result // empty' "$agent_output" 2>/dev/null || echo "")
            
            if [ -n "$result" ]; then
                # Extract JSON from result (handles markdown code fences)
                local parsed_json
                if command -v extract_json_from_text &>/dev/null; then
                    parsed_json=$(extract_json_from_text "$result" 2>/dev/null || echo "")
                else
                    parsed_json="$result"
                fi
                
                if [ -n "$parsed_json" ] && echo "$parsed_json" | jq empty 2>/dev/null; then
                    # Extract components
                    local clean_objective
                    clean_objective=$(echo "$parsed_json" | jq -r '.objective // empty' 2>/dev/null)
                    local output_spec
                    output_spec=$(echo "$parsed_json" | jq -r '.output_specification // "null"' 2>/dev/null)
                    
                    if [ -n "$clean_objective" ]; then
                        # Update session.json
                        local temp_session="${session_file}.tmp"
                        jq --arg obj "$clean_objective" \
                           --arg spec "$output_spec" \
                           '.objective = $obj | 
                            .output_specification = (if $spec == "null" or $spec == "" then null else $spec end) |
                            .prompt_parsed = true' \
                           "$session_file" > "$temp_session"
                        
                        mv "$temp_session" "$session_file"
                        
                        # Update knowledge graph with clean objective
                        local kg_file="$session_dir/knowledge-graph.json"
                        if [ -f "$kg_file" ]; then
                            local temp_kg="${kg_file}.tmp"
                            jq --arg obj "$clean_objective" \
                               '.research_objective = $obj' \
                               "$kg_file" > "$temp_kg"
                            mv "$temp_kg" "$kg_file"
                        fi
                        
                        echo "  ✓ Session and knowledge graph updated with clean objective" >&2
                        
                        # Verbose output - show parsed results
                        if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
                            echo "" >&2
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                            echo "📝 Prompt Parser Results" >&2
                            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
                            echo "" >&2
                            echo "Core Objective (for research agents):" >&2
                            echo "  $clean_objective" >&2
                            echo "" >&2
                            if [[ -n "$output_spec" && "$output_spec" != "null" ]]; then
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
                        
                        # Clean up
                        rm -f "$session_dir/user-prompt.txt"
                        
                        return 0
                    fi
                fi
            fi
        fi
        
        echo "  ⚠ Warning: Could not extract parsed results, using original prompt" >&2
    else
        echo "  ⚠ Warning: Prompt parsing failed, using original prompt" >&2
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

