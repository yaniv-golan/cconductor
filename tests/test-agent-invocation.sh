#!/bin/bash
# Test Agent Invocation System
# Verifies that agents can be invoked and return proper JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           Agent Invocation Test Suite                    ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Claude CLI availability
echo "Test 1: Checking Claude CLI availability..."
if bash "$PROJECT_ROOT/src/utils/invoke-agent.sh" check; then
    echo "✅ Pass: Claude CLI is available"
else
    echo "❌ Fail: Claude CLI not found"
    exit 1
fi
echo ""

# Test 2: Simple agent invocation
echo "Test 2: Invoking research-planner agent..."
TEST_DIR=$(mktemp -d)
cat > "$TEST_DIR/input.json" <<'EOF'
{
  "research_question": "What is Kubernetes?",
  "mode": "default"
}
EOF

if timeout 120 bash "$PROJECT_ROOT/src/utils/invoke-agent.sh" invoke-simple \
    research-planner \
    "Analyze research question: What is Kubernetes? Provide JSON with tasks array." \
    "$TEST_DIR/output.txt" \
    120; then
    echo "✅ Pass: Agent invoked successfully"
else
    echo "❌ Fail: Agent invocation failed"
    rm -rf "$TEST_DIR"
    exit 1
fi
echo ""

# Test 3: JSON extraction
echo "Test 3: Extracting JSON from output..."
if bash "$PROJECT_ROOT/src/utils/invoke-agent.sh" extract-json \
    "$TEST_DIR/output.txt" \
    "$TEST_DIR/extracted.json"; then
    echo "✅ Pass: JSON extracted successfully"
else
    echo "❌ Fail: JSON extraction failed"
    rm -rf "$TEST_DIR"
    exit 1
fi
echo ""

# Test 4: JSON validation
echo "Test 4: Validating extracted JSON..."
if jq -e '.tasks | length > 0' "$TEST_DIR/extracted.json" >/dev/null 2>&1; then
    echo "✅ Pass: JSON is valid and contains tasks"
    TASK_COUNT=$(jq '.tasks | length' "$TEST_DIR/extracted.json")
    echo "   Found $TASK_COUNT tasks"
else
    echo "❌ Fail: JSON validation failed"
    cat "$TEST_DIR/extracted.json"
    rm -rf "$TEST_DIR"
    exit 1
fi
echo ""

# Cleanup
rm -rf "$TEST_DIR"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           All Tests Passed! ✅                            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Agent invocation system is operational."
echo ""

