# AEG → AIF Export Examples

_Companion reference for `src/utils/export-aif.sh`_

## Example Mission Snapshot
Assume a mission `mission_1762000000000000000` produced the following AEG artefacts:

```
argument/
  aeg.log.jsonl
  aeg.graph.json
  aeg.quality.json
```

The materialised graph contains a single claim supported by two evidence fragments and attacked by a contradictory statistic:

```json
{
  "schema_version": "2025-10-30",
  "generated_at": "2025-10-30T21:12:02Z",
  "nodes": [
    {"id": "I:clm-trials-001", "type": "I", "text": "mRNA-3927 entered Phase 3 in 2025", "status": "active"},
    {"id": "I:evd-pr-001", "type": "I", "statement": "Press release 2025-08-11", "source_id": "src-press-release"},
    {"id": "I:evd-fda-001", "type": "I", "statement": "FDA filing lists 1800 participants", "source_id": "src-fda-filing"},
    {"id": "RA:clm-trials-001:000", "type": "RA", "scheme_id": "supporting-evidence"},
    {"id": "CA:ctd-claim-size", "type": "CA", "scheme_id": "contradiction"},
    {"id": "I:prf-confidence", "type": "I", "statement": "Preference: rely on primary filings"}
  ],
  "edges": [
    {"from": "I:evd-pr-001", "to": "RA:clm-trials-001:000", "role": "premise"},
    {"from": "RA:clm-trials-001:000", "to": "I:clm-trials-001", "role": "conclusion"},
    {"from": "I:evd-fda-001", "to": "CA:ctd-claim-size", "role": "attacker"},
    {"from": "CA:ctd-claim-size", "to": "I:clm-trials-001", "role": "target"},
    {"from": "I:prf-confidence", "to": "PA:prf-0001", "role": "premise"},
    {"from": "PA:prf-0001", "to": "I:clm-trials-001", "role": "preferred"},
    {"from": "PA:prf-0001", "to": "I:clm-trials-002", "role": "dispreferred"}
  ],
  "sources": {
    "src-press-release": {
      "url": "https://example.org/pr",
      "title": "Company launches phase 3 trial",
      "hash": "sha256:..."
    },
    "src-fda-filing": {
      "url": "https://fda.gov/documents/2025-1800",
      "title": "FDA Trial Summary",
      "hash": "sha256:..."
    }
  }
}
```

## Export Command
```
./src/utils/export-aif.sh --session research-sessions/mission_1762000000000000000 --output out/aif.jsonld
```

The exporter performs the following steps:

1. Ensures `aeg.graph.json` is up to date (invokes `materialize-argument-graph.sh` when needed).
2. Loads JSON-LD vocabulary and schemes from `config/schemes.jsonld`.
3. Generates canonical IRIs: `mission://mission_1762000000000000000/nodes/I:clm-trials-001`.
4. Emits the JSON-LD document containing the context, nodes, and edges.

## Generated JSON-LD (excerpt)
```json
{
  "@context": [
    "https://www.arg.tech/aif-schema.jsonld",
    {"cc": "mission://mission_1762000000000000000/context#"}
  ],
  "@id": "mission://mission_1762000000000000000/graph",
  "@type": "aif:ArgumentGraph",
  "aif:nodes": [
    {
      "@id": "mission://mission_1762000000000000000/nodes/I:clm-trials-001",
      "@type": "aif:I-node",
      "aif:claimText": "mRNA-3927 entered Phase 3 in 2025",
      "cc:status": "active",
      "cc:agent": "academic-researcher",
      "cc:missionStep": "S3.task.001"
    },
    {
      "@id": "mission://mission_1762000000000000000/nodes/RA:clm-trials-001:000",
      "@type": "aif:RA-node",
      "aif:scheme": "mission://mission_1762000000000000000/schemes/supporting-evidence",
      "aif:premise": [
        {"@id": "mission://mission_1762000000000000000/nodes/I:evd-pr-001"}
      ],
      "aif:conclusion": {"@id": "mission://mission_1762000000000000000/nodes/I:clm-trials-001"}
    },
    {
      "@id": "mission://mission_1762000000000000000/nodes/CA:ctd-claim-size",
      "@type": "aif:CA-node",
      "aif:attacker": {"@id": "mission://mission_1762000000000000000/nodes/I:evd-fda-001"},
      "aif:target": {"@id": "mission://mission_1762000000000000000/nodes/I:clm-trials-001"}
    }
  ],
  "aif:edges": [
    {
      "@type": "aif:DirectedEdge",
      "aif:from": {"@id": "mission://mission_1762000000000000000/nodes/I:evd-pr-001"},
      "aif:to": {"@id": "mission://mission_1762000000000000000/nodes/RA:clm-trials-001:000"},
      "cc:role": "premise"
    },
    {
      "@type": "aif:DirectedEdge",
      "aif:from": {"@id": "mission://mission_1762000000000000000/nodes/RA:clm-trials-001:000"},
      "aif:to": {"@id": "mission://mission_1762000000000000000/nodes/I:clm-trials-001"},
      "cc:role": "conclusion"
    }
  ],
  "cc:sources": [
    {
      "@id": "mission://mission_1762000000000000000/sources/src-press-release",
      "@type": "aif:F-node",
      "aif:sourceText": "Company launches phase 3 trial",
      "cc:url": "https://example.org/pr"
    }
  ]
}
```

## Validation Workflow
1. `./src/utils/export-aif.sh --session <dir> --output <path>`
2. `jq empty <path>` (syntax check)
3. `./scripts/validate-jsonld.sh <path>` (bundled script invoking `jsonld` or `jq` fallback)
4. Load into OVA3: `Tools → Import JSON-LD`, paste file or path.

## Troubleshooting
- **Missing RA nodes**: run `materialize-argument-graph.sh --session … --force`. The quality gate will block synthesis if RA coverage < 95%.
- **Duplicate node IDs**: call `src/utils/migrate-claim-ids.sh --session … --dedupe` before exporting.
- **Unknown schemes**: ensure `config/schemes.jsonld` includes custom scheme definitions and rerun exporter.

## Additional Examples
- `./aeg-to-aif-examples/` contains fixture directories with minimal, medium, and complex graphs. Each fixture has:
  - `aeg.log.jsonl`
  - `aeg.graph.json`
  - `expected.aif.jsonld`
  - `notes.md` describing rationale

Use `./tests/aif-hypothesis-sandbox/run-aif-hypothesis-test.sh` to run the regression suite across fixtures.
