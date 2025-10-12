#!/usr/bin/env bash
# Unit Tests for data-utils.sh
# Tests data transformation utility functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_UTILS="$PROJECT_ROOT/src/utils/data-utils.sh"

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

# Setup test fixtures
setup_test_data() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    
    # Create sample JSON files for merging
    cat > "$test_dir/data1.json" <<'EOF'
{
  "name": "Test",
  "value": 1,
  "items": ["a", "b"]
}
EOF

    cat > "$test_dir/data2.json" <<'EOF'
{
  "value": 2,
  "extra": "field"
}
EOF

    # Create sample findings files
    cat > "$test_dir/findings-1.json" <<'EOF'
{
  "agent": "web-researcher",
  "claims": [
    {"claim": "Claim A", "confidence": 0.9},
    {"claim": "Claim B", "confidence": 0.8}
  ]
}
EOF

    cat > "$test_dir/findings-2.json" <<'EOF'
{
  "agent": "academic-researcher",
  "claims": [
    {"claim": "Claim B", "confidence": 0.8},
    {"claim": "Claim C", "confidence": 0.7}
  ]
}
EOF

    # Create sample array data for CSV conversion
    cat > "$test_dir/array-data.json" <<'EOF'
[
  {"name": "Item1", "value": 100},
  {"name": "Item2", "value": 200}
]
EOF
}

# Test 1: Merge JSON files
test_merge_json() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    local output
    output=$("$DATA_UTILS" merge "$test_dir/data1.json" "$test_dir/data2.json")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "merge-json: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if merge worked (later values should override)
    local value
    value=$(echo "$output" | jq -r '.value')
    local extra
    extra=$(echo "$output" | jq -r '.extra')
    
    if [[ "$value" == "2" ]] && [[ "$extra" == "field" ]]; then
        pass_test "merge-json: merges objects correctly"
    else
        fail_test "merge-json: incorrect merge" "value=2, extra=field" "value=$value, extra=$extra"
    fi
    
    rm -rf "$test_dir"
}

# Test 2: Consolidate findings
test_consolidate_findings() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    cd "$test_dir"
    local output
    output=$("$DATA_UTILS" consolidate "findings-*.json")
    cd - > /dev/null
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "consolidate-findings: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if consolidation worked
    local total
    total=$(echo "$output" | jq -r '.total')
    
    if [[ "$total" == "2" ]]; then
        pass_test "consolidate-findings: consolidates correctly"
    else
        fail_test "consolidate-findings: incorrect count" "2" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 3: Extract unique claims
test_extract_unique_claims() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    cd "$test_dir"
    local output
    output=$("$DATA_UTILS" extract-claims "findings-*.json")
    cd - > /dev/null
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "extract-unique-claims: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if unique extraction worked (should have 3 unique claims: A, B, C)
    local total
    total=$(echo "$output" | jq -r '.total')
    
    if [[ "$total" == "3" ]]; then
        pass_test "extract-unique-claims: deduplicates correctly"
    else
        fail_test "extract-unique-claims: incorrect unique count" "3" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 4: Convert JSON to CSV
test_json_to_csv() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    local output
    output=$("$DATA_UTILS" to-csv "$test_dir/array-data.json")
    
    # Check if output contains CSV data (should have headers and 2 data rows)
    # Note: jq outputs headers as JSON array (3 lines) + 2 data rows = 6 lines
    local data_rows
    data_rows=$(echo "$output" | grep -c ',' || true)
    
    if [[ "$data_rows" -ge "2" ]]; then
        pass_test "json-to-csv: converts data rows correctly"
    else
        fail_test "json-to-csv: missing data rows" ">=2 rows" "$data_rows rows"
    fi
    
    rm -rf "$test_dir"
}

# Test 5: Create summary
test_create_summary() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    local output
    output=$("$DATA_UTILS" summarize "$test_dir/data1.json" "Test Summary")
    
    # Check if output contains markdown header
    if echo "$output" | grep -q "# Test Summary"; then
        pass_test "create-summary: generates markdown summary"
    else
        fail_test "create-summary: missing markdown header" "# Test Summary" "$output"
    fi
    
    rm -rf "$test_dir"
}

# Test 6: Group by field
test_group_by_field() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    setup_test_data "$test_dir"
    
    local output
    output=$("$DATA_UTILS" group-by "$test_dir/array-data.json" "name")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "group-by-field: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if grouping worked (should have 2 groups)
    local group_count
    group_count=$(echo "$output" | jq '. | length')
    
    if [[ "$group_count" == "2" ]]; then
        pass_test "group-by-field: groups correctly"
    else
        fail_test "group-by-field: incorrect group count" "2" "$group_count"
    fi
    
    rm -rf "$test_dir"
}

# Test 7: Handle no findings files
test_no_findings() {
    run_test
    local test_dir="$PROJECT_ROOT/test-data-utils-$$"
    mkdir -p "$test_dir"
    
    cd "$test_dir"
    local output
    output=$("$DATA_UTILS" consolidate "findings-*.json")
    cd - > /dev/null
    
    # Should return empty result gracefully
    if echo "$output" | jq -e '.total == 0' > /dev/null 2>&1; then
        pass_test "no-findings: handles empty gracefully"
    else
        fail_test "no-findings: doesn't handle empty correctly" "total=0" "$output"
    fi
    
    rm -rf "$test_dir"
}

# Test 8: Handle missing file
test_missing_file() {
    run_test
    
    local output
    output=$("$DATA_UTILS" to-csv "/nonexistent/file.json" 2>&1) || true
    
    # Should return error
    if echo "$output" | grep -q "Error"; then
        pass_test "missing-file: handles missing file with error"
    else
        fail_test "missing-file: doesn't handle error correctly" "error message" "$output"
    fi
}

# Run all tests
echo "=========================================="
echo "Testing data-utils.sh"
echo "=========================================="
echo ""

test_merge_json
test_consolidate_findings
test_extract_unique_claims
test_json_to_csv
test_create_summary
test_group_by_field
test_no_findings
test_missing_file

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

