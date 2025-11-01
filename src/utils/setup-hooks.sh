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
    
    local changed=0

    # Ensure session hooks directory exists
    local session_hooks_dir="$session_dir/.claude/hooks"
    if [ ! -d "$session_hooks_dir" ]; then
        mkdir -p "$session_hooks_dir"
        changed=1
    fi
    
    # Copy hooks to session directory only when contents differ
    local hook_files=(
        "pre-tool-use.sh"
        "post-tool-use.sh"
        "stop-build-evidence.sh"
        "evidence_fragment.pl"
        "hook-bootstrap.sh"
    )

    local hook_file
    for hook_file in "${hook_files[@]}"; do
        local source_file="$source_hooks_dir/$hook_file"
        local dest_file="$session_hooks_dir/$hook_file"

        if [ ! -f "$source_file" ]; then
            echo "Warning: Missing hook source $source_file" >&2
            continue
        fi

        if [ ! -f "$dest_file" ] || ! cmp -s "$source_file" "$dest_file"; then
            cp "$source_file" "$dest_file"
            changed=1
        fi

        chmod +x "$dest_file"
    done
    
    # Path to settings file
    local settings_file="$session_dir/.claude/settings.json"
    
    # Initialize settings if it doesn't exist
    if [ ! -f "$settings_file" ]; then
        echo '{}' > "$settings_file"
        changed=1
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
    local temp_settings
    temp_settings=$(mktemp "${TMPDIR:-/tmp}/setup-hooks.XXXXXX")
    jq --argjson hooks "$hooks_config" '
        .hooks = (.hooks // {}) |
        .hooks.PreToolUse = $hooks.hooks.PreToolUse |
        .hooks.PostToolUse = $hooks.hooks.PostToolUse |
        .hooks.Stop = $hooks.hooks.Stop
    ' "$settings_file" > "$temp_settings"

    if ! cmp -s "$temp_settings" "$settings_file"; then
        mv "$temp_settings" "$settings_file"
        changed=1
    else
        rm -f "$temp_settings"
    fi
    
    if [ "$changed" -eq 0 ]; then
        echo "• Tool observability hooks already configured (no changes)" >&2
    else
        echo "✓ Tool observability hooks configured (copied to session)" >&2
    fi
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
