#!/usr/bin/env bash
# Test: Simple research query

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

require_command python3 "brew install python3" "apt install python3" || exit 1

echo "=== Testing Simple Query ==="

# Test question
QUESTION="What is the time complexity of Python's dict lookup?"

echo "Question: $QUESTION"

CCONDUCTOR_BIN="$PROJECT_ROOT/cconductor"
if [ -x "$PROJECT_ROOT/scripts/dev_cconductor.sh" ]; then
    CCONDUCTOR_BIN="$PROJECT_ROOT/scripts/dev_cconductor.sh"
fi

# Run research
"$CCONDUCTOR_BIN" "$QUESTION"

# Check outputs exist
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

REPORT_PATH=""
if [ -f "$SESSION_DIR/report/mission-report.md" ]; then
    REPORT_PATH="$SESSION_DIR/report/mission-report.md"
elif [ -f "$SESSION_DIR/final/mission-report.md" ]; then
    REPORT_PATH="$SESSION_DIR/final/mission-report.md"
elif [ -f "$SESSION_DIR/70_report/mission-report.md" ]; then
    REPORT_PATH="$SESSION_DIR/70_report/mission-report.md"
fi

if [ -z "$REPORT_PATH" ]; then
    echo "✗ Report not found in expected locations"
    exit 1
fi

echo "✓ Report generated successfully ($REPORT_PATH)"

# Basic validation
if grep -q "Executive Summary" "$REPORT_PATH"; then
    echo "✓ Report contains executive summary"
fi

if grep -q "Sources" "$REPORT_PATH"; then
    echo "✓ Report contains sources"
fi

echo "=== Test Complete ==="
