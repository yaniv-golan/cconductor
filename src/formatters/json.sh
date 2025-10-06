#!/usr/bin/env bash
# JSON Output Formatter
# Ensures clean, validated JSON output

set -euo pipefail

RESEARCH_FILE="$1"

if [ ! -f "$RESEARCH_FILE" ]; then
    echo "Error: Research file not found: $RESEARCH_FILE" >&2
    exit 1
fi

# Validate and pretty-print JSON
if jq empty "$RESEARCH_FILE" 2>/dev/null; then
    jq '.' "$RESEARCH_FILE"
else
    echo "Error: Invalid JSON in research file" >&2
    exit 1
fi
