#!/usr/bin/env bash
# Validate mission orchestrator dual-mode decision loading (manifest vs fallback)

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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/event-logger.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"

# Global toggle used by the stubbed invoke_agent_v2 implementation.
TEST_ORCH_MODE=""

# Stub invoke_agent_v2 so we can control artifact behavior without invoking real agents.
invoke_agent_v2() {
    local _agent_name="$1"
    local _input_file="$2"
    local _output_file="$3"
    local _timeout="$4"
    local session_dir="$5"
    shift 5 || true

    case "${TEST_ORCH_MODE:-}" in
        manifest_success)
            mkdir -p "$session_dir/work/mission-orchestrator"
            cat > "$session_dir/work/mission-orchestrator/manifest.actual.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "agent": "mission-orchestrator",
  "generated_at": "2025-11-01T00:00:00Z",
  "contract_path": "config/artifact-contracts/mission-orchestrator/manifest.expected.json",
  "contract_sha256": "stubbed",
  "validation_phase": "phase2",
  "validation_duration_ms": 1,
  "artifacts": [
    {
      "slot": "decision_json",
      "slot_instance": 0,
      "relative_path": "artifacts/mission-orchestrator/decision.json",
      "content_type": "application/json",
      "schema_id": "artifact://orchestrator/decision@v1",
      "required": true,
      "status": "present",
      "sha256": "stubbed",
      "size_bytes": 120,
      "validated_at": "2025-11-01T00:00:00Z",
      "validation": {
        "schema": "passed",
        "checksum": "skipped"
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
JSON
            mkdir -p "$session_dir/artifacts/mission-orchestrator"
            cat > "$session_dir/artifacts/mission-orchestrator/decision.json" <<'JSON'
{
  "reasoning": {
    "synthesis_approach": "Review latest findings from academic agents",
    "gap_prioritization": "Address unanswered critical watch topics first",
    "key_insights": [
      "Knowledge graph still lacks medical trials coverage"
    ],
    "strategic_decisions": [
      "Send web-researcher to gather regulatory updates"
    ]
  },
  "action": "invoke",
  "agent": "web-researcher",
  "task": "Collect regulatory updates impacting the mission objective",
  "context": "Focus on authoritative regulatory bodies and publish dates within the last two years.",
  "input_artifacts": [],
  "rationale": "Need regulatory context before advising stakeholders",
  "expected_impact": "Improves compliance readiness with fresh regulatory evidence"
}
JSON
            jq -n '{result: ""}' > "$_output_file"
            ;;
        fallback_result)
            mkdir -p "$session_dir/work/mission-orchestrator"
            cat > "$session_dir/work/mission-orchestrator/manifest.actual.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "agent": "mission-orchestrator",
  "generated_at": "2025-11-01T00:00:00Z",
  "contract_path": "config/artifact-contracts/mission-orchestrator/manifest.expected.json",
  "contract_sha256": "stubbed",
  "validation_phase": "phase2",
  "validation_duration_ms": 1,
  "artifacts": [],
  "summary": {
    "required_total": 1,
    "required_present": 0,
    "optional_present": 0,
    "total_artifacts": 0,
    "missing_slots": [
      {
        "slot": "decision_json",
        "relative_path": "artifacts/mission-orchestrator/decision.json",
        "required": true
      }
    ],
    "checksum_failures": [],
    "schema_failures": []
  }
}
JSON
            local fallback_payload
            fallback_payload=$'Streaming analysis\n{"reasoning":{"synthesis_approach":"Fallback reasoning path","gap_prioritization":"Primary tasks addressed first","key_insights":["Manual fallback engaged"],"strategic_decisions":["Continue with existing agent plan"]},"action":"early_exit","reason":"All success criteria met","confidence":0.9,"evidence":"All deliverables validated"}\n'
            jq -n --arg text "$fallback_payload" '{result: $text}' > "$_output_file"
            ;;
        session_limit_error)
            mkdir -p "$session_dir/artifacts/mission-orchestrator"
            cat > "$session_dir/artifacts/mission-orchestrator/decision.json" <<'JSON'
{
  "reasoning": {
    "synthesis_approach": "Previous decision placeholder",
    "gap_prioritization": "Maintain prior plan",
    "key_insights": ["Ensure backup persists"],
    "strategic_decisions": ["Hold until quota resets"]
  },
  "action": "invoke",
  "agent": "web-researcher",
  "task": "Previous task",
  "context": "previous context"
}
JSON
            jq -n '{
              type: "result",
              subtype: "success",
              is_error: true,
              result: "Session limit reached ∙ resets 3pm",
              usage: { output_tokens: 0 }
            }' > "$_output_file"
            return 1
            ;;
        *)
            echo "Test harness misconfigured: TEST_ORCH_MODE=$TEST_ORCH_MODE" >&2
            return 1
            ;;
    esac
    return 0
}

