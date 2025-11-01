# Argument Contract Skill

> **Invoke this skill before you emit any `argument_event` payloads.**
> It packages the full Argument Event Emission Contract so every agent can stream claims, evidence, contradictions, and retractions consistently.

## Quick Summary (TL;DR)
- Purpose: ensure all argument-capable agents emit structured JSON events that `argument-writer.sh` can ingest without errors.
- Envelope: stream `custom_event` payloads named `argument_event` with an `events` array that matches the Argument Event Graph schema.
- Scope: academic-researcher (now), web-researcher, pdf-analyzer, market-analyzer, fact-checker, and quality-remediator (as their emission workflows land).

## When to Use
- You are about to assert a claim, log supporting/contradicting evidence, withdraw a statement, or record preferences/metadata related to mission arguments.
- The orchestrator or another agent requests argument verification or alignment.
- Mission logic marks the agent as `argument_capable: true` in `src/utils/agent-registry.sh`.

## Workflow
1. **Collect context**: include the orchestrator-provided `mission_step` breadcrumb with every event you emit.
2. **Bundle events**: emit claims together with their supporting evidence whenever possible so downstream tooling can link them deterministically.
3. **Stable identifiers**:
   - `claim_id`: deterministic per mission (hash trimmed claim text plus scope, or reuse orchestrator IDs).
   - `evidence_id`: stable per evidence fragment; reference the primary `claim_id`.
   - Use the same IDs if you update a claim; emit a `retraction` event if you withdraw it.
4. **Emit events during streaming** using the `argument_event` envelope (see below). The payload rides alongside your normal JSON/file outputs and does not replace them.
5. **Validate before streaming**: sanity-check against the schema in `docs/contributers/argument/ARGUMENT_EVENT_GRAPH.md` (fields table below) to avoid writer rejections.
6. **Handle failures**: if the runtime returns a validation error, fix the payload and retry; malformed events are dropped and logged to `logs/system-errors.log`.

### Expected Stream Envelope
```json
{
  "type": "stream_event",
  "event": {
    "type": "custom_event",
    "name": "argument_event",
    "payload": {
      "events": [
        {
          "event_type": "claim",
          "mission_step": "S1.task.001",
          "payload": {
            "claim_id": "clm-market-share-2025",
            "text": "Company X captured 18% of the US market in FY2025.",
            "sources": ["src-census-2025"],
            "premises": ["evd-census-2025"]
          }
        },
        {
          "event_type": "evidence",
          "mission_step": "S1.task.001",
          "payload": {
            "evidence_id": "evd-census-2025",
            "claim_id": "clm-market-share-2025",
            "role": "support",
            "statement": "Census Bureau tables list Company X at 18% share in 2025.",
            "source": "src-census-2025",
            "quality": "high"
          }
        }
      ]
    }
  }
}
```

### Required Fields
| Field | Description |
|-------|-------------|
| `mission_step` | Deterministic breadcrumb supplied by the orchestrator; include it on every event. |
| `agent` | Agent slug; omit to let the runtime auto-fill. |
| `event_type` | `claim`, `evidence`, `contradiction`, `preference`, `metadata`, or `retraction`. |
| `payload` | Structured data matching `docs/contributers/argument/ARGUMENT_EVENT_GRAPH.md`. |
| `timestamp` | ISO 8601 UTC; optional (writer substitutes stream timestamp when missing). |

### Event Types & Guidance
- `claim`: concise factual assertion; include `claim_id`, `text`, `sources`, and `premises`.
- `evidence`: supports or refutes a claim; include `evidence_id`, `claim_id`, `role`, `statement`, `source`, and `quality`.
- `contradiction`: link `attacker_claim_id` to `target_claim_id` with `basis` and `sources`.
- `preference`: express judgement or prioritisation decisions; add `target_claim_id` when relevant.
 - `metadata`: supply supplemental context (methodology, scope, caveats).
 - `retraction`: withdraw a prior claim; reference the original `claim_id` and describe the reason.

### Reference Snippet
```
Argument Contract engaged.
- Emitting claim clm-market-share-2025 with supporting evidence evd-census-2025 (S1.task.001).
- Validated payload against docs/contributers/argument/ARGUMENT_EVENT_GRAPH.md; mission_step + IDs stable.
- No retractions required this step.
```

## Runtime Setup
- Launch the Claude CLI with `--output-format stream-json --include-partial-messages`.
- For structured prompts, add `--input-format stream-json` so tool requests arrive as streaming payloads.
- When tooling blocks streaming, fall back to the legacy ```json argument_events``` block (same schema).
- Helpers:
  - `bash src/utils/argument-events.sh id --prefix clm --mission-step <step> --seed "<claim text>"` → deterministic base32 claim IDs (12 chars by default).
  - `bash src/utils/argument-events.sh envelope --events-json '<events array or object>'` → wrap payloads in the correct stream envelope.

## Prompt & Output Guidance
- Load the schema snippet via `knowledge-loader.sh` to pre-validate events.
- Cite evidence IDs alongside textual citations in findings and manifest outputs so downstream agents can cross-reference.
- Encourage deterministic hashing hints (e.g., trimmed claim text + mission_step) to keep IDs stable across retries.
- When your research output mentions the contract, affirm compliance (e.g., “Argument Contract skill engaged; emitting claim/evidence bundles for mission step S2.task.003.”).

## Testing & Validation
- Automated: `tests/test-argument-event-graph.sh` ensures emitted payloads materialise into the Argument Event Graph without schema errors.
- Sandboxed: `tests/aif-hypothesis-sandbox/run-aif-hypothesis-test.sh` validates sample fixtures and regression suites.
- Manual: initialize a mission session, confirm `.claude/skills/argument-contract/SKILL.md` is present, and ensure the Claude sidebar lists the skill.

## Failure Handling
- Validation errors: emitted to `logs/system-errors.log`; adjust payload and retry.
- Duplicate IDs: writer deduplicates but you must still maintain stable IDs for idempotency.
- Fallback for tool limits: if streaming fails, emit a legacy ```json argument_events``` block that matches the same schema.

## Safety & Limits
- Skill operates entirely in-repo—no network calls.
- Do not fabricate evidence; each claim must cite real sources that also appear in findings files or mission artifacts.
- Respect mission confidentiality; only reference sources already allowed by the orchestrator.
- Agents not yet migrated can set `argument_capable: false`; orchestrator skips argument gating until you adopt this skill.

## Stay in Sync
- This skill mirrors the authoritative contract in `docs/contributers/argument/ARGUMENT_AGENT_CONTRACT.md`. Whenever one changes, update the other in the same pull request and note it in `docs/internal/argument-skill-rollout.matrix.md`.
