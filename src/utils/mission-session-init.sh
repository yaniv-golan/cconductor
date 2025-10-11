#!/usr/bin/env bash
# Mission Session Initialization
# Simplified session setup for mission-based research (v0.2.0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Initialize a new mission session
# Creates session directory with unique timestamp and minimal structure
#
# Usage: initialize_session "research objective"
# Returns: session_dir path on stdout
initialize_session() {
    local mission_objective="$1"
    
    if [[ -z "$mission_objective" ]]; then
        echo "Error: Mission objective required" >&2
        return 1
    fi
    
    # Create session directory with unique timestamp to prevent collisions
    local timestamp
    # Check if we can get subsecond precision (GNU date with %N)
    if date +%s%N &>/dev/null 2>&1 && [[ "$(date +%s%N)" =~ ^[0-9]+$ ]]; then
        # GNU date (Linux) - use nanoseconds
        timestamp=$(date +%s%N)
    else
        # macOS or other - use seconds + PID + random
        timestamp="$(date +%s)_$$_${RANDOM}"
    fi
    
    local session_dir="$PROJECT_ROOT/research-sessions/mission_${timestamp}"
    
    # Create directory structure
    mkdir -p "$session_dir/artifacts"
    mkdir -p "$session_dir/.claude/agents"
    
    # Create session metadata
    jq -n \
        --arg objective "$mission_objective" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg session_type "mission" \
        --arg version "0.2.0" \
        '{
            session_type: $session_type,
            objective: $objective,
            created_at: $timestamp,
            version: $version
        }' > "$session_dir/session.json"
    
    echo "$session_dir"
}

# Export for use in subshells
export -f initialize_session


