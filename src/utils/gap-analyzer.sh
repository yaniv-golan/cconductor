#!/usr/bin/env bash
# Gap Analyzer
# Identifies knowledge gaps in the research

set -euo pipefail

# Constants - Gap detection thresholds
readonly MIN_ENTITY_DESCRIPTION_LENGTH=50  # Entities with <50 char descriptions need more detail
readonly HIGH_RELATED_COUNT=3              # Entity with 3+ relationships is highly connected
readonly LOW_RELATED_COUNT=1               # Entity with 1+ relationships has some context
readonly HIGH_MATCH_COUNT=2                # Gap appearing in 2+ contexts is significant
readonly LOW_MATCH_COUNT=0                 # Gap with any matches gets some priority

# Constants - Priority levels for gaps
readonly GAP_PRIORITY_MAX=10     # Maximum priority (clamp at this)

# Analyze knowledge graph for gaps
analyze_gaps() {
    local kg_json="$1"
    local min_priority="${2:-6}"

    # Extract entities and claims
    local entities
    entities=$(echo "$kg_json" | jq -c '.entities[]')
    local claims
    claims=$(echo "$kg_json" | jq -c '.claims[]')

    local gaps='[]'

    # Gap type 1: Mentioned but unexplained entities
    while IFS= read -r entity; do
        local entity_name
        entity_name=$(echo "$entity" | jq -r '.name')
        local entity_desc
        entity_desc=$(echo "$entity" | jq -r '.description // ""')

        # Check if entity has sufficient explanation
        if [ ${#entity_desc} -lt $MIN_ENTITY_DESCRIPTION_LENGTH ]; then
            # Entity lacks detailed explanation
            local gap
            gap=$(jq -n \
                --arg question "What is $entity_name in detail?" \
                --arg priority "7" \
                --arg reason "Entity mentioned but not explained in detail" \
                --arg entity "$entity_name" \
                '{question: $question, priority: ($priority | tonumber), reason: $reason, related_entities: [$entity]}')

            gaps=$(echo "$gaps" | jq --argjson gap "$gap" '. += [$gap]')
        fi
    done <<< "$entities"

    # Gap type 2: Low-confidence claims
    while IFS= read -r claim; do
        local confidence
        confidence=$(echo "$claim" | jq -r '.confidence // 0')
        local statement
        statement=$(echo "$claim" | jq -r '.statement')

        if (( $(echo "$confidence < 0.70" | bc -l) )); then
            # Low confidence claim needs more evidence
            local gap
            gap=$(jq -n \
                --arg question "Find more evidence for: $statement" \
                --arg priority "8" \
                --arg reason "Claim has low confidence ($confidence), needs more sources" \
                '{question: $question, priority: ($priority | tonumber), reason: $reason}')

            gaps=$(echo "$gaps" | jq --argjson gap "$gap" '. += [$gap]')
        fi
    done <<< "$claims"

    # Gap type 3: Relationships without explanations
    local relationships
    relationships=$(echo "$kg_json" | jq -c '.relationships[]')
    while IFS= read -r rel; do
        local from
        from=$(echo "$rel" | jq -r '.from')
        local to
        to=$(echo "$rel" | jq -r '.to')
        local type
        type=$(echo "$rel" | jq -r '.type')
        local note
        note=$(echo "$rel" | jq -r '.note // ""')

        if [ -z "$note" ]; then
            local gap
            gap=$(jq -n \
                --arg question "How does $from relate to $to (via $type)?" \
                --arg priority "6" \
                --arg reason "Relationship exists but mechanism not explained" \
                --arg from "$from" \
                --arg to "$to" \
                '{question: $question, priority: ($priority | tonumber), reason: $reason, related_entities: [$from, $to]}')

            gaps=$(echo "$gaps" | jq --argjson gap "$gap" '. += [$gap]')
        fi
    done <<< "$relationships"

    # Filter by minimum priority and return
    echo "$gaps" | jq --arg min "$min_priority" \
        'map(select(.priority >= ($min | tonumber))) | sort_by(-.priority)'
}

# Detect questions raised in agent outputs
detect_questions() {
    local agent_output="$1"

    # Look for explicit gap identifications
    echo "$agent_output" | jq '.gaps_identified // []'
}

# Categorize gaps
categorize_gaps() {
    local gaps_json="$1"

    jq 'group_by(
        if (.priority >= 9) then "critical"
        elif (.priority >= 7) then "important"
        elif (.priority >= 5) then "moderate"
        else "minor"
        end
    ) | map({category: .[0].priority, gaps: .})' <<< "$gaps_json"
}

# Score gap priority
score_gap_priority() {
    local gap_json="$1"
    local kg_json="$2"

    local base_priority
    base_priority=$(echo "$gap_json" | jq '.priority // 5')

    # Boost priority if related to many entities
    local related_count
    related_count=$(echo "$gap_json" | jq '.related_entities | length')
    local entity_boost=0
    if [ "$related_count" -gt $HIGH_RELATED_COUNT ]; then
        entity_boost=2
    elif [ "$related_count" -gt $LOW_RELATED_COUNT ]; then
        entity_boost=1
    fi

    # Boost priority if related to research question core concepts
    local research_question
    research_question=$(echo "$kg_json" | jq -r '.research_question')
    local question_text
    question_text=$(echo "$gap_json" | jq -r '.question')

    # Simple keyword matching (would be better with NLP)
    local relevance_boost=0
    local rq_words
    rq_words=$(echo "$research_question" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n')
    local gap_words
    gap_words=$(echo "$question_text" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n')

    local match_count=0
    while IFS= read -r word; do
        if echo "$gap_words" | grep -qw "$word"; then
            ((match_count++)) || true
        fi
    done <<< "$rq_words"

    if [ "$match_count" -gt $HIGH_MATCH_COUNT ]; then
        relevance_boost=2
    elif [ "$match_count" -gt $LOW_MATCH_COUNT ]; then
        relevance_boost=1
    fi

    # Calculate final priority
    local final_priority
    final_priority=$((base_priority + entity_boost + relevance_boost))

    # Cap at max priority
    if [ "$final_priority" -gt $GAP_PRIORITY_MAX ]; then
        final_priority=$GAP_PRIORITY_MAX
    fi

    echo "$gap_json" | jq --arg priority "$final_priority" '.priority = ($priority | tonumber)'
}

# Export functions
export -f analyze_gaps
export -f detect_questions
export -f categorize_gaps
export -f score_gap_priority

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        analyze)
            analyze_gaps "$(cat "$2")" "${3:-6}"
            ;;
        detect)
            detect_questions "$(cat "$2")"
            ;;
        categorize)
            categorize_gaps "$(cat "$2")"
            ;;
        *)
            echo "Usage: $0 {analyze|detect|categorize} <input_file> [min_priority]"
            echo ""
            echo "Commands:"
            echo "  analyze <kg.json> [min_priority]    - Analyze knowledge graph for gaps"
            echo "  detect <agent_output.json>          - Extract gaps from agent output"
            echo "  categorize <gaps.json>              - Categorize gaps by priority"
            ;;
    esac
fi
