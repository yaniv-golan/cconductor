#!/usr/bin/env bash
# Path Resolver - Expands configured paths with variable substitution
# Removes hardcoded paths, enables multiple installations

set -euo pipefail

# Get project root
if [ -n "${PROJECT_ROOT:-}" ]; then
    # PROJECT_ROOT already set, use it as-is
    :
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Source core helpers first
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || true

# Source platform-aware paths
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/platform-paths.sh"

# Source config loader
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/config-loader.sh"

# Set platform-aware path variables
PLATFORM_DATA=$(get_data_dir)
PLATFORM_CACHE=$(get_cache_dir)
PLATFORM_LOGS=$(get_log_dir)
PLATFORM_CONFIG=$(get_config_dir)

# Resolve path with variable expansion
# Usage: resolve_path "cache_dir"
# Returns: Expanded absolute path
resolve_path() {
    local path_key="$1"

    # Load paths config (overlay pattern)
    local paths_config
    paths_config=$(load_config "paths")

    # Get raw path
    local raw_path
    raw_path=$(echo "$paths_config" | jq -r ".$path_key // empty")

    if [ -z "$raw_path" ]; then
        echo "ERROR: Path key not found: $path_key" >&2
        echo "       Available paths: $(echo "$paths_config" | jq -r 'keys[]' | paste -sd, -)" >&2
        return 1
    fi

    # Expand variables
    local expanded_path="$raw_path"
    expanded_path="${expanded_path//\$\{HOME\}/$HOME}"
    expanded_path="${expanded_path//\$\{PROJECT_ROOT\}/$PROJECT_ROOT}"
    expanded_path="${expanded_path//\$\{USER\}/$USER}"
    expanded_path="${expanded_path//\$\{PLATFORM_DATA\}/$PLATFORM_DATA}"
    expanded_path="${expanded_path//\$\{PLATFORM_CACHE\}/$PLATFORM_CACHE}"
    expanded_path="${expanded_path//\$\{PLATFORM_LOGS\}/$PLATFORM_LOGS}"
    expanded_path="${expanded_path//\$\{PLATFORM_CONFIG\}/$PLATFORM_CONFIG}"

    # Resolve to absolute path (handle ~ and relative paths)
    expanded_path=$(eval echo "$expanded_path")

    # Normalize path (remove trailing slashes, resolve ..)
    # Only normalize if parent directory exists, otherwise keep the expanded path
    local parent_dir
    parent_dir=$(dirname -- "$expanded_path")
    if [ -d "$parent_dir" ]; then
        expanded_path=$(cd -P -- "$parent_dir" && pwd -P)/$(basename -- "$expanded_path")
    fi

    echo "$expanded_path"
}

# Resolve path and ensure directory exists
# Usage: ensure_path_exists "cache_dir"
# Returns: Expanded absolute path (creates if missing)
ensure_path_exists() {
    local path_key="$1"
    local path
    path=$(resolve_path "$path_key")

    # Create directory if it doesn't exist
    if [ ! -d "$path" ]; then
        mkdir -p "$path" 2>/dev/null || {
            if command -v log_warn &>/dev/null; then
                log_warn "Could not create directory: $path"
            else
                echo "Warning: Could not create directory: $path" >&2
            fi
            return 1
        }
    fi

    echo "$path"
}

# List all configured paths
# Usage: list_paths
# Prints: Table of path keys, configured values, and resolved paths
list_paths() {
    local paths_config
    paths_config=$(load_config "paths")

    echo "Configured Paths"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "Path Key                  | Configured Value"
    echo "─────────────────────────────────────────────────────────"
    echo "$paths_config" | jq -r 'to_entries[] | "  \(.key | ascii_downcase) → \(.value)"' | column -t -s '→'
    echo ""
    echo "Resolved Paths"
    echo "════════════════════════════════════════════════════════"
    echo ""
    echo "$paths_config" | jq -r 'keys[]' | while read -r key; do
        local resolved
        resolved=$(resolve_path "$key" 2>/dev/null || echo "ERROR")
        local exists_marker=""
        if [ -d "$resolved" ]; then
            exists_marker="✓"
        elif [ -f "$resolved" ]; then
            exists_marker="✓ (file)"
        else
            exists_marker="✗"
        fi
        printf "  %-22s → %s %s\n" "$key" "$resolved" "$exists_marker"
    done
}

