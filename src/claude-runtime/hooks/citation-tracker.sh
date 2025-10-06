#!/usr/bin/env bash
# Citation Tracker Hook
# Maintains a database of all sources accessed during research

CITATIONS_DB="$HOME/.claude/research-engine/citations.json"
mkdir -p "$(dirname "$CITATIONS_DB")"

# Initialize citations file if it doesn't exist
[ ! -f "$CITATIONS_DB" ] && echo "[]" > "$CITATIONS_DB"

TOOL_NAME=$(jq -r '.tool_name')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

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
