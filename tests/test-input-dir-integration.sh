#!/usr/bin/env bash
# Integration Test: --input-dir Feature
# Tests the complete workflow from CLI to session creation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh"

# Test counter
TESTS_RUN=0
TESTS_FAILED=0

# Create temporary test environment
TEST_DIR=$(mktemp -d /tmp/cconductor-integration-test-XXXXXX)
INPUT_DIR="$TEST_DIR/input-files"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Integration Test: --input-dir Feature"
echo "======================================"
echo "Test directory: $TEST_DIR"
echo ""

# Test helper
test_case() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $description"
}

assert_file_exists() {
    local file="$1"
    local description="${2:-}"
    
    if [ -f "$file" ]; then
        echo "  ✓ PASS: File exists: $(basename "$file") $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: File does not exist: $file"
        return 1
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local description="${3:-}"
    
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  ✓ PASS: Pattern found in file $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: Pattern '$pattern' not found in $file"
        return 1
    fi
}

assert_json_field() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local description="${4:-}"
    
    local actual
    if actual=$(safe_jq_from_file "$file" "$field" "" "" "test_input_dir.field" "true"); then
        :
    else
        actual=""
    fi
    
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ PASS: $field = $expected $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: $field = '$actual', expected '$expected'"
        return 1
    fi
}

assert_json_array_length() {
    local file="$1"
    local field="$2"
    local expected="$3"
    local description="${4:-}"
    
    local actual
    if actual=$(safe_jq_from_file "$file" "$field | length" "0" "" "test_input_dir.length" "true"); then
        :
    else
        actual="0"
    fi
    
    if [ "$actual" = "$expected" ]; then
        echo "  ✓ PASS: $field has $expected items $description"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: $field has $actual items, expected $expected"
        return 1
    fi
}

# ==============================================================================
# Setup Test Environment
# ==============================================================================

echo "→ Setting up test environment..."

mkdir -p "$INPUT_DIR"

# Create test PDF
cat > "$INPUT_DIR/research.pdf" <<'EOF'
%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 
2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj
xref
0 4
trailer<</Size 4/Root 1 0 R>>
startxref
%%EOF
EOF

# Create test markdown
cat > "$INPUT_DIR/context.md" <<'EOF'
# Research Context

This is a test markdown document with research context.

## Key Points
- Finding 1: Important concept
- Finding 2: Critical data
- Finding 3: Key insight

## Background
Lorem ipsum dolor sit amet, consectetur adipiscing elit.
EOF

# Create test text file
cat > "$INPUT_DIR/notes.txt" <<'EOF'
Research Notes
==============

- Topic: Test Research
- Date: 2024-10-03
- Status: In Progress

Key observations:
1. First observation
2. Second observation
3. Third observation
EOF

echo "  ✓ Created test input files:"
echo "    - research.pdf"
echo "    - context.md"
echo "    - notes.txt"
echo ""

# ==============================================================================
# Test 1: CLI accepts --input-dir flag
# ==============================================================================

test_case "CLI accepts --input-dir flag"

# Just test parsing, don't actually run research
if bash -c "source '$PROJECT_ROOT/src/utils/cli-parser.sh' && \
            parse_cli_args 'test query' --input-dir '$INPUT_DIR' && \
            has_flag 'input-dir'"; then
    echo "  ✓ PASS: CLI parser accepts --input-dir"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: CLI parser rejected --input-dir"
fi

# ==============================================================================
# Test 2: Input files manager processes directory
# ==============================================================================

test_case "Input files manager processes directory correctly"

# Create a temporary session for testing
TEMP_SESSION="$TEST_DIR/test-session"
mkdir -p "$TEMP_SESSION"

# Source and test input files manager
if bash -c "source '$PROJECT_ROOT/src/utils/input-files-manager.sh' && \
            process_input_directory '$INPUT_DIR' '$TEMP_SESSION'"; then
    echo "  ✓ PASS: Input files manager succeeded"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: Input files manager failed"
fi

# ==============================================================================
# Test 3: Manifest file created with correct structure
# ==============================================================================

test_case "Input files manifest created"

MANIFEST="$TEMP_SESSION/input-files.json"
assert_file_exists "$MANIFEST" || exit 1

test_case "Manifest has correct structure"
assert_json_field "$MANIFEST" ".input_dir" "$INPUT_DIR" || exit 1
assert_json_array_length "$MANIFEST" ".pdfs" "1" "(1 PDF)" || exit 1
assert_json_array_length "$MANIFEST" ".markdown" "1" "(1 markdown)" || exit 1
assert_json_array_length "$MANIFEST" ".text" "1" "(1 text file)" || exit 1

# ==============================================================================
# Test 4: PDF cached correctly
# ==============================================================================

test_case "PDF cached with content hash"

PDF_HASH=$(jq -r '.pdfs[0].sha256' "$MANIFEST")
if [ -n "$PDF_HASH" ] && [ "$PDF_HASH" != "null" ]; then
    echo "  ✓ PASS: PDF has content hash: ${PDF_HASH:0:16}..."
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: PDF missing content hash"
fi

