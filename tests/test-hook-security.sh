#!/usr/bin/env bash
# Security/Integration Tests for Hook Validation
# Tests that pre-tool-use hook properly whitelists utilities
# 
# NOTE: These tests verify the whitelist configuration exists and is
# properly documented. Full integration testing requires running actual
# missions, which is more expensive and tested separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRE_TOOL_HOOK="$PROJECT_ROOT/src/utils/hooks/pre-tool-use.sh"

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

# Test 1: Hook file exists
test_hook_exists() {
    run_test
    
    if [[ -f "$PRE_TOOL_HOOK" ]]; then
        pass_test "hook-exists: pre-tool-use.sh found"
    else
        fail_test "hook-exists: pre-tool-use.sh not found" "file exists" "file missing"
    fi
}

# Test 2: Hook contains whitelist for calculate.sh
test_whitelist_calculate() {
    run_test
    
    if grep -q "calculate\.sh" "$PRE_TOOL_HOOK"; then
        pass_test "whitelist-config: calculate.sh in whitelist"
    else
        fail_test "whitelist-config: calculate.sh not in whitelist" "found in hook" "not found"
    fi
}

# Test 3: Hook contains whitelist for kg-utils.sh
test_whitelist_kg_utils() {
    run_test
    
    if grep -q "kg-utils\.sh" "$PRE_TOOL_HOOK"; then
        pass_test "whitelist-config: kg-utils.sh in whitelist"
    else
        fail_test "whitelist-config: kg-utils.sh not in whitelist" "found in hook" "not found"
    fi
}

# Test 4: Hook contains whitelist for data-utils.sh
test_whitelist_data_utils() {
    run_test
    
    if grep -q "data-utils\.sh" "$PRE_TOOL_HOOK"; then
        pass_test "whitelist-config: data-utils.sh in whitelist"
    else
        fail_test "whitelist-config: data-utils.sh not in whitelist" "found in hook" "not found"
    fi
}

# Test 5: Hook checks mission-orchestrator agent
test_orchestrator_check() {
    run_test
    
    if grep -q "mission-orchestrator" "$PRE_TOOL_HOOK"; then
        pass_test "agent-check: hook checks for mission-orchestrator"
    else
        fail_test "agent-check: hook doesn't check agent" "agent check" "not found"
    fi
}

# Test 6: Utilities are executable
test_utilities_executable() {
    run_test
    
    local all_executable=true
    for util in calculate.sh kg-utils.sh data-utils.sh; do
        if [[ ! -x "$PROJECT_ROOT/src/utils/$util" ]]; then
            all_executable=false
            break
        fi
    done
    
    if $all_executable; then
        pass_test "utilities-executable: all utilities have execute permission"
    else
        fail_test "utilities-executable: some utilities not executable" "all executable" "some missing +x"
    fi
}

# Test 7: Utilities have CLI interface
test_utilities_cli() {
    run_test
    
    local all_have_cli=true
    for util in calculate.sh kg-utils.sh data-utils.sh; do
        if ! grep -q "BASH_SOURCE" "$PROJECT_ROOT/src/utils/$util"; then
            all_have_cli=false
            break
        fi
    done
    
    if $all_have_cli; then
        pass_test "utilities-cli: all utilities have CLI interface"
    else
        fail_test "utilities-cli: some utilities missing CLI" "CLI pattern" "not found"
    fi
}

# Test 8: Documentation exists
test_documentation_exists() {
    run_test
    
    if [[ -f "$PROJECT_ROOT/docs/ORCHESTRATOR_UTILITIES.md" ]]; then
        pass_test "documentation: utilities are documented"
    else
        fail_test "documentation: missing ORCHESTRATOR_UTILITIES.md" "file exists" "file missing"
    fi
}

# Test 9: Orchestrator system prompt mentions utilities
test_orchestrator_prompt() {
    run_test
    
    local prompt_file="$PROJECT_ROOT/src/claude-runtime/agents/mission-orchestrator/system-prompt.md"
    if [[ -f "$prompt_file" ]] && grep -q "kg-utils.sh" "$prompt_file"; then
        pass_test "orchestrator-prompt: utilities documented in system prompt"
    else
        fail_test "orchestrator-prompt: utilities not in prompt" "mentioned in prompt" "not found"
    fi
}

# Test 10: Whitelist uses proper regex anchors
test_whitelist_regex_anchors() {
    run_test
    
    # Check if the whitelist regex uses ^ anchor to prevent similar names
    if grep -q "\^(src/utils/calculate" "$PRE_TOOL_HOOK"; then
        pass_test "whitelist-regex: uses proper anchors for security"
    else
        fail_test "whitelist-regex: missing regex anchors" "^ anchor" "not found"
    fi
}

# Run all tests
echo "=========================================="
echo "Testing Hook Security (Whitelist Configuration)"
echo "=========================================="
echo ""
echo "NOTE: These tests verify security configuration."
echo "Full runtime testing requires live mission execution."
echo ""

test_hook_exists
test_whitelist_calculate
test_whitelist_kg_utils
test_whitelist_data_utils
test_orchestrator_check
test_utilities_executable
test_utilities_cli
test_documentation_exists
test_orchestrator_prompt
test_whitelist_regex_anchors

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

