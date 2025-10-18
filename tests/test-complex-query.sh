#!/usr/bin/env bash
# Test: Complex multi-faceted research query

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Complex Query ==="

# Complex question requiring multiple research angles
QUESTION="How does Rust's borrow checker work, and how does it compare to C++'s approach to memory safety?"

echo "Question: $QUESTION"

CCONDUCTOR_BIN="$PROJECT_ROOT/cconductor"
if [ -x "$PROJECT_ROOT/scripts/dev_cconductor.sh" ]; then
    CCONDUCTOR_BIN="$PROJECT_ROOT/scripts/dev_cconductor.sh"
fi

# Run research
"$CCONDUCTOR_BIN" "$QUESTION"

# Validation
# Get session directory using path resolver
SESSION_DIR_BASE=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve session_dir 2>/dev/null || echo "")

find_latest_session() {
    local base="$1"
    [ -d "$base" ] || return 1
    python3 - "$base" <<'PY'
import os, sys
base = sys.argv[1]
candidates = []
for entry in os.listdir(base):
    path = os.path.join(base, entry)
    if os.path.isdir(path):
        candidates.append((os.path.getmtime(path), path))
if not candidates:
    sys.exit(1)
candidates.sort(reverse=True)
print(candidates[0][1])
PY
}

SESSION_DIR=""
if [ -n "$SESSION_DIR_BASE" ]; then
    SESSION_DIR=$(find_latest_session "$SESSION_DIR_BASE" 2>/dev/null || echo "")
fi
if [ -z "$SESSION_DIR" ]; then
    SESSION_DIR=$(find_latest_session "$PROJECT_ROOT/research-sessions" 2>/dev/null || echo "")
fi

if [ -z "$SESSION_DIR" ]; then
    echo "✗ Could not locate latest session directory"
    exit 1
fi

if [ -f "$SESSION_DIR/output/mission-report.md" ]; then
    echo "✓ Complex query handled successfully"

    # Check for depth
    LINE_COUNT=$(wc -l < "$SESSION_DIR/output/mission-report.md")
    if [ "$LINE_COUNT" -gt 100 ]; then
        echo "✓ Report has sufficient depth ($LINE_COUNT lines)"
    else
        echo "⚠ Report may be too short ($LINE_COUNT lines)"
    fi

    # Check for multiple sources
    SOURCE_COUNT=$(grep -c "^\- \[.*\](http" "$SESSION_DIR/output/mission-report.md" || true)
    if [ "$SOURCE_COUNT" -gt 5 ]; then
        echo "✓ Multiple sources cited ($SOURCE_COUNT sources)"
    else
        echo "⚠ Few sources cited ($SOURCE_COUNT sources)"
    fi
fi

echo "=== Test Complete ==="
