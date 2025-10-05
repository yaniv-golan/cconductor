#!/bin/bash
# Test: Termination Validation with Missing Field
# Verifies that missing termination_recommendation field defaults to false

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test: Termination Validation                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Define should_terminate function (extracted from cconductor-adaptive.sh)
should_terminate() {
    local coordinator_output_file="$1"

    local should_stop
    should_stop=$(cat "$coordinator_output_file" | jq -r '.termination_recommendation // false')
    [ "$should_stop" = "true" ]
}

# Create test directory
TEST_DIR="$PROJECT_ROOT/.test-termination-$$"
mkdir -p "$TEST_DIR"

echo "→ Test 1: Missing termination_recommendation field"
echo ""

# Create coordinator output WITHOUT termination_recommendation field
cat > "$TEST_DIR/coordinator-missing.json" <<'EOF'
{
  "recommendations": ["Continue research"],
  "new_tasks": []
}
EOF

if should_terminate "$TEST_DIR/coordinator-missing.json"; then
    echo "  ✗ FAILED: should_terminate returned true for missing field"
    result1=1
else
    echo "  ✓ PASSED: should_terminate correctly defaulted to false"
    result1=0
fi

echo ""
echo "→ Test 2: Explicit false value"
echo ""

# Create coordinator output WITH termination_recommendation = false
cat > "$TEST_DIR/coordinator-false.json" <<'EOF'
{
  "recommendations": ["Continue research"],
  "termination_recommendation": false,
  "termination_reason": "",
  "new_tasks": []
}
EOF

if should_terminate "$TEST_DIR/coordinator-false.json"; then
    echo "  ✗ FAILED: should_terminate returned true for explicit false"
    result2=1
else
    echo "  ✓ PASSED: should_terminate correctly returned false"
    result2=0
fi

echo ""
echo "→ Test 3: Explicit true value"
echo ""

# Create coordinator output WITH termination_recommendation = true
cat > "$TEST_DIR/coordinator-true.json" <<'EOF'
{
  "recommendations": ["Research complete"],
  "termination_recommendation": true,
  "termination_reason": "Confidence threshold reached",
  "new_tasks": []
}
EOF

if should_terminate "$TEST_DIR/coordinator-true.json"; then
    echo "  ✓ PASSED: should_terminate correctly returned true"
    result3=0
else
    echo "  ✗ FAILED: should_terminate returned false for explicit true"
    result3=1
fi

echo ""
echo "→ Test 4: Null value"
echo ""

# Create coordinator output WITH termination_recommendation = null
cat > "$TEST_DIR/coordinator-null.json" <<'EOF'
{
  "recommendations": ["Continue research"],
  "termination_recommendation": null,
  "new_tasks": []
}
EOF

if should_terminate "$TEST_DIR/coordinator-null.json"; then
    echo "  ✗ FAILED: should_terminate returned true for null"
    result4=1
else
    echo "  ✓ PASSED: should_terminate correctly defaulted to false for null"
    result4=0
fi

# Cleanup
rm -rf "$TEST_DIR"

echo ""
if [ $result1 -eq 0 ] && [ $result2 -eq 0 ] && [ $result3 -eq 0 ] && [ $result4 -eq 0 ]; then
    echo "✅ TEST PASSED: Termination validation handles all cases correctly"
    exit 0
else
    echo "❌ TEST FAILED: Some termination validation cases failed"
    exit 1
fi

