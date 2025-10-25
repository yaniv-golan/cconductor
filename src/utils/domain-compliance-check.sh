#!/usr/bin/env bash
# Domain Compliance Check - Lightweight mid-mission enforcement with drift detection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/domain-helpers.sh"

SESSION_DIR="${1:-}"
if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
    echo '{"error":"invalid_session"}' >&2
    exit 1
fi

HEURISTICS_FILE="$SESSION_DIR/meta/domain-heuristics.json"
KG_FILE="$SESSION_DIR/knowledge/knowledge-graph.json"

if [[ ! -f "$HEURISTICS_FILE" ]]; then
    echo '{"status":"no_heuristics"}'
    exit 0
fi

if [[ ! -f "$KG_FILE" ]]; then
    echo '{"status":"no_kg"}'
    exit 0
fi

HEURISTICS_JSON=$(cat "$HEURISTICS_FILE")

array_to_json() {
    if [[ $# -eq 0 ]]; then
        echo '[]'
    else
        printf '%s\n' "$@" | jq -R . | jq -s .
    fi
}

missing_stakeholders=()
missing_milestones=()
unexpected_topics=()
drift_factors=()
uncategorized_sources=0
total_sources=0

while IFS= read -r source_json; do
    [[ -z "$source_json" || "$source_json" == "null" ]] && continue
    total_sources=$((total_sources + 1))
    if [[ $(map_source_to_stakeholder "$source_json" "$HEURISTICS_JSON") == "uncategorized" ]]; then
        uncategorized_sources=$((uncategorized_sources + 1))
    fi
done < <(jq -c '.claims[]? | .sources[]?' "$KG_FILE" 2>/dev/null || echo "")

while IFS=$'\t' read -r category importance; do
    [[ -z "$category" ]] && continue
    if [[ "$importance" == "critical" ]]; then
        local_found=false
        while IFS= read -r source_json; do
            [[ -z "$source_json" || "$source_json" == "null" ]] && continue
            if [[ $(map_source_to_stakeholder "$source_json" "$HEURISTICS_JSON") == "$category" ]]; then
                local_found=true
                break
            fi
        done < <(jq -c '.claims[]? | .sources[]?' "$KG_FILE" 2>/dev/null || echo "")
        if [[ "$local_found" == false ]]; then
            missing_stakeholders+=("$category")
        fi
    fi
done < <(echo "$HEURISTICS_JSON" | jq -r '.stakeholder_categories | to_entries[]? | "\(.key)\t\(.value.importance)"')

while IFS= read -r watch_item_json; do
    [[ -z "$watch_item_json" || "$watch_item_json" == "null" ]] && continue
    importance=$(echo "$watch_item_json" | jq -r '.importance // ""')
    if [[ "$importance" != "critical" ]]; then
        continue
    fi
        found=false
    while IFS= read -r claim_json; do
        [[ -z "$claim_json" || "$claim_json" == "null" ]] && continue
        if match_watch_item "$watch_item_json" "$claim_json"; then
            found=true
            break
        fi
    done < <(jq -c '.claims[]?' "$KG_FILE" 2>/dev/null || echo "")
    if [[ "$found" == false ]]; then
            canonical=$(echo "$watch_item_json" | jq -r '.canonical // ""')
        [[ -n "$canonical" ]] && missing_milestones+=("$canonical")
    fi
done < <(echo "$HEURISTICS_JSON" | jq -c '.mandatory_watch_items[]?')

known_topics=$(echo "$HEURISTICS_JSON" | jq -r '.freshness_requirements[]? | .topic' 2>/dev/null || echo "")
while IFS= read -r claim_json; do
    [[ -z "$claim_json" || "$claim_json" == "null" ]] && continue
    claim_topic=$(echo "$claim_json" | jq -r '.topic // ""')
    if [[ -n "$claim_topic" && "$claim_topic" != "null" ]]; then
        if ! printf '%s\n' "$known_topics" | grep -qx "$claim_topic" 2>/dev/null; then
            if ! printf '%s\n' "${unexpected_topics[@]}" | grep -qx "$claim_topic" 2>/dev/null; then
                unexpected_topics+=("$claim_topic")
            fi
        fi
    fi
done < <(jq -c '.claims[]?' "$KG_FILE" 2>/dev/null || echo "")

drift_score="0"
if [[ $total_sources -gt 0 ]]; then
    uncategorized_pct=$(awk "BEGIN {printf \"%.1f\", ($uncategorized_sources / $total_sources) * 100}")
    if awk "BEGIN {exit !($uncategorized_pct > 30)}"; then
        drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.4}")
        drift_factors+=("High uncategorized sources: ${uncategorized_pct}%")
    elif awk "BEGIN {exit !($uncategorized_pct > 15)}"; then
        drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.2}")
        drift_factors+=("Moderate uncategorized sources: ${uncategorized_pct}%")
    fi
fi

critical_missing_count=${#missing_stakeholders[@]}
if [[ $critical_missing_count -ge 3 ]]; then
    drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.4}")
    drift_factors+=("Multiple missing critical stakeholders: $critical_missing_count")
elif [[ $critical_missing_count -ge 2 ]]; then
    drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.2}")
    drift_factors+=("Some missing critical stakeholders: $critical_missing_count")
fi

unexpected_count=${#unexpected_topics[@]}
if [[ $unexpected_count -ge 3 ]]; then
    drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.2}")
    drift_factors+=("Multiple unexpected topics: $unexpected_count")
elif [[ $unexpected_count -ge 2 ]]; then
    drift_score=$(awk "BEGIN {printf \"%.2f\", $drift_score + 0.1}")
    drift_factors+=("Some unexpected topics: $unexpected_count")
fi

drift_level="none"
drift_recommendation=""
if awk "BEGIN {exit !($drift_score >= 0.6)}"; then
    drift_level="high"
    drift_recommendation="Consider re-invoking domain-heuristics agent with refined scope to capture new stakeholders/topics"
elif awk "BEGIN {exit !($drift_score >= 0.3)}"; then
    drift_level="moderate"
    drift_recommendation="Monitor for continued drift; may need heuristics refresh if gaps persist"
fi

missing_stakeholders_json=$(array_to_json "${missing_stakeholders[@]}")
missing_milestones_json=$(array_to_json "${missing_milestones[@]}")
unexpected_topics_json=$(array_to_json "${unexpected_topics[@]}")
drift_factors_json=$(array_to_json "${drift_factors[@]}")

jq -n \
    --argjson missing_stakeholders "$missing_stakeholders_json" \
    --argjson missing_milestones "$missing_milestones_json" \
    --arg drift_score "$drift_score" \
    --arg drift_level "$drift_level" \
    --argjson drift_factors "$drift_factors_json" \
    --arg drift_recommendation "$drift_recommendation" \
    --argjson unexpected_topics "$unexpected_topics_json" \
    --argjson uncategorized_count "$uncategorized_sources" \
    --argjson total_sources "$total_sources" \
    '{
        status: "checked",
        missing_stakeholders: $missing_stakeholders,
        missing_milestones: $missing_milestones,
        domain_drift: {
            score: ($drift_score | tonumber),
            level: $drift_level,
            factors: $drift_factors,
            recommendation: $drift_recommendation,
            unexpected_topics: $unexpected_topics,
            uncategorized_sources: {
                count: $uncategorized_count,
                total: $total_sources,
                percentage: (if $total_sources > 0 then ($uncategorized_count / $total_sources) * 100 else 0 end)
            }
        },
        compliance_summary: (if ($missing_stakeholders | length) == 0 and ($missing_milestones | length) == 0 then "compliant" else "gaps_detected" end)
    }'
