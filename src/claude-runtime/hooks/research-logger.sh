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

# Source shared-state utilities (provides get_timestamp, locking helpers)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || true

# Configuration
LOG_DIR="$HOME/.claude/research-engine"
AUDIT_LOG="$LOG_DIR/audit.log"
QUERY_LOG="$LOG_DIR/queries.log"

umask 077
mkdir -p "$LOG_DIR"
touch "$AUDIT_LOG" "$QUERY_LOG" 2>/dev/null || true
chmod 600 "$AUDIT_LOG" "$QUERY_LOG" 2>/dev/null || true

append_json_line() {
    local file="$1"
    local payload="$2"
    printf '%s\n' "$payload" >> "$file"
}

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
        append_json_line "$QUERY_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg query "$QUERY" '{timestamp:$ts, tool:$tool, query:$query}')"
        append_json_line "$AUDIT_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg query "$QUERY" '{timestamp:$ts, event:"web_search", query:$query, tool:$tool}')"
        ;;

    WebFetch)
        URL=$(echo "$input" | jq -r '.tool_input.url')
        append_json_line "$QUERY_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg url "$URL" '{timestamp:$ts, tool:$tool, url:$url}')"
        append_json_line "$AUDIT_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg url "$URL" '{timestamp:$ts, event:"web_fetch", url:$url, tool:$tool}')"
        ;;

    Task)
        AGENT=$(echo "$input" | jq -r '.tool_input.subagent_type')
        DESCRIPTION=$(echo "$input" | jq -r '.tool_input.description')
        append_json_line "$AUDIT_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg agent "$AGENT" --arg desc "$DESCRIPTION" '{timestamp:$ts, event:"task", agent:$agent, description:$desc, tool:$tool}')"
        ;;

    Read)
        FILE=$(echo "$input" | jq -r '.tool_input.file_path')
        append_json_line "$AUDIT_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg file "$FILE" '{timestamp:$ts, event:"read", file:$file, tool:$tool}')"
        ;;

    Grep)
        PATTERN=$(echo "$input" | jq -r '.tool_input.pattern')
        SEARCH_PATH=$(echo "$input" | jq -r '.tool_input.path // "."')
        append_json_line "$AUDIT_LOG" "$(jq -n --arg ts "$TIMESTAMP" --arg tool "$TOOL_NAME" --arg pattern "$PATTERN" --arg path "$SEARCH_PATH" '{timestamp:$ts, event:"grep", pattern:$pattern, path:$path, tool:$tool}')"
        ;;
esac

# Always allow the tool to proceed
exit 0
