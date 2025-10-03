#!/bin/bash
# Test: Market sizing and competitive analysis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Market Research ==="

# Market research question
QUESTION="What is the TAM for AI-powered customer service tools, and who are the major competitors?"

echo "Question: $QUESTION"

# Run research (mode detection is automatic based on question)
"$PROJECT_ROOT/delve" "$QUESTION"

# Validation
# Get session directory using path resolver
SESSION_DIR_BASE=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve session_dir)
SESSION_DIR=$(find "$SESSION_DIR_BASE" -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 ls -td 2>/dev/null | head -1)

if [ -f "$SESSION_DIR/research-report.md" ]; then
    echo "✓ Market research memo generated"

    # Check for TAM/SAM/SOM
    if grep -q "TAM\|SAM\|SOM\|Total Addressable Market" "$SESSION_DIR/research-report.md"; then
        echo "✓ Market sizing included"
    else
        echo "⚠ Market sizing may be missing"
    fi

    # Check for competitive analysis
    if grep -q "competitors\|Competitive\|market share" "$SESSION_DIR/research-report.md"; then
        echo "✓ Competitive analysis present"
    else
        echo "⚠ Competitive analysis may be missing"
    fi

    # Check for financial data
    if grep -q "funding\|revenue\|valuation\|ARR\|growth" "$SESSION_DIR/research-report.md"; then
        echo "✓ Financial metrics included"
    fi

    # Check for market sources
    if grep -q "Crunchbase\|market report\|Gartner\|Forrester" "$SESSION_DIR/research-report.md"; then
        echo "✓ Market research sources cited"
    fi

    # Check for data quality notes
    if grep -q "disclosed\|estimated\|methodology" "$SESSION_DIR/research-report.md"; then
        echo "✓ Data quality noted"
    fi
else
    echo "✗ Report not found"
    exit 1
fi

echo "=== Test Complete ==="