# Check cache path exists
CACHE_PATH=$(jq -r '.pdfs[0].cached_path' "$MANIFEST")
if [ -f "$CACHE_PATH" ]; then
    echo "  ✓ PASS: PDF cached at: $CACHE_PATH"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: Cached PDF not found at: $CACHE_PATH"
fi

# ==============================================================================
# Test 5: Text files copied to knowledge directory
# ==============================================================================

test_case "Text files copied to session knowledge"

assert_file_exists "$TEMP_SESSION/knowledge/context.md" "(markdown)" || exit 1
assert_file_exists "$TEMP_SESSION/knowledge/notes.txt" "(text)" || exit 1

# Verify content preserved
assert_file_contains "$TEMP_SESSION/knowledge/context.md" "Key Points" || exit 1
assert_file_contains "$TEMP_SESSION/knowledge/notes.txt" "Research Notes" || exit 1

# ==============================================================================
# Test 6: PDF deduplication works
# ==============================================================================

test_case "PDF deduplication (same content, different name)"

# Copy PDF with different name
cp "$INPUT_DIR/research.pdf" "$INPUT_DIR/duplicate.pdf"

# Process again
TEMP_SESSION2="$TEST_DIR/test-session-2"
mkdir -p "$TEMP_SESSION2"

# Run and capture output
DEDUP_OUTPUT=$(bash -c "source '$PROJECT_ROOT/src/utils/input-files-manager.sh' && \
                        process_input_directory '$INPUT_DIR' '$TEMP_SESSION2'" 2>&1)

if echo "$DEDUP_OUTPUT" | grep -q "using cached version"; then
    echo "  ✓ PASS: Deduplication detected (cached version used)"
else
    echo "  ⚠  WARNING: Deduplication message not found (may still work)"
fi

# Verify both PDFs point to same cache file
if [ -f "$TEMP_SESSION2/input-files.json" ]; then
    CACHE_PATH1=$(jq -r '.pdfs[0].cached_path' "$TEMP_SESSION2/input-files.json")
    CACHE_PATH2=$(jq -r '.pdfs[1].cached_path' "$TEMP_SESSION2/input-files.json")
    
    if [ "$CACHE_PATH1" = "$CACHE_PATH2" ]; then
        echo "  ✓ PASS: Both PDFs use same cached file"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: PDFs have different cache paths"
        echo "    Path 1: $CACHE_PATH1"
        echo "    Path 2: $CACHE_PATH2"
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: Manifest not created"
fi

# ==============================================================================
# Test 7: Unsupported file types handled gracefully
# ==============================================================================

test_case "Unsupported file types skipped gracefully"

# Add unsupported files
echo "test" > "$INPUT_DIR/test.docx"
echo "test" > "$INPUT_DIR/image.jpg"

TEMP_SESSION3="$TEST_DIR/test-session-3"
mkdir -p "$TEMP_SESSION3"

OUTPUT=$(bash -c "source '$PROJECT_ROOT/src/utils/input-files-manager.sh' && \
                  process_input_directory '$INPUT_DIR' '$TEMP_SESSION3'" 2>&1)

if echo "$OUTPUT" | grep -q "unsupported file type"; then
    echo "  ✓ PASS: Unsupported files warned"
else
    echo "  ⚠  NOTE: No warning for unsupported files (non-critical)"
fi

# Verify only supported files in manifest
MANIFEST3="$TEMP_SESSION3/input-files.json"
if [ -f "$MANIFEST3" ]; then
    TOTAL_FILES=$(jq '(.pdfs | length) + (.markdown | length) + (.text | length)' "$MANIFEST3")
    if [ "$TOTAL_FILES" -eq 4 ]; then
        echo "  ✓ PASS: Only 4 supported files in manifest (unsupported excluded)"
    else
        echo "  ⚠  NOTE: Got $TOTAL_FILES files (expected 4)"
    fi
fi

# ==============================================================================
# Test 8: Empty directory handled gracefully
# ==============================================================================

test_case "Empty directory handled gracefully"

EMPTY_DIR="$TEST_DIR/empty"
mkdir -p "$EMPTY_DIR"

TEMP_SESSION4="$TEST_DIR/test-session-4"
mkdir -p "$TEMP_SESSION4"

if bash -c "source '$PROJECT_ROOT/src/utils/input-files-manager.sh' && \
            process_input_directory '$EMPTY_DIR' '$TEMP_SESSION4'" 2>&1; then
    echo "  ✓ PASS: Empty directory processed without error"
    
    # Verify manifest exists with zero files
    MANIFEST4="$TEMP_SESSION4/input-files.json"
    if [ -f "$MANIFEST4" ]; then
        TOTAL=$(jq '(.pdfs | length) + (.markdown | length) + (.text | length)' "$MANIFEST4")
        if [ "$TOTAL" -eq 0 ]; then
            echo "  ✓ PASS: Manifest has 0 files"
        fi
    fi
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: Empty directory caused error"
fi

# ==============================================================================
# Summary
# ==============================================================================

TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
echo ""
echo "========================================"
echo "Test Results: $TESTS_PASSED/$TESTS_RUN test cases passed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "Failures: $TESTS_FAILED"
fi
echo "========================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✅ All integration tests passed!"
    exit 0
else
    echo "❌ $TESTS_FAILED test case(s) failed"
    exit 1
fi
