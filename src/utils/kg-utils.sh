#!/usr/bin/env bash
# Knowledge Graph Utilities
# Safe data operations for orchestrator agents

set -euo pipefail

# Extract all claims from knowledge graph
extract_claims() {
    local kg_file="${1:-knowledge-graph.json}"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{claims: [], error: $err}'
        return 1
    fi
    
    jq '{claims: .claims, total: (.claims | length)}' "$kg_file"
}

# Extract entities from knowledge graph
extract_entities() {
    local kg_file="${1:-knowledge-graph.json}"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{entities: [], error: $err}'
        return 1
    fi
    
    jq '{entities: .entities, total: (.entities | length)}' "$kg_file"
}

# Compute knowledge graph statistics
compute_kg_stats() {
    local kg_file="${1:-knowledge-graph.json}"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{error: $err}'
        return 1
    fi
    
    jq '{
        total_claims: (.claims | length),
        total_entities: (.entities | length),
        total_relationships: (.relationships | length),
        claims_by_status: (.claims | group_by(.verification_status // "unknown") | 
            map({(.[0].verification_status // "unknown"): length}) | add // {}),
        avg_confidence: (if (.claims | length) > 0 then 
            ([.claims[].confidence | select(. != null) | tonumber] | 
            if length > 0 then (add / length) else 0 end) else 0 end),
        high_confidence_claims: ([.claims[] | select(.confidence and (.confidence | tonumber) >= 0.8)] | length),
        sources_count: ([.claims[].sources[]?.url] | unique | length)
    }' "$kg_file"
}

# Filter claims by confidence threshold
filter_by_confidence() {
    local kg_file="${1:-knowledge-graph.json}"
    local threshold="${2:-0.7}"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{filtered_claims: [], error: $err}'
        return 1
    fi
    
    jq --argjson threshold "$threshold" \
        '{filtered_claims: [.claims[] | select(.confidence >= $threshold)],
          total: ([.claims[] | select(.confidence >= $threshold)] | length)}' \
        "$kg_file"
}

# Find claims by category
filter_by_category() {
    local kg_file="${1:-knowledge-graph.json}"
    local category="$2"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{filtered_claims: [], error: $err}'
        return 1
    fi
    
    jq --arg cat "$category" \
        '{filtered_claims: [.claims[] | select(.category == $cat)],
          total: ([.claims[] | select(.category == $cat)] | length)}' \
        "$kg_file"
}

# Get unique categories from knowledge graph
list_categories() {
    local kg_file="${1:-knowledge-graph.json}"
    
    if [[ ! -f "$kg_file" ]]; then
        jq -n --arg err "Knowledge graph file not found: $kg_file" \
            '{categories: [], error: $err}'
        return 1
    fi
    
    jq '{categories: ([.claims[].category] | unique | sort)}' "$kg_file"
}

# Export functions
export -f extract_claims
export -f extract_entities
export -f compute_kg_stats
export -f filter_by_confidence
export -f filter_by_category
export -f list_categories

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        extract-claims)
            extract_claims "${2:-knowledge-graph.json}"
            ;;
        extract-entities)
            extract_entities "${2:-knowledge-graph.json}"
            ;;
        stats)
            compute_kg_stats "${2:-knowledge-graph.json}"
            ;;
        filter-confidence)
            filter_by_confidence "${2:-knowledge-graph.json}" "${3:-0.7}"
            ;;
        filter-category)
            filter_by_category "${2:-knowledge-graph.json}" "$3"
            ;;
        list-categories)
            list_categories "${2:-knowledge-graph.json}"
            ;;
        *)
            cat <<EOF
Knowledge Graph Utilities for LLM Agents
=========================================

Safe data operations on knowledge graphs without requiring script creation.

Usage: $0 <command> [args]

Commands:
  extract-claims [kg_file]           - Extract all claims
  extract-entities [kg_file]         - Extract all entities
  stats [kg_file]                    - Compute comprehensive statistics
  filter-confidence [kg_file] [min]  - Filter claims by confidence >= min
  filter-category [kg_file] <cat>    - Filter claims by category
  list-categories [kg_file]          - List unique categories

Examples:
  # Get statistics
  $0 stats knowledge-graph.json
  
  # Extract high-confidence claims
  $0 filter-confidence knowledge-graph.json 0.8
  
  # Get all claims in a specific category
  $0 filter-category knowledge-graph.json "efficacy"
  
  # List all categories
  $0 list-categories knowledge-graph.json

Output: JSON format for easy parsing
EOF
            ;;
    esac
fi

