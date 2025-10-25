# Cost Capture Validation (Manual Test)

This helper script exercises the assumptions behind the “Persist Per‑Invocation
Claude Costs” plan without touching the production codebase.

## What it checks

1. The jq expression `(.usage.total_cost_usd // .total_cost_usd // 0) |
   tonumber? // 0` returns the expected value for:
   - Responses with `usage.total_cost_usd`
   - Responses with only top-level `total_cost_usd`
   - Responses missing both fields (fallback to 0)
2. Passing the extracted cost into `budget_record_invocation` updates
   `meta/budget.json` (`spent.cost_usd` and the per-invocation ledger).

## Running the test

```bash
cd "$(git rev-parse --show-toplevel)"
bash tests/manual/cost-capture-validation/run_cost_capture_tests.sh
```

The script creates a throwaway session directory under `mktemp`, so it is safe
to run on any machine and leaves no residue. A success run prints “All cost
capture assumptions validated.” and exits 0; any failure stops immediately with
an explanatory message.

Delete this `tests/manual/cost-capture-validation/` directory when you no longer
need the manual check.