setup_session_dir() {
    local session_dir
    session_dir="$(mktemp -d -t orch-test-XXXXXX)"
    mkdir -p "$session_dir/meta" "$session_dir/logs" "$session_dir/work" "$session_dir/artifacts"
    echo '{}' > "$session_dir/meta/session.json"
    init_events "$session_dir"
    printf '%s\n' "$session_dir"
}

cleanup_session_dir() {
    local dir="$1"
    rm -rf "$dir"
}

context_payload='{
  "mission": {
    "objective": "Test mission orchestrator dual mode",
    "constraints": {}
  },
  "agents": [
    {"name": "web-researcher"}
  ],
  "iteration": 1,
  "state": {
    "domain_compliance": {
      "compliance_summary": "none"
    },
    "session_manifest": {},
    "budget_summary": {
      "spent_usd": 0,
      "budget_usd": 10,
      "spent_invocations": 0,
      "max_agent_invocations": 5,
      "elapsed_minutes": 0,
      "max_time_minutes": 60
    },
    "last_5_decisions": []
  }
}'

echo "→ Scenario 1: manifest-driven decision"
session_dir="$(setup_session_dir)"
TEST_ORCH_MODE="manifest_success"
manifest_output="$(invoke_mission_orchestrator "$session_dir" "$context_payload")"
echo "$manifest_output" | jq '.action' >/dev/null
if [[ "$(echo "$manifest_output" | jq -r '.action')" != "invoke" ]]; then
    echo "Expected manifest decision to use invoke action" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
manifest_event="$(tail -n 1 "$session_dir/logs/events.jsonl")"
echo "$manifest_event" | jq -e '.type == "orchestrator_decision_source" and .data.source == "manifest" and (.data.success == true)' >/dev/null
cleanup_session_dir "$session_dir"

echo "→ Scenario 2: fallback to result stream"
session_dir="$(setup_session_dir)"
TEST_ORCH_MODE="fallback_result"
fallback_output="$(invoke_mission_orchestrator "$session_dir" "$context_payload")"
echo "$fallback_output" | jq '.action' >/dev/null
if [[ "$(echo "$fallback_output" | jq -r '.action')" != "early_exit" ]]; then
    echo "Expected fallback decision to request early_exit" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
fallback_event="$(tail -n 1 "$session_dir/logs/events.jsonl")"
echo "$fallback_event" | jq -e '.type == "orchestrator_decision_source" and .data.source == "result_fallback" and (.data.success == true)' >/dev/null
cleanup_session_dir "$session_dir"

echo "→ Scenario 3: provider session limit abort"
session_dir="$(setup_session_dir)"
TEST_ORCH_MODE="session_limit_error"
set +e
invoke_mission_orchestrator "$session_dir" "$context_payload" >"$session_dir/out.json"
limit_status=$?
set -e
if [[ $limit_status -eq 0 ]]; then
    echo "Expected orchestrator to signal failure on session limit" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
reason=$(jq -r '.reason // empty' "$session_dir/out.json" 2>/dev/null || echo "")
if [[ "$reason" != *"Session limit"* ]]; then
    echo "Expected early_exit reason to mention session limit" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
if [[ ! -f "$session_dir/artifacts/mission-orchestrator/decision.json" ]]; then
    echo "Previous decision artifact was not preserved" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
if ! jq -s 'map(select(.type == "provider_session_limit" and .data.agent == "mission-orchestrator")) | length > 0' "$session_dir/logs/events.jsonl" >/dev/null; then
    echo "Expected provider_session_limit event in telemetry" >&2
    cleanup_session_dir "$session_dir"
    exit 1
fi
cleanup_session_dir "$session_dir"

echo "✓ Mission orchestrator dual-mode decision tests passed"
