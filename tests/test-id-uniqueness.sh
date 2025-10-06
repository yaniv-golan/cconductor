#!/usr/bin/env bash
# Test: ID Uniqueness After Deletions
# Verifies that entity/task IDs remain unique even after deletions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test: ID Uniqueness After Deletions                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Source required modules
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/task-queue.sh"

# Create test session
TEST_SESSION="$PROJECT_ROOT/research-sessions/test_id_uniqueness_$$"
mkdir -p "$TEST_SESSION"

echo "→ Testing Task ID Uniqueness..."
echo ""

# Initialize task queue
tq_init "$TEST_SESSION" >/dev/null

# Add 5 tasks
for i in {1..5}; do
    task_id=$(tq_add_task "$TEST_SESSION" "{\"type\": \"test\", \"query\": \"Task $i\"}")
    echo "  Created task: $task_id"
done

# Get all task IDs
all_ids=$(tq_read "$TEST_SESSION" | jq -r '.tasks[].id')
echo ""
echo "  Initial task IDs: $(echo "$all_ids" | tr '\n' ' ')"

# Manually delete task t2 and t3 from the queue (simulating deletion)
echo ""
echo "→ Simulating task deletions (t2, t3)..."
jq '.tasks |= map(select(.id != "t2" and .id != "t3")) | 
    .stats.total_tasks = (.tasks | length) |
    .stats.pending = ([.tasks[] | select(.status == "pending")] | length)' \
    "$TEST_SESSION/task-queue.json" > "$TEST_SESSION/task-queue.json.tmp"
mv "$TEST_SESSION/task-queue.json.tmp" "$TEST_SESSION/task-queue.json"

remaining=$(tq_read "$TEST_SESSION" | jq -r '.tasks[].id' | tr '\n' ' ')
echo "  Remaining tasks: $remaining"

# Add 3 more tasks (should get IDs t5, t6, t7 not t2, t3)
echo ""
echo "→ Adding new tasks after deletion..."
new_ids=()
for i in {6..8}; do
    task_id=$(tq_add_task "$TEST_SESSION" "{\"type\": \"test\", \"query\": \"Task $i\"}")
    new_ids+=("$task_id")
    echo "  Created task: $task_id"
done

# Check for duplicates
echo ""
echo "→ Checking for duplicate task IDs..."
all_final_ids=$(tq_read "$TEST_SESSION" | jq -r '.tasks[].id')
unique_count=$(echo "$all_final_ids" | sort -u | wc -l | xargs)
total_count=$(echo "$all_final_ids" | wc -l | xargs)

if [ "$unique_count" -eq "$total_count" ]; then
    echo "  ✓ All task IDs are unique"
    task_result=0
else
    echo "  ✗ Found duplicate task IDs!"
    echo "  All IDs: $(echo "$all_final_ids" | tr '\n' ' ')"
    task_result=1
fi

echo ""
echo "→ Testing Entity ID Uniqueness..."
echo ""

# Initialize knowledge graph
kg_init "$TEST_SESSION" "Test query" >/dev/null

# Create coordinator output with entities
cat > "$TEST_SESSION/test-entities.json" <<EOF
{
  "entities_discovered": [
    {"name": "Entity 1", "type": "test"},
    {"name": "Entity 2", "type": "test"},
    {"name": "Entity 3", "type": "test"}
  ],
  "claims": [],
  "relationships_discovered": [],
  "gaps_detected": [],
  "contradictions_detected": [],
  "leads_identified": [],
  "citations": []
}
EOF

# Add entities via bulk update
kg_bulk_update "$TEST_SESSION" "$TEST_SESSION/test-entities.json" >/dev/null
entity_ids=$(kg_read "$TEST_SESSION" | jq -r '.entities[].id' | tr '\n' ' ')
echo "  Initial entity IDs: $entity_ids"

# Manually delete entity e1 (simulating deletion)
echo ""
echo "→ Simulating entity deletion (e1)..."
jq '.entities |= map(select(.id != "e1")) |
    .stats.total_entities = (.entities | length)' \
    "$TEST_SESSION/knowledge-graph.json" > "$TEST_SESSION/knowledge-graph.json.tmp"
mv "$TEST_SESSION/knowledge-graph.json.tmp" "$TEST_SESSION/knowledge-graph.json"

remaining_entities=$(kg_read "$TEST_SESSION" | jq -r '.entities[].id' | tr '\n' ' ')
echo "  Remaining entities: $remaining_entities"

# Add more entities (should get e3, e4 not e1)
echo ""
echo "→ Adding new entities after deletion..."
cat > "$TEST_SESSION/test-entities2.json" <<EOF
{
  "entities_discovered": [
    {"name": "Entity 4", "type": "test"},
    {"name": "Entity 5", "type": "test"}
  ],
  "claims": [],
  "relationships_discovered": [],
  "gaps_detected": [],
  "contradictions_detected": [],
  "leads_identified": [],
  "citations": []
}
EOF

kg_bulk_update "$TEST_SESSION" "$TEST_SESSION/test-entities2.json" >/dev/null
all_entity_ids=$(kg_read "$TEST_SESSION" | jq -r '.entities[].id')
echo "  New entity IDs: $(echo "$all_entity_ids" | tr '\n' ' ')"

# Check for duplicates
echo ""
echo "→ Checking for duplicate entity IDs..."
unique_entity_count=$(echo "$all_entity_ids" | sort -u | wc -l | xargs)
total_entity_count=$(echo "$all_entity_ids" | wc -l | xargs)

if [ "$unique_entity_count" -eq "$total_entity_count" ]; then
    echo "  ✓ All entity IDs are unique"
    entity_result=0
else
    echo "  ✗ Found duplicate entity IDs!"
    echo "  All IDs: $(echo "$all_entity_ids" | tr '\n' ' ')"
    entity_result=1
fi

# Cleanup
rm -rf "$TEST_SESSION"

echo ""
if [ $task_result -eq 0 ] && [ $entity_result -eq 0 ]; then
    echo "✅ TEST PASSED: All IDs remain unique after deletions"
    exit 0
else
    echo "❌ TEST FAILED: Duplicate IDs detected"
    exit 1
fi

