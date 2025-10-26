#!/usr/bin/env bash
# Regression test for quality gate uncategorized stakeholder samples

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        exec /usr/local/bin/bash "$0" "$@"
    fi
fi

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_SCRIPT="$PROJECT_ROOT/src/claude-runtime/hooks/quality-gate.sh"

if [[ ! -x "$GATE_SCRIPT" ]]; then
    echo "quality gate hook not found at $GATE_SCRIPT" >&2
    exit 1
fi

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export CCONDUCTOR_CONFIG_DIR="$TMP_ROOT/config-overlay"
export CCONDUCTOR_USER_CONFIG_DIR="$TMP_ROOT/user-config"
mkdir -p "$CCONDUCTOR_CONFIG_DIR" "$CCONDUCTOR_USER_CONFIG_DIR"

DEFAULT_KG_JSON=$(cat <<'JSON'
{
  "claims": [
    {
      "id": "c-001",
      "statement": "Recent regulatory filings cite new emission limits",
      "confidence": 0.82,
      "sources": [
        {
          "url": "https://journal.example.edu/report",
          "title": "Peer Insights \"Alpha\"",
          "credibility": "peer_reviewed",
          "date": "2025-02-01"
        },
        {
          "url": "https://startup.blogspace.io/posts/next-gen",
          "title": "“Next-Gen” Stakeholder Outlook",
          "credibility": "blog",
          "date": "2025-01-12"
        }
      ]
    },
    {
      "id": "c-002",
      "statement": "Agency guidance requires two independent monitoring audits",
      "confidence": 0.77,
      "sources": [
        {
          "url": "https://gov.example.gov/releases/monitoring-guide.pdf",
          "title": "Agency Monitoring Guide",
          "credibility": "official",
          "date": "2024-11-09"
        },
        {
          "url": "https://analysis.marketwatchers.test/brief",
          "title": "3rd-party summary",
          "credibility": "news",
          "date": "2024-12-20"
        }
      ]
    }
  ],
  "stats": {
    "unresolved_contradictions": 0
  }
}
JSON
)

EMPTY_STAKEHOLDER_HEURISTICS=$(cat <<'JSON'
{
  "stakeholder_categories": {},
  "freshness_requirements": [],
  "mandatory_watch_items": []
}
JSON
)

NO_PATTERN_HEURISTICS=$(cat <<'JSON'
{
  "stakeholder_categories": {
    "academics": {
      "description": "Academic journals",
      "importance": "high",
      "domain_patterns": [],
      "keyword_patterns": []
    }
  }
}
JSON
)

MIXED_PATTERN_HEURISTICS=$(cat <<'JSON'
{
  "stakeholder_categories": {
    "academics": {
      "description": "Peer reviewed sources",
      "importance": "high",
      "domain_patterns": ["journal.example.edu"],
      "keyword_patterns": ["insights"]
    },
    "regulators": {
      "description": "Government regulators",
      "importance": "critical",
      "domain_patterns": ["gov.example.gov"],
      "keyword_patterns": ["guidance"]
    }
  },
  "freshness_requirements": [],
  "mandatory_watch_items": []
}
JSON
)

write_session() {
    local case_name="$1"
    local heuristics="$2"
    local kg_payload="${3:-$DEFAULT_KG_JSON}"
    local session_dir="$TMP_ROOT/$case_name"

    mkdir -p "$session_dir/meta" "$session_dir/knowledge" "$session_dir/artifacts"

    cat >"$session_dir/meta/session.json" <<'JSON'
{
  "objective": "Test mission",
  "mission_name": "debug",
  "created_at": "2025-10-20T00:00:00Z"
}
JSON

    printf '%s' "$kg_payload" >"$session_dir/knowledge/knowledge-graph.json"
    printf '%s' "$heuristics" >"$session_dir/meta/domain-heuristics.json"
    echo "$session_dir"
}

run_case() {
    local case_name="$1"
    local heuristics="$2"
    local kg_payload="${3:-$DEFAULT_KG_JSON}"
    local session_dir
    session_dir=$(write_session "$case_name" "$heuristics" "$kg_payload")

    if ! "$BASH" "$GATE_SCRIPT" "$session_dir" >"$TMP_ROOT/$case_name.log" 2>&1; then
        echo "quality gate failed for $case_name" >&2
        cat "$TMP_ROOT/$case_name.log" >&2 || true
        exit 1
    fi

    local summary_file="$session_dir/artifacts/quality-gate-summary.json"
    if [[ ! -f "$summary_file" ]]; then
        echo "summary missing for $case_name" >&2
        exit 1
    fi

    if ! jq -e '.uncategorized_sources.samples | type == "array"' "$summary_file" >/dev/null; then
        echo "uncategorized samples malformed for $case_name" >&2
        cat "$summary_file" >&2 || true
        exit 1
    fi
}

run_case "empty_stakeholders" "$EMPTY_STAKEHOLDER_HEURISTICS"
run_case "no_patterns" "$NO_PATTERN_HEURISTICS"
run_case "mixed_patterns" "$MIXED_PATTERN_HEURISTICS"

# Malformed manual patterns should not crash the gate
printf '{"additional_patterns": ' >"$CCONDUCTOR_USER_CONFIG_DIR/stakeholder-patterns.json"
run_case "malformed_manual_config" "$MIXED_PATTERN_HEURISTICS"
rm -f "$CCONDUCTOR_USER_CONFIG_DIR/stakeholder-patterns.json"

echo "Quality gate malformed stakeholder sample tests passed."
