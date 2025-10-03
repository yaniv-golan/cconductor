#!/bin/bash
# Agent Invocation Helper
# Invokes Claude CLI agents with proper context

set -euo pipefail

# Check if Claude CLI is available
check_claude_cli() {
    if ! command -v claude &> /dev/null; then
        echo "Error: Claude CLI not found in PATH" >&2
        echo "Please install Claude CLI: https://docs.claude.com/en/docs/claude-code/overview" >&2
        return 1
    fi
    return 0
}

# Invoke a Claude agent with input/output files
invoke_agent() {
    local agent_name="$1"
    local input_file="$2"
    local output_file="$3"
    local timeout="${4:-600}"  # 10 minutes default
    local session_dir="${5:-}"  # REQUIRED: session directory for context isolation
    
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
    
    # Create prompt that references the agent and includes input data
    local prompt
    prompt=$(cat <<EOF
Please process this research task using your capabilities as the $agent_name agent.

Input data:
$(cat "$input_file")

Provide your response in the structured JSON format specified in your agent definition.
EOF
)
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    # Change to session directory
    local original_dir
    original_dir=$(pwd)
    cd "$session_dir" || return 1
    
    echo "⚡ Invoking $agent_name agent from session context..." >&2
    
    # Run Claude in non-interactive mode
    # Claude will auto-discover agents from .claude/ in current directory
    # Note: MCP config disabled until proper format is implemented
    if echo "$prompt" | timeout "$timeout" claude \
        --print \
        --output-format text \
        --model sonnet \
        > "$output_file" 2>&1; then
        
        # Return to original directory
        cd "$original_dir" || true
        
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

# Invoke agent with JSON input/output
invoke_agent_json() {
    local agent_name="$1"
    local input_json="$2"
    local output_file="$3"
    local timeout="${4:-600}"
    local session_dir="${5:-}"  # REQUIRED: session directory
    
    # Create temp input file
    local temp_input
    temp_input=$(mktemp)
    echo "$input_json" > "$temp_input"
    
    # Invoke agent with session context
    invoke_agent "$agent_name" "$temp_input" "$output_file" "$timeout" "$session_dir"
    local result=$?
    
    # Cleanup
    rm -f "$temp_input"
    
    return $result
}

# Invoke agent with direct prompt (simple interface)
invoke_agent_simple() {
    local agent_name="$1"
    local prompt_text="$2"
    local output_file="$3"
    local timeout="${4:-600}"
    local session_dir="${5:-}"  # REQUIRED: session directory
    
    # Validate session_dir
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
    
    # Change to session directory
    local original_dir
    original_dir=$(pwd)
    cd "$session_dir" || return 1
    
    echo "⚡ Invoking $agent_name agent from session context..." >&2
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    # Run Claude directly with the prompt
    # Note: MCP config disabled until proper format is implemented
    if echo "$prompt_text" | timeout "$timeout" claude \
        --print \
        --output-format text \
        --model sonnet \
        > "$output_file" 2>&1; then
        
        cd "$original_dir" || true
        echo "✓ Agent $agent_name completed successfully" >&2
        return 0
    else
        local exit_code=$?
        cd "$original_dir" || true
        
        if [ $exit_code -eq 124 ]; then
            echo "✗ Agent $agent_name timed out after ${timeout}s" >&2
        else
            echo "✗ Agent $agent_name failed with code $exit_code" >&2
        fi
        return 1
    fi
}

# Parse JSON output from Claude (handle both direct JSON and text wrapper)
extract_json_output() {
    local output_file="$1"
    local extracted_file="$2"
    
    if [ ! -f "$output_file" ]; then
        echo "Error: Output file not found: $output_file" >&2
        return 1
    fi
    
    # Try to extract JSON from the output
    # Claude might wrap it in markdown code blocks or text
    if grep -q '```json' "$output_file"; then
        # Extract from markdown code block
        # shellcheck disable=SC2016
        sed -n '/```json/,/```/p' "$output_file" | \
            sed '1d;$d' > "$extracted_file"
    elif grep -q '```' "$output_file"; then
        # Generic code block without json marker
        # shellcheck disable=SC2016
        sed -n '/```/,/```/p' "$output_file" | \
            sed '1d;$d' > "$extracted_file"
    elif grep -q '^{' "$output_file"; then
        # Already JSON, just copy
        cp "$output_file" "$extracted_file"
    else
        # Try to find JSON in the output (look for { ... } blocks)
        awk '/^{/,/^}/' "$output_file" > "$extracted_file"
        if [ ! -s "$extracted_file" ]; then
            echo "Warning: Could not extract JSON from output" >&2
            cp "$output_file" "$extracted_file"
        fi
    fi
    
    # Validate extracted JSON
    if jq '.' "$extracted_file" >/dev/null 2>&1; then
        return 0
    else
        echo "Warning: Extracted content is not valid JSON" >&2
        # Try to pretty-print anyway for debugging
        cat "$extracted_file" >&2
        return 1
    fi
}

# Auto-extract JSON after agent invocation
invoke_agent_with_extraction() {
    local agent_name="$1"
    local input_file="$2"
    local output_file="$3"
    local timeout="${4:-600}"
    local session_dir="${5:-}"  # REQUIRED: session directory
    
    # Temp file for raw output
    local raw_output="${output_file}.raw"
    
    # Invoke agent with session context
    if invoke_agent "$agent_name" "$input_file" "$raw_output" "$timeout" "$session_dir"; then
        # Extract JSON
        if extract_json_output "$raw_output" "$output_file"; then
            rm -f "$raw_output"
            return 0
        else
            echo "Warning: JSON extraction failed, using raw output" >&2
            mv "$raw_output" "$output_file"
            return 1
        fi
    else
        return 1
    fi
}

# Export functions
export -f check_claude_cli
export -f invoke_agent
export -f invoke_agent_json
export -f invoke_agent_simple
export -f extract_json_output

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        invoke)
            invoke_agent "$2" "$3" "$4" "${5:-600}" "$6"
            ;;
        invoke-json)
            invoke_agent_json "$2" "$3" "$4" "${5:-600}" "$6"
            ;;
        invoke-simple)
            invoke_agent_simple "$2" "$3" "$4" "${5:-600}" "$6"
            ;;
        extract-json)
            extract_json_output "$2" "$3"
            ;;
        check)
            check_claude_cli && echo "✓ Claude CLI is available"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args...]

Commands:
  invoke <agent> <input_file> <output_file> [timeout] <session_dir>
      Invoke agent with input from file
      
  invoke-json <agent> <json_string> <output_file> [timeout] <session_dir>
      Invoke agent with JSON string input
      
  invoke-simple <agent> <prompt> <output_file> [timeout] <session_dir>
      Invoke agent with simple text prompt
      
  extract-json <output_file> <extracted_file>
      Extract JSON from agent output
      
  check
      Check if Claude CLI is available

Examples:
  $0 invoke research-planner input.json output.json 600 /path/to/session
  $0 invoke-simple research-planner "What is Docker?" output.txt 600 /path/to/session
  $0 check

Notes:
  - session_dir is REQUIRED and must contain a .claude/ directory
  - Timeout default is 600 seconds (10 minutes)
EOF
            ;;
    esac
fi

