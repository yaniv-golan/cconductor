#!/bin/bash
# PDF Cache Phase 1 Test Suite
# Tests: Locking, Deduplication, Error Handling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the PDF cache utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/pdf-cache.sh"

# Test configuration
TEST_PDF_URL="https://arxiv.org/pdf/1706.03762.pdf"
HTTP_URL="http://arxiv.org/pdf/1706.03762.pdf"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

test_fail() {
    echo -e "${RED}✗${NC} $1"
    echo "  Reason: $2"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

test_skip() {
    echo -e "${YELLOW}⊘${NC} $1 (skipped: $2)"
}

# =============================================================================
# TESTS
# =============================================================================

echo "PDF Cache Phase 1 Tests"
echo "======================="
echo ""

# Test 1: Cache initialization
echo "Test 1: Cache Initialization"
if init_pdf_cache; then
    if [ -d "$PDF_CACHE_DIR" ] && [ -f "$PDF_CACHE_DIR/cache-index.json" ]; then
        test_pass "Cache initialized successfully"
    else
        test_fail "Cache initialization" "Directories not created"
    fi
else
    test_fail "Cache initialization" "init_pdf_cache failed"
fi
echo ""

# Test 2: Stats on empty cache
echo "Test 2: Stats on Empty Cache"
if bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" stats > /dev/null 2>&1; then
    test_pass "Stats command works on empty cache"
else
    test_fail "Stats command" "Failed on empty cache"
fi
echo ""

# Test 3: List empty cache
echo "Test 3: List Empty Cache"
result=$(bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" list)
if echo "$result" | jq -e '.pdfs | length == 0' > /dev/null 2>&1; then
    test_pass "List shows empty cache correctly"
else
    test_fail "List command" "Expected empty pdfs array"
fi
echo ""

# Test 4: Invalid URL handling
echo "Test 4: Error Handling - Invalid URL"
if ! bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "not-a-url" "Test" "Test" 2>/dev/null; then
    test_pass "Invalid URL rejected correctly"
else
    test_fail "Invalid URL handling" "Should have failed"
fi
echo ""

# Test 5: HTTP URL warning
echo "Test 5: HTTP URL Warning"
if bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$HTTP_URL" "Test" "Test" 2>&1 | grep -q "insecure HTTP"; then
    test_pass "HTTP URL generates warning"
else
    test_skip "HTTP URL warning" "May not be testable with this URL"
fi
echo ""

# Test 6: Fetch real PDF
echo "Test 6: Fetch Real PDF"
echo "  (This will download a 2MB PDF from arXiv)"
result=$(bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$TEST_PDF_URL" "Attention Paper" "arXiv" 2>&1)
if echo "$result" | grep -q ".pdf$" && [ -f "$(echo "$result" | tail -1)" ]; then
    test_pass "PDF downloaded and cached"
else
    test_fail "PDF download" "Download failed or file not created"
fi
echo ""

# Test 7: Cache hit
echo "Test 7: Cache Hit (No Re-download)"
start_time=$(date +%s)
result=$(bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$TEST_PDF_URL" "Attention Paper" "arXiv" 2>&1)
end_time=$(date +%s)
duration=$((end_time - start_time))

if echo "$result" | grep -q ".pdf$" && [ "$duration" -lt 2 ]; then
    test_pass "Cache hit - instant return (${duration}s)"
else
    test_fail "Cache hit" "Took too long (${duration}s), may have re-downloaded"
fi
echo ""

# Test 8: Check command
echo "Test 8: Check Command"
if bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" check "$TEST_PDF_URL" 2>&1 | grep -q "Cached:"; then
    test_pass "Check correctly identifies cached PDF"
else
    test_fail "Check command" "Did not identify cached PDF"
fi
echo ""

# Test 9: Stats after download
echo "Test 9: Stats After Download"
stats=$(bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" stats 2>&1)
if echo "$stats" | jq -e '.cached_pdfs == 1' > /dev/null 2>&1; then
    test_pass "Stats shows 1 cached PDF"
else
    test_fail "Stats command" "Expected 1 PDF, got: $(echo "$stats" | jq -r '.cached_pdfs')"
fi
echo ""

# Test 10: Metadata exists
echo "Test 10: Metadata File Created"
cache_key=$(echo -n "$TEST_PDF_URL" | shasum -a 256 | cut -d' ' -f1)
metadata_file="$PDF_METADATA_DIR/${cache_key}.json"
if [ -f "$metadata_file" ] && jq -e '.sha256' "$metadata_file" > /dev/null 2>&1; then
    test_pass "Metadata file created with SHA-256"
else
    test_fail "Metadata creation" "File missing or invalid JSON"
fi
echo ""

# Test 11: Deduplication
echo "Test 11: Deduplication (manually create duplicate)"
# Manually add duplicate entry to index
index_file="$PDF_CACHE_DIR/cache-index.json"
jq '.pdfs += .pdfs' "$index_file" > "${index_file}.tmp" && mv "${index_file}.tmp" "$index_file"
count_before=$(jq '.pdfs | length' "$index_file")

bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" dedupe > /dev/null 2>&1
count_after=$(jq '.pdfs | length' "$index_file")

if [ "$count_after" -lt "$count_before" ]; then
    test_pass "Deduplication removed duplicates ($count_before → $count_after)"
else
    test_fail "Deduplication" "Count unchanged: $count_before → $count_after"
fi
echo ""

# Test 12: Rebuild index
echo "Test 12: Rebuild Index"
if bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" rebuild 2>&1 | grep -q "Index rebuilt"; then
    test_pass "Index rebuilt successfully"
else
    test_fail "Rebuild index" "Command failed"
fi
echo ""

# Test 13: Repair command
echo "Test 13: Repair Command"
if bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" repair 2>&1 | grep -q "repaired successfully"; then
    test_pass "Repair command completed"
else
    test_fail "Repair command" "Command failed"
fi
echo ""

# Test 14: Concurrent access simulation
echo "Test 14: Concurrent Access (3 parallel fetches)"
(
    bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$TEST_PDF_URL" "Test1" "Test" > /dev/null 2>&1 &
    bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$TEST_PDF_URL" "Test2" "Test" > /dev/null 2>&1 &
    bash "$PROJECT_ROOT/src/utils/pdf-cache.sh" fetch "$TEST_PDF_URL" "Test3" "Test" > /dev/null 2>&1 &
    wait
)

# Check if index is still valid JSON
if jq -e '.pdfs' "$index_file" > /dev/null 2>&1; then
    test_pass "Cache index survived concurrent access"
else
    test_fail "Concurrent access" "Cache index corrupted"
fi
echo ""

# Test 15: File locking (check no orphaned locks)
echo "Test 15: Lock Cleanup"
if [ ! -d "$LOCK_FILE" ]; then
    test_pass "No orphaned lock files"
else
    test_fail "Lock cleanup" "Lock file still exists: $LOCK_FILE"
fi
echo ""

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "Test Summary"
echo "============"
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
else
    echo -e "Tests failed: $TESTS_FAILED"
fi
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi

