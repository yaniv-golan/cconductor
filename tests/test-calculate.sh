#!/usr/bin/env bash
# Unit Tests for calculate.sh
# Tests safe calculation utility functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALCULATE="$PROJECT_ROOT/src/utils/calculate.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test result tracking
pass_test() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} $1"
}

fail_test() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} $1"
    if [[ -n "${2:-}" ]]; then
        echo "  Expected: $2"
    fi
    if [[ -n "${3:-}" ]]; then
        echo "  Got: $3"
    fi
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Helper: Compare floating point numbers with tolerance
float_equals() {
    local val1="$1"
    local val2="$2"
    local tolerance="${3:-0.01}"
    
    # Use awk for floating point comparison
    awk -v v1="$val1" -v v2="$val2" -v tol="$tolerance" \
        'BEGIN { diff = (v1 - v2); if (diff < 0) diff = -diff; exit !(diff <= tol) }'
}

# Test 1: Basic calculation
test_basic_calc() {
    run_test
    
    local output
    output=$("$CALCULATE" calc "2 + 2")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "basic-calc: invalid JSON output" "valid JSON" "$output"
        return
    fi
    
    # Check result
    local result
    result=$(echo "$output" | jq -r '.result')
    
    if [[ "$result" == "4" ]]; then
        pass_test "basic-calc: 2 + 2 = 4"
    else
        fail_test "basic-calc: incorrect result" "4" "$result"
    fi
}

# Test 2: Multiplication
test_multiplication() {
    run_test
    
    local output
    output=$("$CALCULATE" calc "500000000 * 50")
    
    # Check result
    local result
    result=$(echo "$output" | jq -r '.result')
    
    if [[ "$result" == "25000000000" ]]; then
        pass_test "multiplication: handles large numbers"
    else
        fail_test "multiplication: incorrect result" "25000000000" "$result"
    fi
}

# Test 3: Division with precision
test_division() {
    run_test
    
    local output
    output=$("$CALCULATE" calc "10 / 3")
    
    # Check result (should have precision)
    local result
    result=$(echo "$output" | jq -r '.result')
    
    # Result should be close to 3.333333...
    if float_equals "$result" "3.333333" 0.001; then
        pass_test "division: handles precision correctly"
    else
        fail_test "division: incorrect precision" "~3.333333" "$result"
    fi
}

# Test 4: Calculate percentage
test_percentage() {
    run_test
    
    local output
    output=$("$CALCULATE" percentage 5000000 50000000)
    
    # Check result
    local result
    result=$(echo "$output" | jq -r '.percentage')
    
    if [[ "$result" == "10.00" ]] || [[ "$result" == "10" ]]; then
        pass_test "percentage: 5M/50M = 10%"
    else
        fail_test "percentage: incorrect result" "10.00" "$result"
    fi
}

# Test 5: Calculate growth rate
test_growth_rate() {
    run_test
    
    local output
    output=$("$CALCULATE" growth 10000000 15000000 2>&1)
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "growth-rate: invalid JSON output" "valid JSON" "$output"
        return
    fi
    
    # Check result
    local growth
    growth=$(echo "$output" | jq -r '.growth_rate')
    local multiplier
    multiplier=$(echo "$output" | jq -r '.multiplier')
    
    if [[ "$growth" == "50.00" ]] && [[ "$multiplier" == "1.50" ]]; then
        pass_test "growth-rate: 10M→15M = 50% growth, 1.5x"
    else
        fail_test "growth-rate: incorrect result" "50.00, 1.50" "$growth, $multiplier"
    fi
}

# Test 6: Calculate CAGR
test_cagr() {
    run_test
    
    local output
    output=$("$CALCULATE" cagr 1000000 10000000 5)
    
    # Check result (should be ~58.49%)
    local cagr
    cagr=$(echo "$output" | jq -r '.cagr')
    
    if float_equals "$cagr" "58.49" 0.1; then
        pass_test "cagr: 1M→10M over 5 years = ~58.49%"
    else
        fail_test "cagr: incorrect result" "~58.49" "$cagr"
    fi
}

# Test 7: Invalid expression
test_invalid_expression() {
    run_test
    
    local output
    output=$("$CALCULATE" calc "rm -rf /" 2>&1) || true
    
    # Should return error JSON
    if echo "$output" | jq -e '.error' > /dev/null 2>&1; then
        pass_test "invalid-expression: rejects dangerous input"
    else
        fail_test "invalid-expression: doesn't validate input" "error field" "$output"
    fi
}

# Test 8: Division by zero (percentage)
test_division_by_zero() {
    run_test
    
    local output
    output=$("$CALCULATE" percentage 100 0 2>&1) || true
    
    # Should return error
    if echo "$output" | jq -e '.error' > /dev/null 2>&1; then
        pass_test "division-by-zero: handles error gracefully"
    else
        fail_test "division-by-zero: doesn't handle error" "error field" "$output"
    fi
}

# Test 9: Invalid input (non-numbers)
test_invalid_input() {
    run_test
    
    local output
    output=$("$CALCULATE" percentage "abc" 100 2>&1) || true
    
    # Should return error
    if echo "$output" | jq -e '.error' > /dev/null 2>&1; then
        pass_test "invalid-input: validates input types"
    else
        fail_test "invalid-input: doesn't validate types" "error field" "$output"
    fi
}

# Test 10: Negative numbers
test_negative_numbers() {
    run_test
    
    local output
    output=$("$CALCULATE" calc "-10 + 5")
    
    # Check result
    local result
    result=$(echo "$output" | jq -r '.result')
    
    if [[ "$result" == "-5" ]]; then
        pass_test "negative-numbers: handles negative numbers"
    else
        fail_test "negative-numbers: incorrect result" "-5" "$result"
    fi
}

# Run all tests
echo "=========================================="
echo "Testing calculate.sh"
echo "=========================================="
echo ""

test_basic_calc
test_multiplication
test_division
test_percentage
test_growth_rate
test_cagr
test_invalid_expression
test_division_by_zero
test_invalid_input
test_negative_numbers

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    exit 1
else
    echo -e "Tests failed: $TESTS_FAILED"
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi

