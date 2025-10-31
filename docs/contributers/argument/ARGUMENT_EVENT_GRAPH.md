# Argument Event Graph (AEG) Schema

_Last updated: October&nbsp;30,&nbsp;2025._

## Overview
The Argument Event Graph (AEG) is the canonical, deterministic representation of all argumentative structures discovered during a CConductor mission. It is optimised for append-only updates from Bash utilities and subsequent export to the Argument Interchange Format (AIF) without introducing non-core dependencies. Mission agents emit structured events (`claim`, `evidence`, `contradiction`, `preference`, `retraction`, and `metadata`) which are appended to an immutable log and subsequently materialised into a graph (`aeg.graph.json`). The exporter converts this graph into JSON-LD that conforms to AIF vocabularies (`I`, `RA`, `CA`, `PA`, `F` nodes).

> Runtime reminder: the `argument-contract` Claude skill distributes the emission checklist to every mission session. Agents must invoke it prior to streaming events so the payloads adhere to this schema.

```
mission_123/
  argument/
    aeg.log.jsonl           # Append-only event log
    aeg.index.json          # Deduplication hints (event_id → seq)
    aeg.graph.json          # Materialised nodes/edges
    aeg.quality.json        # Coverage metrics for quality gates
```

## Event Envelope
All payloads share the same envelope to simplify ingestion:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `event_id` | `string` | ✅ | Base32-encoded SHA-256 of `event_type` + `payload` + `mission_step`. Provided by agents; regenerated if absent. |
| `event_type` | `string` | ✅ | One of `claim`, `evidence`, `contradiction`, `preference`, `metadata`, `retraction`. |
| `mission_step` | `string` | ✅ | Deterministic label for orchestration step (e.g., `S3.task.001`). Used for ordering and hashing. |
| `agent` | `string` | ✅ | Agent slug emitting the event (`academic-researcher`, `synthesis-agent`, etc.). |
| `timestamp` | `string` | ✅ | ISO 8601 UTC; writer normalises on ingest. |
| `payload` | `object` | ✅ | Event-type specific content (see below). |
| `stream_offset` | `number` | ➖ | Offset from Claude stream for ordering; writer fills with monotonic counter when omitted. |
| `provenance` | `object` | ➖ | Additional context: input file, tool call ids, checksum of agent output fragment. |

Events may be emitted singly or in batches. The writer normalises both cases so that each JSON object is appended on its own line (`.log.jsonl`).

## Payload Structures

### Claims (`event_type: "claim"`)
```
{
  "claim_id": "clm-2025-10-30T18-12-45Z-001",
  "text": "mRNA-3927 entered phase 3 trials in 2025.",
  "modality": "assertion",
  "confidence": 0.82,
  "domain": "biotech",
  "tags": ["trial-phase", "mRNA"],
  "sources": [
    {
      "source_id": "src-...-001",
      "kind": "web",
      "url": "https://example.org/press-release",
      "title": "Moderna announces phase 3 trial",
      "published": "2025-08-11",
      "excerpt": "Phase 3 trial begins in August 2025…"
    }
  ],
  "premises": ["evd-...-001", "evd-...-002"],
  "hash_strategy": "sha256:text+sources"
}
```
`claim_id` is globally unique within the mission. `premises` references evidence events; if omitted the materialiser creates a single RA node linking the claim directly to its sources.

### Evidence (`event_type: "evidence"`)
```
{
  "evidence_id": "evd-...-001",
  "claim_id": "clm-...-001",
  "role": "support",         # or "context", "counter"
  "statement": "Company press release dated Aug 11 2025…",
  "source": "src-...-001",
  "quality": "high",         # high/medium/low/unknown
  "numeric": {
    "value": 2300,
    "unit": "participants",
    "normalised": "2.3e3",
    "basis": "reported",
    "currency": null
  }
}
```
Evidence is the atomic unit for RA construction. `role="counter"` produces an intermediate node used by the materialiser for CA edges.

### Contradictions (`event_type: "contradiction"`)
```
{
  "contradiction_id": "ctd-...-001",
  "attacker_claim_id": "clm-...-002",
  "target_claim_id": "clm-...-001",
  "basis": "conflicting-statistic",   # Enumerated in config/schemes.jsonld
  "explanation": "FDA filing lists sample size = 1800",
  "sources": ["src-...-010"],
  "attacker_text": "FDA's 2025 report indicates only 1800 participants."
}
```
Materialisation produces CA nodes with incoming edges from both claims.

