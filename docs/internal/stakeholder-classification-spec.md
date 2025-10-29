# Stakeholder Classification Reliability Spec

## Problem Statement

- **Quality gate gaps:** `src/utils/quality-gate.sh` fails missions when critical stakeholder categories have zero mapped sources, yet today up to ~20% of citations funnel into the fallback `"uncategorized"` bucket because substring matching in `src/utils/domain-helpers.sh` is brittle.  
- **In-mission overhead:** Analysts must hand-maintain `~/.config/cconductor/stakeholder-patterns.json` to teach the system that “transport.canada.ca” is a regulator or “PitchBook” is a benchmark provider. The warnings are noisy and drift persists across reruns.  
- **Knowledge graph integrity:** We deliberately avoid mutating `knowledge/knowledge-graph.json` during remediation, so any mid-mission fix must live alongside—not inside—the KG.  
- **Constraints:** We must reuse existing CLI agents (Claude Code missions, quality remediator), Bash helpers, and JSON tooling. No new third-party parsers or services.

## Objectives

1. **Deterministic gate decisions in-mission.** The gate must always know whether each mission-defined critical stakeholder has ≥1 supporting source, without relying on human pattern edits.  
2. **Fast pipeline first, LLM tail only.** Keep classification lightweight (patterns + heuristics) and call Claude only for the remaining tail, caching outputs so reruns are instant.  
3. **Mission-scoped flexibility.** Allow each mission to define the stakeholder vocabulary it cares about, yet keep the key list explicit so the gate can evaluate it.  
4. **Zero knowledge-graph mutation.** Store classification artifacts as session files (`session/...`) and leave KG structure untouched.  
5. **Auditable evolution.** Capture suggestions (new aliases, pattern promotions, unresolved items) in reports so maintainers can decide how to extend the resolver over time.

### Non-Goals

- Cross-mission taxonomy unification. (Future tooling may read mission outputs, but this spec stays mission-scoped.)  
- Introducing new dependencies (YAML parser, third-party libs). All artifacts remain JSON + Bash.  
- Replacing domain-heuristics agent or existing quality-remediator flows; instead we harness them.

## Current Infrastructure Overview

- **Domain heuristics agent (`src/utils/mission-orchestration.sh` lines ~1500-1600):** Emits stakeholder hints and watch items per mission.  
- **Pattern matcher (`src/utils/domain-helpers.sh::map_source_to_stakeholder`):** Substring-based matching + manual overrides.  
- **Quality gate (`src/utils/quality-gate.sh` + `artifacts/quality-gate.json`):** Aggregates counts, checks critical categories, reports `uncategorized_sources`.  
- **Quality remediator agent:** Already re-fetches fresher evidence; we can reuse its invocation plumbing for a classifier tail step.  
- **Session artifacts:** `research-sessions/<id>/session/`, `logs/events.jsonl`, `artifacts/quality-gate*.json`.

## Proposed Architecture

### 1. Mission-Scoped Policy & Resolver (JSON)

- **`policy.json` (template under `config/missions/<mission-id>/`):**
  ```json
  {
    "version": "0.3",
    "importance_levels": ["critical", "important", "informative"],
    "categories": {
      "regulator": {
        "importance": "critical",
        "description": "National or regional safety regulators"
      },
      "investigator": {
        "importance": "critical",
        "description": "Independent accident investigation bodies"
      },
      "operator": {
        "importance": "important",
        "description": "Airlines and charter operators"
      },
      "manufacturer": {
        "importance": "important",
        "description": "Airframe / engine / avionics OEMs"
      },
      "union": {
        "importance": "informative",
        "description": "Pilot or labor unions"
      }
    },
    "gate": {
      "min_sources_per_critical": 1,
      "min_total_sources": 12,
      "uncategorized_max_pct": 0.15
    }
  }
  ```
