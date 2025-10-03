#!/bin/bash
# Bibliography Generator
# Formats citations in multiple academic styles (APA, Chicago, Vancouver)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Format single citation in APA style (7th edition)
format_apa() {
    local citation_json="$1"

    echo "$citation_json" | jq -r '
        # Authors (Last, F. M.)
        (if .authors then
            (.authors |
                if length == 1 then
                    .[0].family + ", " + (.[0].given[0:1] // "") + "."
                elif length == 2 then
                    .[0].family + ", " + (.[0].given[0:1] // "") + "., & " +
                    .[1].family + ", " + (.[1].given[0:1] // "") + "."
                else
                    .[0].family + ", " + (.[0].given[0:1] // "") + "., et al."
                end)
        else "Unknown Author" end) +

        # Year
        " (" + (.year | tostring) + "). " +

        # Title (italicized in most contexts, but plain text here)
        .title +

        # Journal/Source
        (if .journal then
            ". *" + .journal + "*" +
            (if .volume then ", " + (.volume | tostring) else "" end) +
            (if .issue then "(" + (.issue | tostring) + ")" else "" end) +
            (if .pages then ", " + .pages else "" end) +
            "."
        elif .type == "book" then
            (if .publisher then ". " + .publisher else "" end) +
            "."
        else
            "."
        end) +

        # DOI or URL
        (if .doi then
            " https://doi.org/" + .doi
        elif .url then
            " " + .url
        else
            ""
        end)
    '
}

# Format single citation in Chicago style (17th edition, author-date)
format_chicago() {
    local citation_json="$1"

    echo "$citation_json" | jq -r '
        # Authors (Last, First)
        (if .authors then
            (.authors |
                if length == 1 then
                    .[0].family + ", " + (.[0].given // "")
                elif length == 2 then
                    .[0].family + ", " + (.[0].given // "") + ", and " +
                    .[1].family + ", " + (.[1].given // "")
                elif length == 3 then
                    .[0].family + ", " + (.[0].given // "") + ", " +
                    .[1].family + ", " + (.[1].given // "") + ", and " +
                    .[2].family + ", " + (.[2].given // "")
                else
                    .[0].family + ", " + (.[0].given // "") + " et al."
                end)
        else "Unknown Author" end) +

        # Year
        ". " + (.year | tostring) + ". " +

        # Title (quoted for articles, italicized for books)
        (if .type == "journal_article" then
            "\"" + .title + ".\""
        else
            "*" + .title + "*"
        end) +

        # Journal/Source
        (if .journal then
            " *" + .journal + "*" +
            (if .volume then " " + (.volume | tostring) else "" end) +
            (if .issue then ", no. " + (.issue | tostring) else "" end) +
            (if .pages then " (" + (.year | tostring) + "): " + .pages else "" end) +
            "."
        elif .type == "book" then
            (if .publisher then ". " + .publisher else "" end) +
            "."
        else
            "."
        end) +

        # DOI or URL
        (if .doi then
            " https://doi.org/" + .doi + "."
        elif .url then
            " " + .url + "."
        else
            ""
        end)
    '
}

# Format single citation in Vancouver style (numeric)
format_vancouver() {
    local citation_json="$1"
    local citation_number="${2:-1}"

    echo "$citation_json" | jq -r --arg num "$citation_number" '
        # Number
        $num + ". " +

        # Authors (Last FM)
        (if .authors then
            (.authors |
                if length <= 6 then
                    map(.family + " " + ((.given[0:1] // "") | ascii_upcase)) | join(", ")
                else
                    (.[0:3] | map(.family + " " + ((.given[0:1] // "") | ascii_upcase)) | join(", ")) + ", et al"
                end)
        else "Unknown Author" end) +

        # Title
        ". " + .title + ". " +

        # Journal/Source
        (if .journal then
            .journal +
            (if .year then ". " + (.year | tostring) else "" end) +
            (if .volume then ";" + (.volume | tostring) else "" end) +
            (if .issue then "(" + (.issue | tostring) + ")" else "" end) +
            (if .pages then ":" + .pages else "" end) +
            "."
        elif .type == "book" then
            (if .publisher then .publisher + "; " else "" end) +
            (.year | tostring) + "."
        else
            (.year | tostring) + "."
        end) +

        # DOI or URL
        (if .doi then
            " doi:" + .doi
        elif .url then
            " Available from: " + .url
        else
            ""
        end)
    '
}

# Generate full bibliography from knowledge graph
generate_bibliography() {
    local kg_file="$1"
    local style="${2:-apa}"
    local output_format="${3:-text}"

    # Get all citations from knowledge graph
    local citations
    citations=$(jq -c '.citations[]?' "$kg_file")

    if [ -z "$citations" ]; then
        echo "No citations found in knowledge graph" >&2
        return 1
    fi

    local bibliography=""
    local citation_num=1

    # Sort citations by author last name, then year
    citations=$(echo "$citations" | jq -s 'sort_by(.authors[0].family, .year)')

    case "$output_format" in
        markdown)
            bibliography="# References\n\n"
            ;;
        html)
            bibliography="<div class=\"references\">\n<h2>References</h2>\n<ol>\n"
            ;;
    esac

    # Format each citation
    while IFS= read -r citation; do
        local formatted=""

        case "$style" in
            apa)
                formatted=$(format_apa "$citation")
                ;;
            chicago)
                formatted=$(format_chicago "$citation")
                ;;
            vancouver)
                formatted=$(format_vancouver "$citation" "$citation_num")
                ;;
            *)
                echo "Unknown citation style: $style" >&2
                return 1
                ;;
        esac

        case "$output_format" in
            markdown)
                bibliography="${bibliography}${formatted}\n\n"
                ;;
            html)
                bibliography="${bibliography}  <li>${formatted}</li>\n"
                ;;
            text)
                bibliography="${bibliography}${formatted}\n\n"
                ;;
        esac

        citation_num=$((citation_num + 1))
    done <<< "$(echo "$citations" | jq -c '.[]')"

    case "$output_format" in
        html)
            bibliography="${bibliography}</ol>\n</div>"
            ;;
    esac

    echo -e "$bibliography"
}

# Generate in-text citation reference
generate_inline_citation() {
    local citation_json="$1"
    local style="${2:-apa}"

    case "$style" in
        apa|chicago)
            # Author-date format: (Smith, 2021)
            echo "$citation_json" | jq -r '
                "(" +
                (if .authors then
                    (if (.authors | length) == 1 then
                        .authors[0].family
                    elif (.authors | length) == 2 then
                        .authors[0].family + " & " + .authors[1].family
                    else
                        .authors[0].family + " et al."
                    end)
                else "Unknown" end) +
                ", " + (.year | tostring) + ")"
            '
            ;;
        vancouver)
            # Numeric format: [1]
            local citation_id
            citation_id=$(echo "$citation_json" | jq -r '.id')
            echo "[$citation_id]"
            ;;
        *)
            echo "(Unknown style)" >&2
            return 1
            ;;
    esac
}

# Get citation by ID and format inline
get_inline_citation_by_id() {
    local kg_file="$1"
    local citation_id="$2"
    local style="${3:-apa}"

    local citation
    citation=$(jq --arg id "$citation_id" \
        '.citations[]? | select(.id == $id)' \
        "$kg_file")

    if [ -z "$citation" ]; then
        echo "(Citation not found: $citation_id)" >&2
        return 1
    fi

    generate_inline_citation "$citation" "$style"
}

# Generate bibliography section for a specific claim
generate_claim_bibliography() {
    local kg_file="$1"
    local claim_id="$2"
    local style="${3:-apa}"

    # Get citation IDs for this claim
    local citation_ids
    citation_ids=$(jq -r --arg claim "$claim_id" \
        '.claims[]? | select(.id == $claim) | .sources[]?.citation_id' \
        "$kg_file")

    if [ -z "$citation_ids" ]; then
        echo "No citations found for claim: $claim_id" >&2
        return 1
    fi

    local bibliography=""
    local citation_num=1

    while IFS= read -r citation_id; do
        local citation
        citation=$(jq --arg id "$citation_id" \
            '.citations[]? | select(.id == $id)' \
            "$kg_file")

        if [ -n "$citation" ]; then
            local formatted=""

            case "$style" in
                apa)
                    formatted=$(format_apa "$citation")
                    ;;
                chicago)
                    formatted=$(format_chicago "$citation")
                    ;;
                vancouver)
                    formatted=$(format_vancouver "$citation" "$citation_num")
                    ;;
            esac

            bibliography="${bibliography}${formatted}\n\n"
            citation_num=$((citation_num + 1))
        fi
    done <<< "$citation_ids"

    echo -e "$bibliography"
}

# Validate citation completeness
validate_citation() {
    local citation_json="$1"

    echo "$citation_json" | jq -e '
        # Required fields for all citations
        (.title and .year) and

        # At least one author or source identifier
        ((.authors and (.authors | length) > 0) or .organization) and

        # At least one locator (DOI, URL, or journal details)
        (.doi or .url or .journal)
    ' > /dev/null

    return $?
}

# Export functions
export -f format_apa
export -f format_chicago
export -f format_vancouver
export -f generate_bibliography
export -f generate_inline_citation
export -f get_inline_citation_by_id
export -f generate_claim_bibliography
export -f validate_citation

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        format)
            # Format single citation
            style="${3:-apa}"
            case "$style" in
                apa)
                    format_apa "$(cat "$2")"
                    ;;
                chicago)
                    format_chicago "$(cat "$2")"
                    ;;
                vancouver)
                    format_vancouver "$(cat "$2")" "${4:-1}"
                    ;;
                *)
                    echo "Unknown style: $style" >&2
                    exit 1
                    ;;
            esac
            ;;
        generate)
            # Generate full bibliography
            generate_bibliography "$2" "${3:-apa}" "${4:-text}"
            ;;
        inline)
            # Generate inline citation
            generate_inline_citation "$(cat "$2")" "${3:-apa}"
            ;;
        claim)
            # Generate bibliography for specific claim
            generate_claim_bibliography "$2" "$3" "${4:-apa}"
            ;;
        validate)
            # Validate citation
            if validate_citation "$(cat "$2")"; then
                echo "✅ Citation is valid"
            else
                echo "❌ Citation is incomplete" >&2
                exit 1
            fi
            ;;
        *)
            cat <<EOF
Bibliography Generator - Format citations in academic styles

Usage: $0 <command> <args>

Commands:
  format <citation.json> <style> [num]    Format single citation
  generate <kg.json> <style> [format]     Generate full bibliography
  inline <citation.json> <style>          Generate inline citation
  claim <kg.json> <claim_id> <style>      Generate bibliography for claim
  validate <citation.json>                Validate citation completeness

Styles:
  apa        APA 7th edition (default)
  chicago    Chicago 17th edition (author-date)
  vancouver  Vancouver (numeric)

Output formats (for generate):
  text       Plain text (default)
  markdown   Markdown format
  html       HTML format

Examples:
  # Format a citation in APA style
  $0 format citation.json apa

  # Generate full bibliography in Chicago style
  $0 generate session/kg.json chicago markdown

  # Get inline citation for a specific claim
  $0 claim session/kg.json claim_042 apa

  # Validate citation completeness
  $0 validate citation.json
EOF
            ;;
    esac
fi
