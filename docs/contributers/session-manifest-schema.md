# Session Manifest Schema (v1)

## Overview

`session-manifest.json` captures a curated view of the session state for the mission orchestrator and related tooling. It is regenerated before each orchestrator turn and stored at `meta/session-manifest.json` inside the session directory.

- **Scope**: knowledge graph coverage, quality gate status, high-priority gaps, key artifacts, recent agent outputs, and canonical relative paths for orchestration resources.
- **Paths**: every path in the manifest is relative to the session root. `knowledge_graph.file_absolute` exists only for backward compatibility and should not be surfaced to agents.
- **Versioning**: the current schema version is `1`. Increment the `version` field and update this file when breaking structural changes are introduced.

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

## Updating the Schema

1. Bump `version` and extend this document with new/changed fields.
2. Adjust `session-manifest-builder.sh` to emit the updated structure.
3. Update orchestrator prompt/docs to teach new semantics.
4. Add regression tests covering the new fields or invariants.

