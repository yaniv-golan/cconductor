#!/usr/bin/env bash
# Summarization Utilities
# Creates progressive summaries to manage context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source required helpers following repository conventions
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/file-helpers.sh"

require_command jq

validate_summary_input() {
    local input_file="$1"
    local context="${2:-summarizer}"

    if [[ -z "$input_file" ]]; then
        log_error "$context input file not provided"
        return 1
    fi

    if [[ ! -f "$input_file" ]]; then
        log_error "$context input file not found: $input_file"
        return 1
    fi

    if ! jq empty "$input_file" >/dev/null 2>&1; then
        log_error "$context input file is not valid JSON: $input_file"
        return 1
    fi

    return 0
}

# Create a summary of research findings
create_summary() {
    local input_file="$1"
    local max_length="${2:-2000}"  # Max tokens (approximate)

    validate_summary_input "$input_file" "summarizer.create_summary" || return 1

    if [[ -z "$max_length" || ! "$max_length" =~ ^[0-9]+$ ]]; then
        log_warn "summarizer.create_summary invalid max length '$max_length', defaulting to 2000"
        max_length=2000
    fi

    local summary
    if ! summary=$(jq --argjson max_int "$max_length" '
        {
            total_sources: ([.[] | .source] | unique | length),
            total_facts: ([.[] | .key_facts[]] | length),
            credibility_breakdown: (
                group_by(.credibility) |
                map({(.[0].credibility): length}) |
                add
            ),
            top_facts: ([.[] | .key_facts[]] | .[0:($max_int / 100 | floor)]),
            sources: ([.[] | {
                url: .source,
                title: .source_title,
                fact_count: .fact_count
            }])
        }
    ' "$input_file" 2>/dev/null); then
        log_error "summarizer.create_summary failed to generate summary for $input_file"
        return 1
    fi

    printf '%s\n' "$summary"
}

# Create a hierarchical summary with different detail levels
create_hierarchical_summary() {
    local input_file="$1"
    local output_dir="$2"

    validate_summary_input "$input_file" "summarizer.create_hierarchical_summary" || return 1

    if [[ -z "$output_dir" ]]; then
        log_error "summarizer.create_hierarchical_summary output directory not provided"
        return 1
    fi

    ensure_dir "$output_dir"

    local level1="$output_dir/summary-level1.json"
    local level2="$output_dir/summary-level2.json"
    local level3="$output_dir/summary-level3.json"

    if ! jq '[.[] | .key_facts[0:2]] | flatten | .[0:10]' "$input_file" > "$level1" 2>/dev/null; then
        log_error "summarizer.create_hierarchical_summary failed to write $level1"
        return 1
    fi

    if ! jq '[.[] | .key_facts[0:5]] | flatten | .[0:40]' "$input_file" > "$level2" 2>/dev/null; then
        log_error "summarizer.create_hierarchical_summary failed to write $level2"
        return 1
    fi

    if ! cp "$input_file" "$level3"; then
        log_error "summarizer.create_hierarchical_summary failed to copy $input_file to $level3"
        return 1
    fi
}

# Export functions
export -f create_summary
export -f create_hierarchical_summary
