#!/usr/bin/env bash
# Citation Tracker Hook
# Maintains a database of all sources accessed during research

set -euo pipefail

# Find project root robustly (hooks may run in various contexts)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    # shellcheck disable=SC2329
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    # shellcheck disable=SC2329
    is_valid_json() { echo "$1" | jq empty 2>/dev/null; }
}

# Source path resolver for configuration-aware locations (optional)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh" 2>/dev/null || true

# Source shared-state for atomic operations (with fallback)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || {
    # Fallback: atomic_json_update won't be available, use manual locking
    # shellcheck disable=SC2329
    atomic_json_update() { return 1; }
}

CITATIONS_DB_DEFAULT="$HOME/.claude/research-engine/citations.json"
if command -v resolve_path >/dev/null 2>&1; then
    CITATIONS_DB=$(resolve_path "citations_db" 2>/dev/null || echo "$CITATIONS_DB_DEFAULT")
else
    CITATIONS_DB="$CITATIONS_DB_DEFAULT"
fi

mkdir -p "$(dirname "$CITATIONS_DB")"

# Initialize citations file if it doesn't exist
[ ! -f "$CITATIONS_DB" ] && echo "[]" > "$CITATIONS_DB"

if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

citation_apply_update() {
    local expr="$1"
    shift
    local -a args=("$@")
    local tmp="${CITATIONS_DB}.tmp"

    if jq "${args[@]}" "$expr" "$CITATIONS_DB" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CITATIONS_DB"
        return 0
    fi

    rm -f "$tmp"
    return 1
}

update_citations() {
    local expr="$1"
    shift
    local -a args=("$@")

    if type atomic_json_update &>/dev/null; then
        atomic_json_update "$CITATIONS_DB" "${args[@]}" "$expr"
        return $?
    fi

    if command -v with_lock >/dev/null 2>&1; then
        with_lock "$CITATIONS_DB" citation_apply_update "$expr" "${args[@]}"
        return $?
    fi

    if command -v with_simple_lock >/dev/null 2>&1; then
        with_simple_lock "${CITATIONS_DB}.lock" citation_apply_update "$expr" "${args[@]}"
        return $?
    fi

    citation_apply_update "$expr" "${args[@]}"
}

# Read and validate stdin
input=$(cat)
if [[ -z "$input" ]] || ! is_valid_json "$input"; then
    # Invalid or empty input - exit gracefully (hooks should not block)
    exit 0
fi

TOOL_NAME=$(echo "$input" | jq -r '.tool_name')
TIMESTAMP=$(get_timestamp)

# Track web sources
if [ "$TOOL_NAME" = "WebFetch" ]; then
    URL=$(echo "$input" | jq -r '.tool_input.url')
    # shellcheck disable=SC2016
    update_citations '. += [{url: $url, accessed: $ts, type: "web"}]' --arg url "$URL" --arg ts "$TIMESTAMP"
elif [ "$TOOL_NAME" = "Read" ]; then
    FILE=$(echo "$input" | jq -r '.tool_input.file_path')
    # shellcheck disable=SC2016
    update_citations '. += [{file: $file, accessed: $ts, type: "code"}]' --arg file "$FILE" --arg ts "$TIMESTAMP"
fi

exit 0
