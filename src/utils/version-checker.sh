#!/bin/bash
# Version Checker - Auto-update detection and notification
# Checks GitHub for new releases and notifies user

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
REPO="yaniv-golan/delve"
CACHE_TTL_SECONDS=86400  # 24 hours

# Source dependencies
if [ -f "$PROJECT_ROOT/src/utils/platform-paths.sh" ]; then
    source "$PROJECT_ROOT/src/utils/platform-paths.sh"
    CACHE_FILE="$(get_data_dir)/version-check.cache"
else
    # Fallback
    CACHE_FILE="$HOME/.local/share/delve/version-check.cache"
fi

# Get current installed version
get_current_version() {
    if [ -f "$PROJECT_ROOT/VERSION" ]; then
        cat "$PROJECT_ROOT/VERSION"
    else
        echo "unknown"
    fi
}

# Get latest version from GitHub (with timeout)
get_latest_version() {
    local api_url="https://api.github.com/repos/${REPO}/releases/latest"
    
    # Try API first (2 second timeout)
    local latest=$(curl -s -m 2 "$api_url" 2>/dev/null | \
                   grep -oP '"tag_name": "\K[^"]+' 2>/dev/null | \
                   sed 's/^v//' | head -1)
    
    if [ -n "$latest" ]; then
        echo "$latest"
        return 0
    fi
    
    # Fallback: redirect from releases/latest
    latest=$(curl -sI -m 2 "https://github.com/${REPO}/releases/latest" 2>/dev/null | \
             grep -i '^location:' | \
             sed -n 's/.*\/tag\/v\?\([0-9.]*\).*/\1/p' | head -1)
    
    if [ -n "$latest" ]; then
        echo "$latest"
        return 0
    fi
    
    return 1
}

# Compare semantic versions (returns 0 if update available)
compare_versions() {
    local current="$1"
    local latest="$2"
    
    current="${current#v}"
    latest="${latest#v}"
    
    [ "$current" = "$latest" ] && return 1
    
    if [ "$(printf '%s\n%s' "$current" "$latest" | sort -V | head -n1)" = "$current" ]; then
        return 0  # Update available
    fi
    
    return 1
}

# Check if we should check for updates
should_check_for_updates() {
    # Check if disabled in config
    local config="$PROJECT_ROOT/config/delve-config.json"
    if [ -f "$config" ]; then
        local enabled=$(jq -r '.update_settings.check_for_updates // true' "$config" 2>/dev/null)
        [ "$enabled" != "true" ] && return 1
    fi
    
    # Check cache age
    if [ -f "$CACHE_FILE" ]; then
        local last_check=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        local now=$(date +%s)
        local age=$((now - last_check))
        
        [ $age -lt $CACHE_TTL_SECONDS ] && return 1
    fi
    
    return 0
}

# Cache version check result
cache_version_check() {
    local current="$1"
    local latest="$2"
    local update_available="$3"
    
    mkdir -p "$(dirname "$CACHE_FILE")"
    
    cat > "$CACHE_FILE" << EOF
{
  "last_check": $(date +%s),
  "current_version": "$current",
  "latest_version": "$latest",
  "update_available": $update_available,
  "release_url": "https://github.com/${REPO}/releases/tag/v${latest}"
}
EOF
}

# Show update notification
show_update_notification() {
    local current="$1"
    local latest="$2"
    local style="${3:-full}"
    
    if [ "$style" = "minimal" ]; then
        echo ""
        echo "ℹ️  New version available: v${latest} (current: v${current})"
        echo "   Run 'delve --update' to upgrade"
        echo ""
        return
    fi
    
    # Full notification
    echo ""
    echo "╭────────────────────────────────────────────────────╮"
    printf "│ 🆕 Update Available: v%-8s → v%-8s       │\n" "$current" "$latest"
    echo "│                                                    │"
    echo "│ Update now:                                        │"
    echo "│   delve --update                                   │"
    echo "│                                                    │"
    echo "│ Release notes:                                     │"
    echo "│   https://github.com/${REPO}/releases/latest      │"
    echo "│                                                    │"
    echo "│ To disable: Edit config/delve-config.json         │"
    echo "╰────────────────────────────────────────────────────╯"
    echo ""
}

# Check for updates (async, non-blocking)
check_for_updates_async() {
    should_check_for_updates || return 0
    
    # Fork to background
    (
        current=$(get_current_version)
        latest=$(get_latest_version 2>/dev/null)
        
        if [ -n "$latest" ] && [ "$latest" != "unknown" ]; then
            if compare_versions "$current" "$latest"; then
                cache_version_check "$current" "$latest" true
            else
                cache_version_check "$current" "$latest" false
            fi
        fi
    ) &
}

# Check for updates (synchronous)
check_for_updates_sync() {
    local current=$(get_current_version)
    local latest=$(get_latest_version)
    
    if [ -z "$latest" ] || [ "$latest" = "unknown" ]; then
        echo "Unable to check for updates (offline or API unavailable)"
        return 1
    fi
    
    echo "Current version: v${current}"
    echo "Latest version:  v${latest}"
    
    if compare_versions "$current" "$latest"; then
        echo ""
        echo "✅ Update available!"
        cache_version_check "$current" "$latest" true
        return 0
    else
        echo ""
        echo "✅ You have the latest version"
        cache_version_check "$current" "$latest" false
        return 1
    fi
}

# Show notification if update is cached
show_cached_notification() {
    [ ! -f "$CACHE_FILE" ] && return 1
    
    local update_available=$(jq -r '.update_available // false' "$CACHE_FILE" 2>/dev/null)
    
    if [ "$update_available" = "true" ]; then
        local current=$(jq -r '.current_version // "unknown"' "$CACHE_FILE")
        local latest=$(jq -r '.latest_version // "unknown"' "$CACHE_FILE")
        local config="$PROJECT_ROOT/config/delve-config.json"
        local style="full"
        
        if [ -f "$config" ]; then
            style=$(jq -r '.update_settings.update_notification_style // "full"' "$config" 2>/dev/null)
        fi
        
        show_update_notification "$current" "$latest" "$style"
        return 0
    fi
    
    return 1
}

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        --check) check_for_updates_sync ;;
        --async) check_for_updates_async ;;
        --show) show_cached_notification ;;
        --current) get_current_version ;;
        --latest) get_latest_version ;;
        *)
            echo "Version Checker - Auto-update detection"
            echo ""
            echo "Usage: version-checker.sh [command]"
            echo ""
            echo "Commands:"
            echo "  --check     Check for updates now"
            echo "  --async     Check in background"
            echo "  --show      Show cached notification"
            echo "  --current   Print current version"
            echo "  --latest    Print latest version"
            echo ""
            echo "Current: $(get_current_version)"
            echo "Cache: $CACHE_FILE"
            ;;
    esac
fi

