# LibraryMemory Skill

> **Use this skill whenever a research agent is about to call WebFetch.**
> It checks the shared research library and returns cached evidence so we can avoid redundant fetches.

## Quick Summary (TL;DR)
- Purpose: reuse digests from `library/` instead of hitting WebFetch.
- Main actions: hash URL → show digest → summarise → recommend `reuse` or `refresh`.
- Typical users: web-researcher, academic-researcher, fact-checker, market-analyzer.

## When to Use
- Before WebFetch/WebSearch on a URL that might already be stored
- When the orchestrator says "check cached sources" or "library has a digest"
- When validating an existing claim’s URL and you want supporting quotes quickly

## Provided Commands
- `bash library-memory/hash-url.sh <url>` → SHA-256 hash of the URL
- `bash library-memory/show-digest.sh [--limit N] (--url <url> | --hash <hash>)` → returns a concise JSON digest

## Library Layout
- `library/manifest.json` – manifest keyed by URL hash (`sha256(url)`)
- `library/sources/<hash>.json` – digest with `url`, `titles`, `entries[]` (claim, quote, confidence, session, collected_at)
- Every session has a symlink `library/ → <project-root>/library`

## Workflow
1. **Hash** the target URL: `bash library-memory/hash-url.sh <url>`
2. **Retrieve digest**: `bash library-memory/show-digest.sh --hash <hash>`
3. If the command returns `{}`, report “no cached digest found” and proceed with normal fetch logic. Otherwise:
   - Summarize key entries (claim, quote, confidence, session)
   - Note `last_updated` and advise whether cached evidence is sufficient
4. Respond to the caller with a brief digest summary and recommendation (`reuse cached evidence` vs `fetch fresh copy`).

### Expected Response Snippet
```
Cached digest found for https://alejandrocremades.com/... (last_updated 2025-10-19T14:21:25Z)
- Claim: VCs require $1B+ TAM (confidence 0.90)
  Quote: "Your market size should be at least $1B. Probably more."
- Claim: SOM expectations are 1-5% (confidence 0.90)
  Quote: "Most VCs believe 1-5% is a good range."
Recommendation: reuse cached evidence; skip WebFetch unless fresher data is required.
```

## Safety & Limits
- Read-only access to `library/`
- If files are missing or malformed, return a clear explanation
- Only quote what exists in the stored entries—never fabricate evidence
- If `last_updated` is older than ~6 months or the user explicitly requests fresh data, recommend fetching a live copy.

## Failure Handling
- If `hash-url.sh` or `show-digest.sh` fails, respond with the error message and instruct the caller to proceed with WebFetch.
- If the manifest/digest JSON is malformed, report the issue and do not attempt to patch it.
- Keep responses concise (1–3 bullet points plus recommendation) unless the user explicitly asks for more detail.
