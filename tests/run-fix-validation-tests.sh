#!/bin/bash
# Master Test Runner for Bug Fix Validation
# Runs all tests to validate the recent bug fixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║         DELVE BUG FIX VALIDATION TEST SUITE                ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Track results
declare -a test_results
declare -a test_names

run_test() {
    local test_script="$1"
    local test_name="$2"
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Running: $test_name"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    if bash "$test_script"; then
        test_results+=("PASS")
        echo -e "${GREEN}✓ $test_name PASSED${NC}"
    else
        test_results+=("FAIL")
        echo -e "${RED}✗ $test_name FAILED${NC}"
    fi
    
    test_names+=("$test_name")
}

# Run all tests
run_test "$SCRIPT_DIR/test-session-collision.sh" "Session ID Collision Prevention"
run_test "$SCRIPT_DIR/test-id-uniqueness.sh" "ID Uniqueness After Deletions"
run_test "$SCRIPT_DIR/test-lock-timeout.sh" "Lock Timeout Accuracy"
run_test "$SCRIPT_DIR/test-agent-failure.sh" "Agent Failure Task Status Updates"
run_test "$SCRIPT_DIR/test-termination-validation.sh" "Termination Validation"

# Print summary
echo ""
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     TEST SUMMARY                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

passed=0
failed=0

for i in "${!test_names[@]}"; do
    test_name="${test_names[$i]}"
    result="${test_results[$i]}"
    
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((passed++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((failed++))
    fi
done

total=$((passed + failed))

echo ""
echo "────────────────────────────────────────────────────────────"
printf "Total: %d tests | " "$total"
printf "${GREEN}Passed: %d${NC} | " "$passed"
printf "${RED}Failed: %d${NC}\n" "$failed"
echo "────────────────────────────────────────────────────────────"
echo ""

if [ $failed -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}║   ✓✓✓ ALL TESTS PASSED - BUG FIXES VALIDATED ✓✓✓          ║${NC}"
    echo -e "${GREEN}║                                                            ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}║   ✗✗✗ SOME TESTS FAILED - REVIEW NEEDED ✗✗✗                ║${NC}"
    echo -e "${RED}║                                                            ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 1
fi

