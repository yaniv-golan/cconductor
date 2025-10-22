#!/usr/bin/env bash
# Citation Tracker Hook
# Maintains a database of all sources accessed during research

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

# Source shared-state for atomic operations (with fallback)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || {
    # Fallback: atomic_json_update won't be available, use manual locking
    atomic_json_update() { return 1; }
}

CITATIONS_DB="$HOME/.claude/research-engine/citations.json"
mkdir -p "$(dirname "$CITATIONS_DB")"

# Initialize citations file if it doesn't exist
[ ! -f "$CITATIONS_DB" ] && echo "[]" > "$CITATIONS_DB"

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

    # Add to citations database with atomic update
    # Source shared-state if available, otherwise use basic locking
    if type atomic_json_update &>/dev/null; then
        # shellcheck disable=SC2016
        atomic_json_update "$CITATIONS_DB" --arg url "$URL" --arg ts "$TIMESTAMP" \
            '. += [{url: $url, accessed: $ts, type: "web"}]'
    else
        # Fallback: manual temp file with brief lock attempt
        lock_dir="${CITATIONS_DB}.lock"
        if mkdir "$lock_dir" 2>/dev/null; then
            jq --arg url "$URL" --arg ts "$TIMESTAMP" \
                '. += [{url: $url, accessed: $ts, type: "web"}]' \
                "$CITATIONS_DB" > "$CITATIONS_DB.tmp" && mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
            rmdir "$lock_dir"
        fi
    fi

elif [ "$TOOL_NAME" = "Read" ]; then
    FILE=$(echo "$input" | jq -r '.tool_input.file_path')

    # Add file to citations with atomic update
        # shellcheck disable=SC2016
    if type atomic_json_update &>/dev/null; then
        atomic_json_update "$CITATIONS_DB" --arg file "$FILE" --arg ts "$TIMESTAMP" \
            '. += [{file: $file, accessed: $ts, type: "code"}]'
    else
        # Fallback: manual temp file with brief lock attempt
        lock_dir="${CITATIONS_DB}.lock"
        if mkdir "$lock_dir" 2>/dev/null; then
            jq --arg file "$FILE" --arg ts "$TIMESTAMP" \
                '. += [{file: $file, accessed: $ts, type: "code"}]' \
                "$CITATIONS_DB" > "$CITATIONS_DB.tmp" && mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
            rmdir "$lock_dir"
        fi
    fi
fi

exit 0
