#!/usr/bin/env bash
# Test: Agent Failure Task Status Updates
# Verifies that tasks are marked as failed when agents fail

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Test: Agent Failure Task Status Updates                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Source required modules
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/task-queue.sh"

# Create test session
TEST_SESSION="$PROJECT_ROOT/research-sessions/test_agent_failure_$$"
mkdir -p "$TEST_SESSION"
mkdir -p "$TEST_SESSION/raw"

echo "→ Setting up test session..."

# Initialize task queue
tq_init "$TEST_SESSION" >/dev/null

# Add test tasks
echo ""
echo "→ Creating test tasks..."
task1=$(tq_add_task "$TEST_SESSION" '{"type": "research", "agent": "test-agent", "query": "Test 1", "priority": 5}')
task2=$(tq_add_task "$TEST_SESSION" '{"type": "research", "agent": "test-agent", "query": "Test 2", "priority": 5}')
echo "  Created tasks: $task1, $task2"

# Mark tasks as in progress
echo ""
echo "→ Marking tasks as in_progress..."
tq_start_task "$TEST_SESSION" "$task1"
tq_start_task "$TEST_SESSION" "$task2"

# Verify they are in progress
in_progress_count=$(tq_read "$TEST_SESSION" | jq '[.tasks[] | select(.status == "in_progress")] | length')
echo "  Tasks in_progress: $in_progress_count"

if [ "$in_progress_count" -ne 2 ]; then
    echo "  ✗ Expected 2 in_progress tasks, got $in_progress_count"
    rm -rf "$TEST_SESSION"
    exit 1
fi

# Simulate agent failure by marking tasks as failed
echo ""
echo "→ Simulating agent failure (marking tasks as failed)..."
tq_fail_task "$TEST_SESSION" "$task1" "Agent test-agent failed to execute"
tq_fail_task "$TEST_SESSION" "$task2" "Agent test-agent failed to execute"

# Check results
echo ""
echo "→ Checking task statuses after failure..."

failed_count=$(tq_read "$TEST_SESSION" | jq '[.tasks[] | select(.status == "failed")] | length')
in_progress_after=$(tq_read "$TEST_SESSION" | jq '[.tasks[] | select(.status == "in_progress")] | length')

echo "  Failed tasks: $failed_count"
echo "  In_progress tasks: $in_progress_after"

# Verify error messages are stored
task1_error=$(tq_read "$TEST_SESSION" | jq -r --arg id "$task1" '.tasks[] | select(.id == $id) | .error')
task2_error=$(tq_read "$TEST_SESSION" | jq -r --arg id "$task2" '.tasks[] | select(.id == $id) | .error')

echo ""
echo "→ Checking error messages..."
echo "  Task $task1 error: $task1_error"
echo "  Task $task2 error: $task2_error"

# Cleanup
rm -rf "$TEST_SESSION"

echo ""
if [ "$failed_count" -eq 2 ] && [ "$in_progress_after" -eq 0 ]; then
    if [[ "$task1_error" == *"failed"* ]] && [[ "$task2_error" == *"failed"* ]]; then
        echo "✅ TEST PASSED: Agent failures properly update task status"
        exit 0
    else
        echo "❌ TEST FAILED: Error messages not stored correctly"
        exit 1
    fi
else
    echo "❌ TEST FAILED: Task statuses not updated correctly"
    echo "   Expected: 2 failed, 0 in_progress"
    echo "   Got: $failed_count failed, $in_progress_after in_progress"
    exit 1
fi

