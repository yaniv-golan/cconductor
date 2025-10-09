#!/usr/bin/env bash
# Platform Compatibility Test Suite
# Tests dashboard epoch conversion and temp paths on macOS and Linux

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/dashboard.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/platform-paths.sh"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       Platform Compatibility Test Suite                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Detect current platform
CURRENT_OS=$(uname -s)
echo "Current Platform: $CURRENT_OS"
echo ""

# Test 1: platform-paths.sh
echo "=== Test 1: Platform Paths ===" 
echo "Testing get_tmp_dir()..."
TMP_DIR=$(get_tmp_dir)
echo "  Temp dir: $TMP_DIR"

if [ -d "$TMP_DIR" ] && [ -w "$TMP_DIR" ]; then
    echo "  ✅ PASS: Temp directory exists and is writable"
else
    echo "  ❌ FAIL: Temp directory not accessible"
    exit 1
fi

echo ""
echo "All platform paths:"
show_platform_paths
echo ""

# Test 2: Dashboard epoch conversion
echo "=== Test 2: Dashboard Epoch Conversion ==="
echo "Testing calculate_elapsed_seconds()..."

# Test with timestamp from 1 hour ago
if [ "$CURRENT_OS" = "Darwin" ]; then
    PAST_TIME=$(date -ju -v-1H +"%Y-%m-%dT%H:%M:%SZ")
else
    PAST_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
fi

echo "  Testing with timestamp: $PAST_TIME (1 hour ago)"
RUNTIME=$(calculate_elapsed_seconds "$PAST_TIME")
echo "  Calculated runtime: $RUNTIME seconds"

# Should be approximately 3600 seconds (1 hour) - allow 100 second variance
if [ "$RUNTIME" -ge 3500 ] && [ "$RUNTIME" -le 3700 ]; then
    echo "  ✅ PASS: Runtime is approximately 3600 seconds (1 hour)"
else
    echo "  ❌ FAIL: Runtime is $RUNTIME, expected ~3600"
    exit 1
fi

# Test with current timestamp
if [ "$CURRENT_OS" = "Darwin" ]; then
    NOW=$(date -ju +"%Y-%m-%dT%H:%M:%SZ")
else
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi

echo ""
echo "  Testing with current time: $NOW"
RUNTIME_NOW=$(calculate_elapsed_seconds "$NOW")
echo "  Calculated runtime: $RUNTIME_NOW seconds"

if [ "$RUNTIME_NOW" -le 5 ]; then
    echo "  ✅ PASS: Runtime is approximately 0 seconds"
else
    echo "  ❌ FAIL: Runtime is $RUNTIME_NOW, expected ~0"
    exit 1
fi

# Test 3: Invalid timestamp handling
echo ""
echo "=== Test 3: Invalid Timestamp Handling ==="
echo "  Testing with invalid timestamp..."
INVALID_RUNTIME=$(calculate_elapsed_seconds "invalid")
if [ "$INVALID_RUNTIME" = "0" ]; then
    echo "  ✅ PASS: Invalid timestamp returns 0 (graceful fallback)"
else
    echo "  ❌ FAIL: Invalid timestamp returned $INVALID_RUNTIME, expected 0"
    exit 1
fi

# Test 4: Temp file creation
echo ""
echo "=== Test 4: Temp File Creation ==="
echo "  Testing temp file creation in platform temp dir..."
TEST_FILE=$(mktemp "$(get_tmp_dir)/cconductor-test-XXXXXX")
echo "  Created temp file: $TEST_FILE"

if [ -f "$TEST_FILE" ]; then
    echo "test" > "$TEST_FILE"
    if [ -s "$TEST_FILE" ]; then
        echo "  ✅ PASS: Temp file created and writable"
        rm -f "$TEST_FILE"
    else
        echo "  ❌ FAIL: Temp file not writable"
        rm -f "$TEST_FILE"
        exit 1
    fi
else
    echo "  ❌ FAIL: Temp file not created"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               ✅ ALL TESTS PASSED                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Platform: $CURRENT_OS"
echo "Tests run: 4"
echo "Tests passed: 4"
echo "Tests failed: 0"
echo ""
echo "This test suite validates:"
echo "  • Platform-specific temp directory access"
echo "  • BSD/GNU date epoch conversion compatibility"
echo "  • Graceful handling of invalid timestamps"
echo "  • Temp file creation and cleanup"

