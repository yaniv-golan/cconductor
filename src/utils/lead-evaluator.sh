#!/bin/bash
# Lead Evaluator
# Identifies and scores promising research leads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Constants - Citation thresholds
readonly CITATION_THRESHOLD_CRITICAL=500  # Papers with 500+ citations are critical
readonly CITATION_THRESHOLD_HIGH=100      # Papers with 100+ citations are highly important
readonly CITATION_THRESHOLD_MEDIUM=50     # Papers with 50+ citations are moderately important

# Constants - Priority levels
readonly PRIORITY_MAX=10         # Maximum priority value (clamp at this)
readonly PRIORITY_CRITICAL=9     # Critical priority for top-tier leads
readonly PRIORITY_HIGH=8         # High priority leads
readonly PRIORITY_MEDIUM=7       # Medium priority leads
readonly PRIORITY_LOW=5          # Low priority base level

# Constants - Lead evaluation thresholds
readonly MIN_MENTIONS_THRESHOLD=3    # Entity must be mentioned 3+ times to be significant
readonly MIN_DESCRIPTION_LENGTH=100  # Entities with <100 char descriptions need more detail
readonly MIN_TYPE_COUNT_THRESHOLD=3  # Gap must appear in 3+ entity types to be significant

# Evaluate leads from knowledge graph
evaluate_leads() {
    local kg_json="$1"
    local min_priority="${2:-6}"

    local leads='[]'

    # Lead type 1: Highly cited papers
    local entities=$(echo "$kg_json" | jq -c '.entities[] | select(.type == "paper")')
    while IFS= read -r entity; do
        local name=$(echo "$entity" | jq -r '.name')
        local citations=$(echo "$entity" | jq -r '.citations // 0')
        local pdf_path=$(echo "$entity" | jq -r '.cached_pdf // ""')

        # High citation count = important paper
        local priority=$PRIORITY_LOW
        if [ "$citations" -gt $CITATION_THRESHOLD_CRITICAL ]; then
            priority=$PRIORITY_CRITICAL
        elif [ "$citations" -gt $CITATION_THRESHOLD_HIGH ]; then
            priority=$PRIORITY_HIGH
        elif [ "$citations" -gt $CITATION_THRESHOLD_MEDIUM ]; then
            priority=$PRIORITY_MEDIUM
        fi

        # Boost if we have PDF but haven't analyzed deeply
        if [ -n "$pdf_path" ] && [ "$pdf_path" != "null" ]; then
            priority=$((priority + 1))
        fi

        if [ "$priority" -ge "$min_priority" ]; then
            local lead=$(jq -n \
                --arg desc "Analyze highly cited paper: $name" \
                --arg priority "$priority" \
                --arg reason "Paper has $citations citations, likely contains valuable insights" \
                --arg source "$name" \
                --arg pdf "$pdf_path" \
                '{
                    description: $desc,
                    priority: ($priority | tonumber),
                    reason: $reason,
                    source: $source,
                    pdf_path: $pdf,
                    type: "citation"
                }')

            leads=$(echo "$leads" | jq --argjson lead "$lead" '. += [$lead]')
        fi
    done <<< "$entities"

    # Lead type 2: Foundational concepts mentioned but not deeply explored
    local relationships=$(echo "$kg_json" | jq -c '.relationships[] | select(.type == "theoretical_foundation")')
    while IFS= read -r rel; do
        local from=$(echo "$rel" | jq -r '.from')
        local to=$(echo "$rel" | jq -r '.to')

        local lead=$(jq -n \
            --arg desc "Explore theoretical foundation: $from" \
            --arg priority "7" \
            --arg reason "This is a foundational concept for $to" \
            --arg source "$from" \
            '{
                description: $desc,
                priority: ($priority | tonumber),
                reason: $reason,
                source: $source,
                type: "foundation"
            }')

        leads=$(echo "$leads" | jq --argjson lead "$lead" '. += [$lead]')
    done <<< "$relationships"

    # Lead type 3: Frequently mentioned entities with low coverage
    local entities_all=$(echo "$kg_json" | jq -c '.entities[]')
    while IFS= read -r entity; do
        local name=$(echo "$entity" | jq -r '.name')
        local confidence=$(echo "$entity" | jq -r '.confidence // 0.5')
        local desc_length=$(echo "$entity" | jq -r '.description // ""' | wc -c | xargs)

        # Mentioned multiple times (check in claims and relationships)
        local mentions=$(echo "$kg_json" | jq --arg name "$name" \
            '[.claims[], .relationships[]] | map(select(. | tostring | contains($name))) | length')

        if [ "$mentions" -gt $MIN_MENTIONS_THRESHOLD ] && [ "$desc_length" -lt $MIN_DESCRIPTION_LENGTH ]; then
            # Frequently mentioned but not well understood
            local lead=$(jq -n \
                --arg desc "Deep dive into frequently mentioned concept: $name" \
                --arg priority "7" \
                --arg reason "Mentioned $mentions times but lacks detail" \
                --arg source "$name" \
                '{
                    description: $desc,
                    priority: ($priority | tonumber),
                    reason: $reason,
                    source: $source,
                    type: "frequent_mention"
                }')

            leads=$(echo "$leads" | jq --argjson lead "$lead" '. += [$lead]')
        fi
    done <<< "$entities_all"

    # Lead type 4: Cross-domain connections
    local entity_types=$(echo "$kg_json" | jq '[.entities[].type] | unique')
    local type_count=$(echo "$entity_types" | jq 'length')

    if [ "$type_count" -gt $MIN_TYPE_COUNT_THRESHOLD ]; then
        # Multiple domains involved - might be worth exploring connections
        local lead=$(jq -n \
            --arg desc "Explore cross-domain connections" \
            --arg priority "6" \
            --arg reason "Research spans multiple domains, connections may reveal insights" \
            '{
                description: $desc,
                priority: ($priority | tonumber),
                reason: $reason,
                type: "cross_domain"
            }')

        leads=$(echo "$leads" | jq --argjson lead "$lead" '. += [$lead]')
    fi

    # Filter and sort by priority
    echo "$leads" | jq --arg min "$min_priority" \
        'map(select(.priority >= ($min | tonumber))) | sort_by(-.priority)'
}

