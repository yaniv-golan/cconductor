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
    
    # Get script directory (where hooks are located)
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local hooks_dir="$script_dir/hooks"
    
    # Ensure .claude directory exists
    local claude_dir="$session_dir/.claude"
    mkdir -p "$claude_dir"
    
    # Path to settings file
    local settings_file="$claude_dir/settings.json"
    
    # Initialize settings if it doesn't exist
    if [ ! -f "$settings_file" ]; then
        echo '{}' > "$settings_file"
    fi
    
    # Create hooks configuration
    local hooks_config
    hooks_config=$(jq -n \
        --arg pre_hook "$hooks_dir/pre-tool-use.sh" \
        --arg post_hook "$hooks_dir/post-tool-use.sh" \
        '{
            hooks: {
                PreToolUse: [{
                    matcher: "*",
                    hooks: [{
                        type: "command",
                        command: $pre_hook
                    }]
                }],
                PostToolUse: [{
                    matcher: "*",
                    hooks: [{
                        type: "command",
                        command: $post_hook
                    }]
                }]
            }
        }')
    
    # Merge with existing settings
    jq --argjson hooks "$hooks_config" '. + $hooks' "$settings_file" > "${settings_file}.tmp"
    mv "${settings_file}.tmp" "$settings_file"
    
    echo "✓ Tool observability hooks configured" >&2
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

