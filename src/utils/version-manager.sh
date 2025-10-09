#!/usr/bin/env bash
# Version Manager - Unified version operations
# Combines version checking, comparison, and update detection
# Replaces: version-check.sh + version-checker.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration for update checking
REPO="yaniv-golan/cconductor"
CACHE_TTL_SECONDS=86400  # 24 hours

# Source dependencies
if [ -f "$PROJECT_ROOT/src/utils/platform-paths.sh" ]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/src/utils/platform-paths.sh"
    CACHE_FILE="$(get_data_dir)/version-check.cache"
else
    # Fallback
    CACHE_FILE="$HOME/.local/share/cconductor/version-check.cache"
fi

# Source config loader
if [ -f "$SCRIPT_DIR/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/config-loader.sh"
fi

# ═══════════════════════════════════════════════════════════════════
# SECTION 1: VERSION PARSING & COMPARISON
# ═══════════════════════════════════════════════════════════════════

# Parse semantic version into components
# Usage: parse_version "1.2.3-alpha"
# Returns: JSON with major, minor, patch, prerelease
parse_version() {
    local version="$1"

    # Remove 'v' prefix if present
    version="${version#v}"

    # Split on dash for prerelease
    local version_core="${version%%-*}"
    local prerelease=""
    if [[ "$version" == *"-"* ]]; then
        prerelease="${version#*-}"
    fi

    # Split version core into major.minor.patch
    local major minor patch
    IFS='.' read -r major minor patch <<< "$version_core"

    # Default missing components to 0
    major="${major:-0}"
    minor="${minor:-0}"
    patch="${patch:-0}"

    # Return as JSON
    jq -n \
        --arg major "$major" \
        --arg minor "$minor" \
        --arg patch "$patch" \
        --arg prerelease "$prerelease" \
        '{
            major: ($major | tonumber),
            minor: ($minor | tonumber),
            patch: ($patch | tonumber),
            prerelease: $prerelease
        }'
}

# Compare two versions
# Usage: compare_versions "1.2.3" "1.3.0"
# Returns: -1 (v1 < v2), 0 (v1 == v2), 1 (v1 > v2)
compare_versions() {
    local v1="$1"
    local v2="$2"

    local parsed1
    parsed1=$(parse_version "$v1")
    local parsed2
    parsed2=$(parse_version "$v2")

    local major1
    major1=$(echo "$parsed1" | jq -r '.major')
    local minor1
    minor1=$(echo "$parsed1" | jq -r '.minor')
    local patch1
    patch1=$(echo "$parsed1" | jq -r '.patch')

    local major2
    major2=$(echo "$parsed2" | jq -r '.major')
    local minor2
    minor2=$(echo "$parsed2" | jq -r '.minor')
    local patch2
    patch2=$(echo "$parsed2" | jq -r '.patch')

    # Compare major
    if [ "$major1" -lt "$major2" ]; then
        echo "-1"
        return 0
    elif [ "$major1" -gt "$major2" ]; then
        echo "1"
        return 0
    fi

    # Major equal, compare minor
    if [ "$minor1" -lt "$minor2" ]; then
        echo "-1"
        return 0
    elif [ "$minor1" -gt "$minor2" ]; then
        echo "1"
        return 0
    fi

    # Minor equal, compare patch
    if [ "$patch1" -lt "$patch2" ]; then
        echo "-1"
        return 0
    elif [ "$patch1" -gt "$patch2" ]; then
        echo "1"
        return 0
    fi

    # All equal
    echo "0"
}

# Check if two versions are compatible
# Usage: is_compatible "1.2.3" "1.5.0"
# Returns: 0 if compatible (same major version), 1 if not
is_compatible() {
    local v1="$1"
    local v2="$2"

    local parsed1
    parsed1=$(parse_version "$v1")
    local parsed2
    parsed2=$(parse_version "$v2")

    local major1
    major1=$(echo "$parsed1" | jq -r '.major')
    local major2
    major2=$(echo "$parsed2" | jq -r '.major')

    if [ "$major1" -eq "$major2" ]; then
        return 0
    else
        return 1
    fi
}

# Get current engine version
# Usage: get_engine_version
# Returns: Version string from VERSION file
get_engine_version() {
    local version_file="$PROJECT_ROOT/VERSION"

    if [ ! -f "$version_file" ]; then
        echo "Error: VERSION file not found: $version_file" >&2
        return 1
    fi

    local version
    version=$(head -n1 "$version_file" | tr -d '[:space:]')

    if [ -z "$version" ]; then
        echo "Error: VERSION file is empty" >&2
        return 1
    fi

    echo "$version"
}

