#!/usr/bin/env bash
# Regression tests for web-researcher KG integration (manifest counts vs arrays)

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4.0 or higher is required to run this test." >&2
        exit 1
    fi
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
export PROJECT_ROOT

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"
# Ensure multi-argument validation helpers are active for tests
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/validation.sh"

TESTS_RUN=0
TESTS_FAILED=0
TEMP_DIRS=()

# shellcheck disable=SC2329
cleanup() {
    for dir in "${TEMP_DIRS[@]:-}"; do
        rm -rf "$dir" 2>/dev/null || true
    done
}
trap cleanup EXIT

test_case() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $1"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ $message"
    else
        echo "  ✗ $message (expected '$expected', got '$actual')" >&2
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

create_session() {
    local session_dir
    session_dir=$(mktemp -d "${TMPDIR:-/tmp}/kg-web-researcher.XXXXXX")
    TEMP_DIRS+=("$session_dir")
    mkdir -p "$session_dir/knowledge" "$session_dir/work/web-researcher"

    cat >"$session_dir/knowledge/knowledge-graph.json" <<'EOF'
{
  "schema_version": "1.0",
  "entities": [],
  "claims": [],
  "stats": {
    "total_entities": 0,
    "total_claims": 0,
    "total_sources": 0
  }
}
EOF

    cat >"$session_dir/work/web-researcher/manifest.actual.json" <<'EOF'
{
  "schema_version": "1.0.0",
  "agent": "web-researcher",
  "generated_at": "2025-11-05T12:00:00Z",
  "contract_path": "config/artifact-contracts/web-researcher/manifest.expected.json",
  "contract_sha256": "placeholder",
  "validation_phase": "phase2",
  "validation_duration_ms": 1,
  "artifacts": [
    {
      "slot": "web_research_findings",
      "slot_instance": 0,
      "relative_path": "work/web-researcher/findings-t0.json",
      "content_type": "application/json",
      "schema_id": "artifact://research/findings@v1",
      "required": true,
      "status": "present",
      "sha256": "placeholder",
      "size_bytes": 1234,
      "validated_at": "2025-11-05T12:00:00Z",
      "validation": {
        "schema": "passed",
        "checksum": "passed"
      },
      "messages": []
    }
  ],
  "summary": {
    "required_total": 1,
    "required_present": 1,
    "optional_present": 0,
    "total_artifacts": 1,
    "missing_slots": [],
    "checksum_failures": [],
    "schema_failures": []
  }
}
EOF

    echo "$session_dir"
}

write_findings() {
    local session_dir="$1"
    cat >"$session_dir/work/web-researcher/findings-t0.json" <<'EOF'
{
  "entities_discovered": [
    {
      "name": "Example Ventures",
      "type": "organization"
    }
  ],
  "claims": [
    {
      "statement": "Example Ventures prefers bottom-up TAM validation.",
      "sources": [
        {
          "url": "https://example.com/ventures"
        }
      ]
    }
  ]
}
EOF
}

test_case "count-only manifest defers to findings files"
session_counts=$(create_session)
write_findings "$session_counts"

cat >"$session_counts/work/web-researcher/output.json" <<'EOF'
{
  "status": "completed",
  "entities_discovered": 1,
  "claims": 1,
  "result": {
    "artifacts_created": [
      "work/web-researcher/findings-t0.json"
    ]
  }
}
EOF

if ! kg_integrate_agent_output "$session_counts" "$session_counts/work/web-researcher/output.json"; then
    echo "  ✗ kg_integrate_agent_output returned failure for count-only manifest" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    entity_total=$(jq '.entities | length' "$session_counts/knowledge/knowledge-graph.json")
    claim_total=$(jq '.claims | length' "$session_counts/knowledge/knowledge-graph.json")
    assert_equals "1" "$entity_total" "entity added from findings file"
    assert_equals "1" "$claim_total" "claim added from findings file"
fi

test_case "legacy array manifest still integrates inline data"
session_arrays=$(create_session)
rm -f "$session_arrays/work/web-researcher/manifest.actual.json"

cat >"$session_arrays/work/web-researcher/output.json" <<'EOF'
{
  "status": "completed",
  "result": "{\"status\":\"completed\",\"entities_discovered\":[{\"name\":\"Legacy Capital\",\"type\":\"organization\"}],\"claims\":[{\"statement\":\"Legacy Capital accepts triangulated TAM calculations.\",\"sources\":[{\"url\":\"https://legacy.example.com/tam\"}]}]}"
}
EOF

if ! kg_integrate_agent_output "$session_arrays" "$session_arrays/work/web-researcher/output.json"; then
    echo "  ✗ kg_integrate_agent_output returned failure for array manifest" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
else
    entity_total=$(jq '.entities | length' "$session_arrays/knowledge/knowledge-graph.json")
    claim_total=$(jq '.claims | length' "$session_arrays/knowledge/knowledge-graph.json")
    assert_equals "1" "$entity_total" "entity added from inline array"
    assert_equals "1" "$claim_total" "claim added from inline array"
fi

echo
echo "Tests run: $TESTS_RUN"
if [[ "$TESTS_FAILED" -gt 0 ]]; then
    echo "Failures : $TESTS_FAILED"
    exit 1
else
    echo "All tests passed"
    exit 0
fi
