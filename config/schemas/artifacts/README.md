# Artifact Schema Notes

- `artifact://json/prompt-analysis@v1` distinguishes `objective` (the cleaned goal the orchestrator assigns to agents) from `research_question` (the verbatim user prompt). Treat them as separate fields when validating or transforming prompt analysis data to avoid conflating original wording with the normalized objective.