- **`resolver.json`:** Mission-owned alias/pattern map (templates in `config/missions/...`, session copies in `meta/`). Raw tags used for alias lookup come from deterministic hostname + title token extraction.
  ```json
  {
    "aliases": {
      "federal_authorities": "regulator",
      "faa": "regulator",
      "easa": "regulator",
      "transport canada": "regulator",
      "ntsb": "investigator"
    },
    "patterns": [
      {"pattern": "*.faa.gov", "category": "regulator"},
      {"pattern": "*.easa.europa.eu", "category": "regulator"},
      {"pattern": "*.tc.gc.ca", "category": "regulator"},
      {"pattern": "*.transport.canada.ca", "category": "regulator"},
      {"pattern": "*.ntsb.gov", "category": "investigator"}
    ]
  }
  ```
- **Consumption:** Extend `src/utils/domain-helpers.sh` to load mission-scoped `policy.json`/`resolver.json` (fallbacks if missing) using existing `load_config` plumbing; everything stays in Bash + `jq`.

### 2. Classification Pipeline (Session Scoped)

- **Entry point:** `src/utils/stakeholder-classifier.sh` (Bash + `jq`) invoked by mission orchestration whenever the KG source count increases (e.g., >40) or after the final iteration. The script persists a checkpoint (`session/stakeholder-classifier.checkpoint.json`) recording the last processed source count to avoid redundant work, for example:
  ```json
  {
    "last_run_timestamp": "2025-10-29T18:22:00Z",
    "kg_source_count": 47,
    "classifications_written": 43,
    "needs_review": 4
  }
  ```
- **Deterministic steps:**
  1. **Pattern match:** Extract URL hostname and compare against resolver globs using a `case "$host" in $pattern)` block.  
  2. **Alias lookup:** Generate raw tags (hostname + normalized title tokens/acronyms) and map via `resolver.aliases`.  
  3. **Heuristics:** Apply quick Bash rules (e.g., `.gov` ⇒ regulator; `union`+`pilot` ⇒ union).
- **LLM tail:** Remaining sources are batched (≤25) and sent to the `stakeholder-classifier` Claude agent through `invoke_agent.sh`. The prompt lists canonical keys from `policy.json` and requires JSON like:
  ```json
  [
    {"url": "...", "category": "regulator", "confidence": 0.94},
    {"url": "...", "category": "needs_review", "confidence": 0.31, "suggest_alias": {"alias": "civil_aviation", "category": "regulator"}}
  ]
  ```
  Input payload supplied to the agent:
  ```json
  {
    "canonical_categories": ["regulator", "investigator", "operator", "manufacturer", "union"],
    "sources": [
      {"url": "https://example.com/article", "title": "Example Title"},
      {"url": "https://another.com/report", "title": "Report Title"}
    ]
  }
  ```
  Default model selection follows the agent manifest (e.g., `claude-haiku-4-5`) and can be overridden per mission using the standard agent override config (e.g., `config/missions/<mission>/agent-overrides.json` or session `meta/agent-overrides.json`). Each batch invocation should record cost/duration via `budget_record_invocation` for visibility in mission metrics.
- **Output JSONL:** Each source appends a line to `session/stakeholder-classifications.jsonl`, using the existing hashing helper (shared with the library skill) for `source_id`:
  ```json
  {
    "source_id": "c9f6f2b4d1a3e5b0",
    "url": "https://www.transport.canada.ca/...",
    "raw_tags": ["transport.canada.ca", "transport", "canada", "authority"],
    "resolved_category": "regulator",
    "resolver_path": "pattern:*.transport.canada.ca",
    "confidence": 0.98,
    "llm_attempted": false,
    "timestamp": "2025-10-29T18:22:00Z"
  }
  ```
  If the shared helper is not yet exported from a common script, add a small wrapper (e.g., `hash_source_id()`) that formats the first 16 hex chars of `sha256(url)` so all features share consistent IDs.
- **Caching & logging:** Before hitting the LLM, the script checks (via `jq`) if `source_id` already exists. All classification runs emit `log_event` entries (start, completion, alias suggestions) for auditability.
- **Error handling:** If the agent reply is missing/invalid JSON, mark the batch as `"needs_review"`, log a warning via `log_warn`, and continue without blocking the mission.

### 3. Quality Gate Update

- Introduce `src/utils/stakeholder-gate.sh` (Bash + `jq`) that consumes `policy.json`, `resolver.json`, and `session/stakeholder-classifications.jsonl`.  
- Checks enforced:
  1. Each `categories[*].importance == "critical"` has ≥ `gate.min_sources_per_critical`.  
  2. `total_sources >= gate.min_total_sources`.  
  3. `(uncategorized / total) ≤ gate.uncategorized_max_pct` (where uncategorized includes `"needs_review"` or missing entries).
