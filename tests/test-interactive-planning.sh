#!/usr/bin/env bash
# Test interactive planning functionality

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "════════════════════════════════════════════════════════════"
echo "Testing Interactive Planning Functionality"
echo "════════════════════════════════════════════════════════════"
echo ""

# Test 1: Check that invoke-agent.sh has the new function
echo "Test 1: Checking invoke-agent.sh for interactive function..."
if grep -q "invoke_agent_interactive" "$PROJECT_ROOT/src/utils/invoke-agent.sh"; then
    echo "✓ invoke_agent_interactive function found"
else
    echo "✗ invoke_agent_interactive function NOT found"
    exit 1
fi
echo ""

# Test 2: Check that initial_planning uses allow_user_guidance
echo "Test 2: Checking initial_planning for interactive mode check..."
if grep -q "allow_user_guidance" "$PROJECT_ROOT/src/cconductor-adaptive.sh"; then
    echo "✓ allow_user_guidance check found in initial_planning"
else
    echo "✗ allow_user_guidance check NOT found"
    exit 1
fi
echo ""

# Test 3: Check default config has allow_user_guidance: true
echo "Test 3: Checking default config..."
allow_guidance=$(jq -r '.termination.allow_user_guidance' "$PROJECT_ROOT/config/adaptive-config.default.json")
if [ "$allow_guidance" = "true" ]; then
    echo "✓ Default config has allow_user_guidance: true"
else
    echo "✗ Default config has allow_user_guidance: $allow_guidance (expected: true)"
    exit 1
fi
echo ""

# Test 4: Check invoke-interactive is exported
echo "Test 4: Checking function exports..."
if grep -q "export -f invoke_agent_interactive" "$PROJECT_ROOT/src/utils/invoke-agent.sh"; then
    echo "✓ invoke_agent_interactive is exported"
else
    echo "✗ invoke_agent_interactive is NOT exported"
    exit 1
fi
echo ""

# Test 5: Check CLI interface includes invoke-interactive
echo "Test 5: Checking CLI interface..."
if grep -q "invoke-interactive)" "$PROJECT_ROOT/src/utils/invoke-agent.sh"; then
    echo "✓ invoke-interactive command available in CLI"
else
    echo "✗ invoke-interactive command NOT available in CLI"
    exit 1
fi
echo ""

echo "════════════════════════════════════════════════════════════"
echo "All Tests Passed! ✓"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Interactive planning is now available!"
echo ""
echo "To test with a real query:"
echo "  ./cconductor \"What is quantum computing?\""
echo ""
echo "Expected behavior:"
echo "  1. System shows: '→ Interactive planning mode enabled'"
echo "  2. Research planner presents its understanding"
echo "  3. Waits for your confirmation"
echo "  4. Creates tasks after confirmation"
echo ""



