#!/bin/bash
# Test PDF Content-Addressed Caching

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the PDF cache utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/pdf-cache.sh"

# Test counter
TESTS_RUN=0
TESTS_FAILED=0

# Create temporary test directory
TEST_DIR=$(mktemp -d /tmp/delve-test-XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Using test directory: $TEST_DIR"
echo ""

# Override cache directory for testing
export PDF_CACHE_DIR="$TEST_DIR/cache"
export PDF_METADATA_DIR="$TEST_DIR/cache/metadata"

# Initialize cache
init_pdf_cache

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

assert_file_exists() {
    local file="$1"
    
    if [ -f "$file" ]; then
        echo "  ✓ PASS: File exists: $(basename "$file")"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: File does not exist: $file"
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

# Create test PDF files
echo "Setting up test files..."
echo "%PDF-1.4 Test file 1" > "$TEST_DIR/test1.pdf"
echo "%PDF-1.4 Test file 2" > "$TEST_DIR/test2.pdf"
cp "$TEST_DIR/test1.pdf" "$TEST_DIR/test1-copy.pdf"  # Same content as test1
echo ""

# Test 1: Compute file hash
test_case "compute_file_hash works"
hash1=$(compute_file_hash "$TEST_DIR/test1.pdf")
if [[ -n "$hash1" ]] && [[ ${#hash1} -eq 64 ]]; then
    assert_true "Hash is 64 characters (SHA-256)"
else
    assert_false "Hash is not valid: $hash1"
fi

# Test 2: Same content produces same hash
test_case "Same content produces same hash"
hash1=$(compute_file_hash "$TEST_DIR/test1.pdf")
hash1_copy=$(compute_file_hash "$TEST_DIR/test1-copy.pdf")
assert_equals "$hash1" "$hash1_copy" || exit 1

# Test 3: Different content produces different hash
test_case "Different content produces different hash"
hash2=$(compute_file_hash "$TEST_DIR/test2.pdf")
if [[ "$hash1" != "$hash2" ]]; then
    assert_true "Hashes are different"
else
    assert_false "Hashes should be different"
    exit 1
fi

# Test 4: cache_local_pdf adds file to cache
test_case "cache_local_pdf adds file to cache"
cached_path=$(cache_local_pdf "$TEST_DIR/test1.pdf" "test1.pdf")
if [[ -n "$cached_path" ]]; then
    assert_file_exists "$cached_path" || exit 1
else
    assert_false "cache_local_pdf returned empty path"
    exit 1
fi

# Test 5: cache_has_content_hash detects cached file
test_case "cache_has_content_hash detects cached file"
if cache_has_content_hash "$hash1"; then
    assert_true "Content hash found in cache"
else
    assert_false "Content hash should be in cache"
    exit 1
fi

# Test 6: Caching same content again returns same path (deduplication)
test_case "Deduplication: same content returns same cached file"
cached_path2=$(cache_local_pdf "$TEST_DIR/test1-copy.pdf" "test1-copy.pdf")
assert_equals "$cached_path" "$cached_path2" "(same cache path)" || exit 1

# Test 7: get_cache_path_by_content_hash retrieves correct path
test_case "get_cache_path_by_content_hash works"
retrieved_path=$(get_cache_path_by_content_hash "$hash1")
assert_equals "$cached_path" "$retrieved_path" || exit 1

# Test 8: Cache index exists and is valid JSON
test_case "Cache index is valid JSON"
if jq empty "$PDF_CACHE_DIR/cache-index.json" 2>/dev/null; then
    assert_true "cache-index.json is valid JSON"
else
    assert_false "cache-index.json is not valid JSON"
    exit 1
fi

# Test 9: Cache index contains content_hash field
test_case "Cache index contains content_hash field"
content_hash_in_index=$(jq -r '.pdfs[0].content_hash' "$PDF_CACHE_DIR/cache-index.json")
assert_equals "$hash1" "$content_hash_in_index" || exit 1

# Test 10: Metadata file contains correct information
test_case "Metadata file contains correct source type"
metadata_file="$PDF_METADATA_DIR/${hash1}.json"
if [ -f "$metadata_file" ]; then
    source_type=$(jq -r '.source' "$metadata_file")
    assert_equals "local" "$source_type" || exit 1
else
    assert_false "Metadata file not found"
    exit 1
fi

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

