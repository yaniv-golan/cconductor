#!/bin/bash
# Test: Scientific research query with academic sources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Scientific Research ==="

# Scientific question requiring academic sources
QUESTION="What is the current state of research on quantum error correction in topological qubits?"

echo "Question: $QUESTION"

# Run research in scientific mode
"$PROJECT_ROOT/src/research.sh" --mode scientific --template scientific-report "$QUESTION"

# Validation
SESSION_DIR=$(find "$PROJECT_ROOT/research-sessions" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -td 2>/dev/null | head -1)

if [ -f "$SESSION_DIR/research-report.md" ]; then
    echo "✓ Scientific research report generated"

    # Check for academic sources
    if grep -q "arXiv\|Google Scholar\|pubmed\|ieee" "$SESSION_DIR/research-report.md"; then
        echo "✓ Report contains academic sources"
    else
        echo "⚠ Few academic sources found"
    fi

    # Check for methodology discussion
    if grep -q "Methodology\|methodology\|experimental\|statistical" "$SESSION_DIR/research-report.md"; then
        echo "✓ Methodology assessment present"
    else
        echo "⚠ Methodology assessment may be missing"
    fi

    # Check for peer review mentions
    if grep -q "peer.review\|journal\|conference" "$SESSION_DIR/research-report.md"; then
        echo "✓ Peer review status discussed"
    fi

    # Check for citation network
    if grep -q "Citation\|citation\|References" "$SESSION_DIR/research-report.md"; then
        echo "✓ Citations included"
    fi
else
    echo "✗ Report not found"
    exit 1
fi

echo "=== Test Complete ==="
