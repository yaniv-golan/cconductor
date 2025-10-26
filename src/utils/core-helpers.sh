#!/usr/bin/env bash
# Core Helper Functions - Universal utilities for all scripts
# Source this file at the top of any cconductor script for common functionality
#
# Usage:
#   source "$PROJECT_ROOT/src/utils/core-helpers.sh"
#
# This file provides lightweight, universally useful helpers that reduce
# code duplication across the codebase.

if [[ -n "${CORE_HELPERS_LOADED:-}" ]]; then
    if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
        return 0
    else
        exit 0
    fi
fi

if [[ -z "${CCONDUCTOR_BOOTSTRAP_LOADED:-}" ]]; then
    CORE_HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$CORE_HELPERS_DIR/bootstrap.sh" ]]; then
        # shellcheck disable=SC1091
        source "$CORE_HELPERS_DIR/bootstrap.sh"
        if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
            return 0
        else
            exit 0
        fi
    fi
fi

export CORE_HELPERS_LOADED=1

set -euo pipefail

# ============================================================================
# DEPENDENCY CHECKING
# ============================================================================

# Check for required command-line tool with helpful error message
# Usage: require_command "jq" "brew install jq" "apt install jq"
# Returns: 0 if command exists, 1 if not (with error message)
require_command() {
    local cmd="$1"
    local install_macos="${2:-brew install $cmd}"
    local install_linux="${3:-apt install $cmd}"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        cat >&2 <<EOF
Error: $cmd is required but not installed

Install:
  macOS:  $install_macos
  Linux:  $install_linux
EOF
        return 1
    fi
    return 0
}

# Check multiple commands at once
# Usage: require_commands "jq:brew install jq:apt install jq" "curl:brew install curl:apt install curl"
# Returns: 0 if all exist, 1 if any missing
require_commands() {
    local failed=0
    for spec in "$@"; do
        IFS=':' read -r cmd mac_install linux_install <<< "$spec"
        if ! require_command "$cmd" "$mac_install" "$linux_install"; then
            failed=1
        fi
    done
    return $failed
}

# ============================================================================
# TIMESTAMP FUNCTIONS
# ============================================================================

# Get ISO 8601 timestamp (UTC) - standard precision
# Usage: timestamp=$(get_timestamp)
# Returns: YYYY-MM-DDTHH:MM:SSZ
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get high-precision timestamp with microseconds (for event logging)
# Usage: timestamp=$(get_timestamp_precise)
# Returns: YYYY-MM-DDTHH:MM:SS.µµµµµµZ (falls back to standard if unavailable)
get_timestamp_precise() {
    date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || get_timestamp
}

# Get Unix epoch timestamp (seconds since 1970-01-01)
# Usage: epoch=$(get_epoch)
# Returns: Unix timestamp as integer
get_epoch() {
    date -u +%s
}

# ============================================================================
# SIMPLE LOCKING (for cases where shared-state.sh is too heavy)
# ============================================================================

