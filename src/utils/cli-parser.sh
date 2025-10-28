#!/usr/bin/env bash
# CLI Argument Parser
# Parses command-line flags and stores them in global variables
#
# Usage:
#   source cli-parser.sh
#   parse_cli_args "$@"
#   if has_flag "input-dir"; then
#     input_dir=$(get_flag "input-dir")
#   fi
#
# Requires: Bash 4.0+ for associative arrays

set -euo pipefail

# Check Bash version (need 4.0+ for associative arrays)
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    echo "Error: Bash 4.0 or higher is required for CLI parser" >&2
    echo "Current version: $BASH_VERSION" >&2
    echo "" >&2
    echo "On macOS, install with: brew install bash" >&2
    echo "Then run with: /usr/local/bin/bash or /opt/homebrew/bin/bash" >&2
    exit 1
fi

# Initialize global flag storage
declare -A CLI_FLAGS
declare -a CLI_ARGS

# Known boolean flags (flags that never take a value)
declare -a BOOLEAN_FLAGS=(
    "verbose" "debug" "help" "h" "version" "v"
    "update" "check-update" "no-update-check"
    "init" "yes" "y" "non-interactive"
    "no-cache" "no-web-fetch-cache" "no-web-search-cache"
    "enable-watchdog" "disable-watchdog"
    "enable-agent-timeouts" "disable-agent-timeouts"
)

# Check if a flag is boolean
is_boolean_flag() {
    local flag="$1"
    for bool_flag in "${BOOLEAN_FLAGS[@]}"; do
        if [[ "$flag" == "$bool_flag" ]]; then
            return 0
        fi
    done
    return 1
}

# Parse command-line arguments
# Usage: parse_cli_args "$@"
parse_cli_args() {
    # Reset arrays
    CLI_FLAGS=()
    CLI_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --*=*)
                # Handle --flag=value format
                local flag="${1%%=*}"
                local value="${1#*=}"
                flag="${flag#--}"  # Remove leading --
                CLI_FLAGS["$flag"]="$value"
                shift
                ;;
            --*)
                # Handle --flag value format
                local flag="${1#--}"
                
                # Check if this is a known boolean flag
                if is_boolean_flag "$flag"; then
                    CLI_FLAGS["$flag"]="true"
                    shift
                elif [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
                    # Next arg doesn't start with dash, treat as value
                    CLI_FLAGS["$flag"]="$2"
                    shift 2
                else
                    # No value or next arg is another flag - boolean flag
                    CLI_FLAGS["$flag"]="true"
                    shift
                fi
                ;;
            -*)
                # Handle single-dash flags like -y
                local flag="${1#-}"
                
                # Check if this is a known boolean flag
                if is_boolean_flag "$flag"; then
                    CLI_FLAGS["$flag"]="true"
                    shift
                elif [[ $# -gt 1 ]] && [[ ! "$2" =~ ^- ]]; then
                    # Check if it's a value flag (next arg doesn't start with dash)
                    CLI_FLAGS["$flag"]="$2"
                    shift 2
                else
                    # Boolean flag
                    CLI_FLAGS["$flag"]="true"
                    shift
                fi
                ;;
            *)
                # Positional argument
                CLI_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# Get flag value with optional default
# Usage: value=$(get_flag "flag-name" "default-value")
get_flag() {
    local flag="$1"
    local default="${2:-}"
    echo "${CLI_FLAGS[$flag]:-$default}"
}

# Check if flag was provided
# Usage: if has_flag "flag-name"; then ... fi
has_flag() {
    local flag="$1"
    # Use bash 4.0+ compatible test (not 4.2+ -v)
    [[ "${CLI_FLAGS[$flag]+isset}" == "isset" ]]
}

# Get positional argument by index (0-based)
# Usage: arg=$(get_arg 0)
get_arg() {
    local index="$1"
    if [[ $index -lt ${#CLI_ARGS[@]} ]]; then
        echo "${CLI_ARGS[$index]}"
    else
        echo ""
    fi
}

# Get number of positional arguments
# Usage: count=$(get_arg_count)
get_arg_count() {
    echo "${#CLI_ARGS[@]}"
}

# Validate required flags
# Usage: require_flag "flag-name" "Custom error message"
require_flag() {
    local flag="$1"
    local error_msg="${2:-Flag --$flag is required}"
    
    if ! has_flag "$flag"; then
        echo "Error: $error_msg" >&2
        return 1
    fi
    return 0
}

# Debug: Print all parsed arguments
debug_cli_args() {
    echo "Flags:" >&2
    for flag in "${!CLI_FLAGS[@]}"; do
        echo "  --$flag = ${CLI_FLAGS[$flag]}" >&2
    done
    
    echo "Positional arguments:" >&2
    for i in "${!CLI_ARGS[@]}"; do
        echo "  [$i] = ${CLI_ARGS[$i]}" >&2
    done
}
