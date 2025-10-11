#!/usr/bin/env bash
# Test Knowledge Graph Artifact Processor
# Tests validation, merging, and error handling

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/kg-artifact-processor.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/verbose.sh" 2>/dev/null || true

echo "═══════════════════════════════════════════════════════"
echo "  KG Artifact Processor Test Suite"
echo "═══════════════════════════════════════════════════════"
echo ""

# Create test session
TEST_SESSION="$PROJECT_ROOT/test-kg-artifacts-$$"
mkdir -p "$TEST_SESSION"

cleanup() {
    rm -rf "$TEST_SESSION"
}
trap cleanup EXIT

# Test 1: Valid artifacts
echo "Test 1: Valid Artifacts"
echo "────────────────────────────────────────────────────────"

# Create test KG
cat > "$TEST_SESSION/knowledge-graph.json" <<'EOF'
{
  "research_question": "Test",
  "entities": [],
  "claims": []
}
EOF

# Create test artifacts
mkdir -p "$TEST_SESSION/artifacts/test-agent"
cat > "$TEST_SESSION/artifacts/test-agent/completion.json" <<'EOF'
{
  "completed_at": "2025-10-11T19:30:00Z",
  "status": "success"
}
EOF

cat > "$TEST_SESSION/artifacts/test-agent/data.json" <<'EOF'
{
  "items_processed": 42,
  "confidence": 0.85
}
EOF

# Create lockfile
touch "$TEST_SESSION/test-agent.kg.lock"

# Process
echo "Processing artifacts..."
if process_kg_artifacts "$TEST_SESSION" "test-agent"; then
    echo "✓ Processing succeeded"
else
    echo "✗ Processing failed"
    exit 1
fi

# Verify lockfile removed
if [ ! -f "$TEST_SESSION/test-agent.kg.lock" ]; then
    echo "✓ Lockfile removed"
else
    echo "✗ Lockfile still exists"
    exit 1
fi

# Verify merge
if jq -e '.["test-agent"]' "$TEST_SESSION/knowledge-graph.json" >/dev/null; then
    echo "✓ Artifacts merged into KG"
    echo "  Merged content:"
    jq -C '.["test-agent"]' "$TEST_SESSION/knowledge-graph.json" | sed 's/^/    /'
else
    echo "✗ Artifacts not found in KG"
    exit 1
fi

echo ""

# Test 2: Invalid JSON
echo "Test 2: Invalid JSON (Error Handling)"
echo "────────────────────────────────────────────────────────"

# Create invalid artifacts
mkdir -p "$TEST_SESSION/artifacts/bad-agent"
echo "invalid json" > "$TEST_SESSION/artifacts/bad-agent/bad.json"
touch "$TEST_SESSION/bad-agent.kg.lock"

echo "Processing invalid artifacts..."
if process_kg_artifacts "$TEST_SESSION" "bad-agent"; then
    echo "✗ Should have failed but succeeded"
    exit 1
else
    echo "✓ Processing correctly failed"
fi

# Verify lockfile renamed
if [ -f "$TEST_SESSION/bad-agent.kg.lock.error" ]; then
    echo "✓ Lockfile renamed to .error"
else
    echo "✗ Lockfile not renamed"
    exit 1
fi

# Verify retry instructions created
if [ -f "$TEST_SESSION/bad-agent.retry-instructions.json" ]; then
    echo "✓ Retry instructions created"
    echo "  Instructions:"
    jq -C '.instructions[]' "$TEST_SESSION/bad-agent.retry-instructions.json" | sed 's/^/    /'
else
    echo "✗ Retry instructions not created"
    exit 1
fi

echo ""

# Test 3: Oversized file
echo "Test 3: Oversized File (>64KB)"
echo "────────────────────────────────────────────────────────"

mkdir -p "$TEST_SESSION/artifacts/big-agent"
# Create a file larger than 64KB
dd if=/dev/zero of="$TEST_SESSION/artifacts/big-agent/big.json" bs=1024 count=65 2>/dev/null
# Make it valid JSON
echo '{"data":"' > "$TEST_SESSION/artifacts/big-agent/big.json"
head -c 70000 /dev/zero | base64 >> "$TEST_SESSION/artifacts/big-agent/big.json"
echo '"}' >> "$TEST_SESSION/artifacts/big-agent/big.json"
touch "$TEST_SESSION/big-agent.kg.lock"

echo "Processing oversized artifacts..."
if process_kg_artifacts "$TEST_SESSION" "big-agent"; then
    echo "✗ Should have failed but succeeded"
    exit 1
else
    echo "✓ Processing correctly failed for oversized file"
fi

if [ -f "$TEST_SESSION/big-agent.kg.lock.error" ]; then
    echo "✓ Lockfile renamed to .error"
else
    echo "✗ Lockfile not renamed"
    exit 1
fi

echo ""

# Test 4: No artifacts (normal case)
echo "Test 4: No Lockfile (Normal Case)"
echo "────────────────────────────────────────────────────────"

echo "Processing without lockfile..."
if process_kg_artifacts "$TEST_SESSION" "nonexistent-agent"; then
    echo "✓ Processing succeeded (no-op)"
else
    echo "✗ Processing failed unexpectedly"
    exit 1
fi

echo ""

# Test 5: Validation function directly
echo "Test 5: Direct Validation"
echo "────────────────────────────────────────────────────────"

mkdir -p "$TEST_SESSION/artifacts/validate-test"
cat > "$TEST_SESSION/artifacts/validate-test/valid.json" <<'EOF'
{"test": "data"}
EOF

if validate_artifact_metadata "$TEST_SESSION" "validate-test"; then
    echo "✓ Validation succeeded for valid artifacts"
else
    echo "✗ Validation failed for valid artifacts"
    exit 1
fi

# Test invalid case
echo "invalid" > "$TEST_SESSION/artifacts/validate-test/invalid.json"
if validate_artifact_metadata "$TEST_SESSION" "validate-test"; then
    echo "✗ Validation should have failed"
    exit 1
else
    echo "✓ Validation correctly failed for invalid JSON"
fi

echo ""

# Summary
echo "═══════════════════════════════════════════════════════"
echo "  ✅ All Tests Passed!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✓ Valid artifacts processed and merged correctly"
echo "  ✓ Invalid JSON handled with error and retry instructions"
echo "  ✓ Oversized files rejected"
echo "  ✓ No lockfile case handled gracefully"
echo "  ✓ Direct validation function works correctly"
echo ""

