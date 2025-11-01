#!/usr/bin/env bash
# Security Fixes Validation Test
# Quick tests for critical security fixes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Security Fixes Validation Test Suite                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Command injection prevention (Issue #1)
echo "Test 1: Command Injection Prevention"
echo "--------------------------------------"
test_file=$(mktemp)
echo "test" > "$test_file"
# shellcheck disable=SC1091
if ! source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null; then
    fail "Could not source shared-state.sh"
fi
injection_file="/tmp/security_test_injection_$$"
with_lock "$test_file" echo "foo; touch $injection_file" > /dev/null 2>&1 || true
if [ ! -f "$injection_file" ]; then
    pass "Command injection prevented (eval removed)"
else
    fail "Command injection still possible!"
    rm -f "$injection_file"
fi
rm -f "$test_file"
rm -rf "${test_file}.lock" 2>/dev/null || true
echo ""

# Test 2: Stale lock cleanup (Issue #2)
echo "Test 2: Stale Lock Cleanup on Errors"
echo "--------------------------------------"
test_file=$(mktemp)
echo "test" > "$test_file"
# Test that lock is released after atomic_read
atomic_read "$test_file" > /dev/null 2>&1 || true
if [ ! -d "${test_file}.lock" ]; then
    pass "Lock released after atomic operation"
else
    fail "Stale lock remains"
    rm -rf "${test_file}.lock"
fi
rm -f "$test_file"
echo ""

# Test 3: get_timestamp in hooks (Issue #3)
echo "Test 3: Hooks Have get_timestamp Function"
echo "--------------------------------------"
if grep -q "source.*shared-state.sh" "$PROJECT_ROOT/src/claude-runtime/hooks/citation-tracker.sh"; then
    pass "citation-tracker.sh sources shared-state.sh"
else
    fail "citation-tracker.sh missing shared-state.sh"
fi

if grep -q "source.*shared-state.sh" "$PROJECT_ROOT/src/claude-runtime/hooks/research-logger.sh"; then
    pass "research-logger.sh sources shared-state.sh"
else
    fail "research-logger.sh missing shared-state.sh"
fi
echo ""

# Test 4: Self-update checksum verification (Issue #4)
echo "Test 4: Self-Update Checksum Verification"
echo "--------------------------------------"
if grep -q "sha256sum.*checksum" "$PROJECT_ROOT/src/utils/init-and-update.sh" || \
   grep -q "shasum.*checksum" "$PROJECT_ROOT/src/utils/init-and-update.sh"; then
    pass "Self-update now verifies checksums"
else
    fail "Self-update doesn't verify checksums"
fi
echo ""

# Test 5: safe-fetch stderr separation (Issue #5)
echo "Test 5: Safe-Fetch stderr Separation"
echo "--------------------------------------"
if grep -q "TEMP_STDERR" "$PROJECT_ROOT/src/utils/safe-fetch.sh" && \
   grep -q -- "-o.*TEMP_FILE" "$PROJECT_ROOT/src/utils/safe-fetch.sh"; then
    pass "safe-fetch separates stderr from output"
else
    fail "safe-fetch still mixes stderr into output"
fi
echo ""

# Test 6: Lock release safety (Issue #6)
echo "Test 6: Lock Release Uses Safe rmdir"
echo "--------------------------------------"
if grep -q "rmdir.*lock_file" "$PROJECT_ROOT/src/shared-state.sh"; then
    pass "lock_release uses safe rmdir (not rm -rf)"
else
    fail "lock_release still uses dangerous rm -rf"
fi
echo ""

# Test 7: debug.sh doesn't mutate shell options (Issue #11)
echo "Test 7: debug.sh Shell Option Safety"
echo "--------------------------------------"
if grep -q 'if.*BASH_SOURCE.*=.*0.*then' "$PROJECT_ROOT/src/utils/debug.sh"; then
    pass "debug.sh only sets options when run directly"
else
    fail "debug.sh mutates caller's shell options"
fi
echo ""

# Test 8: setup-hooks idempotency (Issue #12)
echo "Test 8: setup-hooks Idempotency"
echo "--------------------------------------"
if grep -q "already configured" "$PROJECT_ROOT/src/utils/setup-hooks.sh"; then
    pass "setup-hooks checks for existing configuration"
else
    fail "setup-hooks not idempotent"
fi
echo ""

# Test 9: Safe-fetch configuration (Issues #8, #9)
echo "Test 9: Safe-Fetch Policy Configuration"
echo "--------------------------------------"
if [ -f "$PROJECT_ROOT/config/safe-fetch-policy.json" ]; then
    if jq empty "$PROJECT_ROOT/config/safe-fetch-policy.json" 2>/dev/null; then
        pass "safe-fetch-policy.json exists and is valid"
    else
        fail "safe-fetch-policy.json is invalid JSON"
    fi
else
    fail "safe-fetch-policy.json not found"
fi

if grep -q "allow_localhost" "$PROJECT_ROOT/src/utils/safe-fetch.sh" && \
   grep -q "BLOCK_EXECUTABLES" "$PROJECT_ROOT/src/utils/safe-fetch.sh"; then
    pass "safe-fetch uses configurable policies"
else
    fail "safe-fetch doesn't use configuration"
fi
echo ""

# Test 10: Other high-priority fixes
echo "Test 10: Other High-Priority Fixes"
echo "--------------------------------------"

# Issue #27: semver validation
if grep -q "semver" "$PROJECT_ROOT/scripts/verify-version.sh"; then
    pass "verify-version validates semver format"
else
    fail "verify-version doesn't validate semver"
fi

# Issue #35: artifact-manager array initialization
if grep -q '// \[\]' "$PROJECT_ROOT/src/utils/artifact-manager.sh"; then
    pass "artifact-manager initializes handoffs array"
else
    fail "artifact-manager doesn't initialize arrays"
fi

# Issue #47: code-health searches all of src/
if grep -q 'grep.*src/' "$PROJECT_ROOT/scripts/code-health.sh"; then
    pass "code-health searches all subdirectories"
else
    fail "code-health has limited search paths"
fi
echo ""

# Test 11: Path resolver command substitution hardening
echo "Test 11: Path Resolver Command Substitution"
echo "--------------------------------------"
tmp_config_dir=$(mktemp -d)
injected_marker="$tmp_config_dir/injected.txt"
cat <<JSON > "$tmp_config_dir/paths.json"
{
  "cache_dir": "\${PROJECT_ROOT}/\$(echo injected > $injected_marker)"
}
JSON

CCONDUCTOR_CONFIG_DIR="$tmp_config_dir" \
    bash -lc "source '$PROJECT_ROOT/src/utils/path-resolver.sh'; resolve_path cache_dir" \
    >/dev/null 2>&1 || true

if [ -f "$injected_marker" ]; then
    fail "resolve_path executed command substitution from config"
else
    pass "resolve_path treats command substitution as literal text"
fi
rm -rf "$tmp_config_dir"
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All security fixes validated!${NC}"
    exit 0
fi
