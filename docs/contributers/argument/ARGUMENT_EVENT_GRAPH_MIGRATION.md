# Knowledge Graph ↔️ Argument Event Graph Migration Strategy

_Last updated: October 30, 2025._

## Goals
1. Dual-write claim/evidence data to both the legacy knowledge graph (KG) structure and the new Argument Event Graph (AEG).
2. Preserve backwards compatibility for existing resume flows and dashboards.
3. Provide reversible toggles (`CCONDUCTOR_ENABLE_AEG`, `CCONDUCTOR_ENABLE_KG_AEG_DUALWRITE`).

## File Layout
```
research-sessions/mission_xxx/
  knowledge/
    knowledge-graph.json     # Unchanged legacy knowledge graph
    knowledge-metadata.json  # Legacy metadata
  argument/
    aeg.log.jsonl            # Append-only event log
    aeg.graph.json           # Materialised graph
    aeg.quality.json         # Gate metrics
```

## Dual-Write Flow
1. `src/utils/argument-writer.sh` ingests structured events during agent execution. When `CCONDUCTOR_ENABLE_KG_AEG_DUALWRITE=1`, the writer emits simplified claim/evidence stubs into `knowledge/`.
2. `src/utils/materialize-argument-graph.sh` builds `aeg.graph.json` and `aeg.quality.json`.
3. `src/utils/kg-integrate.sh` reads both data sources; new helper `sync_aeg_to_kg_surfaces` merges relevant summaries.

## Migration Phases
| Phase | Toggle | Behaviour |
|-------|--------|-----------|
| 0.10  | `CCONDUCTOR_ENABLE_AEG=0` | AEG disabled, legacy behaviour. |
| 0.12  | `CCONDUCTOR_ENABLE_AEG=1` | Writer + materialiser enabled, exporter optional. |
| 0.20  | `CCONDUCTOR_ENABLE_KG_AEG_DUALWRITE=1` | Sync key metrics (`claim_coverage`, `contradiction_surface`) into KG knowledge metadata. |
| 0.30  | Remove toggle | AEG always on; fallback path retained via `--disable-aeg` CLI flag. |

## Rollback Procedure
1. Set `CCONDUCTOR_ENABLE_AEG=0` (environment variable or `config/mission.default.json` override).
2. Remove `argument/` directory if needed (or leave as artefact).
3. Rerun mission synthesis to regenerate reports without AEG gating.

## Migration Checklist
- [ ] Confirm `.claude/skills/argument-contract/` exists in new sessions and matches `./ARGUMENT_AGENT_CONTRACT.md`.
- [ ] Ensure `argument/` directories are git-ignored.
- [ ] Update `docs/SESSION_RESUME_GUIDE.md` with instructions for resuming missions with AEG artefacts.
- [ ] Add `aeg` key to `research-sessions/meta/session-manifest.json` entries (done in code).
- [ ] Update `tests/aif-hypothesis-sandbox/run-aif-hypothesis-test.sh` to load fixtures with both KG + AEG data.
- [ ] Regenerate `docs/AGENTS_DIRECTORY.md` after updating agent prompts.

## Known Limitations
- Full bidirectional migration (AEG → KG) is scoped for Phase 1. Currently only summary metrics sync back to the KG.
- Legacy resume scripts ignore `argument/`. Operators must re-run `materialize-argument-graph.sh` after resuming older missions.
- External tools referencing `knowledge/knowledge-graph.json` remain untouched; updates must be performed manually.

## Support Commands
- `./src/utils/materialize-argument-graph.sh --session $(./src/utils/path-resolver.sh resolve session_dir)`
- `./src/utils/kg-integrate.sh --session … --sync-aeg`

## Update Workflow
Whenever schema or dual-write behaviour changes:
1. Amend this document with new toggle states or migration steps.
2. Update `docs/UPGRADE.md` with a brief release note.
3. Ping maintainers to run end-to-end mission validation with both toggles.
