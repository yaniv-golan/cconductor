#!/usr/bin/env bash
# Test: Scientific research query with academic sources

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Scientific Research ==="

# Scientific question requiring academic sources
QUESTION="What is the current state of research on quantum error correction in topological qubits?"

echo "Question: $QUESTION"

CCONDUCTOR_BIN="$PROJECT_ROOT/cconductor"
if [ -x "$PROJECT_ROOT/scripts/dev_cconductor.sh" ]; then
    CCONDUCTOR_BIN="$PROJECT_ROOT/scripts/dev_cconductor.sh"
fi

# Run research (mode detection is automatic based on question)
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
    echo "✓ Scientific research report generated"

    # Check for academic sources
    if grep -q "arXiv\|Google Scholar\|pubmed\|ieee" "$SESSION_DIR/output/mission-report.md"; then
        echo "✓ Report contains academic sources"
    else
        echo "⚠ Few academic sources found"
    fi

    # Check for methodology discussion
    if grep -q "Methodology\|methodology\|experimental\|statistical" "$SESSION_DIR/output/mission-report.md"; then
        echo "✓ Methodology assessment present"
    else
        echo "⚠ Methodology assessment may be missing"
    fi

    # Check for peer review mentions
    if grep -q "peer.review\|journal\|conference" "$SESSION_DIR/output/mission-report.md"; then
        echo "✓ Peer review status discussed"
    fi

    # Check for citation network
    if grep -q "Citation\|citation\|References" "$SESSION_DIR/output/mission-report.md"; then
        echo "✓ Citations included"
    fi
else
    echo "✗ Report not found"
    exit 1
fi

echo "=== Test Complete ==="
