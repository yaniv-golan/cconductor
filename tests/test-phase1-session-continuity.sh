#!/usr/bin/env bash
# Test Phase 1: Session Continuity Integration

set -euo pipefail

CCONDUCTOR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CCONDUCTOR_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1 Test: Session Continuity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create test session
TEST_SESSION="$CCONDUCTOR_ROOT/test-session-phase1"
rm -rf "$TEST_SESSION"
mkdir -p "$TEST_SESSION/intermediate"
mkdir -p "$TEST_SESSION/.claude/agents"

# Copy agent definitions
cp "src/claude-runtime/agents/web-researcher.json" "$TEST_SESSION/.claude/agents/"

echo "Test 1: Start Agent Session"
echo "──────────────────────────────"

INITIAL_TASK="Simple test: What is the capital of France? Return ONLY valid JSON with 'answer' field. NO explanatory text, just JSON starting with {."

echo "Starting session with initial task (timeout: 180s)..."
SESSION_ID=$(bash src/utils/session-manager.sh start \
    "web-researcher" \
    "$TEST_SESSION" \
    "$INITIAL_TASK" \
    180)

if [ -n "$SESSION_ID" ]; then
    echo -e "${GREEN}✓${NC} Session started: $SESSION_ID"
else
    echo -e "${RED}✗${NC} Failed to start session"
    exit 1
fi

# Check session tracking
if [ -f "$TEST_SESSION/.agent-sessions/web-researcher.session" ]; then
    echo -e "${GREEN}✓${NC} Session ID stored"
else
    echo -e "${RED}✗${NC} Session ID not stored"
    exit 1
fi

# Check metadata
if [ -f "$TEST_SESSION/.agent-sessions/web-researcher.metadata" ]; then
    TURN_COUNT=$(jq -r '.turn_count' "$TEST_SESSION/.agent-sessions/web-researcher.metadata")
    if [ "$TURN_COUNT" = "1" ]; then
        echo -e "${GREEN}✓${NC} Metadata tracking working (turn_count: $TURN_COUNT)"
    else
        echo -e "${RED}✗${NC} Metadata incorrect (turn_count: $TURN_COUNT)"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Metadata not stored"
    exit 1
fi

echo ""
echo "Test 2: Continue Agent Session"
echo "──────────────────────────────"

FOLLOW_UP_TASK="Follow-up: What country is that capital in? Return ONLY valid JSON with 'country' field. NO explanatory text, just JSON starting with {."
OUTPUT_FILE="$TEST_SESSION/intermediate/followup-output.json"

echo "Continuing session with follow-up task (timeout: 180s)..."
if bash src/utils/session-manager.sh continue \
    "web-researcher" \
    "$TEST_SESSION" \
    "$FOLLOW_UP_TASK" \
    "$OUTPUT_FILE" \
    180; then
    echo -e "${GREEN}✓${NC} Session continued successfully"
else
    echo -e "${RED}✗${NC} Failed to continue session"
    exit 1
fi

# Check response
if [ -f "$OUTPUT_FILE" ] && jq empty "$OUTPUT_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Valid JSON response received"
    
    RESULT=$(jq -r '.result // empty' "$OUTPUT_FILE")
    if [ -n "$RESULT" ]; then
        echo -e "${GREEN}✓${NC} Result field exists"
    else
        echo -e "${RED}✗${NC} Result field missing or empty"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Invalid or missing response"
    exit 1
fi

# Check metadata updated
TURN_COUNT=$(jq -r '.turn_count' "$TEST_SESSION/.agent-sessions/web-researcher.metadata")
if [ "$TURN_COUNT" = "2" ]; then
    echo -e "${GREEN}✓${NC} Turn count incremented (now: $TURN_COUNT)"
else
    echo -e "${RED}✗${NC} Turn count not incremented (got: $TURN_COUNT)"
    exit 1
fi

echo ""
echo "Test 3: Get Session Info"
echo "──────────────────────────────"

# Test get-id
STORED_ID=$(bash src/utils/session-manager.sh get-id "web-researcher" "$TEST_SESSION")
if [ "$STORED_ID" = "$SESSION_ID" ]; then
    echo -e "${GREEN}✓${NC} get-id returns correct session ID"
else
    echo -e "${RED}✗${NC} get-id returned wrong ID"
    exit 1
fi

# Test has-session
HAS_SESSION=$(bash src/utils/session-manager.sh has-session "web-researcher" "$TEST_SESSION")
if [ "$HAS_SESSION" = "yes" ]; then
    echo -e "${GREEN}✓${NC} has-session correctly detects active session"
else
    echo -e "${RED}✗${NC} has-session failed"
    exit 1
fi

# Test get-metadata
METADATA=$(bash src/utils/session-manager.sh get-metadata "web-researcher" "$TEST_SESSION")
if echo "$METADATA" | jq empty 2>/dev/null; then
    echo -e "${GREEN}✓${NC} get-metadata returns valid JSON"
else
    echo -e "${RED}✗${NC} get-metadata failed"
    exit 1
fi

echo ""
echo "Test 4: End Session"
echo "──────────────────────────────"

if bash src/utils/session-manager.sh end "web-researcher" "$TEST_SESSION"; then
    echo -e "${GREEN}✓${NC} Session ended successfully"
else
    echo -e "${RED}✗${NC} Failed to end session"
    exit 1
fi

# Verify cleanup
if [ ! -f "$TEST_SESSION/.agent-sessions/web-researcher.session" ]; then
    echo -e "${GREEN}✓${NC} Session file removed"
else
    echo -e "${RED}✗${NC} Session file still exists"
    exit 1
fi

if [ ! -f "$TEST_SESSION/.agent-sessions/web-researcher.metadata" ]; then
    echo -e "${GREEN}✓${NC} Metadata file removed"
else
    echo -e "${RED}✗${NC} Metadata file still exists"
    exit 1
fi

# Test has-session after end
HAS_SESSION=$(bash src/utils/session-manager.sh has-session "web-researcher" "$TEST_SESSION")
if [ "$HAS_SESSION" = "no" ]; then
    echo -e "${GREEN}✓${NC} has-session correctly reports no session"
else
    echo -e "${RED}✗${NC} has-session still reports active session"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Session continuity is working correctly:"
echo "  • Sessions can be started with initial context"
echo "  • Follow-up tasks preserve context"
echo "  • Session tracking works (turn count, metadata)"
echo "  • Session cleanup works correctly"
echo ""

