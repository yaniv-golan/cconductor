#!/usr/bin/env bash
# Research Logger Hook
# Logs all research activities for audit trail and reproducibility

# Find project root robustly (hooks may run in various contexts)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    is_valid_json() { echo "$1" | jq empty 2>/dev/null; }
}

# Configuration
LOG_DIR="$HOME/.claude/research-engine"
AUDIT_LOG="$LOG_DIR/audit.log"
QUERY_LOG="$LOG_DIR/queries.log"

mkdir -p "$LOG_DIR"

# Read and validate stdin
input=$(cat)
if [[ -z "$input" ]] || ! is_valid_json "$input"; then
    # Invalid or empty input - exit gracefully (hooks should not block)
    exit 0
fi

# Parse tool call information from stdin (JSON)
TOOL_NAME=$(echo "$input" | jq -r '.tool_name')
TIMESTAMP=$(get_timestamp)

# Log based on tool type (parse from $input)
case "$TOOL_NAME" in
    WebSearch)
        QUERY=$(echo "$input" | jq -r '.tool_input.query')
        echo "$TIMESTAMP | WebSearch | $QUERY" >> "$QUERY_LOG"
        echo "$TIMESTAMP | WebSearch | Query: $QUERY" >> "$AUDIT_LOG"
        ;;

    WebFetch)
        URL=$(echo "$input" | jq -r '.tool_input.url')
        echo "$TIMESTAMP | WebFetch | $URL" >> "$QUERY_LOG"
        echo "$TIMESTAMP | WebFetch | URL: $URL" >> "$AUDIT_LOG"
        ;;

    Task)
        AGENT=$(echo "$input" | jq -r '.tool_input.subagent_type')
        DESCRIPTION=$(echo "$input" | jq -r '.tool_input.description')
        echo "$TIMESTAMP | Task | Agent: $AGENT | $DESCRIPTION" >> "$AUDIT_LOG"
        ;;

    Read)
        FILE=$(echo "$input" | jq -r '.tool_input.file_path')
        echo "$TIMESTAMP | Read | File: $FILE" >> "$AUDIT_LOG"
        ;;

    Grep)
        PATTERN=$(echo "$input" | jq -r '.tool_input.pattern')
        SEARCH_PATH=$(echo "$input" | jq -r '.tool_input.path // "."')
        echo "$TIMESTAMP | Grep | Pattern: $PATTERN | Path: $SEARCH_PATH" >> "$AUDIT_LOG"
        ;;
esac

# Always allow the tool to proceed
exit 0
