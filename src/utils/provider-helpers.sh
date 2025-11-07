#!/usr/bin/env bash
# Provider Helpers - Error classification and retry logic for API providers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load json-helpers for safe_jq_from_json
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh" 2>/dev/null || {
    echo "Warning: json-helpers.sh not found, provider error classification may be limited" >&2
}

# Classify whether an error is retryable
# Returns 0 (success) if error is retryable, 1 (failure) if not
provider_is_retryable_error() {
    local error_json="$1"
    
    if [[ -z "$error_json" || "$error_json" == "null" || "$error_json" == "{}" ]]; then
        return 1
    fi
    
    local error_type
    error_type=$(safe_jq_from_json "$error_json" '.type // ""' "" "" "error.type" 2>/dev/null || echo "")
    local error_message
    error_message=$(safe_jq_from_json "$error_json" '.message // ""' "" "" "error.message" 2>/dev/null || echo "")
    
    case "$error_type" in
        api_error)
            # Retryable: Overloaded, rate limit
            if [[ "$error_message" =~ (Overloaded|overloaded|rate.?limit|Rate.?Limit) ]]; then
                return 0
            fi
            ;;
        timeout|connection_error)
            # Transient network issues are retryable
            return 0
            ;;
        *)
            # Unknown error types or permanent failures are not retryable
            ;;
    esac
    
    return 1
}

