#!/usr/bin/env bash
# Setup Claude Code hooks for tool-level observability
# Configures PreToolUse and PostToolUse hooks in session's .claude/settings.json

set -euo pipefail

setup_tool_hooks() {
    local session_dir="$1"
    
    if [ -z "$session_dir" ] || [ ! -d "$session_dir" ]; then
        echo "Error: Invalid session directory: $session_dir" >&2
        return 1
    fi
    
    # Get script directory (where source hooks are located)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local source_hooks_dir="$script_dir/hooks"
    
    # Ensure session hooks directory exists
    local session_hooks_dir="$session_dir/.claude/hooks"
    mkdir -p "$session_hooks_dir"
    
    # Copy hooks to session directory
    # This avoids issues with spaces in paths and makes sessions portable
    cp "$source_hooks_dir/pre-tool-use.sh" "$session_hooks_dir/"
    cp "$source_hooks_dir/post-tool-use.sh" "$session_hooks_dir/"
    cp "$source_hooks_dir/stop-build-evidence.sh" "$session_hooks_dir/"
    cp "$source_hooks_dir/evidence_fragment.pl" "$session_hooks_dir/"
    cp "$source_hooks_dir/hook-bootstrap.sh" "$session_hooks_dir/"
    chmod +x "$session_hooks_dir/pre-tool-use.sh"
    chmod +x "$session_hooks_dir/post-tool-use.sh"
    chmod +x "$session_hooks_dir/stop-build-evidence.sh"
    chmod +x "$session_hooks_dir/hook-bootstrap.sh"
    chmod +x "$session_hooks_dir/evidence_fragment.pl"
    
    # Path to settings file
    local settings_file="$session_dir/.claude/settings.json"
    
    # Initialize settings if it doesn't exist
    if [ ! -f "$settings_file" ]; then
        echo '{}' > "$settings_file"
    fi
    
    # Create hooks configuration using RELATIVE paths
    # This ensures hooks work regardless of spaces in repo path
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
            }],
            Stop: [{
                hooks: [{
                    type: "command",
                    command: ".claude/hooks/stop-build-evidence.sh"
                }]
            }]
        }
    }')
    
    # Merge with existing settings
    # Note: This intentionally REPLACES hook arrays (not merges) to ensure session isolation.
    # Each session gets a clean set of cconductor hooks, preventing conflicts between
    # different research sessions running concurrently. This is by design for session safety.
    jq --argjson hooks "$hooks_config" '
        .hooks = (.hooks // {}) |
        .hooks.PreToolUse = $hooks.hooks.PreToolUse |
        .hooks.PostToolUse = $hooks.hooks.PostToolUse |
        .hooks.Stop = $hooks.hooks.Stop
    ' "$settings_file" > "${settings_file}.tmp"
    mv "${settings_file}.tmp" "$settings_file"
    
    echo "✓ Tool observability hooks configured (copied to session)" >&2
    return 0
}

# If called directly, set up hooks for provided session directory
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    setup_tool_hooks "$1"
fi
