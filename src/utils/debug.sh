#!/usr/bin/env bash
# Debug Utility - Conditional debug logging
# Usage: Set CCONDUCTOR_DEBUG=1 to enable debug output

# Don't use pipefail here - this is a utility that should be safe to source
set -euo pipefail 2>/dev/null || set -eu

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
    echo "[ERROR $(date +%H:%M:%S)] $*" >&2
}

# Log warning (always shown)
warn() {
    echo "[WARN $(date +%H:%M:%S)] $*" >&2
}

# Log info (always shown)
info() {
    echo "[INFO $(date +%H:%M:%S)] $*" >&2
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
