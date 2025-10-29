#!/usr/bin/env bash
# Quality gate regression test

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_SCRIPT="$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

write_stakeholder_artifacts() {
    local dir="$1"
    mkdir -p "$dir/session"
    cat >"$dir/session/stakeholder-classifications.jsonl" <<'JSONL'
{"source_id":"s1","url":"https://www.whitehouse.gov","raw_tags":["whitehouse","government"],"resolved_category":"government","resolver_path":"pattern:*.gov","confidence":0.95,"llm_attempted":false,"timestamp":"2025-10-29T00:00:00Z"}
{"source_id":"s2","url":"https://journals.example.edu","raw_tags":["example.edu","academic"],"resolved_category":"academic","resolver_path":"pattern:*.edu","confidence":0.90,"llm_attempted":false,"timestamp":"2025-10-29T00:00:00Z"}
JSONL
    mkdir -p "$dir/meta"
    cat >"$dir/meta/stakeholder-policy.json" <<'EOF'
{
  "version": "0.3",
  "importance_levels": ["critical", "important"],
  "categories": {
    "government": {"importance": "critical"},
    "academic": {"importance": "critical"}
  },
  "gate": {
    "min_sources_per_critical": 1,
    "min_total_sources": 2,
    "uncategorized_max_pct": 0.25
  }
}
EOF
    cat >"$dir/meta/stakeholder-resolver.json" <<'EOF'
{
  "aliases": {
    "government": "government",
    "academic": "academic"
  },
  "patterns": [
    {"pattern": "*.gov", "category": "government"},
    {"pattern": "*.edu", "category": "academic"}
  ]
}
EOF
}

create_session_json() {
    local session_dir="$1"
    mkdir -p "$session_dir/meta"
    cat >"$session_dir/meta/session.json" <<'EOF'
{
    "created_at": "2025-10-14T00:00:00Z",
    "objective": "Test quality gate"
}
EOF
}

mkdir -p "$tmp_root/pass"
create_session_json "$tmp_root/pass"
write_stakeholder_artifacts "$tmp_root/pass"
mkdir -p "$tmp_root/pass/knowledge"
mkdir -p "$tmp_root/pass/artifacts"
cat >"$tmp_root/pass/knowledge/knowledge-graph.json" <<'EOF'
{
    "claims": [
        {
            "id": "c0",
            "statement": "Sample claim passes gate",
            "confidence": 0.92,
            "sources": [
                {
                    "url": "https://journal.example.edu/paper",
                    "credibility": "peer_reviewed",
                    "date": "2025-01-01"
                },
                {
                    "url": "https://data.gov/report",
                    "credibility": "official",
                    "date": "2024-10-01"
                }
            ]
        }
    ],
    "stats": {
        "unresolved_contradictions": 0
    }
}
EOF

"$GATE_SCRIPT" "$tmp_root/pass" >/tmp/quality-gate-test-pass.log 2>&1
pass_exit=$?
if [[ $pass_exit -ne 0 ]]; then
    echo "Expected pass case to succeed, exit $pass_exit" >&2
    cat /tmp/quality-gate-test-pass.log >&2 || true
    exit 1
fi

pass_report="$tmp_root/pass/artifacts/quality-gate.json"
if [[ ! -f "$pass_report" ]]; then
    echo "Pass report missing at $pass_report" >&2
    exit 1
fi

pass_status=$(jq -r '.status' "$pass_report")
if [[ "$pass_status" != "passed" ]]; then
    echo "Expected pass status, got $pass_status" >&2
    exit 1
fi

pass_summary="$tmp_root/pass/artifacts/quality-gate-summary.json"
if [[ ! -f "$pass_summary" ]]; then
    echo "Pass summary missing at $pass_summary" >&2
    exit 1
fi

if [[ "$(jq -r '.status' "$pass_summary")" != "passed" ]]; then
    echo "Expected pass summary to mark status passed" >&2
    exit 1
fi

mkdir -p "$tmp_root/fail"
create_session_json "$tmp_root/fail"
write_stakeholder_artifacts "$tmp_root/fail"
mkdir -p "$tmp_root/fail/knowledge"
mkdir -p "$tmp_root/fail/artifacts"
cat >"$tmp_root/fail/knowledge/knowledge-graph.json" <<'EOF'
{
    "claims": [
        {
            "id": "c0",
            "statement": "This claim should fail gate",
            "confidence": 0.55,
            "sources": [
                {
                    "url": "https://single-source.example.com/post",
                    "credibility": "blog",
                    "date": "2020-01-01"
                }
            ]
        }
    ],
    "stats": {
        "unresolved_contradictions": 2
    }
}
EOF

"$GATE_SCRIPT" "$tmp_root/fail" >/tmp/quality-gate-test-fail.log 2>&1
fail_exit=$?
if [[ $fail_exit -ne 0 ]]; then
    echo "Expected advisory mode to exit 0 for failing gate, got $fail_exit" >&2
    cat /tmp/quality-gate-test-fail.log >&2 || true
    exit 1
fi

fail_report="$tmp_root/fail/artifacts/quality-gate.json"
if [[ ! -f "$fail_report" ]]; then
    echo "Failure report missing at $fail_report" >&2
    exit 1
fi

fail_status=$(jq -r '.status' "$fail_report")
if [[ "$fail_status" != "failed" ]]; then
    echo "Expected failed status, got $fail_status" >&2
    exit 1
fi

fail_summary="$tmp_root/fail/artifacts/quality-gate-summary.json"
if [[ ! -f "$fail_summary" ]]; then
    echo "Failure summary missing at $fail_summary" >&2
    exit 1
fi

if [[ "$(jq -r '.status' "$fail_summary")" != "failed" ]]; then
    echo "Expected failure summary to mark status failed" >&2
    exit 1
fi

failed_claims=$(jq '.summary.failed_claims' "$fail_report")
if [[ "$failed_claims" -lt 1 ]]; then
    echo "Expected at least one failed claim, got $failed_claims" >&2
    exit 1
fi

echo "Quality gate tests passed."
