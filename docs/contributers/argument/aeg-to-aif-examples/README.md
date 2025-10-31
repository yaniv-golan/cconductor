# Fixture Directory

Placeholder directory for sample AEG → AIF fixtures. Populate with mission-sized examples when available:

- `minimal/`
- `complex/`
- `regression/`

Each fixture should include `aeg.log.jsonl`, `aeg.graph.json`, `expected.aif.jsonld`, and `notes.md`. The automated tests in `tests/aif-hypothesis-sandbox/run-aif-hypothesis-test.sh` read from these fixtures when present.
