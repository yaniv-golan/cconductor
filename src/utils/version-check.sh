#!/bin/bash
# Version Check - Semantic version parsing and compatibility validation
# Ensures session compatibility with current research engine version

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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
        echo "This should never happen - VERSION is required." >&2
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
        echo "This session may be from before version tracking was added." >&2
        return 1
    fi

    echo "$version"
}

# Validate session compatibility with current engine
# Usage: validate_session_compatibility "session_dir"
# Returns: 0 if compatible, 1 if not
validate_session_compatibility() {
    local session_dir="$1"

    local engine_version
    engine_version=$(get_engine_version)
    local session_version
    session_version=$(get_session_version "$session_dir")

    if [ $? -ne 0 ]; then
        return 1
    fi

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
            echo "Consider migrating the session or using the older engine version." >&2
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
    session_version=$(get_session_version "$session_dir")

    if [ $? -ne 0 ]; then
        return 1
    fi

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

# Get version compatibility report
# Usage: version_report "session_dir"
# Prints: Human-readable compatibility report
version_report() {
    local session_dir="$1"

    echo "Version Compatibility Report"
    echo "══════════════════════════════════════════"
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
    session_version=$(get_session_version "$session_dir" 2>/dev/null)

    if [ $? -ne 0 ]; then
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
            echo "      Session may benefit from migration to access new features."
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
            echo ""
            echo "Recommendations:"
            echo "  1. Migrate session to new version (if migration tool available)"
            echo "  2. Use older engine version to continue this session"
            echo "  3. Start new session with current engine"
        else
            echo "Issue: Session created with newer major version"
            echo ""
            echo "Recommendations:"
            echo "  1. Upgrade research engine to match session version"
            echo "  2. Start new session with current engine"
        fi
    fi
}

# Export functions for use in other scripts
export -f parse_version
export -f compare_versions
export -f is_compatible
export -f get_engine_version
export -f get_session_version
export -f validate_session_compatibility
export -f needs_migration
export -f version_report

# CLI interface
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
        engine)
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
        help|--help|-h)
            cat <<EOF
Version Check - Semantic version validation for research sessions

Usage: $0 <command> [args]

Commands:
  parse <version>           Parse version into components (JSON)
  compare <v1> <v2>         Compare two versions (-1, 0, or 1)
  compatible <v1> <v2>      Check if versions are compatible
  engine                    Show current engine version
  session <session_dir>     Show session version
  validate <session_dir>    Validate session compatibility
  report [session_dir]      Full compatibility report
  help                      Show this help

Examples:
  # Parse version
  $0 parse "1.2.3-alpha"

  # Compare versions
  $0 compare "1.2.3" "1.3.0"
  # Output: 1.2.3 < 1.3.0

  # Check compatibility
  $0 compatible "1.2.3" "1.5.0"
  # Output: ✓ Compatible (same major version)

  # Show engine version
  $0 engine
  # Output: 0.1.0-alpha

  # Validate session
  $0 validate research-sessions/my-session
  # Output: ✓ Session is compatible with current engine

  # Get full report
  $0 report research-sessions/my-session

Compatibility Rules:
  - Same major version = Compatible (1.x.x works with 1.y.z)
  - Different major version = Incompatible (1.x.x does NOT work with 2.y.z)
  - Newer engine with old session = Usually works (forward compatible)
  - Older engine with new session = May not work (not backward compatible)

EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
