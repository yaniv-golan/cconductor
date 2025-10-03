#!/bin/bash
# Test: Simple research query

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Simple Query ==="

# Test question
QUESTION="What is the time complexity of Python's dict lookup?"

echo "Question: $QUESTION"

# Run research
"$PROJECT_ROOT/src/research.sh" "$QUESTION"

# Check outputs exist
SESSION_DIR=$(ls -td "$PROJECT_ROOT/research-sessions"/* | head -1)

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
