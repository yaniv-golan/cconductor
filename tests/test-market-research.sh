#!/usr/bin/env bash
# Test: Market sizing and competitive analysis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Market Research ==="

# Market research question
QUESTION="What is the TAM for AI-powered customer service tools, and who are the major competitors?"

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

if [ -f "$SESSION_DIR/final/mission-report.md" ]; then
    echo "✓ Market research memo generated"

    # Check for TAM/SAM/SOM
    if grep -q "TAM\|SAM\|SOM\|Total Addressable Market" "$SESSION_DIR/final/mission-report.md"; then
        echo "✓ Market sizing included"
    else
        echo "⚠ Market sizing may be missing"
    fi

    # Check for competitive analysis
    if grep -q "competitors\|Competitive\|market share" "$SESSION_DIR/final/mission-report.md"; then
        echo "✓ Competitive analysis present"
    else
        echo "⚠ Competitive analysis may be missing"
    fi

    # Check for financial data
    if grep -q "funding\|revenue\|valuation\|ARR\|growth" "$SESSION_DIR/final/mission-report.md"; then
        echo "✓ Financial metrics included"
    fi

    # Check for market sources
    if grep -q "Crunchbase\|market report\|Gartner\|Forrester" "$SESSION_DIR/final/mission-report.md"; then
        echo "✓ Market research sources cited"
    fi

    # Check for data quality notes
    if grep -q "disclosed\|estimated\|methodology" "$SESSION_DIR/final/mission-report.md"; then
        echo "✓ Data quality noted"
    fi
else
    echo "✗ Report not found"
    exit 1
fi

echo "=== Test Complete ==="
