#!/usr/bin/env bash
# Mission Session Initialization
# Simplified session setup for mission-based research (v0.2.0)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load error logger for session initialization
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null || true

# Copy runtime settings to session
# Ensures session inherits proper permissions for WebFetch, Write, etc.
copy_runtime_settings() {
    local session_dir="$1"
    local source_settings="$PROJECT_ROOT/src/claude-runtime/settings.json"
    local target_settings="$session_dir/.claude/settings.json"
    
    if [ -f "$source_settings" ]; then
        mkdir -p "$session_dir/.claude"
        cp "$source_settings" "$target_settings"
        echo "  ✓ Runtime permissions configured" >&2
    else
        echo "  ⚠ Warning: No runtime settings found at $source_settings" >&2
    fi
}

# Copy and configure hooks for tool usage tracking
# Enables live tool tracking in dashboard
copy_hooks() {
    local session_dir="$1"
    local source_hooks="$PROJECT_ROOT/src/utils/hooks"
    local target_hooks="$session_dir/.claude/hooks"
    local settings_file="$session_dir/.claude/settings.json"
    
    if [ ! -d "$source_hooks" ]; then
        echo "  ⚠ Warning: Hooks directory not found at $source_hooks" >&2
        return 1
    fi
    
    # Copy hook scripts
    mkdir -p "$target_hooks"
    cp "$source_hooks/"*.sh "$target_hooks/" 2>/dev/null || true
    chmod +x "$target_hooks/"*.sh 2>/dev/null || true
    
    # Configure hooks in settings.json (required for Claude CLI to invoke them)
    if [ -f "$settings_file" ]; then
        # Create hooks configuration using RELATIVE paths
        local hooks_config
        hooks_config=$(jq -n '{
            hooks: {
                PreToolUse: [{
                    matcher: "*",
                    hooks: [{
                        type: "command",
                        command: ".claude/hooks/pre-tool-use.sh"
                    }]
                }],
                PostToolUse: [{
                    matcher: "*",
                    hooks: [{
                        type: "command",
                        command: ".claude/hooks/post-tool-use.sh"
                    }]
                }]
            }
        }')
        
        # Merge with existing settings
        jq --argjson hooks "$hooks_config" '. + $hooks' "$settings_file" > "${settings_file}.tmp"
        mv "${settings_file}.tmp" "$settings_file"
    fi
    
    echo "  ✓ Tool tracking hooks installed and configured" >&2
}

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
    
    # Prevent collision: if directory already exists (rare race condition), add suffix
    if [[ -d "$session_dir" ]]; then
        session_dir="${session_dir}_${RANDOM}"
        # Double-check the suffixed name doesn't exist either
        while [[ -d "$session_dir" ]]; do
            session_dir="${session_dir%_*}_${RANDOM}"
        done
    fi
    
    # Create directory structure
    mkdir -p "$session_dir/artifacts"
    mkdir -p "$session_dir/raw"  # For agent findings files
    mkdir -p "$session_dir/.claude/agents"
    
    # Initialize error log
    if command -v init_error_log &>/dev/null; then
        init_error_log "$session_dir"
    fi
    
    # Copy runtime settings to session
    copy_runtime_settings "$session_dir"
    
    # Copy hooks for tool tracking
    copy_hooks "$session_dir"
    
    # Capture Claude Code CLI version for journal metadata
    local claude_version="unknown"
    if command -v claude &>/dev/null; then
        # Extract version string, handle various formats
        claude_version=$(claude --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        # If no version number found, use the full first line
        if [ "$claude_version" = "unknown" ]; then
            claude_version=$(claude --version 2>&1 | head -1 | tr -d '\n' || echo "unknown")
        fi
    fi
    
    # Store raw prompt - parsing will be done by orchestrator
    # This ensures prompt-parser is invoked through the proper agent infrastructure
    
    # Create session metadata with runtime information
    # Note: objective will be updated by orchestrator after prompt parsing
    jq -n \
        --arg objective "$mission_objective" \
        --arg question "$mission_objective" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg session_type "mission" \
        --arg version "0.2.0" \
        --arg claude_ver "$claude_version" \
        '{
            session_type: $session_type,
            objective: $objective,
            research_question: $question,
            output_specification: null,
            prompt_parsed: false,
            created_at: $timestamp,
            version: $version,
            runtime: {
                cconductor_version: $version,
                claude_code_version: $claude_ver
            }
        }' > "$session_dir/session.json"
    
    echo "$session_dir"
}

# Export for use in subshells
export -f initialize_session


