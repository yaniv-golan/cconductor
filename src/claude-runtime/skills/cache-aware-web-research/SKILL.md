# Cache-Aware Web Research Skill

> **Use this skill before any WebSearch or WebFetch invocation.**
> It guides agents through cache-aware querying so we reuse existing results, fall back to LibraryMemory digests, and only request fresh data when necessary.

## Quick Summary (TL;DR)
- Purpose: Standardize how every agent reuses cached search results and web digests.
- Tools: `scripts/cache-query-similar.sh`, `library-memory/show-search.sh`, `library-memory/hash-url.sh`, `library-memory/show-digest.sh`.
- Outcome: Fewer redundant calls, consistent logging (`?fresh=1` when needed), and clear reasoning about cache usage.

## When to Use
- Before running WebSearch for any topic that might already be cached.
- Before issuing WebFetch on a URL that could exist in LibraryMemory.
- When the orchestrator or hooks surface “Cached Sources Available” notices.
- During remediation/fact-check flows when you need fresher evidence—this skill explains when to refresh and how to document it.

## Shared Workflow

### 1. Inspect Similar Queries
1. Run `bash scripts/cache-query-similar.sh "<draft query>"`.
2. Review the scored list:
   - If a result has `score ≥ 0.75` (or obviously covers the same concept), reuse its canonical token ordering.
   - Note the `canonical tokens` string for reuse; only append qualifiers (e.g., `"2025"`, `"EU"`) when absolutely necessary.
3. If you adjust the canonical tokens, log why (different geography, timeline, scope).

### 2. Check Cached Search Results
1. Execute `bash library-memory/show-search.sh --query "<canonical tokens>"`.
2. If results exist:
   - Open the referenced JSON file with `Read` to review snippets, providers, timestamps.
   - Decide whether they answer the current question.
3. Only invoke WebSearch if:
   - No cached results exist.
   - Cached snippets are insufficient (missing key aspects, wrong domain focus).
   - You need data about events that occurred AFTER the cache timestamp (breaking news, very recent developments).

**IMPORTANT:** Do NOT use `?fresh=1` just because you need "recent content" (e.g., 2023-2025 papers). Cached search results already contain recent URLs - the cache stores WHICH URLs were found, not the content age. Only use `?fresh=1` when:
   - The search landscape has changed (new sources emerged, major event happened)
   - The cached search is >30 days old AND the topic is fast-moving (breaking news, tech releases)
   - NOT when you simply want papers from recent years (cached searches find those just fine)

### 3. Reuse or Refresh WebFetch Targets
1. For each candidate URL, run:
   ```bash
   bash library-memory/hash-url.sh "<url>"
   bash library-memory/show-digest.sh --hash "<hash>"
   ```
2. If a digest exists:
   - Inspect key quotes, sessions, last-updated timestamp.
   - If still relevant, reuse it (cite the cached digest).
3. If stale or missing:
   - Append `?fresh=1` to the URL when issuing WebFetch.
   - Record why a live fetch is required (e.g., “needs data after 2025-06”).

### 4. Document Decisions
- Mention cached timestamps or canonical tokens in your reasoning so downstream agents understand reuse.
- If you bypass the cache, state the condition (staleness, missing detail, explicit freshness requirement).
- Hooks already enforce caching; your job is to narrate the rationale so the research log is clear.

## Expected Response Snippet
```
Cached search results found for canonical tokens "tam sam som venture capital best practice" (last refresh 2025-09-12T18:04:10Z)
- Using cached snippets from scripts/cache-query-similar.sh (score 0.82) + library-memory/show-search.sh
- Reusing LibraryMemory digest for https://a16z.com/16-more-metrics/ (last_updated 2025-09-05T11:22:08Z)
Decision: reuse cached evidence; no fresh WebSearch/WebFetch required.
```
If you must refresh (rare):
```
Cached search results are from 45 days ago, before the Q4 2025 market report release. Using WebSearch?fresh=1 to capture new analyst sources. Reason: Major market event occurred after cache timestamp.
```

**Bad example (DO NOT DO THIS):**
```
❌ WRONG: "Need 2023-2025 papers, cached search is from June. Using ?fresh=1 to get recent content."
✓ CORRECT: "Cached search from June already contains 2024 paper URLs. Reusing cache."
```

## Safety & Limits
- The Bash tool runs inside the Claude Code sandbox (no outbound network, no package installs). Only call scripts that exist in the repository.
- Hooks still enforce caching automatically; this skill ensures your reasoning explains the decision.
- Do not fabricate cache hits. If scripts return no data, state that plainly and justify any fresh queries.
- Respect mission budgets: keep fresh WebSearch/WebFetch calls focused and tied to explicit needs.

## Failure Handling
- If a script fails, surface the stderr output and fall back gracefully (e.g., request a fresh search with justification).
- If required scripts are missing, report the missing path and proceed cautiously without the cache shortcut.
- When uncertain about freshness, prefer reuse but flag the uncertainty so downstream agents can revisit if needed.
