#!/usr/bin/env bash
# Bootstrap - load core CConductor utilities once per process

if [[ -n "${CCONDUCTOR_BOOTSTRAP_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    else
        exit 0
    fi
fi
export CCONDUCTOR_BOOTSTRAP_LOADED=1

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$BOOTSTRAP_DIR/../.." && pwd)"
    export PROJECT_ROOT
fi

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/platform-paths.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/config-loader.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh"

# Export common helpers for downstream scripts
export -f get_timestamp
export -f log_info
export -f log_error
export -f load_config
export -f resolve_path
export -f path_resolve

# Memoize frequently used platform paths
PLATFORM_DATA="$(get_data_dir)"
export PLATFORM_DATA
PLATFORM_CACHE="$(get_cache_dir)"
export PLATFORM_CACHE
PLATFORM_LOGS="$(get_log_dir)"
export PLATFORM_LOGS
PLATFORM_CONFIG="$(get_config_dir)"
export PLATFORM_CONFIG
