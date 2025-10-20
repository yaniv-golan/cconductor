#!/usr/bin/env bash
# Run all integration tests

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        PATH="/opt/homebrew/bin:$PATH"
        export PATH
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        PATH="/usr/local/bin:$PATH"
        export PATH
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4.0 or higher is required to run the test suite." >&2
        exit 1
    fi
fi

set -euo pipefail

if [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
    PATH="/opt/homebrew/bin:$PATH"
    export PATH
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "  Deep Research Engine - Test Suite"
echo "========================================"
echo ""

TESTS=(
    "test-simple-query.sh"
    "test-complex-query.sh"
    "test-parallel-execution.sh"
    "test-scientific-research.sh"
    "test-market-research.sh"
    "test-web-cache.sh"
    "test-web-search-cache.sh"
    "test-pdf-cache-phase1.sh"
)

PASSED=0
FAILED=0

for test in "${TESTS[@]}"; do
    echo ""
    echo "Running: $test"
    echo "----------------------------------------"

    if "$SCRIPT_DIR/$test"; then
        ((PASSED++))
        echo "✓ $test passed"
    else
        ((FAILED++))
        echo "✗ $test failed"
    fi
    echo "----------------------------------------"
done

echo ""
echo "========================================"
echo "  Test Results"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
