#!/bin/bash
# Confidence Scorer
# Calculates confidence scores for claims and overall research

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/calculate.sh"

# Constants - Source count thresholds
readonly SOURCE_COUNT_EXCELLENT=5   # 5+ sources = excellent confidence
readonly SOURCE_COUNT_GOOD=3        # 3+ sources = good confidence
readonly SOURCE_COUNT_FAIR=2        # 2+ sources = fair confidence
readonly SOURCE_COUNT_MIN=1         # 1 source = minimum confidence

# Constants - Base confidence scores
readonly CONFIDENCE_MAX=0.95              # Never claim 100% certainty
readonly CONFIDENCE_SCORE_EXCELLENT=0.9   # Score for 5+ sources
readonly CONFIDENCE_SCORE_GOOD=0.75       # Score for 3+ sources
readonly CONFIDENCE_SCORE_FAIR=0.6        # Score for 2 sources
readonly CONFIDENCE_SCORE_LOW=0.4         # Score for 1 source
readonly CONFIDENCE_SCORE_MINIMAL=0.3     # Score for 0 sources

# Constants - Quality multipliers
readonly QUALITY_MULT_HIGH=1.1     # High quality evidence boost
readonly QUALITY_MULT_MEDIUM=1.0   # Medium quality (no change)
readonly QUALITY_MULT_LOW=0.8      # Low quality penalty

# Constants - Gap thresholds and penalties
readonly GAP_THRESHOLD_SEVERE=10   # 10+ unresolved gaps is severe
readonly GAP_THRESHOLD_MODERATE=5  # 5+ unresolved gaps is moderate
readonly GAP_THRESHOLD_MINOR=2     # 2+ unresolved gaps is minor
readonly GAP_PENALTY_SEVERE=0.15   # Penalty for severe gaps
readonly GAP_PENALTY_MODERATE=0.10 # Penalty for moderate gaps
readonly GAP_PENALTY_MINOR=0.05    # Penalty for minor gaps

# Constants - Contradiction penalty
readonly CONTRADICTION_PENALTY_PER=0.05  # Penalty per unresolved contradiction

# Constants - General thresholds
readonly DEFAULT_LOW_CONFIDENCE_THRESHOLD=0.70  # Default threshold for low confidence

# Calculate confidence for a single claim
score_claim_confidence() {
    local claim_json="$1"

    local sources
    sources=$(echo "$claim_json" | jq '.sources | length')
    local evidence_quality
    evidence_quality=$(echo "$claim_json" | jq -r '.evidence_quality // "medium"')

    # Base score from sources (more sources = higher confidence)
    local source_score=$CONFIDENCE_SCORE_MINIMAL
    if [ "$sources" -ge $SOURCE_COUNT_EXCELLENT ]; then
        source_score=$CONFIDENCE_SCORE_EXCELLENT
    elif [ "$sources" -ge $SOURCE_COUNT_GOOD ]; then
        source_score=$CONFIDENCE_SCORE_GOOD
    elif [ "$sources" -ge $SOURCE_COUNT_FAIR ]; then
        source_score=$CONFIDENCE_SCORE_FAIR
    elif [ "$sources" -ge $SOURCE_COUNT_MIN ]; then
        source_score=$CONFIDENCE_SCORE_LOW
    fi

    # Evidence quality multiplier
    local quality_mult=$QUALITY_MULT_MEDIUM
    case "$evidence_quality" in
        high)
            quality_mult=$QUALITY_MULT_HIGH
            ;;
        medium)
            quality_mult=$QUALITY_MULT_MEDIUM
            ;;
        low)
            quality_mult=$QUALITY_MULT_LOW
            ;;
    esac

    # Calculate final confidence (use safe calculator)
    local confidence
    confidence=$(safe_calculate "$source_score * $quality_mult" | jq -r '.result' | awk '{printf "%.2f", $0}')

    # Cap at max confidence (never fully certain)
    if awk -v conf="$confidence" -v max="$CONFIDENCE_MAX" 'BEGIN { exit !(conf > max) }'; then
        confidence=$CONFIDENCE_MAX
    fi

    echo "$confidence"
}

