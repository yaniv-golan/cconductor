#!/usr/bin/env bash
# Context Management Utilities
# Prevents context overflow through intelligent pruning and summarization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helpers following repository conventions
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/file-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-loader.sh"

readonly DEFAULT_MAX_FACTS_PER_SOURCE=10
MAX_FACTS_PER_SOURCE="$DEFAULT_MAX_FACTS_PER_SOURCE"

config_value=$(get_config_value "cconductor-config" ".context_management.max_facts_per_source" "$DEFAULT_MAX_FACTS_PER_SOURCE" 2>/dev/null || echo "$DEFAULT_MAX_FACTS_PER_SOURCE")
if [[ -n "$config_value" && "$config_value" =~ ^[0-9]+$ ]]; then
    MAX_FACTS_PER_SOURCE="$config_value"
else
    log_warn "context-manager: invalid max_facts_per_source config '$config_value', defaulting to $DEFAULT_MAX_FACTS_PER_SOURCE"
fi

gather_findings_files() {
    local raw_dir="$1"
    local -a files=()

    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$raw_dir" -maxdepth 1 -type f -name "*-findings*.json" -print0 2>/dev/null)

    printf '%s\n' "${files[@]}"
}

ensure_findings_dir() {
    local raw_dir="$1"
    local context="$2"

    if [[ -z "$raw_dir" ]]; then
        log_error "$context: findings directory not provided"
        return 1
    fi

    if [[ ! -d "$raw_dir" ]]; then
        log_warn "$context: findings directory missing: $raw_dir"
        return 1
    fi

    return 0
}

# Prune raw research findings to essential information
prune_context() {
    local raw_dir="$1"

    ensure_findings_dir "$raw_dir" "context-manager.prune_context" || {
        echo "[]"
        return 1
    }

    mapfile -t findings_files < <(gather_findings_files "$raw_dir")
    if ((${#findings_files[@]} == 0)); then
        log_warn "context-manager.prune_context: no findings files found in $raw_dir"
        echo "[]"
        return 0
    fi

    if ! jq --argjson max "$MAX_FACTS_PER_SOURCE" -s '
        [.[] | .findings[]?] |
        [.[] | select(
            .credibility == "academic" or
            .credibility == "official" or
            .credibility == "high" or
            .credibility == "medium"
        )] |
        group_by(.source_url) |
        [.[] |
            sort_by(.importance // "medium") |
            reverse |
            .[:$max]
        ] |
        flatten |
        unique_by(.fact)
    ' "${findings_files[@]}"; then
        log_error "context-manager.prune_context failed to prune findings in $raw_dir"
        return 1
    fi
}

# Create progressive summaries for synthesis agent
summarize_for_synthesis() {
    local findings_file="$1"

    if [[ -z "$findings_file" ]]; then
        log_error "context-manager.summarize_for_synthesis: findings file not provided"
        return 1
    fi

    if [[ ! -f "$findings_file" ]]; then
        log_warn "context-manager.summarize_for_synthesis: findings file missing: $findings_file"
        echo "[]"
        return 0
    fi

    if ! jq empty "$findings_file" >/dev/null 2>&1; then
        log_error "context-manager.summarize_for_synthesis: invalid JSON $findings_file"
        return 1
    fi

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

estimate_tokens() {
    local file="$1"

    if [[ -z "$file" || ! -f "$file" ]]; then
        log_warn "context-manager.estimate_tokens: file not found: $file"
        echo "0"
        return 1
    fi

    local char_count
    if ! char_count=$(wc -m < "$file" 2>/dev/null); then
        log_error "context-manager.estimate_tokens: failed to measure size of $file"
        echo "0"
        return 1
    fi

    local token_estimate=$((char_count / 4))
    echo "$token_estimate"
}

check_context_limit() {
    local file="$1"
    local limit="${2:-180000}"

    local tokens
    tokens=$(estimate_tokens "$file") || tokens=0

    if [[ -z "$tokens" || ! "$tokens" =~ ^[0-9]+$ ]]; then
        log_warn "context-manager.check_context_limit: unable to determine token count for $file"
        return 1
    fi

    if ((tokens > limit)); then
        log_warn "Context exceeds limit ($tokens > $limit)"
        return 1
    fi

    echo "Context within limit ($tokens / $limit tokens)"
    return 0
}

deduplicate_facts() {
    local findings_file="$1"

    if [[ -z "$findings_file" || ! -f "$findings_file" ]]; then
        log_warn "context-manager.deduplicate_facts: findings file missing: $findings_file"
        echo "[]"
        return 0
    fi

    if ! jq empty "$findings_file" >/dev/null 2>&1; then
        log_error "context-manager.deduplicate_facts: invalid JSON $findings_file"
        return 1
    fi

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

export -f prune_context
export -f summarize_for_synthesis
export -f estimate_tokens
export -f check_context_limit
export -f deduplicate_facts