# Get session version from metadata
# Usage: get_session_version "session_dir"
# Returns: Version string from session metadata
get_session_version() {
    local session_dir="$1"
    local metadata_file="$session_dir/session.json"

    if [ ! -f "$metadata_file" ]; then
        echo "Error: Session metadata not found: $metadata_file" >&2
        return 1
    fi

    local version
    version=$(jq -r '.engine_version // "unknown"' "$metadata_file")

    if [ "$version" = "unknown" ]; then
        echo "Error: Session has no engine version in metadata" >&2
        return 1
    fi

    echo "$version"
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 2: SESSION COMPATIBILITY
# ═══════════════════════════════════════════════════════════════════

# Validate session compatibility with current engine
# Usage: validate_session_compatibility "session_dir"
# Returns: 0 if compatible, 1 if not
validate_session_compatibility() {
    local session_dir="$1"

    local engine_version
    engine_version=$(get_engine_version)
    local session_version
    session_version=$(get_session_version "$session_dir") || return 1

    if is_compatible "$engine_version" "$session_version"; then
        return 0
    else
        echo "Error: Session incompatible with current engine" >&2
        echo "" >&2
        echo "  Session version:  $session_version" >&2
        echo "  Engine version:   $engine_version" >&2
        echo "" >&2

        local comparison
        comparison=$(compare_versions "$engine_version" "$session_version")

        if [ "$comparison" = "1" ]; then
            # Engine is newer
            echo "This session was created with an older version." >&2
        else
            # Session is newer
            echo "This session was created with a newer version." >&2
            echo "Please upgrade the research engine to continue using this session." >&2
        fi

        echo "" >&2
        return 1
    fi
}

# Check if session needs migration
# Usage: needs_migration "session_dir"
# Returns: 0 if migration needed, 1 if not
needs_migration() {
    local session_dir="$1"

    local engine_version
    engine_version=$(get_engine_version)
    local session_version
    session_version=$(get_session_version "$session_dir") || return 1

    # If versions are compatible but engine is newer, migration may be beneficial
    if is_compatible "$engine_version" "$session_version"; then
        local comparison
        comparison=$(compare_versions "$engine_version" "$session_version")
        if [ "$comparison" = "1" ]; then
            # Engine is newer, migration possible
            return 0
        fi
    fi

    return 1
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 3: UPDATE CHECKING (GitHub)
# ═══════════════════════════════════════════════════════════════════

# Get latest version from GitHub (with timeout)
get_latest_version() {
    local api_url="https://api.github.com/repos/${REPO}/releases/latest"
    
    # Try API first (2 second timeout)
    local latest
    latest=$(curl -s -m 2 "$api_url" 2>/dev/null | \
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

# Check if we should check for updates
should_check_for_updates() {
    # Check if disabled in config
    if command -v load_config &>/dev/null; then
        if CCONDUCTOR_CONFIG=$(load_config "cconductor-config" 2>/dev/null); then
            local enabled
            enabled=$(echo "$CCONDUCTOR_CONFIG" | jq -r '.update_settings.check_for_updates // true')
            [ "$enabled" != "true" ] && return 1
        fi
    fi
    
    # Check cache age
    if [ -f "$CACHE_FILE" ]; then
        local last_check
        last_check=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local age
        age=$((now - last_check))
        
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
        echo "   Run 'cconductor --update' to upgrade"
        echo ""
        return
    fi
    
    # Full notification
    echo ""
    echo "╭────────────────────────────────────────────────────╮"
    printf "│ 🆕 Update Available: v%-8s → v%-8s       │\n" "$current" "$latest"
    echo "│                                                    │"
    echo "│ Update now:                                        │"
    echo "│   cconductor --update                              │"
    echo "│                                                    │"
    echo "│ Release notes:                                     │"
    echo "│   https://github.com/${REPO}/releases/latest      │"
    echo "╰────────────────────────────────────────────────────╯"
    echo ""
}

# Check for updates (async, non-blocking)
check_for_updates_async() {
    should_check_for_updates || return 0
    
    # Fork to background
    (
        current=$(get_engine_version)
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
    local current
    current=$(get_engine_version)
    local latest
    latest=$(get_latest_version)
    
    if [ -z "$latest" ] || [ "$latest" = "unknown" ]; then
        echo "Unable to check for updates (offline or API unavailable)"
        return 1
    fi
    
    echo "Current version: v${current}"
    echo "Latest version:  v${latest}"
    
    local comparison
    comparison=$(compare_versions "$current" "$latest")
    if [ "$comparison" = "-1" ]; then
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
    
    local update_available
    update_available=$(jq -r '.update_available // false' "$CACHE_FILE" 2>/dev/null)
    
    if [ "$update_available" = "true" ]; then
        local current
        current=$(jq -r '.current_version // "unknown"' "$CACHE_FILE")
        local latest
        latest=$(jq -r '.latest_version // "unknown"' "$CACHE_FILE")
        local style="full"
        
        # Get notification style from config
        if command -v load_config &>/dev/null; then
            if CCONDUCTOR_CONFIG=$(load_config "cconductor-config" 2>/dev/null); then
                style=$(echo "$CCONDUCTOR_CONFIG" | jq -r '.update_settings.update_notification_style // "full"')
            fi
        fi
        
        show_update_notification "$current" "$latest" "$style"
        return 0
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════════════════════
# SECTION 4: REPORTING
# ═══════════════════════════════════════════════════════════════════

# Get version compatibility report
# Usage: version_report "session_dir"
# Prints: Human-readable compatibility report
version_report() {
    local session_dir="$1"

    echo "Version Compatibility Report"
    echo "══════════════════════════════════════════════════"
    echo ""

    local engine_version
    engine_version=$(get_engine_version)
    echo "Engine version:  $engine_version"

    if [ -z "$session_dir" ] || [ "$session_dir" = "-" ]; then
        echo ""
        echo "No session specified. Engine version information only."
        return 0
    fi

    local session_version
    if ! session_version=$(get_session_version "$session_dir" 2>/dev/null); then
        echo "Session version: (unknown - metadata missing)"
        echo ""
        echo "Status: ⚠️  Cannot determine compatibility"
        return 1
    fi

    echo "Session version: $session_version"
    echo ""

    if is_compatible "$engine_version" "$session_version"; then
        echo "Status: ✓ Compatible"

        local comparison
        comparison=$(compare_versions "$engine_version" "$session_version")
        if [ "$comparison" = "1" ]; then
            echo ""
            echo "Note: Engine is newer than session."
        elif [ "$comparison" = "-1" ]; then
            echo ""
            echo "Note: Session is newer than engine."
            echo "      This is unusual but compatible (same major version)."
        else
            echo ""
            echo "Note: Versions are identical."
        fi
    else
        echo "Status: ✗ Incompatible"
        echo ""

        local comparison
        comparison=$(compare_versions "$engine_version" "$session_version")
        if [ "$comparison" = "1" ]; then
            echo "Issue: Session created with older major version"
        else
            echo "Issue: Session created with newer major version"
            echo ""
            echo "Recommendation: Upgrade research engine to match session version"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════
# EXPORT FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

export -f parse_version
export -f compare_versions
export -f is_compatible
export -f get_engine_version
export -f get_session_version
export -f validate_session_compatibility
export -f needs_migration
export -f get_latest_version
export -f check_for_updates_async
export -f check_for_updates_sync
export -f show_cached_notification
export -f version_report

# ═══════════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════════

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        parse)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 parse <version>" >&2
                exit 1
            fi
            parse_version "$2"
            ;;
        compare)
            if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
                echo "Usage: $0 compare <version1> <version2>" >&2
                exit 1
            fi
            result=$(compare_versions "$2" "$3")
            case "$result" in
                -1) echo "$2 < $3" ;;
                0)  echo "$2 == $3" ;;
                1)  echo "$2 > $3" ;;
            esac
            ;;
        compatible)
            if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
                echo "Usage: $0 compatible <version1> <version2>" >&2
                exit 1
            fi
            if is_compatible "$2" "$3"; then
                echo "✓ Compatible (same major version)"
                exit 0
            else
                echo "✗ Incompatible (different major versions)"
                exit 1
            fi
            ;;
        engine|current)
            get_engine_version
            ;;
        session)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 session <session_dir>" >&2
                exit 1
            fi
            get_session_version "$2"
            ;;
        validate)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 validate <session_dir>" >&2
                exit 1
            fi
            if validate_session_compatibility "$2"; then
                echo "✓ Session is compatible with current engine"
                exit 0
            else
                exit 1
            fi
            ;;
        report)
            version_report "${2:-}"
            ;;
        check-updates|check)
            check_for_updates_sync
            ;;
        latest)
            get_latest_version
            ;;
        show-notification)
            show_cached_notification
            ;;
        help|--help|-h)
            cat <<EOF
