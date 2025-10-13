#!/usr/bin/env bash
# Shared State Protocol
# Handles file locking and concurrent access to shared resources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source error messages
if [ -f "$SCRIPT_DIR/utils/error-messages.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/utils/error-messages.sh"
fi

# Acquire lock on a file
lock_acquire() {
    local file="$1"
    local lock_file="${file}.lock"
    local timeout="${2:-30}"  # seconds
    local start_time
    start_time=$(date +%s)

    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired
            echo $$ > "$lock_file/pid"
            return 0
        fi

        # Check if lock holder is still alive
        if [ -f "$lock_file/pid" ]; then
            local lock_pid
            lock_pid=$(cat "$lock_file/pid" 2>/dev/null || echo "")
            if [ -n "$lock_pid" ]; then
                if ! kill -0 "$lock_pid" 2>/dev/null; then
                    # Lock holder is dead, remove stale lock
                    rm -rf "$lock_file"
                    continue
                fi
            fi
        fi

        # Check if timeout exceeded (using actual elapsed time)
        local elapsed
        elapsed=$(($(date +%s) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            # Use user-friendly error message if available
            if type error_lock_failed &>/dev/null; then
                error_lock_failed "$file" "$timeout"
            else
                echo "Error: Failed to acquire lock on $file after $timeout seconds" >&2
            fi
            return 1
        fi

        sleep 0.1
    done
}

# Release lock
lock_release() {
    local file="$1"
    local lock_file="${file}.lock"

    if [ -d "$lock_file" ]; then
        # Use rmdir instead of rm -rf (safer for directory locks)
        rm -f "$lock_file/pid" 2>/dev/null || true
        rmdir "$lock_file" 2>/dev/null || true
    fi
}

# Get ISO 8601 timestamp (UTC)
# Centralized to ensure consistency across all modules
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Execute with lock (automatic acquire and release)
# Note: Uses explicit lock release instead of trap to avoid interfering with caller's traps
# Usage: with_lock FILE COMMAND [ARGS...]
with_lock() {
    local file="$1"
    shift
    # Now "$@" preserves argument boundaries (safe from injection)

    if lock_acquire "$file"; then
        # Run command safely without eval
        "$@"
        local result=$?

        # Always release lock, even if command failed
        lock_release "$file"

        return $result
    else
        return 1
    fi
}

# Atomic read (with lock)
atomic_read() {
    local file="$1"

    if ! lock_acquire "$file"; then
        return 1
    fi

    # Add trap to ensure cleanup on error
    trap 'lock_release "$file"' RETURN ERR
    cat "$file"
    local result=$?
    lock_release "$file"
    trap - RETURN ERR
    return $result
}

# Atomic write (with lock)
atomic_write() {
    local file="$1"
    local content="$2"

    if ! lock_acquire "$file"; then
        return 1
    fi

    # Add trap to ensure cleanup on error
    trap 'lock_release "$file"' RETURN ERR
    local result=0
    if ! echo "$content" > "$file"; then
        result=$?
    fi
    lock_release "$file"
    trap - RETURN ERR
    return $result
}

# Atomic JSON update (read, modify, write)
# Usage: atomic_json_update FILE [JQ_ARGS...] JQ_EXPR
# The last argument is the jq expression, all others are passed to jq
atomic_json_update() {
    local file="$1"
    shift

    # Last argument is the jq expression, all others are jq args
    local args=("$@")
    local last_idx=$((${#args[@]} - 1))
    local expr="${args[$last_idx]}"
    unset 'args[$last_idx]'

    lock_acquire "$file" || return 1

    # Attempt JSON update with error handling
    local jq_error
    if ! jq_error=$(jq "${args[@]}" "$expr" "$file" 2>&1 > "${file}.tmp"); then
        # JSON update failed
        rm -f "${file}.tmp"
        lock_release "$file"

        # Use user-friendly error message if available
        if type error_json_corrupted &>/dev/null; then
            error_json_corrupted "$file" "$jq_error"
        else
            echo "Error: JSON update failed for $file" >&2
            echo "$jq_error" >&2
        fi
        return 1
    fi

    # Move with error handling
    if ! mv "${file}.tmp" "$file"; then
        # Move failed - cleanup and report
        rm -f "${file}.tmp"
        lock_release "$file"
        echo "Error: Failed to update $file (mv failed)" >&2
        return 1
    fi
    
    lock_release "$file"
}

# Export functions
export -f lock_acquire
export -f lock_release
export -f with_lock
export -f atomic_read
export -f atomic_write
export -f atomic_json_update
export -f get_timestamp