### Preferences (`event_type: "preference"`)
```
{
  "preference_id": "prf-...-001",
  "preferred_claim_id": "clm-...-001",
  "dispreferred_claim_id": "clm-...-003",
  "criteria": "evidence-quality",
  "weight": 0.65,
  "valid_from_seq": 142,
  "explanation": "Claim A has higher-quality primary sources."
}
```
Converted into PA nodes per AIF.

### Retractions (`event_type: "retraction"`)
```
{
  "target_id": "clm-...-003",
  "target_type": "claim",                # or "evidence" / "preference"
  "reason": "source-withdrawn",
  "replacing_claim_id": "clm-...-005"
}
```
Retractions mark the referenced node as inactive. The materialiser preserves the historical node but flags it for downstream exporters and quality gates.

### Metadata (`event_type: "metadata"`)
Used for dual-write metrics and schema versioning.
```
{
  "key": "schema-version",
  "value": "2025.10.30",
  "context": { "writer": "argument-writer.sh", "hash_seed": "v1" }
}
```

## Materialised Graph (`aeg.graph.json`)
```
{
  "schema_version": "2025-10-30",
  "generated_at": "2025-10-30T20:04:12Z",
  "nodes": [
    {"id": "I:clm-...-001", "type": "I", "claim_id": "clm-...-001", "text": "...", "status": "active", "hash": "sha256:..."},
    {"id": "RA:clm-...-001:000", "type": "RA", "supports": ["I:evd-...-001"], "concludes": "I:clm-...-001", "scheme_id": "supporting-evidence"}
  ],
  "edges": [
    {"from": "I:evd-...-001", "to": "RA:clm-...-001:000", "role": "premise"},
    {"from": "RA:clm-...-001:000", "to": "I:clm-...-001", "role": "conclusion"}
  ],
  "sources": {
    "src-...-001": {
      "url": "...",
      "title": "...",
      "hash": "sha256:body"
    }
  },
  "metrics": {
    "claim_coverage": 0.96,
    "contradiction_surface": 3,
    "preference_surface": 1,
    "inactive_nodes": 2
  }
}
```
The materialiser enforces deterministic RA identifiers via broadcasting indexes derived from the ordered `premises` array. Contradictions become CA nodes; preferences become PA nodes. Retractions mark nodes with `status: "retracted"` while retaining historical edges for audit.

## ID Generation
- Claims: `clm-<ISO8601>-<seq>` seeded with mission step.
- Evidence: `evd-<claim_id>-<seq>`.
- Contradictions: `ctd-<attacker>-<target>-<hash>`.
- Preferences: `prf-<preferred>-<dispreferred>-<seq>`.
- Sources: `src-<sha1(url|title|published)>`.
- RA nodes derive from `claim_id` + sorted `premises` hashed via SHA-256 and truncated to 12 bytes base32.

The writer rehashes inputs to avoid collisions and surface deterministic diffs.

## Quality Metrics (`aeg.quality.json`)
```
{
  "coverage": {
    "claims_total": 32,
    "claims_with_ra": 31,
    "contradictions_total": 3,
    "preferences_total": 5
  },
  "violations": [
    {"code": "S8.MISSING_RA", "claim_id": "clm-...-012", "description": "Claim lacks supporting evidence."},
    {"code": "S8.STALE_SOURCE", "claim_id": "clm-...-004", "source_id": "src-...-021"}
  ]
}
```
Quality gates consume this file; synthesis blocks if `violations` is non-empty unless an override is provided.

## Mapping to AIF JSON-LD
| AEG Node/Edge | AIF Mapping |
|---------------|-------------|
| Claim (`I:clm-*`) | **I-node** with `aif:Information` |
| RA Node | **RA-node** referencing scheme from `config/schemes.jsonld` |
| Contradiction | **CA-node** linking attacker and target RA/I nodes |
| Preference | **PA-node** referencing comparative criteria |
| Source descriptor | **F-node** (information source metadata) |

Exporter ensures `@context` produced from `config/schemes.jsonld` and resolves all IDs into IRIs anchored at `mission://<id>/`.

## Retention & Dual Write
- The writer keeps the log append-only.
- Materialiser is idempotent and re-runnable; it consumes the entire log on each invocation but uses streaming jq reductions for speed.
- Exporter reads `aeg.graph.json`; if absent it triggers the materialiser.
- Knowledge graph dual-write is handled by `kg-integrate.sh` using the new `aeg-export` channel documented in `./ARGUMENT_EVENT_GRAPH_MIGRATION.md`.

## Forward Evolution
The schema version is embedded in `aeg.graph.json` (`schema_version`) and in every metadata event. Breaking changes MUST increment the date-stamped version and include migration guidance in `docs/UPGRADE.md`. Non-breaking additions should preserve backwards compatibility by providing reasonable defaults in the materialiser/exporter.
