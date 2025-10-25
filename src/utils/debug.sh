#!/usr/bin/env bash
# Debug Utility - Conditional debug logging
# Usage: Set CCONDUCTOR_DEBUG=1 to enable debug output

# Only set shell options if running directly, not when sourced
# This prevents mutating the caller's shell state
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    set -euo pipefail 2>/dev/null || set -eu
fi

# Source core helpers if available (for timestamps)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/core-helpers.sh" ]]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null || true
fi

# Check if debug mode is enabled
is_debug_enabled() {
    [[ "${CCONDUCTOR_DEBUG:-0}" == "1" ]]
}

# Log debug message (only if debug enabled)
debug() {
    if is_debug_enabled; then
        echo "[DEBUG $(date +%H:%M:%S)] $*" >&2
    fi
}

# Log debug with function/file context
debug_trace() {
    if is_debug_enabled; then
        local caller_info="${BASH_SOURCE[1]##*/}:${BASH_LINENO[0]}:${FUNCNAME[1]}"
        echo "[TRACE $(date +%H:%M:%S)] $caller_info: $*" >&2
    fi
}

# Log error (always shown)
error() {
    if is_debug_enabled; then
        echo "[ERROR $(date +%H:%M:%S)] $*" >&2
    else
        echo "Error: $*" >&2
    fi
}

# Log warning (always shown)
warn() {
    if is_debug_enabled; then
        echo "[WARN $(date +%H:%M:%S)] $*" >&2
    else
        echo "Warning: $*" >&2
    fi
}

# Log info (always shown)
info() {
    if is_debug_enabled; then
        echo "[INFO $(date +%H:%M:%S)] $*" >&2
    else
        echo "$*" >&2
    fi
}

# Enable debug mode for a command
with_debug() {
    CCONDUCTOR_DEBUG=1 "$@"
}

# Trace function entry/exit (only if debug enabled)
trace_function() {
    if is_debug_enabled; then
        local func_name="${FUNCNAME[1]}"
        echo "[TRACE $(date +%H:%M:%S)] >>> Entering: $func_name($*)" >&2
        # shellcheck disable=SC2064
        trap 'echo "[TRACE $(date +%H:%M:%S)] <<< Exiting: '"$func_name"'" >&2' RETURN
    fi
}

# Set up error trap for better debugging
setup_error_trap() {
    if is_debug_enabled; then
        trap 'error "Command failed at ${BASH_SOURCE[0]}:${LINENO} in ${FUNCNAME[0]:-main}"' ERR
    fi
}

# Execute command with error capture for logging
# Usage: debug_exec SESSION_DIR OPERATION COMMAND [ARGS...]
# Returns: exit code of command
# Side effects: Logs errors to logs/system-errors.log if command fails
debug_exec() {
    local session_dir="$1"
    local operation="$2"
    shift 2
    
    local start_time
    start_time=$(if command -v get_epoch &>/dev/null; then get_epoch; else date +%s; fi)
    
    # Capture both stdout and stderr
    local temp_stderr
    temp_stderr=$(mktemp)
    local exit_code=0
    
    if is_debug_enabled; then
        # Debug mode: show everything on console + capture stderr
        debug "Executing: $*"
        if ! "$@" 2> >(tee "$temp_stderr" >&2); then
            exit_code=$?
        fi
    else
        # Normal mode: capture stderr silently
        if ! "$@" 2>"$temp_stderr"; then
            exit_code=$?
        fi
    fi
    
    local end_time
    end_time=$(if command -v get_epoch &>/dev/null; then get_epoch; else date +%s; fi)
    local duration=$((end_time - start_time))
    
    # If command failed, log error
    if [ "$exit_code" -ne 0 ]; then
        local error_msg
        error_msg=$(cat "$temp_stderr" 2>/dev/null || echo "No error output")
        
        # Load error logger if available
        if declare -F log_error >/dev/null 2>&1; then
            log_error "$session_dir" "$operation" \
                "Command failed with exit code $exit_code" \
                "Duration: ${duration}s, Command: $*, Error: $error_msg"
        fi
        
        if is_debug_enabled; then
            error "$operation failed (exit code $exit_code, duration ${duration}s)"
        fi
    elif is_debug_enabled; then
        debug "$operation completed (duration ${duration}s)"
    fi
    
    rm -f "$temp_stderr"
    return "$exit_code"
}

# Export functions for use in subshells
export -f is_debug_enabled
export -f debug
export -f debug_trace
export -f error
export -f warn
export -f info
export -f with_debug
export -f trace_function
export -f setup_error_trap
export -f debug_exec

# Usage examples (only shown when script is run directly)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    cat <<'EOF'
Debug Utility for CConductor
=============================

Enable debug mode:
  export CCONDUCTOR_DEBUG=1
  ./cconductor "your query"

Or for a single run:
  CCONDUCTOR_DEBUG=1 ./cconductor "your query"

Functions available:
  debug "message"              - Log debug message (only if debug enabled)
  debug_trace "message"        - Log with file:line:function context
  error "message"              - Log error (always shown)
  warn "message"               - Log warning (always shown)
  info "message"               - Log info (always shown)
  trace_function "$@"          - Trace function entry/exit
  setup_error_trap             - Set up ERR trap for better error messages

Example usage in scripts:
  source "$SCRIPT_DIR/utils/debug.sh"
  setup_error_trap
  
  my_function() {
      trace_function "$@"
      debug "Processing input: $1"
      # ... function code ...
  }

EOF
fi
