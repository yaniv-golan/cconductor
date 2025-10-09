#!/usr/bin/env bash
# Platform-Aware Path Resolver
# Follows OS conventions for data, cache, and log directories
#
# Standards:
# - macOS: ~/Library/Application Support, ~/Library/Caches, ~/Library/Logs
# - Linux: XDG Base Directory Specification
# - Windows: %APPDATA%, %LOCALAPPDATA%

set -euo pipefail

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get application data directory (persistent user data)
# Examples: databases, user configs, session data
get_data_dir() {
    local os
    os=$(detect_os)
    
    case "$os" in
        macos)
            echo "$HOME/Library/Application Support/CConductor"
            ;;
        linux)
            echo "${XDG_DATA_HOME:-$HOME/.local/share}/cconductor"
            ;;
        windows)
            # Windows paths in WSL/Git Bash
            if [ -n "${APPDATA:-}" ]; then
                echo "$APPDATA/CConductor"
            else
                echo "$HOME/.local/share/cconductor"
            fi
            ;;
        *)
            # Fallback for unknown systems
            echo "$HOME/.local/share/cconductor"
            ;;
    esac
}

# Get cache directory (temporary, can be cleared)
# Examples: PDF cache, downloaded files, temporary processing
get_cache_dir() {
    local os
    os=$(detect_os)
    
    case "$os" in
        macos)
            echo "$HOME/Library/Caches/CConductor"
            ;;
        linux)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/cconductor"
            ;;
        windows)
            if [ -n "${LOCALAPPDATA:-}" ]; then
                echo "$LOCALAPPDATA/CConductor/Cache"
            else
                echo "$HOME/.cache/cconductor"
            fi
            ;;
        *)
            echo "$HOME/.cache/cconductor"
            ;;
    esac
}

# Get log directory (for application logs)
# Examples: audit logs, debug logs, error logs
get_log_dir() {
    local os
    os=$(detect_os)
    
    case "$os" in
        macos)
            echo "$HOME/Library/Logs/CConductor"
            ;;
        linux)
            echo "${XDG_STATE_HOME:-$HOME/.local/state}/cconductor"
            ;;
        windows)
            if [ -n "${LOCALAPPDATA:-}" ]; then
                echo "$LOCALAPPDATA/CConductor/Logs"
            else
                echo "$HOME/.local/state/cconductor"
            fi
            ;;
        *)
            echo "$HOME/.local/state/cconductor"
            ;;
    esac
}

# Get config directory (for user configuration files)
# Note: CConductor stores configs in PROJECT_ROOT/config by default
# This is for future user-level config support
get_config_dir() {
    local os
    os=$(detect_os)
    
    case "$os" in
        macos)
            # macOS can use either ~/Library/Preferences or ~/.config
            # Using ~/.config for consistency with Linux
            echo "$HOME/.config/cconductor"
            ;;
        linux)
            echo "${XDG_CONFIG_HOME:-$HOME/.config}/cconductor"
            ;;
        windows)
            if [ -n "${APPDATA:-}" ]; then
                echo "$APPDATA/CConductor"
            else
                echo "$HOME/.config/cconductor"
            fi
            ;;
        *)
            echo "$HOME/.config/cconductor"
            ;;
    esac
}

# Get temporary directory (platform-aware)
# Uses TMPDIR environment variable if set, falls back to /tmp
get_tmp_dir() {
    echo "${TMPDIR:-/tmp}"
}

# Export all path functions for use in other scripts
export -f detect_os
export -f get_data_dir
export -f get_cache_dir
export -f get_log_dir
export -f get_config_dir
export -f get_tmp_dir

# Print all platform paths (for debugging)
show_platform_paths() {
    local os
    os=$(detect_os)
    
    cat <<EOF
Platform: $os
Data:     $(get_data_dir)
Cache:    $(get_cache_dir)
Logs:     $(get_log_dir)
Config:   $(get_config_dir)
Temp:     $(get_tmp_dir)
EOF
}

# If script is run directly, show paths
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        --data)
            get_data_dir
            ;;
        --cache)
            get_cache_dir
            ;;
        --logs)
            get_log_dir
            ;;
        --config)
            get_config_dir
            ;;
        --tmp|--temp)
            get_tmp_dir
            ;;
        --os)
            detect_os
            ;;
        --show|--help|"")
            show_platform_paths
            ;;
        *)
            echo "Usage: platform-paths.sh [--data|--cache|--logs|--config|--tmp|--os|--show]"
            exit 1
            ;;
    esac
fi

