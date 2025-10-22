#!/usr/bin/env bash
# Citation Manager
# JSON-based citation management for research reports
# Manages citations in knowledge graph without requiring SQLite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"

# Source shared-state
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Add citation to knowledge graph (with deduplication by DOI/URL)
cm_add_citation() {
    local kg_file="$1"
    local citation_json="$2"

    lock_acquire "$kg_file" || {
        log_error "Failed to acquire lock for adding citation"
        return 1
    }

    # Generate citation ID if not provided
    local citation_with_id
    citation_with_id=$(echo "$citation_json" | jq --arg date "$(get_timestamp)" '
        if .id then . else
            . + {
                id: ("cite_" + (now | tostring)),
                added_at: $date,
                cited_by_claims: []
            }
        end
    ')

    # Add to citations array, deduplicate by DOI or URL
    jq --argjson new "$citation_with_id" '
        # Initialize citations array if it doesn not exist
        if .citations == null then .citations = [] else . end |

        # Check if citation already exists (by DOI or URL)
        .citations |= (
            if (. | map(select(
                (.doi != null and .doi == $new.doi) or
                (.url != null and .url == $new.url)
            )) | length > 0) then
                # Already exists, don not add
                .
            else
                # New citation, add it
                . + [$new]
            end
        )
    ' "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"

    # Return the citation ID
    echo "$citation_with_id" | jq -r '.id'
}

# Link citation to claim
cm_link_citation_to_claim() {
    local kg_file="$1"
    local claim_id="$2"
    local citation_id="$3"
    local excerpt="${4:-}"
    local page_number="${5:-}"

    lock_acquire "$kg_file" || {
        log_error "Failed to acquire lock for linking citation"
        return 1
    }

    # Build source object
    local source_obj
    source_obj=$(jq -n \
        --arg cite "$citation_id" \
        --arg excerpt "$excerpt" \
        --arg page "$page_number" \
        '{
            citation_id: $cite,
            relevant_excerpt: (if $excerpt != "" then $excerpt else null end),
            page_number: (if $page != "" then $page else null end)
        }')

    jq --arg claim "$claim_id" \
       --argjson source "$source_obj" '
        # Initialize sources array for claim if needed
        (.claims[] | select(.id == $claim)) |= (
            if .sources == null then .sources = [] else . end
        ) |

        # Add citation_id to claim sources (avoid duplicates)
        (.claims[] | select(.id == $claim).sources) |= (
            if (. | map(.citation_id) | contains([$source.citation_id])) then
                .
            else
                . + [$source]
            end
        ) |

        # Add claim_id to citation cited_by_claims (avoid duplicates)
        (.citations[] | select(.id == $source.citation_id)) |= (
            if .cited_by_claims == null then .cited_by_claims = [] else . end |
            if (.cited_by_claims | contains([$claim])) then
                .
            else
                .cited_by_claims += [$claim]
            end
        )
    ' "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
}

# Get citation by ID
cm_get_citation() {
    local kg_file="$1"
    local citation_id="$2"

    jq --arg id "$citation_id" \
       '.citations[]? | select(.id == $id)' \
       "$kg_file"
}

# Get all citations for a claim
cm_get_claim_citations() {
    local kg_file="$1"
    local claim_id="$2"

    jq --arg claim "$claim_id" '
        [(.claims[]? | select(.id == $claim).sources[]?.citation_id)] as $cite_ids |
        .citations[]? | select(.id as $id | $cite_ids | contains([$id]))
    ' "$kg_file"
}

# Get all citations from knowledge graph
cm_get_all_citations() {
    local kg_file="$1"

    jq '.citations[]?' "$kg_file"
}

# Count total citations
cm_count_citations() {
    local kg_file="$1"

    jq '.citations? | length' "$kg_file"
}

# Validate all claims have citations
cm_validate_all_cited() {
    local kg_file="$1"

    local uncited
    uncited=$(jq -r '
        [.claims[]? | select((.sources? | length) == 0 or .sources == null) | .id] |
        if length > 0 then . else empty end
    ' "$kg_file")

    if [ -n "$uncited" ]; then
        log_warn "Claims without citations: $uncited"
        return 1
    fi
    return 0
}

# Get citation statistics
cm_get_stats() {
    local kg_file="$1"

    jq '{
        total_citations: (.citations? | length),
        citations_with_doi: ([.citations[]? | select(.doi != null)] | length),
        citations_by_type: (.citations? | group_by(.type) | map({type: .[0].type, count: length})),
        claims_with_citations: ([.claims[]? | select((.sources? | length) > 0)] | length),
        claims_without_citations: ([.claims[]? | select((.sources? | length) == 0 or .sources == null)] | length)
    }' "$kg_file"
}

# Remove duplicate citations
cm_deduplicate() {
    local kg_file="$1"

    lock_acquire "$kg_file" || {
        log_error "Failed to acquire lock for deduplication"
        return 1
    }

    jq '.citations |= (. | unique_by(.doi // .url))' "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
}

# Export functions
export -f cm_add_citation
export -f cm_link_citation_to_claim
export -f cm_get_citation
export -f cm_get_claim_citations
export -f cm_get_all_citations
export -f cm_count_citations
export -f cm_validate_all_cited
export -f cm_get_stats
export -f cm_deduplicate

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        add)
            # Add citation from JSON
            cm_add_citation "$2" "$3"
            ;;
        link)
            # Link citation to claim
            cm_link_citation_to_claim "$2" "$3" "$4" "${5:-}" "${6:-}"
            ;;
        get)
            # Get citation by ID
            cm_get_citation "$2" "$3"
            ;;
        claim-citations)
            # Get all citations for a claim
            cm_get_claim_citations "$2" "$3"
            ;;
        list)
            # List all citations
            cm_get_all_citations "$2"
            ;;
        count)
            # Count citations
            cm_count_citations "$2"
            ;;
        validate)
            # Validate all claims cited
            cm_validate_all_cited "$2"
            ;;
        stats)
            # Get statistics
            cm_get_stats "$2"
            ;;
        dedupe)
            # Remove duplicates
            cm_deduplicate "$2"
            ;;
        *)
            cat <<EOF
Citation Manager - Manage citations in knowledge graph

Usage: $0 <command> <args>

Commands:
  add <kg_file> <citation_json>           Add citation to knowledge graph
  link <kg_file> <claim_id> <cite_id> [excerpt] [page]
                                           Link citation to claim
  get <kg_file> <citation_id>             Get citation by ID
  claim-citations <kg_file> <claim_id>    Get all citations for a claim
  list <kg_file>                           List all citations
  count <kg_file>                          Count total citations
  validate <kg_file>                       Validate all claims have citations
  stats <kg_file>                          Get citation statistics
  dedupe <kg_file>                         Remove duplicate citations

Examples:
  # Add a citation
  $0 add session/kg.json '{"type":"journal_article","authors":[{"family":"Smith","given":"J"}],"year":2021,"title":"Title","doi":"10.1234/..."}'

  # Link citation to claim
  $0 link session/kg.json claim_042 cite_001 "Relevant quote" "147"

  # Validate all claims cited
  $0 validate session/kg.json
EOF
            ;;
    esac
fi
