#!/usr/bin/env bash
# Config Loader - Overlay system for upgrade-safe configuration
# Implements .default pattern: user configs overlay defaults without merge conflicts
# User configs stored in OS-appropriate locations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh" 2>/dev/null || true

# Source platform-aware paths
if [ -f "$SCRIPT_DIR/platform-paths.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/platform-paths.sh"
fi

# Get user config directory (OS-appropriate location)
# Can be overridden with CCONDUCTOR_CONFIG_DIR environment variable
get_user_config_dir() {
    if [ -n "${CCONDUCTOR_CONFIG_DIR:-}" ]; then
        echo "$CCONDUCTOR_CONFIG_DIR"
    elif command -v get_config_dir &> /dev/null; then
        get_config_dir
    else
        # Fallback if platform-paths.sh not available
        echo "$HOME/.config/cconductor"
    fi
}

# Load configuration with overlay pattern
# Usage: load_config "config_name" [project_config_dir]
# Returns: JSON config (default overlaid by user config)
# 
# Loading order:
# 1. Project default: PROJECT_ROOT/config/foo.default.json (required, git-tracked)
# 2. User config:     ~/.config/cconductor/foo.json (optional, user customizations)
load_config() {
    local config_name="$1"
    local project_config_dir="${2:-$PROJECT_ROOT/config}"

    # Get file locations
    local default_file="$project_config_dir/${config_name}.default.json"
    local user_config_dir
    user_config_dir=$(get_user_config_dir)
    local user_file="$user_config_dir/${config_name}.json"

    # Validate default config exists (required)
    if [ ! -f "$default_file" ]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$default_file" "Default config not found"
        else
            echo "Error: Default config not found: $default_file" >&2
        fi
        echo "This should never happen - default configs are git-tracked." >&2
        return 1
    fi

    # Validate default config is valid JSON
    if ! jq '.' "$default_file" >/dev/null 2>&1; then
        if command -v log_error &>/dev/null; then
            log_error "Default config is invalid JSON: $default_file"
        else
            echo "Error: Default config is invalid JSON: $default_file" >&2
        fi
        return 1
    fi

    # Start with default config
    local merged_config
    merged_config=$(cat "$default_file")

    # Overlay user config if exists
    if [ -f "$user_file" ]; then
        if jq '.' "$user_file" >/dev/null 2>&1; then
            merged_config=$(echo "$merged_config" | jq -s '.[0] * .[1]' - "$user_file")
        else
            if command -v log_warn &>/dev/null; then
                log_warn "User config is invalid JSON: $user_file"
            else
                echo "Warning: User config is invalid JSON: $user_file" >&2
            fi
            echo "Falling back to default config" >&2
        fi
    fi

    echo "$merged_config"
}

# Get config value with dot notation
# Usage: get_config_value "config_name" ".path.to.value" [default_value]
# Example: get_config_value "adaptive-config" ".max_iterations" "10"
get_config_value() {
    local config_name="$1"
    local path="$2"
    local default_value="${3:-null}"

    local config
    config=$(load_config "$config_name")

    # Extract value with default fallback
    echo "$config" | jq -r "${path} // ${default_value}"
}

# Check if user config exists
# Usage: has_user_config "config_name"
# Returns: 0 if exists, 1 if not
has_user_config() {
    local config_name="$1"
    local user_config_dir
    user_config_dir=$(get_user_config_dir)
    local user_file="$user_config_dir/${config_name}.json"

    [ -f "$user_file" ]
}

# Get location of user config (if it exists)
# Usage: get_user_config_location "config_name"
# Returns: Path to user config or empty if none exists
get_user_config_location() {
    local config_name="$1"
    local user_config_dir
    user_config_dir=$(get_user_config_dir)
    local user_file="$user_config_dir/${config_name}.json"
    
    if [ -f "$user_file" ]; then
        echo "$user_file"
    fi
}

# Copy default to user config (creates in user home directory)
# Usage: init_user_config "config_name"
init_user_config() {
    local config_name="$1"
    local project_config_dir="${2:-$PROJECT_ROOT/config}"

    local default_file="$project_config_dir/${config_name}.default.json"
    local user_config_dir
    user_config_dir=$(get_user_config_dir)
    local user_file="$user_config_dir/${config_name}.json"

    if [ ! -f "$default_file" ]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$default_file" "Default config not found"
        else
            echo "Error: Default config not found: $default_file" >&2
        fi
        return 1
    fi

    # Create user config directory if needed
    if [ ! -d "$user_config_dir" ]; then
        mkdir -p "$user_config_dir"
        echo "Created config directory: $user_config_dir"
    fi

    if [ -f "$user_file" ]; then
        if command -v log_warn &>/dev/null; then
            log_warn "User config already exists: $user_file"
        else
            echo "Warning: User config already exists: $user_file" >&2
        fi
        echo "Not overwriting. Delete it first if you want to reset." >&2
        return 1
    fi

    cp "$default_file" "$user_file"
    echo "Created user config: $user_file"
    echo "You can now customize it without affecting git-tracked defaults."
}

# List all available configs
# Usage: list_configs
list_configs() {
    local config_dir="$PROJECT_ROOT/config"
    local user_config_dir
    user_config_dir=$(get_user_config_dir)

    echo "Available configurations:"
    echo ""

    for default_file in "$config_dir"/*.default.json; do
        if [ ! -f "$default_file" ]; then
            continue
        fi

        local basename
        basename=$(basename "$default_file" .default.json)
        local user_file="$user_config_dir/${basename}.json"

        echo -n "  • $basename"

        if [ -f "$user_file" ]; then
            echo " ✓ (customized)"
        else
            echo " (using default)"
        fi
    done
    
    echo ""
    echo "Config locations:"
    echo "  Defaults:  $config_dir/*.default.json (git-tracked, don't edit)"
    echo "  User:      $user_config_dir/*.json (customize these)"
}

# Validate all configs (useful for CI/testing)
# Usage: validate_configs
validate_configs() {
    local config_dir="$PROJECT_ROOT/config"
    local errors=0

    echo "Validating configurations..."
    echo ""

    for default_file in "$config_dir"/*.default.json; do
        if [ ! -f "$default_file" ]; then
            continue
        fi

        local basename
        basename=$(basename "$default_file" .default.json)

        # Validate default
        echo -n "  Checking $basename.default.json... "
        if jq '.' "$default_file" >/dev/null 2>&1; then
            echo "✓"
        else
            echo "✗ Invalid JSON"
            ((errors++))
        fi

        # Validate user config if exists
        local user_file="$config_dir/${basename}.json"
        if [ -f "$user_file" ]; then
            echo -n "  Checking $basename.json... "
            if jq '.' "$user_file" >/dev/null 2>&1; then
                echo "✓"
            else
                echo "✗ Invalid JSON"
                ((errors++))
            fi
        fi
    done

    echo ""
    if [ $errors -eq 0 ]; then
        echo "All configurations valid ✓"
        return 0
    else
        echo "Found $errors error(s) ✗"
        return 1
    fi
}

# Show config diff (what user changed from default)
# Usage: show_config_diff "config_name"
show_config_diff() {
    local config_name="$1"
    local config_dir="${2:-$PROJECT_ROOT/config}"

    local default_file="$config_dir/${config_name}.default.json"
    local user_config_location
    user_config_location=$(get_user_config_location "$config_name")

    if [ -z "$user_config_location" ]; then
        echo "No user customizations for $config_name"
        return 0
    fi

    echo "Differences between default and user config for $config_name:"
    echo "User config: $user_config_location"
    echo ""

    # Use diff with color if available
    if command -v colordiff >/dev/null 2>&1; then
        colordiff -u <(jq -S '.' "$default_file") <(jq -S '.' "$user_config_location") || true
    else
        diff -u <(jq -S '.' "$default_file") <(jq -S '.' "$user_config_location") || true
    fi
}

# Export functions for use in other scripts
export -f load_config
export -f get_config_value
export -f has_user_config
export -f get_user_config_location
export -f get_user_config_dir
export -f init_user_config
export -f list_configs
export -f validate_configs
export -f show_config_diff

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        load)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 load <config_name>" >&2
                exit 1
            fi
            load_config "$2"
            ;;
        get)
            if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
                echo "Usage: $0 get <config_name> <path> [default]" >&2
                exit 1
            fi
            get_config_value "$2" "$3" "${4:-null}"
            ;;
        init)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 init <config_name>" >&2
                exit 1
            fi
            init_user_config "$2"
            ;;
        list)
            list_configs
            ;;
        validate)
            validate_configs
            ;;
        diff)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 diff <config_name>" >&2
                exit 1
            fi
            show_config_diff "$2"
            ;;
        where)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 where <config_name>" >&2
                exit 1
            fi
            location=$(get_user_config_location "$2")
            if [ -n "$location" ]; then
                echo "$location"
            else
                echo "No user config for $2 (using defaults)"
            fi
            ;;
        help|--help|-h)
            cat <<EOF
Config Loader - Upgrade-safe configuration management

Usage: $0 <command> [args]

Commands:
  load <config_name>              Load config (merged default + user)
  get <config_name> <path>        Get specific config value
  init <config_name>              Create user config from default
  list                            List all available configs
  validate                        Validate all config files
  diff <config_name>              Show user customizations
  where <config_name>             Show location of user config
  help                            Show this help

Examples:
  # Load full config
  $0 load adaptive-config

  # Get specific value
  $0 get adaptive-config .max_iterations

  # Create customizable config (in ~/.config/cconductor/)
  $0 init adaptive-config
  vim ~/.config/cconductor/adaptive-config.json

  # View your changes
  $0 diff adaptive-config

  # Find where your config is
  $0 where adaptive-config

  # Validate everything
  $0 validate

Config Locations:
  Defaults:  PROJECT_ROOT/config/*.default.json  (git-tracked, never edit)
  User:      ~/.config/cconductor/*.json              (customize these)
             
             On macOS:  ~/.config/cconductor/
             On Linux:  ~/.config/cconductor/  (or \$XDG_CONFIG_HOME/cconductor/)
             On Windows: %APPDATA%/CConductor/

Loading Order:
  1. Load default config from project (git-tracked)
  2. Overlay user config from home directory (if exists)
  
  User values override defaults.

Environment Variables:
  CCONDUCTOR_CONFIG_DIR - Override user config directory location


EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
