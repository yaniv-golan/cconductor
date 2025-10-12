#!/usr/bin/env bash
# Unit Tests for kg-utils.sh
# Tests knowledge graph utility functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KG_UTILS="$PROJECT_ROOT/src/utils/kg-utils.sh"

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
setup_test_kg() {
    local test_dir="$1"
    mkdir -p "$test_dir"
    
    # Create a sample knowledge graph
    cat > "$test_dir/knowledge-graph.json" <<'EOF'
{
  "entities": [
    {"id": "e1", "name": "Entity 1", "type": "concept"},
    {"id": "e2", "name": "Entity 2", "type": "concept"},
    {"id": "e3", "name": "Entity 3", "type": "concept"}
  ],
  "claims": [
    {
      "id": "c1",
      "claim": "Test claim 1",
      "confidence": 0.9,
      "category": "efficacy",
      "verification_status": "verified",
      "sources": [{"url": "https://example.com/1"}]
    },
    {
      "id": "c2",
      "claim": "Test claim 2",
      "confidence": 0.7,
      "category": "safety",
      "verification_status": "pending",
      "sources": [{"url": "https://example.com/2"}]
    },
    {
      "id": "c3",
      "claim": "Test claim 3",
      "confidence": 0.5,
      "category": "efficacy",
      "verification_status": "verified",
      "sources": [{"url": "https://example.com/3"}]
    }
  ],
  "relationships": [
    {"source": "e1", "target": "e2", "type": "related_to"}
  ]
}
EOF
}

# Test 1: Extract claims
test_extract_claims() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" extract-claims "$test_dir/knowledge-graph.json")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "extract-claims: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if it has the expected structure
    local total
    total=$(echo "$output" | jq -r '.total')
    if [[ "$total" == "3" ]]; then
        pass_test "extract-claims: returns correct count"
    else
        fail_test "extract-claims: incorrect count" "3" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 2: Extract entities
test_extract_entities() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" extract-entities "$test_dir/knowledge-graph.json")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "extract-entities: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check if it has the expected structure
    local total
    total=$(echo "$output" | jq -r '.total')
    if [[ "$total" == "3" ]]; then
        pass_test "extract-entities: returns correct count"
    else
        fail_test "extract-entities: incorrect count" "3" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 3: Compute stats
test_compute_stats() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" stats "$test_dir/knowledge-graph.json")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "compute-stats: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Check key stats
    local total_claims
    total_claims=$(echo "$output" | jq -r '.total_claims')
    local total_entities
    total_entities=$(echo "$output" | jq -r '.total_entities')
    local high_confidence
    high_confidence=$(echo "$output" | jq -r '.high_confidence_claims')
    
    if [[ "$total_claims" == "3" ]] && [[ "$total_entities" == "3" ]] && [[ "$high_confidence" == "1" ]]; then
        pass_test "compute-stats: calculates correct statistics"
    else
        fail_test "compute-stats: incorrect statistics" "claims=3, entities=3, high_conf=1" "claims=$total_claims, entities=$total_entities, high_conf=$high_confidence"
    fi
    
    rm -rf "$test_dir"
}

# Test 4: Filter by confidence
test_filter_confidence() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" filter-confidence "$test_dir/knowledge-graph.json" 0.8)
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "filter-confidence: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Should only return claims with confidence >= 0.8
    local total
    total=$(echo "$output" | jq -r '.total')
    if [[ "$total" == "1" ]]; then
        pass_test "filter-confidence: filters correctly (>= 0.8)"
    else
        fail_test "filter-confidence: incorrect filter" "1" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 5: Filter by category
test_filter_category() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" filter-category "$test_dir/knowledge-graph.json" "efficacy")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "filter-category: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Should return 2 claims with category "efficacy"
    local total
    total=$(echo "$output" | jq -r '.total')
    if [[ "$total" == "2" ]]; then
        pass_test "filter-category: filters correctly (efficacy)"
    else
        fail_test "filter-category: incorrect filter" "2" "$total"
    fi
    
    rm -rf "$test_dir"
}

# Test 6: List categories
test_list_categories() {
    run_test
    local test_dir="$PROJECT_ROOT/test-kg-utils-$$"
    setup_test_kg "$test_dir"
    
    local output
    output=$("$KG_UTILS" list-categories "$test_dir/knowledge-graph.json")
    
    # Check if output is valid JSON
    if ! echo "$output" | jq -e . > /dev/null 2>&1; then
        fail_test "list-categories: invalid JSON output" "valid JSON" "$output"
        rm -rf "$test_dir"
        return
    fi
    
    # Should return 2 unique categories
    local count
    count=$(echo "$output" | jq -r '.categories | length')
    if [[ "$count" == "2" ]]; then
        pass_test "list-categories: returns correct unique categories"
    else
        fail_test "list-categories: incorrect category count" "2" "$count"
    fi
    
    rm -rf "$test_dir"
}

# Test 7: Handle missing file
test_missing_file() {
    run_test
    
    local output
    output=$("$KG_UTILS" extract-claims "/nonexistent/file.json" 2>&1) || true
    
    # Should return error JSON
    if echo "$output" | jq -e '.error' > /dev/null 2>&1; then
        pass_test "missing-file: handles missing file gracefully"
    else
        fail_test "missing-file: doesn't handle error correctly" "error field in JSON" "$output"
    fi
}

# Run all tests
echo "=========================================="
echo "Testing kg-utils.sh"
echo "=========================================="
echo ""

test_extract_claims
test_extract_entities
test_compute_stats
test_filter_confidence
test_filter_category
test_list_categories
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

