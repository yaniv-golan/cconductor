# Argument Event Emission Contract

_Applies to all agents with `argument_capable: true` in `src/utils/agent-registry.sh`_

> **Runtime Delivery**: This contract ships as the `argument-contract` Claude skill (`src/claude-runtime/skills/argument-contract/SKILL.md`). Every new mission session copies the skill into `.claude/skills/argument-contract/`. Keep this document and the skill file in sync—update them together in the same change.

## Overview
Agents must emit structured JSON events describing every argumentative artefact they generate. The event payloads are consumed by `argument-writer.sh` and must conform to the schema in `./ARGUMENT_EVENT_GRAPH.md`.

## CLI Requirements
- Launch Claude CLI with `--output-format stream-json --include-partial-messages`.
- For structured prompts, include `--input-format stream-json`.
- Agents should emit `argument_event` batches using:
  ```json
  {
    "type": "stream_event",
    "event": {
      "type": "custom_event",
      "name": "argument_event",
      "payload": {
        "events": [ { /* event envelope */ }, … ]
      }
    }
  }
  ```
- Fallback: emit a legacy block code fence with ```json argument_events```; the writer parser handles both.
- Helpers:
  - `src/utils/argument-events.sh id --prefix clm --mission-step <step> --seed "<claim text>"` to produce deterministic base32 IDs (12 chars by default).
  - `src/utils/argument-events.sh envelope --events-json '<events array or object>'` to wrap batches in the standard stream envelope.

## Required Fields
| Field | Description |
|-------|-------------|
| `mission_step` | Deterministic label (use orchestrator-provided breadcrumb). |
| `agent` | Agent slug (auto-filled if omitted). |
| `event_type` | `claim`, `evidence`, `contradiction`, `preference`, `metadata`, `retraction`. |
| `payload` | Structured data matching the schema. |
| `timestamp` | ISO 8601 UTC. Agents may omit; writer substitutes stream timestamp. |

## Emission Examples
### Claim + Evidence Bundle
```json
{
  "events": [
    {
      "event_type": "claim",
      "mission_step": "S3.task.001",
      "payload": {
        "claim_id": "clm-trials-001",
        "text": "mRNA-3927 entered Phase 3 in 2025.",
        "sources": ["src-press-release"],
        "premises": ["evd-press-release"]
      }
    },
    {
      "event_type": "evidence",
      "mission_step": "S3.task.001",
      "payload": {
        "evidence_id": "evd-press-release",
        "claim_id": "clm-trials-001",
        "role": "support",
        "statement": "Press release August 2025…",
        "source": "src-press-release",
        "quality": "high"
      }
    }
  ]
}
```

### Contradiction
```json
{
  "events": [
    {
      "event_type": "contradiction",
      "payload": {
        "contradiction_id": "ctd-sample-size",
        "attacker_claim_id": "clm-trial-stats",
        "target_claim_id": "clm-trials-001",
        "basis": "conflicting-statistic",
        "sources": ["src-fda-filing"]
      }
    }
  ]
}
```

## Failure Handling
- Invalid payloads will produce structured errors written to `logs/system-errors.log`.
- Agents must retry emission with corrected payloads; `argument-writer.sh` rejects malformed events.
- Duplicate `event_id` values are deduped; agents should still maintain stable IDs for idempotency.

## Prompt Guidance
- Load the schema snippet via `knowledge-loader.sh` so the agent can validate fields before emitting.
- Encourage agents to cite evidence IDs alongside the textual sources used in natural language output.
- Provide deterministic hashing hints (e.g., embed trimmed claim text) to keep IDs stable across retries.

## Testing
- `tests/aif-hypothesis-sandbox/run-aif-hypothesis-test.sh` ingests agent fixtures.
- Agents must pass `shellcheck` on prompt helper scripts where applicable.

## Backwards Compatibility
- Agents not yet upgraded can set `argument_capable: false`; orchestrator will skip quality gating until migration completes.
- When both legacy and AEG events exist, the materialiser prefers AEG data but falls back to legacy knowledge graph entries.
