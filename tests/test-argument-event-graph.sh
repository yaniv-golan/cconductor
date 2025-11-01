#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aeg-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SESSION_DIR="${TMP_DIR}/session"
mkdir -p "$SESSION_DIR"

export CCONDUCTOR_ENABLE_AEG=1

# Generate events from academic researcher findings via emitter
SESSION_ACAD="${TMP_DIR}/session_academic"
mkdir -p "$SESSION_ACAD/work/academic-researcher"
cat > "$SESSION_ACAD/work/academic-researcher/findings-t0.json" <<'JSON'
{
  "task_id": "t0",
  "claims": [
    {
      "statement": "Synthetic sample claim backed by two sources.",
      "confidence": 0.9,
      "evidence_quality": "high",
      "sources": [
        {
          "url": "https://example.com/source-1",
          "title": "Source One",
          "credibility": "high",
          "relevant_quote": "Sample supporting quote from source one.",
          "date": "2025-01-01"
        },
        {
          "url": "https://example.com/source-2",
          "title": "Source Two",
          "credibility": "medium",
          "relevant_quote": "Corroborating excerpt from source two.",
          "date": "2025-02-01"
        }
      ],
      "related_entities": ["Sample Entity"]
    }
  ]
}
JSON

events_json="$("$PROJECT_ROOT/src/utils/emit-academic-argument-events.py" "$SESSION_ACAD")"
printf '%s' "$events_json" | jq '. | length > 0' >/dev/null

printf '%s\n' "$events_json" > "${TMP_DIR}/academic-events.json"
"$PROJECT_ROOT/src/utils/argument-writer.sh" append \
    --session "$SESSION_ACAD" \
    --agent "academic-researcher" \
    --file "${TMP_DIR}/academic-events.json"

"$PROJECT_ROOT/src/utils/materialize-argument-graph.sh" --session "$SESSION_ACAD" --force
jq -e '.nodes | length > 0' "$SESSION_ACAD/argument/aeg.graph.json" >/dev/null

cat > "${TMP_DIR}/events.json" <<'JSON'
{
  "events": [
    {
      "event_type": "claim",
      "mission_step": "S1.task.001",
      "payload": {
        "claim_id": "clm-original",
        "text": "Sample therapy reached Phase 3 in 2025.",
        "sources": [
          {
            "source_id": "src-press",
            "url": "https://example.org/press",
            "title": "Press release",
            "published": "2025-08-11"
          }
        ],
        "premises": ["evd-press"]
      }
    },
    {
      "event_type": "evidence",
      "mission_step": "S1.task.001",
      "payload": {
        "evidence_id": "evd-press",
        "claim_id": "clm-original",
        "role": "support",
        "statement": "Press release states Phase 3 launched.",
        "source": "src-press",
        "quality": "high"
      }
    },
    {
      "event_type": "contradiction",
      "mission_step": "S1.task.002",
      "payload": {
        "contradiction_id": "ctd-sample-size",
        "attacker_claim_id": "clm-counter",
        "target_claim_id": "clm-original",
        "basis": "conflicting-statistic",
        "explanation": "Regulator lists 1800 participants.",
        "sources": ["src-regulator"]
      }
    },
    {
      "event_type": "preference",
      "mission_step": "S1.task.003",
      "payload": {
        "preference_id": "prf-evidence",
        "preferred_claim_id": "clm-original",
        "dispreferred_claim_id": "clm-counter",
        "criteria": "evidence-quality",
        "weight": 0.7
      }
    }
  ]
}
JSON

"$PROJECT_ROOT/src/utils/argument-writer.sh" append \
    --session "$SESSION_DIR" \
    --agent "academic-researcher" \
    --mission-step "S1.task.001" \
    --file "${TMP_DIR}/events.json"

"$PROJECT_ROOT/src/utils/materialize-argument-graph.sh" --session "$SESSION_DIR" --force

GRAPH_PATH="$SESSION_DIR/argument/aeg.graph.json"
QUALITY_PATH="$SESSION_DIR/argument/aeg.quality.json"

jq -e '.nodes[] | select(.claim_id == "clm-original")' "$GRAPH_PATH" > /dev/null
jq -e '.metrics.claims_total == 1' "$GRAPH_PATH" > /dev/null
jq -e '.metrics.claim_coverage == 1' "$GRAPH_PATH" > /dev/null
jq -e '.violations | length == 0' "$GRAPH_PATH" > /dev/null

jq -e '.metrics.claims_total == 1' "$QUALITY_PATH" > /dev/null

"$PROJECT_ROOT/src/utils/export-aif.sh" --session "$SESSION_DIR" --output "${TMP_DIR}/aif.jsonld" --pretty
jq -e '."@type" == "aif:ArgumentGraph"' "${TMP_DIR}/aif.jsonld" > /dev/null

"$PROJECT_ROOT/src/utils/migrate-claim-ids.sh" --session "$SESSION_DIR" --dry-run > "${TMP_DIR}/mapping.json"
jq -e '.["clm-original"] == "clm-0001"' "${TMP_DIR}/mapping.json" > /dev/null

"$PROJECT_ROOT/src/utils/migrate-claim-ids.sh" --session "$SESSION_DIR"
"$PROJECT_ROOT/src/utils/materialize-argument-graph.sh" --session "$SESSION_DIR" --force

jq -e '.nodes[] | select(.claim_id == "clm-0001")' "$SESSION_DIR/argument/aeg.graph.json" > /dev/null

echo "✓ Argument Event Graph pipeline test passed"