# Acquire simple lock with timeout using atomic mkdir
# Usage: simple_lock_acquire "/path/to/file.lock" 10
# Returns: 0 on success, 1 on timeout
simple_lock_acquire() {
    local lock_file="$1"
    local timeout="${2:-30}"
    local start_time
    start_time=$(get_epoch)
    
    while ! mkdir "$lock_file" 2>/dev/null; do
        local elapsed=$(($(get_epoch) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Error: Failed to acquire lock after ${timeout}s: $lock_file" >&2
            return 1
        fi
        sleep 0.1
    done
    
    # Store PID for debugging
    echo $$ > "$lock_file/pid" 2>/dev/null || true
    return 0
}

# Release simple lock
# Usage: simple_lock_release "/path/to/file.lock"
simple_lock_release() {
    local lock_file="$1"
    rm -f "$lock_file/pid" 2>/dev/null || true
    rmdir "$lock_file" 2>/dev/null || true
}

# Execute command with automatic lock acquire/release
# Usage: with_simple_lock "/path/to/file.lock" command arg1 arg2
with_simple_lock() {
    local lock_file="$1"
    shift
    
    if simple_lock_acquire "$lock_file"; then
        "$@"
        local result=$?
        simple_lock_release "$lock_file"
        return $result
    else
        return 1
    fi
}

# ============================================================================
# PATH UTILITIES
# ============================================================================

# Resolve script directory (handles spaces in paths)
# Usage: SCRIPT_DIR=$(get_script_dir)
# Note: Uses BASH_SOURCE[1] to get caller's directory
get_script_dir() {
    (cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
}

# Resolve project root from any script by finding VERSION file
# Usage: PROJECT_ROOT=$(get_project_root)
# Returns: Absolute path to project root
get_project_root() {
    local current_dir="${1:-$(pwd)}"
    
    # Walk up until we find VERSION file or reach root
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/VERSION" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    echo "Error: Could not find project root (no VERSION file found)" >&2
    return 1
}

# ============================================================================
# VALIDATION HELPERS (simple cases, defer to validation.sh for complex)
# ============================================================================

# Check if value is not empty
# Usage: is_set "$var" || { echo "Error"; exit 1; }
# Returns: 0 if set and non-empty, 1 otherwise
is_set() {
    [[ -n "${1:-}" ]]
}

# Check if file exists
# Usage: file_exists "$path" || { echo "Not found"; exit 1; }
# Returns: 0 if file exists, 1 otherwise
file_exists() {
    [[ -f "${1:-}" ]]
}

# Check if directory exists
# Usage: dir_exists "$path" || { echo "Not found"; exit 1; }
# Returns: 0 if directory exists, 1 otherwise
dir_exists() {
    [[ -d "${1:-}" ]]
}

# Check if JSON is valid
# Usage: is_valid_json "$json_string" || { echo "Invalid"; exit 1; }
# Returns: 0 if valid JSON, 1 otherwise
is_valid_json() {
    echo "${1:-}" | jq empty 2>/dev/null
}

# ============================================================================
# LOGGING HELPERS
# ============================================================================

# Log info message to stderr with timestamp
# Usage: log_info "Processing started"
log_info() {
    echo "[$(get_timestamp)] INFO: $*" >&2
}

# Log warning message to stderr with timestamp
# Usage: log_warn "Unusual condition detected"
#    OR: log_warn "$session_dir" "operation" "message" ["context"]
log_warn() {
    if [[ -d "${1:-}" ]] && [[ $# -ge 3 ]] && \
       [[ -f "${1}/meta/session.json" ]] && \
       command -v log_session_warning &>/dev/null; then
        log_session_warning "$@"
        return
    fi

    echo "[$(get_timestamp)] WARN: $*" >&2
}

# Log error message to stderr with timestamp
# Usage: log_error "Failed to process file"
#    OR: log_error "$session_dir" "operation" "message" ["context"]
log_error() {
    if [[ -d "${1:-}" ]] && [[ $# -ge 3 ]] && \
       [[ -f "${1}/meta/session.json" ]] && \
       command -v log_session_error &>/dev/null; then
        log_session_error "$@"
        return
    fi

    echo "[$(get_timestamp)] ERROR: $*" >&2
}

# Session-aware error logging wrapper that prefers structured logs
# Usage: log_system_error "$session_dir" "operation" "message" ["context"]
log_system_error() {
    local session_dir="${1:-}"
    local operation="${2:-unknown_operation}"
    local message="${3:-}"
    local context="${4:-}"

    if [[ -z "$message" ]]; then
        log_error "[$operation] (no message provided)"
        return
    fi

    if [[ -d "$session_dir" ]] && [[ -f "$session_dir/meta/session.json" ]] && \
       command -v log_session_error &>/dev/null; then
        log_session_error "$session_dir" "$operation" "$message" "$context"
    else
        if [[ -n "$context" ]]; then
            log_error "[$operation] $message ($context)"
        else
            log_error "[$operation] $message"
        fi
    fi
}

# Session-aware warning logging wrapper with graceful fallback
log_system_warning() {
    local session_dir="${1:-}"
    local operation="${2:-unknown_operation}"
    local message="${3:-}"
    local context="${4:-}"

    if [[ -z "$message" ]]; then
        log_warn "[$operation] (no message provided)"
        return
    fi

    if [[ -d "$session_dir" ]] && [[ -f "$session_dir/meta/session.json" ]] && \
       command -v log_session_warning &>/dev/null; then
        log_session_warning "$session_dir" "$operation" "$message" "$context"
    else
        if [[ -n "$context" ]]; then
            log_warn "[$operation] $message ($context)"
        else
            log_warn "[$operation] $message"
        fi
    fi
}

# Log debug message to stderr with timestamp (only if CCONDUCTOR_DEBUG=1)
# Usage: log_debug "Variable value: $var"
log_debug() {
    if [[ "${CCONDUCTOR_DEBUG:-0}" == "1" ]]; then
        echo "[$(get_timestamp)] DEBUG: $*" >&2
    fi
}

# ============================================================================
# EXPORTS (make available to subshells)
# ============================================================================

export -f require_command
export -f require_commands
export -f get_timestamp
export -f get_timestamp_precise
export -f get_epoch
export -f simple_lock_acquire
export -f simple_lock_release
export -f with_simple_lock
export -f get_script_dir
export -f get_project_root
export -f is_set
export -f file_exists
export -f dir_exists
export -f is_valid_json
export -f log_info
export -f log_warn
export -f log_error
export -f log_debug
export -f log_system_error
export -f log_system_warning
