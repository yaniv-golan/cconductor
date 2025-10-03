#!/bin/bash
# Test: Lock Timeout Accuracy
# Verifies that lock timeout is 10 seconds, not 100 seconds

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test: Lock Timeout Accuracy                              ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Source PDF cache module
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/pdf-cache.sh"

# Initialize cache
init_pdf_cache >/dev/null 2>&1 || true

echo "→ Creating a locked cache file..."
# Manually create lock directory to simulate locked state
mkdir -p "$LOCK_FILE"
echo "9999999" > "$LOCK_FILE/pid"  # Fake PID that doesn't exist
echo "  ✓ Lock created at: $LOCK_FILE"
echo ""

echo "→ Attempting to acquire lock with 3-second timeout..."
echo "  (Should fail after ~3 seconds, not 30 seconds)"
echo ""

start_time=$(date +%s)

# Try to acquire lock with 3-second timeout (will fail because lock exists)
if acquire_cache_lock 3 2>&1; then
    echo "  ✗ Lock acquired (unexpected - lock should be held)"
    result=1
else
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))
    
    echo ""
    echo "  Lock acquisition failed after $elapsed seconds"
    echo ""
    
    # Check if timeout is approximately correct (allow 1 second variance)
    if [ $elapsed -ge 2 ] && [ $elapsed -le 5 ]; then
        echo "  ✓ Timeout is accurate (expected ~3s, got ${elapsed}s)"
        echo ""
        echo "✅ TEST PASSED: Lock timeout is working correctly"
        result=0
    else
        echo "  ✗ Timeout is incorrect (expected ~3s, got ${elapsed}s)"
        
        if [ $elapsed -gt 20 ]; then
            echo "  This suggests the old bug (10x multiplier) is still present"
        fi
        
        echo ""
        echo "❌ TEST FAILED: Lock timeout is inaccurate"
        result=1
    fi
fi

# Cleanup
rm -rf "$LOCK_FILE"

exit $result

