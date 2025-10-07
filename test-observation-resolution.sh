#!/usr/bin/env bash
# Test observation resolution logic

set -euo pipefail

PROJECT_ROOT="/Users/yaniv/Library/Mobile Documents/com~apple~CloudDocs/Documents/code/delve"
SESSION_DIR="$PROJECT_ROOT/research-sessions/session_1759842915552654000"

echo "════════════════════════════════════════════════════════════"
echo "Testing Observation Resolution Logic"
echo "════════════════════════════════════════════════════════════"
echo ""

# Test 1: Check current observations
echo "=== Test 1: Current System Observations ==="
echo ""
echo "System observations in events.jsonl:"
grep '"type":"system_observation"' "$SESSION_DIR/events.jsonl" | jq -r '.data | {component, observation: .observation[0:80]}' | head -5
echo ""

# Test 2: Check knowledge graph state
echo "=== Test 2: Current Knowledge Graph State ==="
echo ""
jq -r '.stats | "Entities: \(.total_entities), Claims: \(.total_claims), Relationships: \(.total_relationships)"' "$SESSION_DIR/knowledge-graph.json"
echo ""

# Test 3: Manually trigger validation logic
echo "=== Test 3: Simulating Validation Logic ==="
echo ""

# Extract observations
observations=$(grep '"type":"system_observation"' "$SESSION_DIR/events.jsonl" | jq -s '.')

# Check if "empty" observation should be resolved
echo "Checking for 'empty knowledge graph' observations..."
echo "$observations" | jq -r '.[] | select(.data.observation | contains("empty")) | {component: .data.component, severity: .data.severity, observation: (.data.observation[0:100])}'
echo ""

# Check current KG stats
entities=$(jq '.stats.total_entities // 0' "$SESSION_DIR/knowledge-graph.json")
claims=$(jq '.stats.total_claims // 0' "$SESSION_DIR/knowledge-graph.json")

echo "Current KG stats: $entities entities, $claims claims"
echo ""

if [ "$entities" -gt 0 ] || [ "$claims" -gt 0 ]; then
    echo "✓ Validation Result: 'Empty graph' observations SHOULD BE RESOLVED"
    echo "  Resolution: Knowledge graph populated with $entities entities and $claims claims"
else
    echo "✗ Validation Result: Knowledge graph is still empty"
fi
echo ""

# Test 4: Check for existing resolution events
echo "=== Test 4: Existing Resolution Events ==="
echo ""
resolution_count=$(grep -c '"type":"observation_resolved"' "$SESSION_DIR/events.jsonl" 2>/dev/null || echo "0")
echo "Found $resolution_count observation_resolved events"

if [ "$resolution_count" -gt 0 ]; then
    echo ""
    echo "Resolution events:"
    grep '"type":"observation_resolved"' "$SESSION_DIR/events.jsonl" | jq -r '.data | {component: .original_observation.component, resolution}'
fi
echo ""

# Test 5: Test dashboard metrics filtering
echo "=== Test 5: Dashboard Metrics Observation Filtering ==="
echo ""
cd "$PROJECT_ROOT"
# shellcheck disable=SC1091
source src/utils/dashboard-metrics.sh

# Run the observation filtering logic
filtered_observations=$(cat "$SESSION_DIR/events.jsonl" 2>/dev/null | \
    jq -s '
        # Get all observations
        (map(select(.type == "system_observation"))) as $all_obs |
        # Get all resolved observation components+text to filter out
        (map(select(.type == "observation_resolved") | 
            .data.original_observation | 
            {component: .component, observation: .observation})) as $resolved |
        # Filter: keep only observations NOT in resolved list
        $all_obs | map(
            . as $obs |
            select(
                ($resolved | map(
                    (.component == $obs.data.component and .observation == $obs.data.observation)
                ) | any) | not
            )
        ) | .[-20:] | reverse
    ' 2>/dev/null || echo '[]')

obs_count=$(echo "$filtered_observations" | jq 'length')
echo "Filtered observations count: $obs_count"

if [ "$obs_count" -gt 0 ]; then
    echo ""
    echo "Remaining unresolved observations:"
    echo "$filtered_observations" | jq -r '.[] | {component: .data.component, severity: .data.severity, observation: (.data.observation[0:80])}'
fi
echo ""

echo "════════════════════════════════════════════════════════════"
echo "Test Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Current state:"
echo "  • Knowledge graph: $entities entities, $claims claims"
echo "  • Resolution events: $resolution_count"
echo "  • Unresolved observations shown in dashboard: $obs_count"
echo ""

if [ "$resolution_count" -eq 0 ] && [ "$entities" -gt 0 ]; then
    echo "⚠️  Fix needs to be applied to this session"
    echo "   Resolution logic will work on NEXT coordinator run"
    echo ""
    echo "To apply fix to THIS session:"
    echo "  1. Re-run dashboard metrics generation"
    echo "  2. Or manually log resolution event"
elif [ "$obs_count" -eq 0 ]; then
    echo "✓ All observations resolved - dashboard should be clean!"
else
    echo "ℹ️  $obs_count observations remain (may be legitimate issues)"
fi
echo ""
