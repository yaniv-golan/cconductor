#!/usr/bin/env bash
# Citation Tracker Hook
# Maintains a database of all sources accessed during research

# Source shared-state.sh for get_timestamp function
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || {
    # Fallback: inline get_timestamp if shared-state.sh not found
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
}

CITATIONS_DB="$HOME/.claude/research-engine/citations.json"
mkdir -p "$(dirname "$CITATIONS_DB")"

# Initialize citations file if it doesn't exist
[ ! -f "$CITATIONS_DB" ] && echo "[]" > "$CITATIONS_DB"

TOOL_NAME=$(jq -r '.tool_name')
TIMESTAMP=$(get_timestamp)

# Track web sources
if [ "$TOOL_NAME" = "WebFetch" ]; then
    URL=$(jq -r '.tool_input.url')

    # Add to citations database
    jq --arg url "$URL" --arg ts "$TIMESTAMP" \
        '. += [{url: $url, accessed: $ts, type: "web"}]' \
        "$CITATIONS_DB" > "$CITATIONS_DB.tmp"

    mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"

elif [ "$TOOL_NAME" = "Read" ]; then
    FILE=$(jq -r '.tool_input.file_path')

    # Add file to citations
    jq --arg file "$FILE" --arg ts "$TIMESTAMP" \
        '. += [{file: $file, accessed: $ts, type: "code"}]' \
        "$CITATIONS_DB" > "$CITATIONS_DB.tmp"

    mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
fi

exit 0