- The runner writes `session/stakeholder-gate-report.md` (human-readable summary) and `session/stakeholder-gate.json` (machine-readable snapshot).  
- `src/utils/quality-gate.sh` shells out to `stakeholder-gate.sh`, preserving the existing gate entry point while removing hard-coded pattern logic.

### 4. Mission Orchestration Hook

- After each orchestrator iteration:
  ```bash
  if command -v classify_stakeholders &>/dev/null || source "$UTILS_DIR/stakeholder-classifier.sh"; then
      classify_stakeholders "$session_dir" || log_warn "stakeholder classification failed"
  fi
  ```
- The wrapper locates mission policy/resolver files, checks KG source delta, runs deterministic steps, and batches Claude calls when required.  
- Reuse existing helpers (`safe_jq_from_file`, `hash_source_id`, logging utilities) to avoid duplication.

### 5. Optional Promotion Workflow

- Gate reports surface alias suggestions returned by the classifier.  
- Optional helper `tools/stakeholder_resolver_promote.sh` (Bash + `jq`) merges accepted suggestions into mission resolver templates with deterministic formatting.

## Implementation Plan

1. **Scaffold mission templates:** Add `config/missions/<mission>/policy.json` and `resolver.json` (seeded from domain-heuristics hints). Document workflow in `docs/QUALITY_GUIDE.md`.  
2. **Shell tooling:**  
   - `src/utils/stakeholder-classifier.sh` for deterministic classification + LLM tail + checkpointing.  
   - `src/utils/stakeholder-gate.sh` for policy enforcement + Markdown report.  
   - Optional `tools/stakeholder_resolver_promote.sh` for alias promotion.  
3. **Wire-up:** Update `quality-gate.sh` to call the new gate runner and `mission-orchestration.sh` to trigger the classifier on source growth.  
4. **Agent addition:** Add `src/claude-runtime/agents/stakeholder-classifier/system-prompt.md` and `src/claude-runtime/agents/stakeholder-classifier/metadata.json`, register in `library/manifest.json`, and ensure default model comes from the manifest (missions can override via config).  
5. **Testing:** Extend `tests/test-quality-gate.sh` with fixtures for policy/gate logic and add an integration scenario demonstrating classification + reporting.  
6. **Docs:** Update `docs/QUALITY_GUIDE.md` and mission READMEs with instructions for editing policy/resolver and promoting aliases.



## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| Classification backlog if LLM unavailable | Pipeline marks as `needs_review`, gate report highlights; rerun once LLM back. |
| Resolver bloat | Review alias suggestions in gate report; only promote high-confidence entries. |
| Policy drift | Keep `policy.json` minimal; re-use domain heuristics watch items to seed categories. |
| Performance | Patterns + heuristics handle majority; LLM tail chunked (e.g., 25 sources per call) with cache. |

## Deliverables

- Mission-scoped `policy.json` and `resolver.json` templates.  
- `session/stakeholder-classifications.jsonl` + `session/stakeholder-gate-report.md` artifacts per run.  
- Updated `quality-gate` outputs reflecting new checks.  
- Documentation in `docs/QUALITY_GUIDE.md` and this spec (`docs/internal/stakeholder-classification-spec.md`) to guide future maintainers.

## Implementation Progress (2025-10-29)

- Mission profile directories now contain `profile.json`, `policy.json`, and `resolver.json` templates for built-in missions; defaults live in `config/stakeholder-policy.default.json` and `config/stakeholder-resolver.default.json`.
- Added `src/utils/stakeholder-classifier.sh` with deterministic pattern/alias/heuristic passes, mission-scoped config resolution, LLM batching via the new `stakeholder-classifier` agent hook, checkpointing, and JSONL output.
- Added `src/utils/stakeholder-gate.sh` that evaluates classification artifacts, writes structured/Markdown reports, and surfaces alias promotion candidates.
- Mission orchestration loop now refreshes stakeholder classifications each iteration; quality gate integrates the new stakeholder gate outputs for pass/fail decisions and uncategorized summaries.
