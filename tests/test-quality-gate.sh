#!/usr/bin/env bash
# Quality gate regression test

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_SCRIPT="$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh"

resolve_test_bash_runtime() {
    if [[ -n "${CCONDUCTOR_BASH_RUNTIME:-}" && -x "${CCONDUCTOR_BASH_RUNTIME}" ]]; then
        printf '%s' "$CCONDUCTOR_BASH_RUNTIME"
        return 0
    fi

    local candidate
    for candidate in "/opt/homebrew/bin/bash" "/usr/local/bin/bash"; do
        if [[ -x "$candidate" ]]; then
            CCONDUCTOR_BASH_RUNTIME="$candidate"
            export CCONDUCTOR_BASH_RUNTIME
            printf '%s' "$candidate"
            return 0
        fi
    done

    candidate="$(command -v bash || true)"
    if [[ -z "$candidate" ]]; then
        echo "Error: Unable to locate a bash runtime in PATH." >&2
        exit 1
    fi

    CCONDUCTOR_BASH_RUNTIME="$candidate"
    export CCONDUCTOR_BASH_RUNTIME
    printf '%s' "$candidate"
}

ensure_modern_bash_runtime() {
    local runtime
    runtime="$(resolve_test_bash_runtime)"

    local major
    # shellcheck disable=SC2016 # evaluated inside the child bash process
    major="$("$runtime" -c 'printf "%s" "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
    if (( major < 4 )); then
        echo "Quality gate tests require Bash >= 4. Found $major at $runtime." >&2
        echo "Install a newer bash (e.g., via \"brew install bash\") and re-run the tests." >&2
        exit 1
    fi

    printf '%s' "$runtime"
}

BASH_RUNTIME="$(ensure_modern_bash_runtime)"
export CCONDUCTOR_BASH_RUNTIME="$BASH_RUNTIME"
BASH_RUNTIME_DIR="$(dirname "$BASH_RUNTIME")"
case ":$PATH:" in
    *":$BASH_RUNTIME_DIR:"*) ;;
    *) PATH="$BASH_RUNTIME_DIR:$PATH" ;;
esac
export PATH

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

mkdir -p "$tmp_root/independence/knowledge"
cat >"$tmp_root/independence/knowledge/knowledge-graph.json" <<'EOF'
{
  "claims": [
    {
      "id": "c-001",
      "statement": "Duplicated domain evidence should fail the enforcement check.",
      "sources": [
        {"url": "https://domain.test/article-a"},
        {"url": "https://domain.test/article-b"}
      ]
    }
  ]
}
EOF

# Expect enforcement to block synthesis when only one domain is present
# shellcheck disable=SC2016
if CCONDUCTOR_REQUIRE_INDEPENDENT_SOURCES=1 PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/independence" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_independent_sources "$SESSION_DIR"
'; then
    echo "Expected independent source check to block synthesis but it succeeded" >&2
    exit 1
fi

issues_file="$tmp_root/independence/meta/independent-source-issues.json"
if [[ ! -f "$issues_file" ]]; then
    echo "Expected independent source issues file to be written" >&2
    exit 1
fi

missing_domains=$(jq -r '.[0].additional_domains_needed' "$issues_file")
if [[ "$missing_domains" -lt 1 ]]; then
    echo "Expected missing domain count >= 1, got $missing_domains" >&2
    exit 1
fi

# Update knowledge graph with a second domain and expect the check to pass
cat >"$tmp_root/independence/knowledge/knowledge-graph.json" <<'EOF'
{
  "claims": [
    {
      "id": "c-001",
      "statement": "Sufficient domain diversity should pass the enforcement check.",
      "sources": [
        {"url": "https://domain.test/article-a"},
        {"url": "https://another.test/report"}
      ]
    }
  ]
}
EOF

# shellcheck disable=SC2016
if ! CCONDUCTOR_REQUIRE_INDEPENDENT_SOURCES=1 PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/independence" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_independent_sources "$SESSION_DIR"
'; then
    echo "Expected independent source check to pass after adding a new domain" >&2
    exit 1
fi

if [[ -f "$issues_file" ]]; then
    echo "Expected independent source issues file to be cleared after passing check" >&2
    exit 1
fi

mkdir -p "$tmp_root/synthesis/artifacts/synthesis-agent"
cat >"$tmp_root/synthesis/artifacts/synthesis-agent/completion.json" <<'EOF'
{
  "synthesized_at": "2025-10-30T00:00:00Z"
}
EOF

