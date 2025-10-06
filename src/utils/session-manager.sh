#!/usr/bin/env bash
# Session Manager for Agent Continuity (Phase 1)
# Manages multi-turn conversations with agents using Claude Code's --resume feature
#
# VALIDATION: Pattern validated in validation_tests/test-13-session-continuity.sh
# - Sessions auto-save (no --save-session flag needed)
# - Extract .session_id from response
# - Use --resume <session_id> for follow-ups
# - System prompts work with --resume

set -euo pipefail

# Get script directory for invoking invoke-agent.sh CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Session state directory structure:
# $session_dir/
#   .agent-sessions/
#     <agent-name>.session    # Contains session_id
#     <agent-name>.metadata   # Contains session metadata (JSON)

# Start a new agent session with initial context
# VALIDATED: test-13-session-continuity.sh
#
# Args:
#   agent_name: Name of agent (e.g., "web-researcher")
#   session_dir: Research session directory
#   initial_task: Initial task/context to provide to agent
#   timeout: Optional timeout in seconds (default: 600)
#
# Returns:
#   Session ID on success, empty on failure
#
# Side Effects:
#   - Creates .agent-sessions/ directory
#   - Stores session_id in .agent-sessions/<agent>.session
#   - Stores metadata in .agent-sessions/<agent>.metadata
#
start_agent_session() {
    local agent_name="$1"
    local session_dir="$2"
    local initial_task="$3"
    local timeout="${4:-600}"

    # Validate inputs
    if [ -z "$agent_name" ] || [ -z "$session_dir" ] || [ -z "$initial_task" ]; then
        echo "Error: start_agent_session requires agent_name, session_dir, and initial_task" >&2
        return 1
    fi

    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: $session_dir" >&2
        return 1
    fi

    # Create session tracking directory
    local sessions_dir="$session_dir/.agent-sessions"
    mkdir -p "$sessions_dir"

    # Check if session already exists for this agent
    local session_file="$sessions_dir/${agent_name}.session"
    if [ -f "$session_file" ]; then
        echo "Warning: Agent $agent_name already has a session, returning existing session_id" >&2
        cat "$session_file"
        return 0
    fi

    echo "⚡ Starting new session for agent: $agent_name" >&2

    # Create temporary files for input/output
    local input_file="$sessions_dir/${agent_name}.start-input.txt"
    local output_file="$sessions_dir/${agent_name}.start-output.json"

    # Write initial task
    echo "$initial_task" > "$input_file"

    # Invoke agent using v2 (which handles systemPrompt, tools, JSON)
    # VALIDATED: invoke_agent_v2 returns JSON with .session_id
    if ! bash "$SCRIPT_DIR/invoke-agent.sh" invoke-v2 \
        "$agent_name" \
        "$input_file" \
        "$output_file" \
        "$timeout" \
        "$session_dir"; then
        echo "Error: Failed to start session for agent $agent_name" >&2
        return 1
    fi

    # Extract session ID
    # VALIDATED: .session_id field exists in response (test-13)
    local session_id
    session_id=$(jq -r '.session_id // empty' "$output_file" 2>/dev/null)

    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        echo "Error: Could not extract session_id from response" >&2
        echo "Response structure:" >&2
        jq 'keys' "$output_file" >&2
        return 1
    fi

    # Store session ID
    echo "$session_id" > "$session_file"

    # Store metadata
    local metadata_file="$sessions_dir/${agent_name}.metadata"
    cat > "$metadata_file" <<EOF
{
  "agent_name": "$agent_name",
  "session_id": "$session_id",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "turn_count": 1,
  "last_updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    echo "✓ Session started for $agent_name: $session_id" >&2
    echo "$session_id"
}

# Continue an existing agent session with a new task
# VALIDATED: test-13-session-continuity.sh
#
# Args:
#   agent_name: Name of agent
#   session_dir: Research session directory
#   task: New task for the agent
#   output_file: File to write response to
#   timeout: Optional timeout in seconds (default: 600)
#
# Returns:
#   0 on success, 1 on failure
#
# Side Effects:
#   - Updates metadata with new turn count and timestamp
#   - Writes response to output_file
#
continue_agent_session() {
    local agent_name="$1"
    local session_dir="$2"
    local task="$3"
    local output_file="$4"
    local timeout="${5:-600}"

    # Validate inputs
    if [ -z "$agent_name" ] || [ -z "$session_dir" ] || [ -z "$task" ] || [ -z "$output_file" ]; then
        echo "Error: continue_agent_session requires agent_name, session_dir, task, and output_file" >&2
        return 1
    fi

    # Check if session exists
    local sessions_dir="$session_dir/.agent-sessions"
    local session_file="$sessions_dir/${agent_name}.session"

    if [ ! -f "$session_file" ]; then
        echo "Error: No active session for agent $agent_name" >&2
        echo "Hint: Call start_agent_session() first" >&2
        return 1
    fi

    # Get session ID
    local session_id
    session_id=$(cat "$session_file")

    echo "⚡ Continuing session for agent: $agent_name (session: $session_id)" >&2

    # Get agent definition for systemPrompt
    local agent_file="$session_dir/.claude/agents/${agent_name}.json"
    if [ ! -f "$agent_file" ]; then
        echo "Error: Agent definition not found: $agent_file" >&2
        return 1
    fi

    local system_prompt
    system_prompt=$(jq -r '.systemPrompt' "$agent_file" 2>/dev/null)

    if [ -z "$system_prompt" ] || [ "$system_prompt" = "null" ]; then
        echo "Error: Agent $agent_name missing systemPrompt" >&2
        return 1
    fi

    # Get tool restrictions
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
    fi

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

    # Build Claude command with --resume
    # VALIDATED: --resume works with --append-system-prompt (test-13)
    local claude_cmd=(
        claude
        --print
        --model sonnet
        --output-format json
        --resume "$session_id"  # VALIDATED: Preserves context
        --append-system-prompt "$system_prompt"
    )

    # Add MCP config if present
    if [ -f "$session_dir/.mcp.json" ]; then
        claude_cmd+=(--mcp-config "$session_dir/.mcp.json")
    fi

    # Add tool restrictions
    if [ -n "$allowed_tools" ]; then
        claude_cmd+=(--allowedTools "$allowed_tools")
    fi
    if [ -n "$disallowed_tools" ]; then
        claude_cmd+=(--disallowedTools "$disallowed_tools")
    fi

    # Create output directory
    mkdir -p "$(dirname "$output_file")"

    # Change to session directory for context
    local original_dir
    original_dir=$(pwd)
    cd "$session_dir" || return 1

    # Invoke Claude with session continuity
    # VALIDATED: Context is preserved from previous turns (test-13)
    if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then
        cd "$original_dir" || true

        # Validate JSON output
        if ! jq empty "$output_file" 2>/dev/null; then
            echo "✗ Agent $agent_name returned invalid JSON" >&2
            return 1
        fi

        # Check for .result field
        local result
        result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)

        if [ -z "$result" ]; then
            echo "✗ Agent $agent_name returned empty .result field" >&2
            return 1
        fi

        # Update metadata
        local metadata_file="$sessions_dir/${agent_name}.metadata"
        if [ -f "$metadata_file" ]; then
            local turn_count
            turn_count=$(jq -r '.turn_count' "$metadata_file")
            turn_count=$((turn_count + 1))

            jq --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
               --arg turns "$turn_count" \
               '.turn_count = ($turns | tonumber) | .last_updated = $timestamp' \
               "$metadata_file" > "${metadata_file}.tmp"
            mv "${metadata_file}.tmp" "$metadata_file"
        fi

        echo "✓ Agent $agent_name turn completed (session: $session_id)" >&2
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

# Get session ID for an agent (if exists)
#
# Args:
#   agent_name: Name of agent
#   session_dir: Research session directory
#
# Returns:
#   Session ID if exists, empty otherwise
#
get_agent_session_id() {
    local agent_name="$1"
    local session_dir="$2"

    local session_file="$session_dir/.agent-sessions/${agent_name}.session"

    if [ -f "$session_file" ]; then
        cat "$session_file"
    else
        echo ""
    fi
}

# Check if agent has an active session
#
# Args:
#   agent_name: Name of agent
#   session_dir: Research session directory
#
# Returns:
#   0 if session exists, 1 otherwise
#
has_agent_session() {
    local agent_name="$1"
    local session_dir="$2"

    local session_file="$session_dir/.agent-sessions/${agent_name}.session"
    [ -f "$session_file" ]
}

# Get session metadata for an agent
#
# Args:
#   agent_name: Name of agent
#   session_dir: Research session directory
#
# Returns:
#   JSON metadata if exists, empty otherwise
#
get_agent_session_metadata() {
    local agent_name="$1"
    local session_dir="$2"

    local metadata_file="$session_dir/.agent-sessions/${agent_name}.metadata"

    if [ -f "$metadata_file" ]; then
        cat "$metadata_file"
    else
        echo "{}"
    fi
}

# End an agent session (cleanup)
#
# Args:
#   agent_name: Name of agent
#   session_dir: Research session directory
#
# Returns:
#   0 on success, 1 if session doesn't exist
#
# Note: This just removes local tracking files. The Claude session
# remains active on their servers until it expires naturally.
#
end_agent_session() {
    local agent_name="$1"
    local session_dir="$2"

    local sessions_dir="$session_dir/.agent-sessions"
    local session_file="$sessions_dir/${agent_name}.session"

    if [ ! -f "$session_file" ]; then
        echo "Warning: No active session to end for agent $agent_name" >&2
        return 1
    fi

    local session_id
    session_id=$(cat "$session_file")

    echo "Ending session for agent $agent_name (session: $session_id)" >&2

    # Remove tracking files
    rm -f "$session_file"
    rm -f "$sessions_dir/${agent_name}.metadata"
    rm -f "$sessions_dir/${agent_name}.start-input.txt"
    rm -f "$sessions_dir/${agent_name}.start-output.json"

    echo "✓ Session ended for $agent_name" >&2
    return 0
}

# Export functions
export -f start_agent_session
export -f continue_agent_session
export -f get_agent_session_id
export -f has_agent_session
export -f get_agent_session_metadata
export -f end_agent_session

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        start)
            start_agent_session "$2" "$3" "$4" "${5:-600}"
            ;;
        continue)
            continue_agent_session "$2" "$3" "$4" "$5" "${6:-600}"
            ;;
        get-id)
            get_agent_session_id "$2" "$3"
            ;;
        has-session)
            has_agent_session "$2" "$3" && echo "yes" || echo "no"
            ;;
        get-metadata)
            get_agent_session_metadata "$2" "$3"
            ;;
        end)
            end_agent_session "$2" "$3"
            ;;
        *)
            cat <<EOF
