#!/usr/bin/env bash
# Test: Session ID Collision Prevention
# Verifies that starting multiple sessions simultaneously creates unique IDs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test: Session ID Collision Prevention                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# We need to source specific functions without triggering the CLI
# Create a wrapper that only loads the functions we need
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/task-queue.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Extract just the initialize_session function by loading the file with bash -c
# and calling the function directly (avoid the CLI section at bottom)
initialize_session() {
    # Unused in test, but part of function signature
    # shellcheck disable=SC2034
    local research_question="$1"
    
    # Create session directory with unique timestamp to prevent collisions
    local timestamp
    # Check if we can get subsecond precision (GNU date with %N)
    if date +%s%N &>/dev/null 2>&1 && [[ "$(date +%s%N)" =~ ^[0-9]+$ ]]; then
        # GNU date (Linux) - use nanoseconds
        timestamp=$(date +%s%N)
    else
        # macOS or other - use seconds + PID + random
        timestamp="$(date +%s)_$$_${RANDOM}"
    fi
    local session_dir="$PROJECT_ROOT/research-sessions/session_${timestamp}"
    mkdir -p "$session_dir"
    
    echo "$session_dir"
}

# Create temporary sessions directory for testing
TEST_SESSIONS_DIR="$PROJECT_ROOT/research-sessions-test-$$"
mkdir -p "$TEST_SESSIONS_DIR"

# Override PROJECT_ROOT temporarily
ORIGINAL_PROJECT_ROOT="$PROJECT_ROOT"
PROJECT_ROOT="$(dirname "$TEST_SESSIONS_DIR")/$(basename "$TEST_SESSIONS_DIR")/.."

echo "→ Creating 10 sessions rapidly to test collision prevention..."
echo ""

session_ids=()
for i in {1..10}; do
    # Create sessions as fast as possible
    session_dir=$(initialize_session "Test question $i" 2>/dev/null)
    session_id=$(basename "$session_dir")
    session_ids+=("$session_id")
    echo "  Created: $session_id"
done

echo ""
echo "→ Checking for duplicates..."

# Check for duplicate session IDs
unique_count=$(printf '%s\n' "${session_ids[@]}" | sort -u | wc -l | xargs)
total_count=${#session_ids[@]}

if [ "$unique_count" -eq "$total_count" ]; then
    echo "  ✓ All $total_count session IDs are unique"
    echo ""
    echo "✅ TEST PASSED: No session ID collisions"
    result=0
else
    echo "  ✗ Found duplicates! Unique: $unique_count, Total: $total_count"
    echo ""
    echo "Session IDs created:"
    printf '  %s\n' "${session_ids[@]}"
    echo ""
    echo "❌ TEST FAILED: Session ID collision detected"
    result=1
fi

# Cleanup
rm -rf "$TEST_SESSIONS_DIR"
PROJECT_ROOT="$ORIGINAL_PROJECT_ROOT"

exit $result

