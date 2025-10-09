#!/usr/bin/env bash
# User-Friendly Error Message Wrappers
# Translates technical errors into actionable user guidance

set -euo pipefail

# Lock acquisition failed
error_lock_failed() {
    local file="$1"
    local timeout="$2"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Research session is locked
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Another research process is using this session, or a previous
session didn't exit cleanly.

Waited: ${timeout} seconds
File: $(basename "$file")

What to do:

1. Check for running research:
   ps aux | grep adaptive-research

2. If no process found, remove stale lock:
   rm -rf $(dirname "$file")/*.lock

3. Then try again:
   ./research resume $(basename "$(dirname "$file")")

For more help: docs/TROUBLESHOOTING.md#locked-session
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# JSON parsing failed
error_json_corrupted() {
    local file="$1"
    local jq_error="${2:-}"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Data file corrupted
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

File: $file

This can happen if:
  • Multiple processes wrote simultaneously (race condition)
  • Research was interrupted (Ctrl+C during write)
  • Disk space is full

Technical details:
$jq_error

What to do:

1. Check disk space:
   df -h

2. If backup exists, restore it:
   cp "${file}.backup" "$file"

3. Otherwise, investigate the file:
   cat "$file" | jq '.'

4. If unfixable, you may need to restart research

For more help: docs/TROUBLESHOOTING.md#corrupted-data
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Agent execution failed
error_agent_failed() {
    local agent_name="$1"
    local task_type="$2"
    local error_message="${3:-}"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Research agent failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Agent: $agent_name
Task: $task_type

Error: $error_message

Common causes:
  • API rate limit exceeded (wait 60 seconds)
  • Network connection issue
  • Agent configuration problem
  • Invalid input data

What to do:

1. Wait 60 seconds, then resume:
   ./research resume

2. Check agent logs:
   ls -la research-sessions/*/intermediate/

3. Verify network connection:
   curl -I https://api.anthropic.com/

4. Check agent configuration:
   cat .claude/agents/${agent_name}.json

For more help: docs/TROUBLESHOOTING.md#agent-failures
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Missing required file
error_missing_file() {
    local file_path="$1"
    local file_description="${2:-file}"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Required file not found
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Missing: $file_description
Path: $file_path

This might mean:
  • Research session was not initialized properly
  • File was deleted accidentally
  • Wrong session directory specified

What to do:

1. Verify session exists:
   ls -la research-sessions/

2. Check if this is the correct session:
   cat research-sessions/[session-name]/metadata.json

3. If starting new research, use:
   ./research "your question here"

For more help: docs/TROUBLESHOOTING.md#missing-files
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Configuration validation failed
error_invalid_config() {
    local config_file="$1"
    local validation_error="${2:-}"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ Invalid configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Config file: $config_file

Validation error:
$validation_error

What to do:

1. Check configuration syntax:
   cat "$config_file" | jq '.'

2. Compare with example:
   cat "$config_file.example"

3. Reset to defaults:
   cp "$config_file.default" "$config_file"

4. Review configuration docs:
   docs/CONFIGURATION.md

For more help: docs/TROUBLESHOOTING.md#config-errors
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# API key missing or invalid
error_api_key() {
    local provider="${1:-Anthropic}"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ API key not configured
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Provider: $provider

The research engine requires an API key to function.

What to do:

1. Get API key:
   • Anthropic: https://console.anthropic.com/
   • OpenAI: https://platform.openai.com/api-keys

2. Set environment variable:
   export ANTHROPIC_API_KEY="your-key-here"

3. Or add to ~/.bashrc or ~/.zshrc:
   echo 'export ANTHROPIC_API_KEY="your-key"' >> ~/.bashrc

4. Verify it's set:
   echo \$ANTHROPIC_API_KEY

For more help: docs/SETUP.md#api-keys
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Disk space low
error_disk_space() {
    local path="$1"
    local available_mb="$2"

    cat >&2 <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Low disk space
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Path: $path
Available: ${available_mb}MB

Research sessions can generate large amounts of data.
You may encounter write failures.

What to do:

1. Check disk usage:
   df -h

2. Clean old sessions:
   ./research clean --older-than 30d

3. Remove intermediate files:
   find research-sessions -name "intermediate" -type d -exec rm -rf {} +

4. Move to larger disk:
   mv research-sessions /path/to/larger/disk/

For more help: docs/TROUBLESHOOTING.md#disk-space
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Export functions for use in other scripts
export -f error_lock_failed
export -f error_json_corrupted
export -f error_agent_failed
export -f error_missing_file
export -f error_invalid_config
export -f error_api_key
export -f error_disk_space
