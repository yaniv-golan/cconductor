#!/usr/bin/env bash
# Safe Fetch Wrapper - Secure curl with size/time limits
# Provides safe fetching with security controls based on configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source config loader
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-loader.sh"

# Parse arguments
URL="$1"
OUTPUT_FILE="${2:-/dev/stdout}"

# Load URL policy from configuration
ALLOW_LOCALHOST=$(get_config_value "safe-fetch-policy" ".url_restrictions.allow_localhost" "false")
ALLOW_IPS=$(get_config_value "safe-fetch-policy" ".url_restrictions.allow_ip_addresses" "false")

# Build URL validation regex based on policy
if [[ "$ALLOW_LOCALHOST" == "true" ]]; then
    # Allow localhost and standard domains
    URL_PATTERN='^https?://(localhost|127\.0\.0\.1|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(:[0-9]+)?(/.*)?$'
elif [[ "$ALLOW_IPS" == "true" ]]; then
    # Allow IP addresses and standard domains
    URL_PATTERN='^https?://([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(:[0-9]+)?(/.*)?$'
else
    # Strict: domain names only (default secure behavior)
    URL_PATTERN='^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$'
fi

# Validate URL format
if ! echo "$URL" | grep -qE "$URL_PATTERN"; then
    echo "Error: Invalid URL format: $URL" >&2
    if [[ "$ALLOW_LOCALHOST" != "true" ]] && echo "$URL" | grep -qE 'localhost|127\.0\.0\.1'; then
        echo "Note: localhost URLs are blocked by policy. To enable, set:" >&2
        echo "  config/safe-fetch-policy.default.json -> url_restrictions.allow_localhost = true" >&2
    elif [[ "$ALLOW_IPS" != "true" ]] && echo "$URL" | grep -qE '^https?://[0-9]{1,3}\.[0-9]'; then
        echo "Note: IP addresses are blocked by policy. To enable, set:" >&2
        echo "  config/safe-fetch-policy.default.json -> url_restrictions.allow_ip_addresses = true" >&2
    else
        echo "URL must be http:// or https:// with valid domain" >&2
    fi
    exit 1
fi

# Load security configuration (overlay pattern)
PROFILE=$(get_config_value "security-config" ".security_profile" "\"strict\"" | tr -d '"')
MAX_SIZE_MB=$(get_config_value "security-config" ".profiles.${PROFILE}.max_fetch_size_mb" "10")
TIMEOUT_SEC=$(get_config_value "security-config" ".profiles.${PROFILE}.fetch_timeout_seconds" "30")

# Convert MB to bytes for curl
MAX_SIZE_BYTES=$((MAX_SIZE_MB * 1024 * 1024))

# Create temporary files for fetch
TEMP_FILE=$(mktemp)
TEMP_STATUS=$(mktemp)
TEMP_STDERR=$(mktemp)
trap 'rm -f "$TEMP_FILE" "$TEMP_STATUS" "$TEMP_STDERR"' EXIT

# Perform fetch with security limits
if ! curl -L \
    --max-redirs 3 \
    --max-time "$TIMEOUT_SEC" \
    --max-filesize "$MAX_SIZE_BYTES" \
    -A "ResearchEngine/1.0 (Academic Research)" \
    --proto =https,http \
    -s \
    -w "%{http_code}" \
    -o "$TEMP_FILE" \
    "$URL" > "$TEMP_STATUS" 2> "$TEMP_STDERR"; then

    echo "Error: Failed to fetch $URL" >&2
    # Show actual error message from curl
    if [ -s "$TEMP_STDERR" ]; then
        cat "$TEMP_STDERR" >&2
    else
        echo "Check network connection and URL validity" >&2
    fi
    exit 1
fi

# Extract HTTP code from curl output
HTTP_CODE=$(cat "$TEMP_STATUS" 2>/dev/null || echo "000")

# Check HTTP status
if [ "$HTTP_CODE" -ge 400 ]; then
    echo "Error: HTTP $HTTP_CODE for $URL" >&2
    exit 1
fi

# Load content policy from configuration
BLOCK_EXECUTABLES=$(get_config_value "safe-fetch-policy" ".content_restrictions.block_executables" "true")
BLOCK_ARCHIVES=$(get_config_value "safe-fetch-policy" ".content_restrictions.block_archives" "true")
BLOCK_COMPRESSED=$(get_config_value "safe-fetch-policy" ".content_restrictions.block_compressed" "false")

# Validate content based on policy
if command -v file >/dev/null 2>&1; then
    FILE_TYPE=$(file -b "$TEMP_FILE")
    
    # Build blocked pattern from configuration
    BLOCKED_PATTERNS=()
    [[ "$BLOCK_EXECUTABLES" == "true" ]] && BLOCKED_PATTERNS+=("executable")
    [[ "$BLOCK_ARCHIVES" == "true" ]] && BLOCKED_PATTERNS+=("archive")
    [[ "$BLOCK_COMPRESSED" == "true" ]] && BLOCKED_PATTERNS+=("compressed data")
    
    if [[ ${#BLOCKED_PATTERNS[@]} -gt 0 ]]; then
        PATTERN=$(IFS="|"; echo "${BLOCKED_PATTERNS[*]}")
        if echo "$FILE_TYPE" | grep -qiE "($PATTERN)"; then
            echo "Error: Blocked content type detected: $FILE_TYPE" >&2
            echo "Content policy blocks this type. To adjust, edit config/safe-fetch-policy.default.json" >&2
            exit 1
        fi
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
