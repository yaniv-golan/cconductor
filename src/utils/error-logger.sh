#!/usr/bin/env bash
# Error Logger - Centralized error and warning logging for observability
# Captures errors that would otherwise be silenced by 2>/dev/null

# Load shared state for timestamp generation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../shared-state.sh"

# Initialize error log for a session
init_error_log() {
    local session_dir="$1"
    local log_file="$session_dir/logs/system-errors.log"

    mkdir -p "$session_dir/logs"
    
    # Create empty log file if it doesn't exist
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        
        # Write header
        cat > "$log_file" <<EOF
# CConductor System Error Log
# Format: JSONL (one JSON object per line)
# Created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# Fields:
#   timestamp - ISO 8601 timestamp
#   severity - "error" or "warning"
#   operation - What was being attempted
#   message - Human-readable error description
#   context - Additional context (file, line, variables, etc.)
#
EOF
    fi
}

# Log an error to session error log (critical failure)
# Note: Different from core-helpers.sh log_error (which is for stderr)
log_session_error() {
    local session_dir="$1"
    local operation="$2"
    local message="$3"
    local context="${4:-}"
    
    _log_entry "$session_dir" "error" "$operation" "$message" "$context"
}

# Log a warning to session error log (non-fatal issue)
# Note: Different from core-helpers.sh log_warn (which is for stderr)
log_session_warning() {
    local session_dir="$1"
    local operation="$2"
    local message="$3"
    local context="${4:-}"
    
    _log_entry "$session_dir" "warning" "$operation" "$message" "$context"
}

# Internal: Write log entry
_log_entry() {
    local session_dir="$1"
    local severity="$2"
    local operation="$3"
    local message="$4"
    local context="$5"
    
    # Ensure log file exists
    init_error_log "$session_dir"
    
    local log_file="$session_dir/logs/system-errors.log"
    local lock_file="$session_dir/.error-log.lock"
    
    # Get timestamp
    local timestamp
    timestamp=$(get_timestamp)
    
    # Build JSON entry
    local entry
    entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg sev "$severity" \
        --arg op "$operation" \
        --arg msg "$message" \
        --arg ctx "$context" \
        '{
            timestamp: $ts,
            severity: $sev,
            operation: $op,
            message: $msg,
            context: $ctx
        }')
    
    # Atomic write with lock
    local max_wait=50  # 5 seconds (50 * 0.1s)
    local wait_count=0
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write entry
            echo "$entry" >> "$log_file"
            rmdir "$lock_file" 2>/dev/null || true
            break
        fi
        
        # Wait and retry
        sleep 0.1
        wait_count=$((wait_count + 1))
        
        if [ "$wait_count" -ge "$max_wait" ]; then
            # Timeout - write anyway (better to have duplicate than lose data)
            echo "$entry" >> "$log_file"
            break
        fi
    done
    
    # If debug mode is enabled, also output to stderr
    if [ "${CCONDUCTOR_DEBUG:-0}" = "1" ]; then
        local symbol
        if [ "$severity" = "error" ]; then
            symbol="❌"
        else
            symbol="⚠️ "
        fi
        echo "$symbol [$severity] $operation: $message${context:+ ($context)}" >&2
    fi
}

# Get error summary for dashboard
get_error_summary() {
    local session_dir="$1"
    local log_file="$session_dir/logs/system-errors.log"
    
    if [ ! -f "$log_file" ]; then
        echo "[]"
        return 0
    fi
    
    # Extract JSON entries (skip comment lines)
    local entries
    entries=$(grep -v '^#' "$log_file" 2>/dev/null || echo "")
    
    if [ -z "$entries" ]; then
        echo "[]"
        return 0
    fi
    
    # Convert to JSON array and get last 10 entries
    echo "$entries" | jq -s '. | sort_by(.timestamp) | reverse | .[0:10]' 2>/dev/null || echo "[]"
}

# Get error counts
get_error_counts() {
    local session_dir="$1"
    local log_file="$session_dir/logs/system-errors.log"
    
    if [ ! -f "$log_file" ]; then
        jq -n '{errors: 0, warnings: 0}'
        return 0
    fi
    
    local error_count=0
    local warning_count=0
    
    if [ -f "$log_file" ]; then
        error_count=$(grep -c '"severity": "error"' "$log_file" 2>/dev/null || echo "0")
        warning_count=$(grep -c '"severity": "warning"' "$log_file" 2>/dev/null || echo "0")
        
        # Sanitize counts (ensure single numeric value)
        error_count=$(echo "$error_count" | head -1 | tr -d '\n' | grep -o '[0-9]*' | head -1)
        error_count=${error_count:-0}
        
        warning_count=$(echo "$warning_count" | head -1 | tr -d '\n' | grep -o '[0-9]*' | head -1)
        warning_count=${warning_count:-0}
    fi
    
    jq -n \
        --argjson errors "$error_count" \
        --argjson warnings "$warning_count" \
        '{errors: $errors, warnings: $warnings}'
}

# Check if there are any critical errors
has_critical_errors() {
    local session_dir="$1"
    local log_file="$session_dir/logs/system-errors.log"
    
    if [ ! -f "$log_file" ]; then
        return 1  # No errors
    fi
    
    if grep -q '"severity": "error"' "$log_file" 2>/dev/null; then
        return 0  # Has errors
    fi
    
    return 1  # No errors
}

# Export functions
export -f init_error_log
export -f log_session_error
export -f log_session_warning
export -f get_error_summary
export -f get_error_counts
export -f has_critical_errors
