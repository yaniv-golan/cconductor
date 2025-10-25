# Digital Research Library & On-Demand Retrieval Plan

> **Objective**  
> Turn post-mission knowledge into a first-class, runtime-managed “research library” that every mission can search before touching the open web. This avoids redundant fetches, preserves institutional learning, and keeps user-owned `knowledge-base-custom/` distinct from system-generated assets.

## 1. Background & Constraints

- **Claude WebFetch responses** do **not** expose full HTML/markdown bodies to hooks (per [Claude Code SDK docs](https://anthropic.mintlify.app/en/docs/claude-code/sdk/sdk-python?utm_source=chatgpt)). We can only persist the structured summaries our agents already create.
- **Knowledge graph + artifacts** already capture vetted claims, citations, and agent outputs, but they are session-scoped. There is no shared, growing corpus.
- `knowledge-base-custom/` is **reserved for user-supplied material** (see `memory-bank/systemPatterns.md` and `memory-bank/projectbrief.md`). System-generated content must live elsewhere.
- Auto-loading large corpora into prompts would blow out context windows; we need a **search-first, load-later** model.

## 2. High-Level Architecture

```
┌──────────────────────┐
│  Post-Mission Stage  │
│  (Digital Librarian) │
└─────────┬────────────┘
          │ 1. Source diffs (citations, KG, artifacts)
          ▼
┌──────────────────────┐
│  System Library Dir  │  <-- new `library/` tree under project root
│  (structured digests)│
└─────────┬────────────┘
          │ 2. Library manifest updates (+ metadata, tags, timestamps)
          ▼
┌──────────────────────┐
│  Library Search Agent│  <-- invoked at mission start / before WebFetch
│  (Read/Grep tools)   │
└─────────┬────────────┘
          │ 3. Emits relevant excerpts + citations
          ▼
┌──────────────────────┐
│  Orchestrator        │  <-- decides if fresh WebFetch still needed
└──────────────────────┘
```

## 3. Deliverables & Workstreams

### 3.1 Library Data Model & Storage
- Create `library/` (repo-managed) with subfolders such as:
  - `library/sources/<year>/<source-slug>.md` – curated digest per source.
  - `library/manifests/index.json` – metadata (URL, hash, tags, domains, first_seen, last_refreshed).
  - `library/topics/<topic>/…` (optional taxonomy for seeded sessions).
- Standardize digest format (front-matter YAML + sections for summary, key claims, quotes, citations). Reference: [Data Catalog Best Practices – NLA](https://www.nla.gov.au/guides/datacatalog) for metadata inspiration.

### 3.2 Digital Librarian Pipeline (post-mission)
- New script `src/utils/digital-librarian.sh` orchestrates:
  1. Collect new sources from `artifacts/manifest.json`, `citations.json`, and knowledge graph diffs.
  2. For each source, invoke a **librarian agent** (new prompt) that builds the digest using existing findings. No new WebFetch calls.
  3. Write digest + update library manifest atomically (use `shared-state.sh` locks).
  4. Attach provenance (session ID, agents, confidence metrics).
- Trigger pipeline from `mission-orchestration.sh`’s completion path or a dedicated `scripts/run-digital-librarian.sh`.

### 3.3 Library Search Agent
- Define `src/claude-runtime/agents/library-search/` with:
  - Tools: `Read`, `Grep`, possibly `Bash` (whitelisted script like `library-search.sh` for regex filtering).
  - Prompt instructing it to: (a) scan provided library file list; (b) emit concise structured findings; (c) recommend fresh research if gaps remain.
- Build helper `src/utils/library-search.sh` that:
  - Selects candidate digests based on manifest metadata (topic tags, recency, domains).
  - Materializes file list for the agent.
  - Caches search results in session `artifacts/` for traceability.

### 3.4 Orchestration Integration
- Update `mission-orchestration.sh` flow:
  1. After prompt parsing and before scheduling web-researcher, call library search helper.
  2. Merge library search findings into knowledge graph / agent context.
  3. Decide whether additional WebFetch tasks are still required.
- Ensure knowledge loader respects new library outputs without auto-loading entire directory—only targeted excerpts enter prompts.

### 3.5 Tooling & CLI Support
- Add `cconductor library` commands (`list`, `show`, `clean`, `rebuild`) to inspect the system library.
- Provide docs for contributors describing librarian pipeline, directory layout, and how to manually refresh digests.

### 3.6 Observability & Testing
- Telemetry: Record counts of library hits vs. fresh WebFetch in `viewer/dashboard-metrics.json`.
- Tests:
  - Unit tests for manifest writer & diff logic (`tests/test-digital-librarian.sh`).
  - Integration test running a fake mission twice; second run should consume only library digests.
  - Regression guard to ensure library digests never leak into `knowledge-base-custom/`.

## 4. Implementation Phases

| Phase | Scope | Key Tasks |
|-------|-------|-----------|
| ✅ P0 (design) | Plan (this doc) | Gather requirements, align with memory-bank |
| 🟡 P1 (infra) | Library filesystem + manifest | Create directory, schema, helper utilities |
| 🟡 P2 (librarian) | Digest generation | Agent prompt, scripts, orchestrator hook-in |
| 🟡 P3 (search) | Library search agent & orchestrator bridge | Helper script, prompt injection, knowledge graph merge |
| 🟡 P4 (tooling) | CLI + docs + tests | Commands, regression tests, documentation updates |

## 5. External References

- Anthropic Claude Code Hooks Guide (pre/post tool limitations): <https://docs.claude.com/en/docs/claude-code/hooks>
- Digital library metadata patterns (National Library of Australia): <https://www.nla.gov.au/guides/datacatalog>
- Incremental knowledge systems (LangGraph Plan/Execute pattern): <https://langchain-ai.github.io/langgraph/tutorials/plan-and-execute/plan-and-execute/>

## 6. Open Questions
- Should we introduce topic taxonomies to avoid unbounded growth in a single folder?
- How aggressively do we prune or refresh old digests (TTL vs. user-triggered refresh)?
- Do we need lightweight embeddings for better local search, or will structured tags suffice initially?

---

**Next step:** implement Phase P1 – create library scaffolding (`library/`, manifest writer, helper scripts) so subsequent phases can hook into a consistent structure.
