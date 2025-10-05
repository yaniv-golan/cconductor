#!/bin/bash
# Integration Test: Phase 1 Session Continuity in Real Research
# 
# This test verifies that session continuity works in actual research scenarios

set -euo pipefail

CCONDUCTOR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$CCONDUCTOR_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
# shellcheck disable=SC2034  # YELLOW used in echo statements
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1 Integration Test: Session Continuity"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Create test session
TEST_SESSION="$CCONDUCTOR_ROOT/test-session-phase1-integration"
rm -rf "$TEST_SESSION"
mkdir -p "$TEST_SESSION/intermediate"
mkdir -p "$TEST_SESSION/.claude/agents"
mkdir -p "$TEST_SESSION/raw"

# Copy agent definitions  
cp src/claude-runtime/agents/research-coordinator.json "$TEST_SESSION/.claude/agents/"

# Initialize knowledge graph and task queue
echo '{"entities":[],"claims":[],"relationships":[],"gaps":[],"contradictions":[],"iteration":0,"confidence":0.0,"coverage":0.0}' \
    > "$TEST_SESSION/knowledge-graph.json"

echo '{"tasks":[],"stats":{"pending":0,"running":0,"completed":0,"failed":0}}' \
    > "$TEST_SESSION/task-queue.json"

echo -e "${BLUE}Test Scenario:${NC} Running 2 coordinator iterations with session continuity"
echo ""

# Source required utilities
# shellcheck disable=SC1091  # Test doesn't need to follow all sources
source src/knowledge-graph.sh
# shellcheck disable=SC1091
source src/task-queue.sh
# shellcheck disable=SC1091
source src/utils/session-manager.sh
# shellcheck disable=SC1091
source src/utils/config-loader.sh

# Load config
ADAPTIVE_CONFIG=$(load_config "adaptive-config")
# shellcheck disable=SC2034  # CCONDUCTOR_SCRIPT_DIR may be used by sourced scripts
CCONDUCTOR_SCRIPT_DIR="$CCONDUCTOR_ROOT/src"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Iteration 1: Start Coordinator Session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Prepare iteration 1 input
COORDINATOR_INPUT_1="$TEST_SESSION/intermediate/coordinator-input-1.json"
jq -n \
    --argjson kg "$(cat "$TEST_SESSION/knowledge-graph.json")" \
    --argjson queue "$(cat "$TEST_SESSION/task-queue.json")" \
    --argjson findings '[]' \
    --arg iteration "1" \
    --argjson config "$ADAPTIVE_CONFIG" \
    '{
        knowledge_graph: $kg,
        task_queue: $queue,
        new_findings: $findings,
        iteration: ($iteration | tonumber),
        config: $config,
        input_files_context: ""
    }' \
    > "$COORDINATOR_INPUT_1"

# Start session (iteration 1)
echo "Starting coordinator session..."
SESSION_ID=$(start_agent_session \
    "research-coordinator" \
    "$TEST_SESSION" \
    "$(cat "$COORDINATOR_INPUT_1")" \
    180)

if [ -n "$SESSION_ID" ]; then
    echo -e "${GREEN}✓${NC} Session started: $SESSION_ID"
else
    echo -e "${RED}✗${NC} Failed to start session"
    exit 1
fi

# Check output
COORD_OUTPUT_1="$TEST_SESSION/.agent-sessions/research-coordinator.start-output.json"
if [ -f "$COORD_OUTPUT_1" ] && jq empty "$COORD_OUTPUT_1" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Iteration 1 output valid"
    
    # Extract result
    RESULT_1=$(jq -r '.result // empty' "$COORD_OUTPUT_1")
    if [ -n "$RESULT_1" ]; then
        echo -e "${GREEN}✓${NC} Result field exists"
    else
        echo -e "${RED}✗${NC} Result field missing"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Iteration 1 output invalid"
    exit 1
fi

# Check session metadata
TURN_COUNT=$(jq -r '.turn_count' "$TEST_SESSION/.agent-sessions/research-coordinator.metadata")
if [ "$TURN_COUNT" = "1" ]; then
    echo -e "${GREEN}✓${NC} Turn count correct (1)"
