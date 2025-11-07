#!/usr/bin/env bash
# Reports watch topic coverage metrics for a session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/bash-runtime.sh"
ensure_modern_bash "$0" "$@"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/mission-state-builder.sh"

usage() {
    echo "Usage: watch-topic-diagnostics.sh <session_dir>" >&2
}

if [[ "$#" -ge 1 && "$1" == "$0" ]]; then
    shift
fi

if [[ "$#" -ne 1 ]]; then
    usage
    exit 1
fi

session_dir="$1"

if [[ ! -d "$session_dir" ]]; then
    log_error "watch-topic diag: session directory not found: $session_dir"
    exit 1
fi

heuristics_file="$session_dir/meta/domain-heuristics.json"
kg_file="$session_dir/knowledge/knowledge-graph.json"

if [[ ! -f "$heuristics_file" ]]; then
    log_error "watch-topic diag: heuristics file missing: $heuristics_file"
    exit 1
fi

if [[ ! -f "$kg_file" ]]; then
    log_error "watch-topic diag: knowledge graph file missing: $kg_file"
    exit 1
fi

is_greater() {
    awk -v a="$1" -v b="$2" 'BEGIN{exit((a+0) > (b+0) ? 0 : 1)}'
}

printf "Watch Topic Coverage Diagnostics for %s\n" "$session_dir"
printf "%-12s %-12s %-10s %-10s %s\n" "TopicID" "BestClaim" "Coverage" "Jaccard" "Statement"

declare -a CLAIM_IDS=()
declare -A CLAIM_TOKENS CLAIM_STATEMENTS

while IFS= read -r claim_entry; do
    claim_id=$(jq -r '.id // ""' <<<"$claim_entry")
    statement=$(jq -r '.statement // ""' <<<"$claim_entry")
    [[ -z "$claim_id" ]] && continue
    CLAIM_IDS+=("$claim_id")
    CLAIM_STATEMENTS["$claim_id"]="$statement"
    CLAIM_TOKENS["$claim_id"]="$(watch_topic_tokenize_text "$statement")"
done < <(jq -c '.claims[]?' "$kg_file")

while IFS= read -r topic_json; do
    importance=$(jq -r '.importance // ""' <<<"$topic_json")
    [[ "${importance,,}" != "critical" ]] && continue

    topic_id=$(jq -r '.id // ""' <<<"$topic_json")
    canonical=$(jq -r '.canonical // ""' <<<"$topic_json")

    canonical_tokens=$(watch_topic_tokenize_text "$canonical")

    best_coverage=0
    best_jaccard=0
    best_claim_id=""
    best_statement=""

    for claim_id in "${CLAIM_IDS[@]}"; do
        statement="${CLAIM_STATEMENTS[$claim_id]}"
        claim_tokens="${CLAIM_TOKENS[$claim_id]}"

        coverage=$(watch_topic_compute_coverage "$canonical_tokens" "$claim_tokens")

        jaccard_score=0
        while IFS= read -r variant; do
            variant_tokens=$(watch_topic_tokenize_text "$variant")
            score=$(watch_topic_compute_jaccard "$variant_tokens" "$claim_tokens")
            if is_greater "$score" "$jaccard_score"; then
                jaccard_score="$score"
            fi
        done < <(jq -r '.variants[]?' <<<"$topic_json")

        canonical_jaccard=$(watch_topic_compute_jaccard "$canonical_tokens" "$claim_tokens")
        if is_greater "$canonical_jaccard" "$jaccard_score"; then
            jaccard_score="$canonical_jaccard"
        fi

        if [[ -n "$coverage" ]] && is_greater "$coverage" "$best_coverage"; then
            best_coverage="$coverage"
            best_claim_id="$claim_id"
            best_statement="$statement"
        fi

        if [[ -n "$jaccard_score" ]] && is_greater "$jaccard_score" "$best_jaccard"; then
            best_jaccard="$jaccard_score"
        fi
    done

    printf "%-12s %-12s %-10.2f %-10.2f %s\n" "$topic_id" "${best_claim_id:-n/a}" "${best_coverage:-0}" "${best_jaccard:-0}" "${best_statement:-n/a}"
done < <(jq -c '.watch_topics[]?' "$heuristics_file")

# Display LLM semantic matching summary
watch_topic_llm_summary() {
    local session_dir="$1"
    
    if [[ ! -f "$session_dir/logs/events.jsonl" ]]; then
        return 0
    fi
    
    # Parse watch_topic_llm_eval events
    local topics_evaluated
    topics_evaluated=$(jq -s '[.[] | select(.type == "watch_topic_llm_eval")] | length' \
        "$session_dir/logs/events.jsonl" 2>/dev/null || echo "0")
    
    if (( topics_evaluated == 0 )); then
        return 0
    fi
    
    local total_cost
    total_cost=$(jq -s '[.[] | select(.type == "watch_topic_llm_eval") | .cost_usd] | add' \
        "$session_dir/logs/events.jsonl" 2>/dev/null || echo "0")
    
    local avg_confidence
    avg_confidence=$(jq -s '
        [.[] | select(.type == "watch_topic_llm_eval") | .best_confidence] |
        if length > 0 then (add / length) else 0 end
    ' "$session_dir/logs/events.jsonl" 2>/dev/null || echo "0")
    
    local total_claims_evaluated
    total_claims_evaluated=$(jq -s '
        [.[] | select(.type == "watch_topic_llm_eval") | .claims_evaluated] | add
    ' "$session_dir/logs/events.jsonl" 2>/dev/null || echo "0")
    
    local total_matches
    total_matches=$(jq -s '
        [.[] | select(.type == "watch_topic_llm_eval") | .matches_found] | add
    ' "$session_dir/logs/events.jsonl" 2>/dev/null || echo "0")
    
    printf "\n"
    printf "LLM Semantic Matching Summary:\n"
    printf "  Topics evaluated: %s\n" "$topics_evaluated"
    printf "  Claims evaluated: %s\n" "$total_claims_evaluated"
    printf "  Matches found: %s\n" "$total_matches"
    printf "  Total LLM cost: \$%s\n" "$total_cost"
    printf "  Avg confidence: %.2f\n" "$avg_confidence"
}

# Call LLM summary function
watch_topic_llm_summary "$session_dir"
