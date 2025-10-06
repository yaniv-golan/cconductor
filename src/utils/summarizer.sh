#!/usr/bin/env bash
# Summarization Utilities
# Creates progressive summaries to manage context

# Create a summary of research findings
create_summary() {
    local input_file="$1"
    local max_length="${2:-2000}"  # Max tokens

    # Extract key information and create concise summary
    jq --arg max "$max_length" '
    {
        total_sources: ([.[] | .source] | unique | length),
        total_facts: ([.[] | .key_facts[]] | length),
        credibility_breakdown: (
            group_by(.credibility) |
            map({(.[0].credibility): length}) |
            add
        ),
        top_facts: ([.[] | .key_facts[]] | .[0:20]),
        sources: ([.[] | {
            url: .source,
            title: .source_title,
            fact_count: .fact_count
        }])
    }' "$input_file"
}

# Create a hierarchical summary with different detail levels
create_hierarchical_summary() {
    local input_file="$1"
    local output_dir="$2"

    # Level 1: Executive summary (500 tokens)
    jq '[.[] | .key_facts[0:2]] | flatten | .[0:10]' "$input_file" \
        > "$output_dir/summary-level1.json"

    # Level 2: Moderate detail (2000 tokens)
    jq '[.[] | .key_facts[0:5]] | flatten | .[0:40]' "$input_file" \
        > "$output_dir/summary-level2.json"

    # Level 3: Full pruned findings (10000 tokens)
    cp "$input_file" "$output_dir/summary-level3.json"
}

# Export functions
export -f create_summary
export -f create_hierarchical_summary
