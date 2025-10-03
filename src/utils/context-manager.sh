#!/bin/bash
# Context Management Utilities
# Prevents context overflow through intelligent pruning and summarization

# Configuration
MAX_FACTS_PER_SOURCE=10
MIN_CREDIBILITY="medium"

# Prune raw research findings to essential information
prune_context() {
    local raw_dir="$1"

    # Combine all findings
    local all_findings="$raw_dir"/*-findings*.json

    # Extract only essential information:
    # - Top N facts per source
    # - Remove low-credibility sources
    # - Deduplicate similar facts
    # - Keep all citations

    jq -s '
        # Flatten all findings arrays
        [.[] | .findings[]?] |

        # Filter by credibility
        [.[] | select(
            .credibility == "academic" or
            .credibility == "official" or
            .credibility == "high" or
            .credibility == "medium"
        )] |

        # Group by source
        group_by(.source_url) |

        # Take top N facts per source (by importance if available)
        [.[] |
            sort_by(.importance // "medium") |
            reverse |
            .[:'"$MAX_FACTS_PER_SOURCE"']
        ] |

        # Flatten back to array
        flatten |

        # Remove duplicates (same fact from different sources)
        unique_by(.fact)
    ' $all_findings
}

# Create progressive summaries for synthesis agent
summarize_for_synthesis() {
    local findings_file="$1"

    # Group by source and create structured summaries
    # This reduces token count by ~50% while preserving key information

    jq '
        group_by(.source_url) |
        map({
            source: .[0].source_url,
            source_title: .[0].source_title,
            credibility: .[0].credibility,
            date: .[0].date,
            key_facts: [.[] | .fact],
            key_quotes: [.[] | select(.quote != null) | .quote],
            fact_count: length
        })
    ' "$findings_file"
}

# Calculate context usage (estimate token count)
estimate_tokens() {
    local file="$1"

    # Rough estimate: 1 token ≈ 4 characters
    local char_count=$(wc -m < "$file")
    local token_estimate=$((char_count / 4))

    echo "$token_estimate"
}

# Check if context is within limits
check_context_limit() {
    local file="$1"
    local limit="${2:-180000}"  # Default: 180k tokens (safe margin)

    local tokens=$(estimate_tokens "$file")

    if [ "$tokens" -gt "$limit" ]; then
        echo "WARNING: Context exceeds limit ($tokens > $limit)"
        return 1
    else
        echo "Context within limit ($tokens / $limit tokens)"
        return 0
    fi
}

# Deduplicate facts across sources
deduplicate_facts() {
    local findings_file="$1"

    # Remove facts that are semantically similar
    # (Simple version: exact match. Advanced: use embedding similarity)

    jq '[
        .[] |
        {
            fact: .fact,
            sources: [.source_url],
            credibility: .credibility
        }
    ] |
    group_by(.fact) |
    map({
        fact: .[0].fact,
        sources: ([.[] | .sources[]] | unique),
        source_count: ([.[] | .sources[]] | unique | length),
        credibility: ([.[] | .credibility] | max)
    })' "$findings_file"
}

# Export functions for use in other scripts
export -f prune_context
export -f summarize_for_synthesis
export -f estimate_tokens
export -f check_context_limit
export -f deduplicate_facts
