#!/bin/bash
# Test: Complex multi-faceted research query

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Complex Query ==="

# Complex question requiring multiple research angles
QUESTION="How does Rust's borrow checker work, and how does it compare to C++'s approach to memory safety?"

echo "Question: $QUESTION"

# Run research
"$PROJECT_ROOT/delve" "$QUESTION"

# Validation
# Get session directory using path resolver
SESSION_DIR_BASE=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve session_dir)
SESSION_DIR=$(find "$SESSION_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -td 2>/dev/null | head -1)

if [ -f "$SESSION_DIR/research-report.md" ]; then
    echo "✓ Complex query handled successfully"

    # Check for depth
    LINE_COUNT=$(wc -l < "$SESSION_DIR/research-report.md")
    if [ "$LINE_COUNT" -gt 100 ]; then
        echo "✓ Report has sufficient depth ($LINE_COUNT lines)"
    else
        echo "⚠ Report may be too short ($LINE_COUNT lines)"
    fi

    # Check for multiple sources
    SOURCE_COUNT=$(grep -c "^\- \[.*\](http" "$SESSION_DIR/research-report.md" || true)
    if [ "$SOURCE_COUNT" -gt 5 ]; then
        echo "✓ Multiple sources cited ($SOURCE_COUNT sources)"
    else
        echo "⚠ Few sources cited ($SOURCE_COUNT sources)"
    fi
fi

echo "=== Test Complete ==="