# Extract leads from agent outputs
extract_leads_from_agent() {
    local agent_output="$1"

    # Look for suggested follow-ups
    echo "$agent_output" | jq '.suggested_follow_ups // []'
}

# Score lead value
score_lead() {
    local lead_json="$1"
    local kg_json="$2"

    local base_priority=$(echo "$lead_json" | jq '.priority // 5')

    # Boost for certain lead types
    local lead_type=$(echo "$lead_json" | jq -r '.type')
    local type_boost=0

    case "$lead_type" in
        citation)
            type_boost=2  # Citations are valuable
            ;;
        foundation)
            type_boost=2  # Foundational concepts are important
            ;;
        frequent_mention)
            type_boost=1
            ;;
        cross_domain)
            type_boost=1
            ;;
    esac

    # Check if lead addresses a gap
    local description=$(echo "$lead_json" | jq -r '.description')
    local gaps=$(echo "$kg_json" | jq -c '.gaps[]')
    local gap_match=0

    while IFS= read -r gap; do
        local gap_question=$(echo "$gap" | jq -r '.question')
        if echo "$description" | grep -qiF "$(echo "$gap_question" | head -c 20)"; then
            gap_match=1
            break
        fi
    done <<< "$gaps"

    if [ "$gap_match" -eq 1 ]; then
        type_boost=$((type_boost + 2))  # Lead addresses a gap
    fi

    # Final priority
    local final_priority=$((base_priority + type_boost))

    # Cap at 10
    if [ "$final_priority" -gt $PRIORITY_MAX ]; then
        final_priority=$PRIORITY_MAX
    fi

    echo "$lead_json" | jq --arg priority "$final_priority" '.priority = ($priority | tonumber)'
}

# Generate exploration task for lead
generate_lead_task() {
    local lead_json="$1"

    local description=$(echo "$lead_json" | jq -r '.description')
    local source=$(echo "$lead_json" | jq -r '.source')
    local pdf_path=$(echo "$lead_json" | jq -r '.pdf_path // ""')
    local priority=$(echo "$lead_json" | jq -r '.priority')

    local agent="web-researcher"
    local query="$description"

    # Use PDF analyzer if we have a PDF
    if [ -n "$pdf_path" ] && [ "$pdf_path" != "null" ]; then
        agent="pdf-analyzer"
        query="Deep analysis of: $source"
    fi

    jq -n \
        --arg type "lead_exploration" \
        --arg agent "$agent" \
        --arg query "$query" \
        --arg priority "$priority" \
        --arg reason "Explore promising lead: $source" \
        --arg pdf "$pdf_path" \
        '{
            type: $type,
            agent: $agent,
            query: $query,
            priority: ($priority | tonumber),
            spawned_by: "research-coordinator",
            reason: $reason,
            pdf_path: $pdf
        }'
}

# Export functions
export -f evaluate_leads
export -f extract_leads_from_agent
export -f score_lead
export -f generate_lead_task

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        evaluate)
            evaluate_leads "$(cat "$2")" "${3:-6}"
            ;;
        extract)
            extract_leads_from_agent "$(cat "$2")"
            ;;
        score)
            score_lead "$(cat "$2")" "$(cat "$3")"
            ;;
        task)
            generate_lead_task "$(cat "$2")"
            ;;
        *)
            echo "Usage: $0 {evaluate|extract|score|task} <input_file> [args]"
            echo ""
            echo "Commands:"
            echo "  evaluate <kg.json> [min_priority]  - Evaluate leads from knowledge graph"
            echo "  extract <agent_output.json>        - Extract leads from agent output"
            echo "  score <lead.json> <kg.json>        - Score lead value"
            echo "  task <lead.json>                   - Generate task for lead exploration"
            ;;
    esac
fi
