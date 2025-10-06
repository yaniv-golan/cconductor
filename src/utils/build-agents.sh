#!/usr/bin/env bash
# Build agent JSON files from source (metadata.json + system-prompt.md)
# Usage: build-agents.sh <output_dir> [session_dir]
#
# Combines metadata.json and system-prompt.md from src/claude-runtime/agents/
# into single JSON files for Claude Code
#
# If session_dir is provided, injects session-specific knowledge context

set -euo pipefail

output_dir="${1:-}"
session_dir="${2:-}"

if [ -z "$output_dir" ]; then
    echo "Usage: build-agents.sh <output_dir> [session_dir]" >&2
    exit 1
fi

mkdir -p "$output_dir"

# Get script directory to find source agents
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SOURCE_DIR="$SCRIPT_DIR/../claude-runtime/agents"

# Source knowledge loader for knowledge injection
# shellcheck disable=SC1091
source "$SCRIPT_DIR/knowledge-loader.sh"

# Build each agent
for agent_dir in "$AGENTS_SOURCE_DIR"/*/; do
    agent_name=$(basename "$agent_dir")
    
    # Skip if not a directory or if old JSON files exist
    if [ ! -d "$agent_dir" ]; then
        continue
    fi
    
    metadata_file="$agent_dir/metadata.json"
    prompt_file="$agent_dir/system-prompt.md"
    
    # Skip if source files don't exist
    if [ ! -f "$metadata_file" ] || [ ! -f "$prompt_file" ]; then
        continue
    fi
    
    # Read base system prompt
    base_prompt=$(cat "$prompt_file")
    
    # Inject knowledge context (respects priority: session > custom > core)
    enhanced_prompt=$(inject_knowledge_context "$agent_name" "$base_prompt" "$session_dir")
    
    # Combine into agent JSON with enhanced prompt
    output_file="$output_dir/${agent_name}.json"
    jq --arg prompt "$enhanced_prompt" \
        '. + {systemPrompt: $prompt}' \
        "$metadata_file" > "$output_file"
    
    echo "  ✓ Built $agent_name" >&2
done

echo "✓ All agents built to: $output_dir" >&2

