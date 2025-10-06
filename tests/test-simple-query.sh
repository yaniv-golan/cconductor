#!/usr/bin/env bash
# Test: Simple research query

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Simple Query ==="

# Test question
QUESTION="What is the time complexity of Python's dict lookup?"

echo "Question: $QUESTION"

# Run research
"$PROJECT_ROOT/cconductor" "$QUESTION"

# Check outputs exist
# Get session directory using path resolver
SESSION_DIR_BASE=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve session_dir)
SESSION_DIR=$(find "$SESSION_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -td 2>/dev/null | head -1)

if [ -f "$SESSION_DIR/research-report.md" ]; then
    echo "✓ Report generated successfully"

    # Basic validation
    if grep -q "Executive Summary" "$SESSION_DIR/research-report.md"; then
        echo "✓ Report contains executive summary"
    fi

    if grep -q "Sources" "$SESSION_DIR/research-report.md"; then
        echo "✓ Report contains sources"
    fi
else
    echo "✗ Report not found"
    exit 1
fi

echo "=== Test Complete ==="