Usage: $0 <command> [args...]

Commands:
  start <agent> <session_dir> <initial_task> [timeout]
      Start new agent session with initial context
      Returns: session_id
      
  continue <agent> <session_dir> <task> <output_file> [timeout]
      Continue existing agent session with new task
      Requires: Prior call to 'start'
      
  get-id <agent> <session_dir>
      Get session ID for agent (if exists)
      
  has-session <agent> <session_dir>
      Check if agent has active session (returns yes/no)
      
  get-metadata <agent> <session_dir>
      Get session metadata (JSON)
      
  end <agent> <session_dir>
      End agent session (cleanup tracking files)

Examples:
  # Start session with context
  session_id=\$(bash $0 start web-researcher ./session-123 "Initial context here")
  
  # Continue session with new task
  bash $0 continue web-researcher ./session-123 "New task" output.json
  
  # Check if session exists
  bash $0 has-session web-researcher ./session-123
  
  # Clean up
  bash $0 end web-researcher ./session-123

Notes:
  - Sessions auto-save (validated in test-13-session-continuity.sh)
  - Context is preserved across continue calls
  - System prompts and tool restrictions still apply
  - Each agent should have its own session for isolation
  - Session IDs are stored in .agent-sessions/ directory

Validation:
  All patterns tested in validation_tests/test-13-session-continuity.sh:
  - Sessions auto-save (no --save-session flag)
  - .session_id extraction works
  - --resume preserves context
  - System prompts work with --resume
EOF
            ;;
    esac
fi

