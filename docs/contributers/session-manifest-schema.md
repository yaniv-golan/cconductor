# Session Manifest Schema (v1)

## Overview

`session-manifest.json` captures a curated view of the session state for the mission orchestrator and related tooling. It is regenerated before each orchestrator turn and stored at `meta/session-manifest.json` inside the session directory. Beginning with the Write-tool canonicalization work, the session manifest now consumes per-agent artifact manifests sourced from `config/artifact-contracts/` and the runtime-generated `work/<agent>/manifest.actual.json` files.

- **Scope**: knowledge graph coverage, quality gate status, high-priority gaps, key artifacts, recent agent outputs, and the validated artifact slots defined in the agent contracts.
- **Paths**: every path in the manifest is relative to the session root. `knowledge_graph.file_absolute` exists only for backward compatibility and should not be surfaced to agents.
- **Versioning**: the current schema version is `1`. Increment the `version` field and update this file when breaking structural changes are introduced. When contract structure changes, bump the `schema_version` in each `manifest.expected.json`.

## Agent Artifact Contracts

### Directory layout

- Expected contracts live under `config/artifact-contracts/<agent>/manifest.expected.json`.
- Artifact schemas live under `config/schemas/artifacts/`. Each schema file exposes an `$id` that matches the `schema_id` value stored in the expected manifest.
- Runtime manifests are written to `work/<agent>/manifest.actual.json` inside the active session. These files use the schema identified by `artifact://system/manifest-actual@v1`.

### `manifest.expected.json`

Every agent has a contract describing the artifacts it must publish through the Write tool. The contract schema is `artifact://system/manifest-expected@v1` and contains:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Contract version. Bump when breaking changes occur. |
| `agent` | string | Agent slug (matches directory name under `src/claude-runtime/agents/`). |
| `description` | string | Human-readable overview of the contract. |
| `artifacts` | array | Ordered list of artifact slots the agent must consider. |

Each entry in `artifacts` contains:

| Field | Type | Description |
|-------|------|-------------|
| `slot` | string | Stable identifier for the artifact slot (used in logging and dashboards). |
| `description` | string | Optional operator-facing description. |
| `relative_path` | string | Path relative to the session root where the artifact is written. |
| `content_type` | string | MIME hint (`text/markdown`, `application/json`, etc.). |
| `schema_id` | string | JSON Schema identifier for validating the artifact or its metadata. |
| `required` | boolean | Whether the orchestrator must fail if the artifact is missing. |
| `checksum` | object | Currently limited to `{ \"algorithm\": \"sha256\" }`. |

### Artifact schemas

- Markdown artifacts reuse `artifact://markdown/base@v1` and specialised schemas (e.g., `artifact://markdown/mission-report@v1`) that constrain metadata such as `content_type`.
- JSON artifacts (e.g., `artifact://synthesis/key-findings@v1`) describe the expected structure of the emitted JSON files. The orchestrator validates these using `jq` via `json-helpers.sh`.
- Non-JSON sentinel files such as locks expose metadata schemas (e.g., `artifact://locks/knowledge-graph@v1`) that ensure the manifest records the expected `content_type`.

### `manifest.actual.json`

After each agent run, the orchestrator writes `work/<agent>/manifest.actual.json` using the `artifact://system/manifest-actual@v1` schema:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | Actual manifest schema version (currently `1.0.0`). |
| `agent` | string | Agent slug. |
| `generated_at` | string | ISO-8601 timestamp when validation completed. |
| `contract_path` | string | Relative path to the expected contract used for validation. |
| `contract_sha256` | string | SHA-256 checksum of the expected contract at validation time. |
| `validation_phase` | string | Migration phase label (`phase1`, `phase2`, `phase3`). |
| `artifacts` | array | Validation results for each slot. |
| `summary` | object | Aggregate counts (required present, optional present, missing slots, checksum/schema failures). |

Each entry inside `artifacts` records:

