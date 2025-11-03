### JSON Artifact Schemas

Schemas under this directory describe machine-readable artifacts written by agents via the Write tool (for example `artifact://json/prompt-analysis@v1`). Place new JSON artifact schemas here so `artifact_schema_path` can resolve `artifact://json/<name>@vX` IDs without collisions with other schema families (markdown, orchestrator, synthesis, etc.).
