#!/bin/bash
# Test: Scientific research query with academic sources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Scientific Research ==="

# Scientific question requiring academic sources
QUESTION="What is the current state of research on quantum error correction in topological qubits?"

echo "Question: $QUESTION"

# Run research (mode detection is automatic based on question)
"$PROJECT_ROOT/cconductor" "$QUESTION"

# Validation
# Get session directory using path resolver
SESSION_DIR_BASE=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve session_dir)
SESSION_DIR=$(find "$SESSION_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -td 2>/dev/null | head -1)

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
