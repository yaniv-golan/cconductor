#!/bin/bash
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
            echo "$HOME/Library/Application Support/Delve"
            ;;
        linux)
            echo "${XDG_DATA_HOME:-$HOME/.local/share}/delve"
            ;;
        windows)
            # Windows paths in WSL/Git Bash
            if [ -n "${APPDATA:-}" ]; then
                echo "$APPDATA/Delve"
            else
                echo "$HOME/.local/share/delve"
            fi
            ;;
        *)
            # Fallback for unknown systems
            echo "$HOME/.local/share/delve"
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
            echo "$HOME/Library/Caches/Delve"
            ;;
        linux)
            echo "${XDG_CACHE_HOME:-$HOME/.cache}/delve"
            ;;
        windows)
            if [ -n "${LOCALAPPDATA:-}" ]; then
                echo "$LOCALAPPDATA/Delve/Cache"
            else
                echo "$HOME/.cache/delve"
            fi
            ;;
        *)
            echo "$HOME/.cache/delve"
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
            echo "$HOME/Library/Logs/Delve"
            ;;
        linux)
            echo "${XDG_STATE_HOME:-$HOME/.local/state}/delve"
            ;;
        windows)
            if [ -n "${LOCALAPPDATA:-}" ]; then
                echo "$LOCALAPPDATA/Delve/Logs"
            else
                echo "$HOME/.local/state/delve"
            fi
            ;;
        *)
            echo "$HOME/.local/state/delve"
            ;;
    esac
}

# Get config directory (for user configuration files)
# Note: Delve stores configs in PROJECT_ROOT/config by default
# This is for future user-level config support
get_config_dir() {
    local os
    os=$(detect_os)
    
    case "$os" in
        macos)
            # macOS can use either ~/Library/Preferences or ~/.config
            # Using ~/.config for consistency with Linux
            echo "$HOME/.config/delve"
            ;;
        linux)
            echo "${XDG_CONFIG_HOME:-$HOME/.config}/delve"
            ;;
        windows)
            if [ -n "${APPDATA:-}" ]; then
                echo "$APPDATA/Delve"
            else
                echo "$HOME/.config/delve"
            fi
            ;;
        *)
            echo "$HOME/.config/delve"
            ;;
    esac
}

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
        --os)
            detect_os
            ;;
        --show|--help|"")
            show_platform_paths
            ;;
        *)
            echo "Usage: platform-paths.sh [--data|--cache|--logs|--config|--os|--show]"
            exit 1
            ;;
    esac
fi