# Calculate overall confidence from knowledge graph
calculate_overall_confidence() {
    local kg_json="$1"

    local claims
    claims=$(echo "$kg_json" | jq '.claims')
    local claim_count
    claim_count=$(echo "$claims" | jq 'length')

    if [ "$claim_count" -eq 0 ]; then
        echo '{"overall": 0.0, "by_category": {}}'
        return
    fi

    # Calculate average confidence across all claims
    local total_confidence
    total_confidence=$(echo "$claims" | jq '[.[].confidence // 0] | add')
    local avg_confidence
    avg_confidence=$(safe_calculate "$total_confidence / $claim_count" | jq -r '.result' | awk '{printf "%.2f", $0}')

    # Penalize if many gaps remain
    local gaps
    gaps=$(echo "$kg_json" | jq '.stats.unresolved_gaps // 0')
    local gap_penalty=0
    if [ "$gaps" -gt $GAP_THRESHOLD_SEVERE ]; then
        gap_penalty=$GAP_PENALTY_SEVERE
    elif [ "$gaps" -gt $GAP_THRESHOLD_MODERATE ]; then
        gap_penalty=$GAP_PENALTY_MODERATE
    elif [ "$gaps" -gt $GAP_THRESHOLD_MINOR ]; then
        gap_penalty=$GAP_PENALTY_MINOR
    fi

    # Penalize if contradictions unresolved
    local contradictions
    contradictions=$(echo "$kg_json" | jq '.stats.unresolved_contradictions // 0')
    local contra_penalty=0
    if [ "$contradictions" -gt 0 ]; then
        contra_penalty=$(safe_calculate "$contradictions * $CONTRADICTION_PENALTY_PER" | jq -r '.result' | awk '{printf "%.2f", $0}')
    fi

    # Calculate final overall confidence
    local final_confidence
    final_confidence=$(safe_calculate "$avg_confidence - $gap_penalty - $contra_penalty" | jq -r '.result' | awk '{printf "%.2f", $0}')

    # Ensure non-negative
    if awk -v conf="$final_confidence" 'BEGIN { exit !(conf < 0) }'; then
        final_confidence=0.0
    fi

    # Calculate confidence by category (if entities have categories)
    local categories
    categories=$(echo "$kg_json" | jq '[.entities[].type] | unique')
    local by_category='{}'

    while IFS= read -r category; do
        if [ "$category" != "null" ] && [ -n "$category" ]; then
            # Get claims related to entities of this category
            local category_entities
            category_entities=$(echo "$kg_json" | jq -c --arg cat "$category" \
                '[.entities[] | select(.type == $cat) | .name]')

            local category_claims
            category_claims=$(echo "$kg_json" | jq --argjson entities "$category_entities" \
                '[.claims[] | select(.related_entities as $re | $entities | any(. as $e | $re | contains([$e])))]')

            local cat_count
            cat_count=$(echo "$category_claims" | jq 'length')

            if [ "$cat_count" -gt 0 ]; then
                local cat_confidence
                cat_confidence=$(echo "$category_claims" | jq '[.[].confidence // 0] | add / length' | awk '{printf "%.2f", $0}')
                by_category=$(echo "$by_category" | jq --arg cat "$category" --arg conf "$cat_confidence" \
                    '. + {($cat): ($conf | tonumber)}')
            fi
        fi
    done <<< "$(echo "$categories" | jq -r '.[]')"

    # Output final confidence scores
    jq -n \
        --arg overall "$final_confidence" \
        --argjson by_cat "$by_category" \
        '{overall: ($overall | tonumber), by_category: $by_cat}'
}

# Calculate coverage score
calculate_coverage() {
    local kg_json="$1"

    # Identify key aspects (entities with high centrality)
    local entities
    entities=$(echo "$kg_json" | jq '.entities | length')

    # Count well-covered aspects (entities with description > 100 chars and confidence > 0.8)
    local well_covered
    well_covered=$(echo "$kg_json" | jq \
        '[.entities[] | select((.description // "" | length) > 100 and (.confidence // 0) > 0.8)] | length')

    # Count partially covered (description 50-100 chars or confidence 0.6-0.8)
    local partial_covered
    partial_covered=$(echo "$kg_json" | jq \
        '[.entities[] | select(((.description // "" | length) >= 50 and (.description // "" | length) <= 100) or
        ((.confidence // 0) >= 0.6 and (.confidence // 0) <= 0.8))] | length')

    # Not covered = total - well_covered - partial_covered
    local not_covered
    not_covered=$((entities - well_covered - partial_covered))

    if [ "$not_covered" -lt 0 ]; then
        not_covered=0
    fi

    jq -n \
        --arg aspects "$entities" \
        --arg well "$well_covered" \
        --arg partial "$partial_covered" \
        --arg not "$not_covered" \
        '{
            aspects_identified: ($aspects | tonumber),
            aspects_well_covered: ($well | tonumber),
            aspects_partially_covered: ($partial | tonumber),
            aspects_not_covered: ($not | tonumber)
        }'
}

# Identify low-confidence areas
identify_low_confidence_areas() {
    local kg_json="$1"
    local threshold="${2:-$DEFAULT_LOW_CONFIDENCE_THRESHOLD}"

    echo "$kg_json" | jq --arg thresh "$threshold" \
        '.claims | map(select(.confidence < ($thresh | tonumber))) |
         group_by(.related_entities[0]) |
         map({area: .[0].related_entities[0], low_confidence_claims: length, avg_confidence: ([.[].confidence] | add / length)})'
}

# Export functions
export -f score_claim_confidence
export -f calculate_overall_confidence
export -f calculate_coverage
export -f identify_low_confidence_areas

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        claim)
            score_claim_confidence "$(cat "$2")"
            ;;
        overall)
            calculate_overall_confidence "$(cat "$2")"
            ;;
        coverage)
            calculate_coverage "$(cat "$2")"
            ;;
        low)
            identify_low_confidence_areas "$(cat "$2")" "${3:-0.70}"
            ;;
        *)
            echo "Usage: $0 {claim|overall|coverage|low} <input_file> [args]"
            echo ""
            echo "Commands:"
            echo "  claim <claim.json>           - Score confidence for a claim"
            echo "  overall <kg.json>            - Calculate overall confidence"
            echo "  coverage <kg.json>           - Calculate coverage score"
            echo "  low <kg.json> [threshold]    - Identify low-confidence areas"
            ;;
    esac
fi
