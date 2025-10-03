#!/bin/bash
# Safe Fetch Wrapper - Secure curl with size/time limits
# Provides safe fetching with security controls based on configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source config loader
source "$SCRIPT_DIR/config-loader.sh"

# Parse arguments
URL="$1"
OUTPUT_FILE="${2:-/dev/stdout}"

# Validate URL format
if ! echo "$URL" | grep -qE '^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'; then
    echo "Error: Invalid URL format: $URL" >&2
    echo "URL must be http:// or https:// with valid domain" >&2
    exit 1
fi

# Load security configuration (overlay pattern)
PROFILE=$(get_config_value "security-config" ".security_profile" "\"strict\"" | tr -d '"')
MAX_SIZE_MB=$(get_config_value "security-config" ".profiles.${PROFILE}.max_fetch_size_mb" "10")
TIMEOUT_SEC=$(get_config_value "security-config" ".profiles.${PROFILE}.fetch_timeout_seconds" "30")

# Convert MB to bytes for curl
MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))

# Create temporary file for fetch
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Perform fetch with security limits
if ! curl -L \
    --max-redirs 3 \
    --max-time "$TIMEOUT_SEC" \
    --max-filesize "$MAX_SIZE_BYTES" \
    -A "ResearchEngine/1.0 (Academic Research)" \
    --proto =https,http \
    -s \
    -w "HTTP_CODE:%{http_code}\n" \
    "$URL" > "$TEMP_FILE" 2>&1; then

    echo "Error: Failed to fetch $URL" >&2
    echo "Check network connection and URL validity" >&2
    exit 1
fi

# Extract HTTP code from curl output
HTTP_CODE=$(grep "HTTP_CODE:" "$TEMP_FILE" | cut -d: -f2 || echo "000")
sed -i.bak '/HTTP_CODE:/d' "$TEMP_FILE" 2>/dev/null || sed -i '' '/HTTP_CODE:/d' "$TEMP_FILE" 2>/dev/null || true

# Check HTTP status
if [ "$HTTP_CODE" -ge 400 ]; then
    echo "Error: HTTP $HTTP_CODE for $URL" >&2
    exit 1
fi

# Validate content isn't binary malware
if command -v file >/dev/null 2>&1; then
    FILE_TYPE=$(file -b "$TEMP_FILE")
    if echo "$FILE_TYPE" | grep -qiE "(executable|archive|compressed data)"; then
        echo "Warning: Binary/executable content detected, skipping" >&2
        echo "File type: $FILE_TYPE" >&2
        exit 1
    fi
fi

# Check file size
ACTUAL_SIZE=$(wc -c < "$TEMP_FILE" | tr -d ' ')
if [ "$ACTUAL_SIZE" -gt "$MAX_SIZE_BYTES" ]; then
    echo "Error: Content exceeds size limit (${MAX_SIZE_MB}MB)" >&2
    exit 1
fi

# Output to destination
if [ "$OUTPUT_FILE" = "/dev/stdout" ]; then
    cat "$TEMP_FILE"
else
    cat "$TEMP_FILE" > "$OUTPUT_FILE"
fi

exit 0
