#!/usr/bin/env bash
# Test CLI Argument Parser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the CLI parser
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/cli-parser.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper
test_case() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $description"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ PASS"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: Expected '$expected', got '$actual' $description"
        return 1
    fi
}

assert_true() {
    local description="$1"
    
    echo "  ✓ PASS: $description"
    return 0
}

assert_false() {
    local description="$1"
    
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: $description"
    return 1
}

# Test 1: Parse --flag value format
test_case "Parse --flag value format"
parse_cli_args --input-dir "/path/to/dir" "research question"
assert_equals "/path/to/dir" "$(get_flag "input-dir")" || exit 1
assert_equals "research question" "$(get_arg 0)" || exit 1

# Test 2: Parse --flag=value format
test_case "Parse --flag=value format"
parse_cli_args --mode=scientific "another question"
assert_equals "scientific" "$(get_flag "mode")" || exit 1
assert_equals "another question" "$(get_arg 0)" || exit 1

# Test 3: Parse boolean flags
test_case "Parse boolean flag (at end)"
parse_cli_args "query" --quiet
assert_equals "true" "$(get_flag "quiet")" || exit 1
assert_equals "query" "$(get_arg 0)" || exit 1

# Test 4: has_flag function
test_case "has_flag returns true for existing flag"
parse_cli_args --input-dir "/path"
if has_flag "input-dir"; then
    assert_true "has_flag detected existing flag"
else
    assert_false "has_flag failed to detect existing flag"
    exit 1
fi

# Test 5: has_flag returns false for non-existing flag
test_case "has_flag returns false for non-existing flag"
parse_cli_args --input-dir "/path"
if ! has_flag "nonexistent"; then
    assert_true "has_flag correctly returned false"
else
    assert_false "has_flag incorrectly detected non-existing flag"
    exit 1
fi

# Test 6: Multiple flags
test_case "Parse multiple flags"
parse_cli_args --input-dir "/path" --mode scientific --output html "query text"
assert_equals "/path" "$(get_flag "input-dir")" || exit 1
assert_equals "scientific" "$(get_flag "mode")" || exit 1
assert_equals "html" "$(get_flag "output")" || exit 1
assert_equals "query text" "$(get_arg 0)" || exit 1

# Test 7: Default values
test_case "get_flag returns default for missing flag"
parse_cli_args "just a query"
assert_equals "default_value" "$(get_flag "missing" "default_value")" || exit 1

# Test 8: Multiple positional arguments
test_case "Parse multiple positional arguments"
parse_cli_args "first" "second" "third"
assert_equals "first" "$(get_arg 0)" || exit 1
assert_equals "second" "$(get_arg 1)" || exit 1
assert_equals "third" "$(get_arg 2)" || exit 1
assert_equals "3" "$(get_arg_count)" || exit 1

# Test 9: Mixed flags and positional args
test_case "Parse mixed flags and positional arguments"
parse_cli_args "query" --flag1 value1 "arg2" --flag2 value2
assert_equals "query" "$(get_arg 0)" || exit 1
assert_equals "arg2" "$(get_arg 1)" || exit 1
assert_equals "value1" "$(get_flag "flag1")" || exit 1
assert_equals "value2" "$(get_flag "flag2")" || exit 1

# Summary
TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
echo ""
echo "================================"
echo "Test Results: $TESTS_PASSED/$TESTS_RUN test cases passed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "Failures: $TESTS_FAILED"
fi
echo "================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ $TESTS_FAILED test case(s) failed"
    exit 1
fi

