#!/usr/bin/env bash
# Research Logger Hook
# Logs all research activities for audit trail and reproducibility

set -euo pipefail

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

# Source path resolver for configurable locations (fallback to defaults)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh" 2>/dev/null || true

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh" 2>/dev/null || true

# Source shared-state utilities (provides get_timestamp, locking helpers)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || true

# Configuration
AUDIT_LOG_DEFAULT="$HOME/.claude/research-engine/audit.log"
AUDIT_LOG_PATH="$AUDIT_LOG_DEFAULT"

if command -v resolve_path >/dev/null 2>&1; then
    resolved_audit_log=$(resolve_path "audit_log" 2>/dev/null || true)
    if [[ -n "${resolved_audit_log:-}" ]]; then
        AUDIT_LOG_PATH="$resolved_audit_log"
    fi
fi

LOG_DIR="$(dirname "$AUDIT_LOG_PATH")"
AUDIT_LOG="$AUDIT_LOG_PATH"
QUERY_LOG="$LOG_DIR/queries.log"

if ! command -v jq >/dev/null 2>&1; then
    # jq is required for structured logging; exit gracefully if unavailable
    exit 0
fi

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

# Memoized parsing: emit pre-built log payloads from a single jq run
TIMESTAMP=$(get_timestamp)

# shellcheck disable=SC2016
while IFS=$'\t' read -r target payload_b64; do
    [ -n "$target" ] || continue
    payload=$(printf '%s' "$payload_b64" | base64 --decode)
    case "$target" in
        query)
            append_json_line "$QUERY_LOG" "$payload"
            ;;
        audit)
            append_json_line "$AUDIT_LOG" "$payload"
            ;;
    esac
done < <(printf '%s' "$input" | jq -r --arg ts "$TIMESTAMP" '
    def base: {timestamp:$ts, tool:.tool_name};
    def record($target; $obj):
        ($obj // empty) | [$target, (base + .) | @base64];
    (
        if .tool_name == "WebSearch" then
            [
                record("query"; {query: .tool_input.query}),
                record("audit"; {event:"web_search", query: .tool_input.query})
            ]
        elif .tool_name == "WebFetch" then
            [
                record("query"; {url: .tool_input.url}),
                record("audit"; {event:"web_fetch", url: .tool_input.url})
            ]
        elif .tool_name == "Task" then
            [
                record("audit"; {
                    event: "task",
                    agent: (.tool_input.subagent_type // ""),
                    description: (.tool_input.description // "")
                })
            ]
        elif .tool_name == "Read" then
            [
                record("audit"; {
                    event: "read",
                    file: (.tool_input.file_path // "")
                })
            ]
        elif .tool_name == "Grep" then
            [
                record("audit"; {
                    event: "grep",
                    pattern: (.tool_input.pattern // ""),
                    path: (.tool_input.path // ".")
                })
            ]
        else
            []
        end
    ) | .[] | @tsv
')

exit 0
