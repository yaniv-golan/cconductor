#!/usr/bin/env bash
# Test: Mission report path handling regression coverage

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4.0 or higher is required to run this test." >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export CCONDUCTOR_MISSION_SCRIPT_DIR="$PROJECT_ROOT/src/utils"
# shellcheck source=../src/utils/mission-orchestration.sh disable=SC1091
source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"

PASS_COUNT=0

assert_success() {
    local message="$1"
    echo "✓ $message"
    PASS_COUNT=$((PASS_COUNT + 1))
}

assert_failure() {
    local message="$1"
    echo "✗ $message" >&2
    exit 1
}

tmp_dir() {
    mktemp -d "${TMPDIR:-/tmp}/mission-report-test.XXXXXX"
}

# Case 1: New path already created by synthesis-agent
session_new=$(tmp_dir)
trap 'rm -rf "$session_new" "$session_legacy" "$session_missing"' EXIT
mkdir -p "$session_new/report"
echo "# Sample Report" > "$session_new/report/mission-report.md"

if validate_synthesis_outputs "$session_new" "synthesis-agent" >/dev/null 2>&1; then
    assert_success "validate_synthesis_outputs accepts report/mission-report.md"
else
    assert_failure "validate_synthesis_outputs rejected valid report/mission-report.md"
fi

if [ -f "$session_new/report/mission-report.md" ]; then
    assert_success "report/mission-report.md exists for new session"
else
    assert_failure "report/mission-report.md missing after successful validation"
fi

# Case 2: Legacy path should be rejected
session_legacy=$(tmp_dir)
echo "# Legacy Report" > "$session_legacy/mission-report.md"

if validate_synthesis_outputs "$session_legacy" "synthesis-agent" >/dev/null 2>&1; then
    assert_failure "validate_synthesis_outputs unexpectedly accepted legacy mission-report.md"
else
    assert_success "validate_synthesis_outputs rejects legacy mission-report.md"
fi

if [ ! -f "$session_legacy/report/mission-report.md" ]; then
    assert_success "No final report created when only legacy file exists"
else
    assert_failure "Legacy validation created unexpected report/mission-report.md"
fi

# Case 3: Missing report should fail validation and return empty relative path
session_missing=$(tmp_dir)
if validate_synthesis_outputs "$session_missing" "synthesis-agent" >/dev/null 2>&1; then
    assert_failure "validate_synthesis_outputs unexpectedly succeeded without report"
else
    assert_success "validate_synthesis_outputs fails when report is missing"
fi

if [ ! -f "$session_missing/report/mission-report.md" ]; then
    assert_success "No final report present when validation fails"
else
    assert_failure "Unexpected report/mission-report.md created for missing report"
fi

echo ""
echo "Mission report path regression checks passed ($PASS_COUNT assertions)."
