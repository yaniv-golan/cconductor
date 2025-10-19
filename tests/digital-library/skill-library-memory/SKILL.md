# LibraryMemory Skill

## Description
Checks the persistent research memory for cached digests before issuing a WebFetch.

## Usage Guidance
- When provided a URL (or a short identifier), compute its hash and look for the corresponding file in the memory directory.
- If a digest exists, surface the summary and citations to the user and recommend skipping a fresh WebFetch unless explicit freshness is required.
- If no digest is found, continue with normal research workflow.

## Tooling Expectations
- Use the Memory Tool (`memory.view`) or client-provided helper scripts to read stored digests.
- Never overwrite user-provided knowledge-base assets; keep cached digests in the dedicated memory folder.

## Example Trigger Prompt
```
Before fetching https://example.com/topic, call the library memory skill to see if we already have a digest for it.
```

## Safety
Only read from memory; do not modify or delete entries unless explicitly instructed by the user.
