# Guard Contract

Guards are lightweight shell functions that gate synthesis by reporting structured status back to the mission orchestrator. Every guard **must** emit a single JSON object on `stdout` and reserve non-zero exit codes for unrecoverable errors (schema violations, file corruption, etc.).

## JSON Payload

- Schema: `config/schemas/orchestration/guard-result.json`
- Required fields:
  - `status`: `"ok"`, `"block"`, or `"error"`
- Optional fields:
  - `blocker`: Identifier for the guard (`watch_topics`, `quality_gate`, `stakeholders`); required when `status == "block"`.
  - `details`: Guard-specific object payload (e.g., `{ "pending": [...] }`).
  - `topics`: Optional array for quick diagnostics (used by the watch topic guard).
  - `suggested_action`: `"delegate_web_researcher"`, `"trigger_remediator"`, or `"none"`.
  - `message`: Human-readable explanation suitable for CLI logs.

### Status Semantics

| Status | Meaning | Orchestrator response |
| --- | --- | --- |
| `ok` | Guard cleared; synthesis may proceed. | Existing blocker state cleared. |
| `block` | Guard detected actionable blockers. | Blockers recorded to `meta/orchestration-state.json` and `meta/synthesis-blockers.json`; synthesis deferred without counting as an attempt. |
| `error` | Guard experienced unrecoverable failure. | Orchestrator logs an error and aborts the synthesis branch. |

Guards should keep stderr chatter minimal and rely on the returned `message` for user-facing guidance. The orchestrator prints `↺ …` lines automatically when blockers are recorded.

## File Artifacts

When a guard reports a block, the orchestrator persists the following:

- `meta/orchestration-state.json`
  - `synthesis_blockers`: Array of blocker entries (`type`, `detected_at`, `details`, `suggested_action`, `message`).
  - `synthesis_attempts`: Count of synthesis-agent invocations that reached the agent.
- `meta/synthesis-blockers.json`
  - Snapshot containing `generated_at` and the current `synthesis_blockers` array. The README points users here when synthesis is pending.

Dashboards and resume flows rely on these files, so guards must avoid side effects and always emit valid JSON.

## Implementation Checklist

1. Refresh prerequisite mission state before evaluating guard-specific logic.
2. Build a payload object, e.g.:
   ```bash
   guard_payload=$(jq -n \
     --arg blocker "watch_topics" \
     --arg suggested "delegate_web_researcher" \
     --arg message "$warning" \
     --argjson topics "$pending_json" \
     '{blocker: $blocker, suggested_action: $suggested, message: $message, topics: $topics}')
   ```
3. Emit the JSON via `mission_orchestration_guard_result "$status" "$guard_payload"`.
4. Return `0` for both `"ok"` and `"block"`; return `1` only when the guard cannot continue.
5. Keep stdout clean—only the JSON payload should be printed.

Following this contract ensures the orchestrator can re-queue research intelligently, surface blockers in manifests, and avoid premature early-exit decisions.
