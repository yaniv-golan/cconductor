#!/usr/bin/env bash
# Research Logger Hook
# Logs all research activities for audit trail and reproducibility

# Source shared-state.sh for get_timestamp function
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || {
    # Fallback: inline get_timestamp if shared-state.sh not found
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
}

# Configuration
LOG_DIR="$HOME/.claude/research-engine"
AUDIT_LOG="$LOG_DIR/audit.log"
QUERY_LOG="$LOG_DIR/queries.log"

mkdir -p "$LOG_DIR"

# Read tool call information from stdin (JSON)
TOOL_NAME=$(jq -r '.tool_name')
TIMESTAMP=$(get_timestamp)

# Log based on tool type
case "$TOOL_NAME" in
    WebSearch)
        QUERY=$(jq -r '.tool_input.query')
        echo "$TIMESTAMP | WebSearch | $QUERY" >> "$QUERY_LOG"
        echo "$TIMESTAMP | WebSearch | Query: $QUERY" >> "$AUDIT_LOG"
        ;;

    WebFetch)
        URL=$(jq -r '.tool_input.url')
        echo "$TIMESTAMP | WebFetch | $URL" >> "$QUERY_LOG"
        echo "$TIMESTAMP | WebFetch | URL: $URL" >> "$AUDIT_LOG"
        ;;

    Task)
        AGENT=$(jq -r '.tool_input.subagent_type')
        DESCRIPTION=$(jq -r '.tool_input.description')
        echo "$TIMESTAMP | Task | Agent: $AGENT | $DESCRIPTION" >> "$AUDIT_LOG"
        ;;

    Read)
        FILE=$(jq -r '.tool_input.file_path')
        echo "$TIMESTAMP | Read | File: $FILE" >> "$AUDIT_LOG"
        ;;

    Grep)
        PATTERN=$(jq -r '.tool_input.pattern')
        PATH=$(jq -r '.tool_input.path // "."')
        echo "$TIMESTAMP | Grep | Pattern: $PATTERN | Path: $PATH" >> "$AUDIT_LOG"
        ;;
esac

# Always allow the tool to proceed
exit 0