# Validate all path keys are defined
# Usage: validate_paths
# Returns: 0 if all keys valid, 1 if any missing
validate_paths() {
    local paths_config
    paths_config=$(load_config "paths")

    local required_keys=(
        "cache_dir"
        "log_dir"
        "session_dir"
        "config_dir"
    )

    local errors=0

    echo "Validating path configuration..."
    echo ""

    for key in "${required_keys[@]}"; do
        local path
        path=$(echo "$paths_config" | jq -r ".$key // empty")
        if [ -z "$path" ]; then
            echo "  ✗ Missing required path key: $key"
            ((errors++))
        else
            echo "  ✓ $key defined"
        fi
    done

    echo ""

    if [ $errors -eq 0 ]; then
        echo "All required paths configured ✓"
        return 0
    else
        echo "Found $errors missing path(s) ✗"
        return 1
    fi
}

# Create all configured directories
# Usage: init_all_paths
# Returns: Number of directories created
init_all_paths() {
    local paths_config
    paths_config=$(load_config "paths")
    local created=0

    echo "Initializing configured paths..."
    echo ""

    echo "$paths_config" | jq -r 'keys[]' | while read -r key; do
        local path
        path=$(resolve_path "$key" 2>/dev/null)

        # Skip file paths (not directories)
        if [[ "$key" == *"_file" ]] || [[ "$key" == *"_db" ]] || [[ "$key" == *"_log" ]]; then
            # Ensure parent directory exists
            local parent_dir
            parent_dir=$(dirname "$path")
            if [ ! -d "$parent_dir" ]; then
                mkdir -p "$parent_dir" 2>/dev/null && {
                    echo "  ✓ Created parent directory: $parent_dir"
                    ((created++))
                }
            fi
        else
            # Create directory
            if [ ! -d "$path" ]; then
                mkdir -p "$path" 2>/dev/null && {
                    echo "  ✓ Created: $path"
                    ((created++))
                }
            else
                echo "  → Exists: $path"
            fi
        fi
    done

    echo ""
    echo "Initialization complete"
}

# Export functions for use in other scripts
export -f resolve_path
export -f ensure_path_exists
export -f list_paths
export -f validate_paths
export -f init_all_paths

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        resolve)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 resolve <path_key>" >&2
                echo "Example: $0 resolve cache_dir" >&2
                exit 1
            fi
            resolve_path "$2"
            ;;
        ensure)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 ensure <path_key>" >&2
                echo "Example: $0 ensure log_dir" >&2
                exit 1
            fi
            ensure_path_exists "$2"
            ;;
        list)
            list_paths
            ;;
        validate)
            validate_paths
            ;;
        init)
            init_all_paths
            ;;
        help|--help|-h)
            cat <<EOF
Path Resolver - Variable expansion for configured paths

Usage: $0 <command> [args]

Commands:
  resolve <path_key>   Expand path with variable substitution
  ensure <path_key>    Resolve and create directory if missing
  list                 Show all configured paths (configured and resolved)
  validate             Check all required paths are defined
  init                 Create all configured directories
  help                 Show this help

Examples:
  # Resolve cache directory
  $0 resolve cache_dir
  # Output: /Users/username/.cache/cconductor

  # Ensure log directory exists
  $0 ensure log_dir
  # Output: /Users/username/.claude/cconductor/logs
  # (creates directory if missing)

  # List all paths
  $0 list

  # Validate configuration
  $0 validate

  # Initialize all directories
  $0 init

Variable Expansion:
  \${HOME}            - User home directory
  \${PROJECT_ROOT}    - Research engine installation directory
  \${USER}            - Current username
  \${PLATFORM_DATA}   - OS-appropriate data directory
  \${PLATFORM_CACHE}  - OS-appropriate cache directory
  \${PLATFORM_LOGS}   - OS-appropriate logs directory
  \${PLATFORM_CONFIG} - OS-appropriate config directory

Path Configuration:
  Default paths: config/paths.default.json (git-tracked, don't edit)
  Custom paths:  ~/.config/cconductor/paths.json (user customizations)

  Create custom config:
    ./src/utils/config-loader.sh init paths
    vim ~/.config/cconductor/paths.json

EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
