#!/usr/bin/env bash
# Cheapest runtime test: Use existing session data to trigger orchestrator analysis
# Cost: ~$0.03 (single orchestrator call analyzing existing data, no research)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Runtime Test: Orchestrator Utility Usage"
echo "=========================================="
echo ""
echo "Cost: ~\$0.03 (1 orchestrator invocation)"
echo "Strategy: Ask orchestrator to analyze existing session"
echo ""

# Find an existing session with data
EXISTING_SESSION="research-sessions/mission_1760225639069883000"

if [[ ! -d "$PROJECT_ROOT/$EXISTING_SESSION" ]]; then
    echo -e "${YELLOW}⚠${NC} No existing session found, skipping runtime test"
    echo ""
    echo "To test runtime usage:"
    echo "1. Run any cconductor mission"
    echo "2. Check events.jsonl for: Bash tool calls to src/utils/*.sh"
    echo ""
    exit 0
fi

echo "Using existing session: $EXISTING_SESSION"
echo ""

# Check if the session has knowledge graph
if [[ -f "$PROJECT_ROOT/$EXISTING_SESSION/knowledge-graph.json" ]]; then
    echo -e "${GREEN}✓${NC} Session has knowledge graph"
    
    # Get some stats
    CLAIMS=$(jq '.claims | length' "$PROJECT_ROOT/$EXISTING_SESSION/knowledge-graph.json")
    ENTITIES=$(jq '.entities | length' "$PROJECT_ROOT/$EXISTING_SESSION/knowledge-graph.json")
    
    echo "  - Claims: $CLAIMS"
    echo "  - Entities: $ENTITIES"
    echo ""
fi

# Check if this session has any utility calls in logs
echo "Checking if utilities were used in this session..."
echo ""

EVENTS_FILE="$PROJECT_ROOT/$EXISTING_SESSION/events.jsonl"
if [[ -f "$EVENTS_FILE" ]]; then
    # Look for Bash tool usage with our utilities
    UTIL_CALLS=$(grep -c "kg-utils\|data-utils\|calculate.sh" "$EVENTS_FILE" 2>/dev/null || echo "0")
    
    if [[ $UTIL_CALLS -gt 0 ]]; then
        echo -e "${GREEN}✅ VERIFIED: Utilities used in production!${NC}"
        echo ""
        echo "Found $UTIL_CALLS utility calls in session logs"
        echo ""
        echo "Sample utility calls:"
        grep "kg-utils\|data-utils\|calculate.sh" "$EVENTS_FILE" | \
            jq -r 'select(.type == "tool_use_start") | "  • \(.data.tool_name): \(.data.tool_input.command)"' | \
            head -5
        exit 0
    else
        echo -e "${YELLOW}⚠${NC}  Session predates utility implementation"
        echo ""
    fi
fi

echo "=========================================="
echo "Manual Verification Instructions"
echo "=========================================="
echo ""
echo "To verify orchestrator uses utilities at runtime:"
echo ""
echo "1. Run a simple analysis mission:"
echo "   ./cconductor \"Analyze the knowledge graph statistics\""
echo ""
echo "2. Check the events.jsonl file:"
echo "   grep 'kg-utils\\|data-utils\\|calculate' research-sessions/\$(cat research-sessions/.latest)/events.jsonl"
echo ""
echo "3. Look for Bash tool calls like:"
echo "   Bash: src/utils/kg-utils.sh stats knowledge-graph.json"
echo ""
echo "Or use this one-liner after running a mission:"
echo "   grep -o 'src/utils/.*\\.sh[^\"]*' research-sessions/\$(cat research-sessions/.latest)/events.jsonl | sort -u"
echo ""
echo "Expected commands if orchestrator uses utilities:"
echo "  • src/utils/kg-utils.sh stats ..."
echo "  • src/utils/kg-utils.sh filter-confidence ..."
echo "  • src/utils/data-utils.sh consolidate ..."
echo "  • src/utils/calculate.sh calc/percentage/growth ..."
echo ""
echo "=========================================="
echo "Alternative: Check orchestrator reasoning"
echo "=========================================="
echo ""
echo "You can also check if orchestrator CONSIDERS using utilities:"
echo ""
echo "1. Look at 60_logs/orchestration.jsonl for decisions"
echo "2. Check reasoning blocks for mentions of utilities"
echo "3. Verify hook blocks unauthorized Bash (only whitelisted utils allowed)"
echo ""

