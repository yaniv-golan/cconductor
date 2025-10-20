# Cache-Aware Web Research Skill – Implementation Plan

## Objective

Create a shared Claude Code skill that standardizes cache-aware web search and fetch guidance for every agent that uses `WebSearch` or `WebFetch`, while retaining existing CLI hook enforcement. The skill should encapsulate the canonical workflow—query normalization, cache inspection, LibraryMemory digests, and controlled refreshes—so individual prompts can defer to it for consistent behavior.

## Current State Recap

- Pre/Post tool hooks already enforce caching via `web-search-cache.sh` and `web-cache.sh`.
- Agent prompts currently repeat cache instructions with inconsistent detail; some agents lack guidance entirely.
- Skills are copied into each session under `.claude/skills/` by `mission-session-init.sh`, making them available to all agents automatically.

## Deliverables

1. **Skill package** under `src/claude-runtime/skills/cache-aware-web-research/` containing:
   - `SKILL.md` with description, activation cues, and step-by-step instructions.
   - Optional helper scripts (if needed) that rely only on repo files.
2. **Prompt updates** so web-enabled agents reference the skill instead of duplicating instructions.
3. **Documentation updates** (README/USAGE + contributor docs) describing the skill.
4. **Regression coverage** ensuring behavior is unchanged/functionally improved.

## Implementation Steps

### Phase 1 – Skill Scaffolding
- [ ] Create `src/claude-runtime/skills/cache-aware-web-research/`.
- [ ] Author `SKILL.md` covering:
  - When to invoke (before WebSearch/WebFetch).
  - Steps: run `scripts/cache-query-similar.sh`, check `library-memory/show-search.sh`, consult `library-memory/hash-url.sh` & `show-digest.sh`, decide on `?fresh=1`, record rationale.
  - Safety notes (sandbox execution, no network access, rely on existing scripts).
  - Example responses.
- [ ] Ensure `mission-session-init.sh` copies the new skill (already handled by `copy_skills`, verify no changes needed).

### Phase 2 – Prompt Alignment
- [ ] Update prompts for:
  - mission-orchestrator
  - web-researcher
  - academic-researcher
  - fact-checker
  - market-analyzer
  - quality-remediator
- [ ] Replace redundant cache instructions with a concise directive to use the skill, keeping agent-specific nuances.
- [ ] Ensure the prompts still mention when fresh data is required (e.g., stale evidence).

### Phase 3 – Documentation
- [ ] README / USAGE: add “Built-in Skills” section listing Cache-Aware Web Research + LibraryMemory.
- [ ] Contributor docs (if any) explaining how to modify the skill.
- [ ] Internal memory bank update noting the shared skill pattern.

### Phase 4 – Testing
- [ ] Run targeted missions (e.g., simple query) to confirm agents load the skill and still hit caches.
- [ ] Monitor `events.jsonl` for `?fresh=1` usage and `library_digest_hit` events.
- [ ] Re-run relevant regression tests (`tests/test-mission-report-paths.sh` already part of workflow, add others if needed).

### Phase 5 – Rollout
- [ ] Update CHANGELOG or release notes.
- [ ] Document the change in PR summary.
- [ ] Communicate to team that cache instructions are centralized in the new skill.

## Timeline (estimate)

| Phase | Task | Effort |
|-------|------|--------|
| 1 | Skill scaffolding | 0.5 day |
| 2 | Prompt updates | 0.5–1 day |
| 3 | Docs | 0.25 day |
| 4 | Testing | 0.5 day |
| 5 | Rollout | 0.1 day |

Total ≈ 2–3 dev days.

## Open Considerations
- Skill should rely solely on existing scripts; no new dependencies allowed (sandbox constraint).
- Hooks remain the source of truth—skill is for reasoning consistency.
- Consider telemetry later to ensure agents invoke the skill (optional).