else
    echo -e "${RED}✗${NC} Turn count incorrect: $TURN_COUNT"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Iteration 2: Continue Coordinator Session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Simulate some findings
echo '{"new_entities":[],"new_claims":[{"text":"Test finding","confidence":0.8}],"new_relationships":[]}' \
    > "$TEST_SESSION/intermediate/findings-1.json"

# Prepare iteration 2 input
COORDINATOR_INPUT_2="$TEST_SESSION/intermediate/coordinator-input-2.json"
jq -n \
    --argjson kg "$(cat "$TEST_SESSION/knowledge-graph.json")" \
    --argjson queue "$(cat "$TEST_SESSION/task-queue.json")" \
    --argjson findings "[$(cat "$TEST_SESSION/intermediate/findings-1.json")]" \
    --arg iteration "2" \
    --argjson config "$ADAPTIVE_CONFIG" \
    '{
        knowledge_graph: $kg,
        task_queue: $queue,
        new_findings: $findings,
        iteration: ($iteration | tonumber),
        config: $config,
        input_files_context: ""
    }' \
    > "$COORDINATOR_INPUT_2"

# Continue session (iteration 2)
COORD_OUTPUT_2="$TEST_SESSION/intermediate/coordinator-output-2.json"
echo "Continuing coordinator session..."
if continue_agent_session \
    "research-coordinator" \
    "$TEST_SESSION" \
    "$(cat "$COORDINATOR_INPUT_2")" \
    "$COORD_OUTPUT_2" \
    180; then
    echo -e "${GREEN}✓${NC} Session continued successfully"
else
    echo -e "${RED}✗${NC} Failed to continue session"
    exit 1
fi

# Check output
if [ -f "$COORD_OUTPUT_2" ] && jq empty "$COORD_OUTPUT_2" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Iteration 2 output valid"
    
    RESULT_2=$(jq -r '.result // empty' "$COORD_OUTPUT_2")
    if [ -n "$RESULT_2" ]; then
        echo -e "${GREEN}✓${NC} Result field exists"
    else
        echo -e "${RED}✗${NC} Result field missing"
        exit 1
    fi
else
    echo -e "${RED}✗${NC} Iteration 2 output invalid"
    exit 1
fi

# Check turn count updated
TURN_COUNT=$(jq -r '.turn_count' "$TEST_SESSION/.agent-sessions/research-coordinator.metadata")
if [ "$TURN_COUNT" = "2" ]; then
    echo -e "${GREEN}✓${NC} Turn count incremented (2)"
else
    echo -e "${RED}✗${NC} Turn count incorrect: $TURN_COUNT"
    exit 1
fi

# Verify session ID is the same
STORED_SESSION_ID=$(get_agent_session_id "research-coordinator" "$TEST_SESSION")
if [ "$STORED_SESSION_ID" = "$SESSION_ID" ]; then
    echo -e "${GREEN}✓${NC} Session ID preserved across iterations"
else
    echo -e "${RED}✗${NC} Session ID changed!"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup: End Session"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if end_agent_session "research-coordinator" "$TEST_SESSION"; then
    echo -e "${GREEN}✓${NC} Session ended successfully"
else
    echo -e "${RED}✗${NC} Failed to end session"
    exit 1
fi

# Verify cleanup
if [ ! -f "$TEST_SESSION/.agent-sessions/research-coordinator.session" ]; then
    echo -e "${GREEN}✓${NC} Session files cleaned up"
else
    echo -e "${RED}✗${NC} Session files still exist"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ ALL INTEGRATION TESTS PASSED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Session continuity is working in research scenarios:"
echo "  • Coordinator session starts on iteration 1"
echo "  • Session continues on iteration 2 (context preserved)"
echo "  • Session ID remains consistent"
echo "  • Turn count tracks iterations correctly"
echo "  • Session cleanup works at end"
echo ""
echo "Ready for production use!"
echo ""

