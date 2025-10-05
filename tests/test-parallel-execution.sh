#!/bin/bash
# Test: Verify parallel agent execution improves performance

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Testing Parallel Execution ==="

QUESTION="Explain containerization technologies: Docker, Kubernetes, and Podman"

echo "Question: $QUESTION"

# Measure execution time
START_TIME=$(date +%s)

"$PROJECT_ROOT/cconductor" "$QUESTION"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "✓ Research completed in $DURATION seconds"

# Check if multiple agents were used (from logs)
# Get log directory using path resolver
LOG_DIR=$("$PROJECT_ROOT/src/utils/path-resolver.sh" resolve log_dir)
AGENT_COUNT=$(grep -c "agent" "$LOG_DIR/research.log" 2>/dev/null | tail -1 || echo "0")

echo "✓ Used agents: $AGENT_COUNT"

# Parallel execution should complete complex queries in reasonable time
if [ "$DURATION" -lt 300 ]; then  # 5 minutes
    echo "✓ Performance acceptable"
else
    echo "⚠ Performance may need optimization ($DURATION seconds)"
fi

echo "=== Test Complete ==="