- `slot`, `relative_path`, `content_type`, `schema_id`, `required`
- `status`: `present`, `missing`, or `invalid`
- `sha256` and `size_bytes` for detected files
- `validated_at`: timestamp of checksum/schema evaluation
- `validation`: `{ "schema": "passed|failed|skipped", "checksum": "passed|failed|skipped" }`
- `messages`: optional array of structured warnings/errors tied to the slot

When an artifact is missing, the entry still appears with `status: "missing"` and a message explaining the failure. Invalid artifacts set `status: "invalid"` and populate `validation.schema` or `validation.checksum` with `failed`.

## Session Manifest

## Top-Level Structure

```json
{
  "version": 1,
  "generated_at": "2025-10-31T16:04:12Z",
  "session": { ... },
  "paths": { ... },
  "knowledge_graph": { ... },
  "quality_gate": { ... },
  "artifacts": { ... },
  "recent_decisions": [ ... ],
  "pending_tasks": [ ... ]
}
```

### session

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Session directory name. |
| `objective` | string&#124;null | Mission objective from `meta/session.json`. |
| `status` | string&#124;null | Session status (`in_progress`, `completed`, etc.). |
| `created_at` | string&#124;null | ISO-8601 created timestamp. |
| `updated_at` | string&#124;null | ISO-8601 completed/updated timestamp if available. |
| `manifest_path` | string | Relative path to this manifest (usually `meta/session-manifest.json`). |

### paths

Relative references for frequently accessed assets:

- `manifest` – `meta/session-manifest.json`
- `mission_state` – `meta/mission_state.json`
- `knowledge_graph` – `knowledge/knowledge-graph.json`
- `orchestration_log` – `logs/orchestration.jsonl`
- `events_log` – `logs/events.jsonl`

### knowledge_graph

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | Relative path to the knowledge graph. |
| `file_absolute` | string&#124;null | Absolute path retained for legacy tooling. |
| `claims` | number | Count of claims currently stored. |
| `entities` | number | Count of entities. |
| `sources` | number | Unique source count derived from claim citations. |
| `last_updated_at` | string&#124;null | ISO timestamp from file mtime. |
| `last_updated_epoch` | number&#124;null | Mtime epoch seconds. |

### quality_gate

Captures the latest quality gate execution:

- `status` – `passed`, `failed`, `not_run`, etc.
- `summary_file` / `details_file` – relative paths to quality gate artifacts when present.
- `summary` – parsed contents of `artifacts/quality-gate-summary.json`.
- `high_priority_gaps` – top five unresolved gaps (description, priority, status, focus) taken from the knowledge graph.

### artifacts

Grouped collections of notable artifacts:

- `domain_heuristics` – array of `{kind, path, updated_at, updated_epoch}` entries (meta, work output, artifact copies).
- `prompt_parser` – similar array covering prompt-parser outputs.
- `recent_agent_outputs` – latest (≤5) agent outputs with agent name, work output path, optional markdown artifact, and timestamps.

### recent_decisions

Array of the last five orchestration decisions (mirrors `mission_state.json:last_5_decisions`).

### pending_tasks

Alias for the high-priority gap slice (top five unresolved gaps). Consumers should treat it as a todo list for closing out critical coverage requirements.

## Aggregation Flow

1. `invoke-agent.sh` loads `config/artifact-contracts/<agent>/manifest.expected.json`, executes the agent, validates the emitted files against the referenced schemas in `config/schemas/artifacts/`, and writes `work/<agent>/manifest.actual.json`.
2. `artifact-manager.sh` ingests the validated `manifest.actual.json` and updates `artifacts/manifest.json`, preserving checksums and timestamps via atomic writes.
3. `session-manifest-builder.sh` reads the agent manifests, combines them with knowledge graph metrics, and re-renders `meta/session-manifest.json`, exposing contract health in the `artifacts` section.

Consumers must avoid reading raw `.result` payloads; the manifest pipeline is now the canonical source for artifact discovery and validation state.

## Updating the Schema

1. Bump `version` and extend this document with new/changed fields.
2. Adjust `session-manifest-builder.sh` to emit the updated structure.
3. Update orchestrator prompt/docs to teach new semantics.
4. Add regression tests covering the new fields or invariants, including validation of the expected and actual agent manifests.
