#!/usr/bin/env bash
# Manual validation harness for the "Persist Per-Invocation Claude Costs" plan.
# It verifies that:
#   1) The jq expression we rely on correctly extracts cost from representative
#      Claude CLI responses.
#   2) Passing that cost into budget_record_invocation updates meta/budget.json as
#      expected (both spent.cost_usd and invocation entries).
#
# Run from the repository root:
#   bash tests/manual/cost-capture-validation/run_cost_capture_tests.sh

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# shellcheck source=/dev/null
source "$REPO_ROOT/src/utils/budget-tracker.sh"

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/cc-cost-test.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT

session_dir="$tmp_root/session"
mkdir -p "$session_dir/work/test-agent"

mission_profile='{
  "constraints": {
    "budget_usd": 25,
    "max_agent_invocations": 10,
    "max_time_minutes": 60
  }
}'

budget_init "$session_dir" "$mission_profile"

extract_cost() {
  local file="$1"
  jq -r '
    (.usage.total_cost_usd // .total_cost_usd // 0)
    | tonumber? // 0
  ' "$file"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if awk -v expected="$expected" -v actual="$actual" '
BEGIN {
  diff = expected - actual
  if (diff < 0) {
    diff = -diff
  }
  abs_tol = 1e-9
  rel_tol = 1e-9
  if (diff <= abs_tol) {
    exit 0
  }
  abs_expected = (expected < 0 ? -expected : expected)
  abs_actual = (actual < 0 ? -actual : actual)
  max_val = (abs_expected > abs_actual ? abs_expected : abs_actual)
  if (max_val == 0) {
    exit (diff <= abs_tol ? 0 : 1)
  }
  if (diff <= rel_tol * max_val) {
    exit 0
  }
  exit 1
}
'; then
    printf '  ✓ %s\n' "$message"
  else
    echo "❌ $message (expected=$expected actual=$actual)" >&2
    exit 1
  fi
}

echo "== Cost extraction cases =="

# Case 1: cost under .usage.total_cost_usd
cat > "$session_dir/work/test-agent/output_case_usage.json" <<'JSON'
{
  "usage": {
    "total_cost_usd": 0.0524267,
    "input_tokens": 1234,
    "output_tokens": 567
  }
}
JSON
cost1=$(extract_cost "$session_dir/work/test-agent/output_case_usage.json")
assert_eq 0.0524267 "$cost1" ".usage.total_cost_usd parsed"

# Case 2: fallback to top-level .total_cost_usd
cat > "$session_dir/work/test-agent/output_case_top.json" <<'JSON'
{
  "total_cost_usd": 0.0195,
  "usage": {
    "input_tokens": 321,
    "output_tokens": 100
  }
}
JSON
cost2=$(extract_cost "$session_dir/work/test-agent/output_case_top.json")
assert_eq 0.0195 "$cost2" "top-level total_cost_usd parsed"

# Case 3: missing cost (should be zero)
cat > "$session_dir/work/test-agent/output_case_missing.json" <<'JSON'
{
  "usage": {
    "input_tokens": 42,
    "output_tokens": 24
  }
}
JSON
cost3=$(extract_cost "$session_dir/work/test-agent/output_case_missing.json")
assert_eq 0 "$cost3" "missing cost defaults to zero"

echo
echo "== Budget tracker integration =="

# Record first invocation
budget_record_invocation "$session_dir" "test-agent" "$cost1" 11

spent_after_first=$(jq -r '.spent.cost_usd' "$session_dir/meta/budget.json")
assert_eq "$cost1" "$spent_after_first" "spent.cost_usd equals first cost"

first_invocation_cost=$(jq -r '.invocations[0].cost_usd' "$session_dir/meta/budget.json")
assert_eq "$cost1" "$first_invocation_cost" "invocations[0].cost_usd stored"

# Record second invocation with fallback cost (no cost field)
budget_record_invocation "$session_dir" "test-agent" "$cost3" 5

spent_after_second=$(jq -r '.spent.cost_usd' "$session_dir/meta/budget.json")
expected_total=$(printf 'scale=12; (%s) + (%s)\n' "$cost1" "$cost3" | bc -l)
assert_eq "$expected_total" "$spent_after_second" "spent.cost_usd accumulates"

echo
echo "All cost capture assumptions validated."
