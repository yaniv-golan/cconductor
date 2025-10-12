#!/usr/bin/env bash
# Test Runner for All Utility Tests
# Runs all utility test suites and provides comprehensive reporting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Overall tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

# Individual suite results
declare -a SUITE_NAMES
declare -a SUITE_RESULTS
declare -a SUITE_DURATIONS

# Banner
echo ""
echo "================================================================"
echo "  CConductor Utility Tests"
echo "================================================================"
echo ""
echo "Testing new bash utilities for agent use:"
echo "  • kg-utils.sh    - Knowledge graph operations"
echo "  • data-utils.sh  - Data transformation"
echo "  • calculate.sh   - Safe math calculations"
echo "  • Hook security  - Whitelist enforcement"
echo ""
echo "================================================================"
echo ""

# Function to run a test suite
run_suite() {
    local suite_name="$1"
    local suite_script="$2"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    SUITE_NAMES+=("$suite_name")
    
    echo -e "${BLUE}▶${NC} Running $suite_name..."
    echo ""
    
    local start_time
    start_time=$(date +%s)
    
    if "$suite_script"; then
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        PASSED_SUITES=$((PASSED_SUITES + 1))
        SUITE_RESULTS+=("PASS")
        SUITE_DURATIONS+=("${duration}s")
        
        echo ""
        echo -e "${GREEN}✓ $suite_name PASSED${NC} (${duration}s)"
    else
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        FAILED_SUITES=$((FAILED_SUITES + 1))
        SUITE_RESULTS+=("FAIL")
        SUITE_DURATIONS+=("${duration}s")
        
        echo ""
        echo -e "${RED}✗ $suite_name FAILED${NC} (${duration}s)"
    fi
    
    echo ""
    echo "----------------------------------------------------------------"
    echo ""
}

# Check if test files exist
check_test_file() {
    local test_file="$1"
    local test_name="$2"
    
    if [[ ! -f "$test_file" ]]; then
        echo -e "${RED}Error: Test file not found: $test_file${NC}" >&2
        return 1
    fi
    
    if [[ ! -x "$test_file" ]]; then
        echo -e "${YELLOW}Warning: Making $test_name executable${NC}"
        chmod +x "$test_file"
    fi
    
    return 0
}

# Make sure all test files are executable
echo "Preparing test environment..."
check_test_file "$SCRIPT_DIR/test-kg-utils.sh" "kg-utils tests" || exit 1
check_test_file "$SCRIPT_DIR/test-data-utils.sh" "data-utils tests" || exit 1
check_test_file "$SCRIPT_DIR/test-calculate.sh" "calculate tests" || exit 1
check_test_file "$SCRIPT_DIR/test-hook-security.sh" "hook security tests" || exit 1
echo -e "${GREEN}✓${NC} All test files found"
echo ""
echo "================================================================"
echo ""

# Run all test suites
run_suite "Knowledge Graph Utils (kg-utils.sh)" "$SCRIPT_DIR/test-kg-utils.sh"
run_suite "Data Transformation (data-utils.sh)" "$SCRIPT_DIR/test-data-utils.sh"
run_suite "Safe Calculations (calculate.sh)" "$SCRIPT_DIR/test-calculate.sh"
run_suite "Hook Security (whitelist enforcement)" "$SCRIPT_DIR/test-hook-security.sh"

# Final summary
echo ""
echo "================================================================"
echo "  FINAL TEST REPORT"
echo "================================================================"
echo ""

# Print individual suite results
for i in "${!SUITE_NAMES[@]}"; do
    name="${SUITE_NAMES[$i]}"
    result="${SUITE_RESULTS[$i]}"
    duration="${SUITE_DURATIONS[$i]}"
    
    if [[ "$result" == "PASS" ]]; then
        echo -e "${GREEN}✓${NC} $name - ${GREEN}PASSED${NC} ($duration)"
    else
        echo -e "${RED}✗${NC} $name - ${RED}FAILED${NC} ($duration)"
    fi
done

echo ""
echo "----------------------------------------------------------------"
echo "Total suites: $TOTAL_SUITES"
echo -e "Passed:       ${GREEN}$PASSED_SUITES${NC}"

if [[ $FAILED_SUITES -gt 0 ]]; then
    echo -e "Failed:       ${RED}$FAILED_SUITES${NC}"
    echo ""
    echo -e "${RED}Some tests failed. Please review the output above.${NC}"
    echo "================================================================"
    exit 1
else
    echo -e "Failed:       $FAILED_SUITES"
    echo ""
    echo -e "${GREEN}🎉 All tests passed successfully!${NC}"
    echo ""
    echo "These utilities are working correctly and safe for agent use."
    echo "================================================================"
    exit 0
fi