# shellcheck disable=SC2016
if PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/synthesis" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    validate_required_synthesis_artifacts "$SESSION_DIR"
'; then
    echo "Expected synthesis artifact validation to fail for incomplete artifacts" >&2
    exit 1
fi

if ! "$PROJECT_ROOT/src/utils/regenerate-synthesis-artifacts.sh" --force "$tmp_root/synthesis" >/tmp/regenerate-synthesis.log 2>&1; then
    echo "Expected regeneration helper to succeed" >&2
    cat /tmp/regenerate-synthesis.log >&2 || true
    exit 1
fi

# shellcheck disable=SC2016
if ! PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/synthesis" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    validate_required_synthesis_artifacts "$SESSION_DIR"
'; then
    echo "Expected synthesis artifact validation to pass after regeneration" >&2
    exit 1
fi

mkdir -p "$tmp_root/watchtopic/meta" "$tmp_root/watchtopic/knowledge"
cat >"$tmp_root/watchtopic/meta/domain-heuristics.json" <<'EOF'
{
  "domain": "test_domain",
  "analysis_timestamp": "2025-11-01T00:00:00Z",
  "stakeholder_categories": {"placeholder": {"importance": "critical"}},
  "freshness_requirements": [],
  "watch_topics": [
    {
      "id": "wt1",
      "canonical": "Nanotech therapy advances",
      "variants": ["nanotechnology therapy", "nanotech keloid treatment"],
      "importance": "critical"
    }
  ],
  "synthesis_guidance": {
    "required_sections": ["Overview"],
    "tone": "neutral"
  }
}
EOF

cat >"$tmp_root/watchtopic/knowledge/knowledge-graph.json" <<'EOF'
{
  "claims": [
    {
      "id": "c0",
      "statement": "General claim unrelated to watch topics",
      "sources": []
    }
  ]
}
EOF

# shellcheck disable=SC2016
if PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/watchtopic" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_watch_topics "$SESSION_DIR"
'; then
    echo "Expected watch topic enforcement to block synthesis when coverage is missing" >&2
    exit 1
fi

cat >"$tmp_root/watchtopic/knowledge/knowledge-graph.json" <<'EOF'
{
  "claims": [
    {
      "id": "c1",
      "statement": "Recent nanotechnology therapy advances show strong efficacy in keloid treatment.",
      "sources": []
    }
  ]
}
EOF

# shellcheck disable=SC2016
if ! PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/watchtopic" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_watch_topics "$SESSION_DIR"
'; then
    echo "Expected watch topic enforcement to pass after coverage claim added" >&2
    exit 1
fi

mkdir -p "$tmp_root/classifier/knowledge" "$tmp_root/classifier/session" "$tmp_root/classifier/meta"
cat >"$tmp_root/classifier/meta/session.json" <<'EOF'
{
  "mission_name": "general-research",
  "objective": "Classifier test"
}
EOF
cat >"$tmp_root/classifier/knowledge/knowledge-graph.json" <<'EOF'
{
  "claims": [
    {
      "id": "c1",
      "statement": "Example statement",
      "sources": [
        {"url": "https://example.com/a", "title": "Example Source"}
      ]
    }
  ]
}
EOF

# shellcheck disable=SC2016
if PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/classifier" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_stakeholder_classifier "$SESSION_DIR"
'; then
    echo "Expected stakeholder classifier check to fail when classifications are missing" >&2
    exit 1
fi

hash_value="$("$PROJECT_ROOT/src/utils/hash-string.sh" "https://example.com/a")"
hash_value="${hash_value:0:16}"
sleep 1
cat >"$tmp_root/classifier/session/stakeholder-classifications.jsonl" <<EOF
{"source_id":"$hash_value","url":"https://example.com/a","category":"test","confidence":0.9}
EOF
touch "$tmp_root/classifier/session/stakeholder-classifications.jsonl"

# shellcheck disable=SC2016
if ! PROJECT_ROOT="$PROJECT_ROOT" SESSION_DIR="$tmp_root/classifier" "$BASH_RUNTIME" -c '
    set -euo pipefail
    source "$PROJECT_ROOT/src/utils/mission-orchestration.sh"
    mission_orchestration_check_stakeholder_classifier "$SESSION_DIR"
'; then
    echo "Expected stakeholder classifier check to pass after classification refresh" >&2
    exit 1
fi

echo "Quality gate tests passed."
