#!/usr/bin/env bash
# Run all integration tests

set -euo pipefail

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