Version Manager - Unified version operations
Combines version checking, compatibility validation, and update detection

USAGE:
  $0 <command> [args]

VERSION PARSING:
  parse <version>           Parse version into JSON components
  compare <v1> <v2>         Compare two versions (-1, 0, or 1)
  compatible <v1> <v2>      Check if versions are compatible

VERSION INFO:
  engine, current           Show current engine version
  latest                    Show latest GitHub release version
  session <dir>             Show session version

SESSION COMPATIBILITY:
  validate <dir>            Validate session compatibility
  report [dir]              Full compatibility report

UPDATE CHECKING:
  check-updates, check      Check for updates (synchronous)
  show-notification         Show cached update notification

HELP:
  help                      Show this help

EXAMPLES:
  # Parse version
  $0 parse "1.2.3-alpha"

  # Compare versions
  $0 compare "1.2.3" "1.3.0"
  # Output: 1.2.3 < 1.3.0

  # Check compatibility
  $0 compatible "1.2.3" "1.5.0"
  # Output: ✓ Compatible (same major version)

  # Show current version
  $0 engine
  # Output: 0.2.0

  # Check for updates
  $0 check-updates
  # Output: Current version: v0.2.0
  #         Latest version:  v0.2.1
  #         ✅ Update available!

  # Validate session
  $0 validate research-sessions/my-session
  # Output: ✓ Session is compatible with current engine

  # Get full report
  $0 report research-sessions/my-session

COMPATIBILITY RULES:
  • Same major version = Compatible (1.x.x works with 1.y.z)
  • Different major version = Incompatible (1.x.x does NOT work with 2.y.z)
  • Newer engine with old session = Usually works (forward compatible)
  • Older engine with new session = May not work (not backward compatible)

UPDATE CHECKING:
  • Checks GitHub for new releases
  • Caches results for 24 hours
  • Can be disabled in config
  • Runs asynchronously to avoid blocking

EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi


