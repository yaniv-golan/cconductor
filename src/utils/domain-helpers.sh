#!/usr/bin/env bash
# Domain Helpers - Shared utilities for domain-aware quality enforcement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-loader.sh" 2>/dev/null || true

# Internal caches to avoid recomputing manual merges for every call
__DOMAIN_HELPERS_LAST_INPUT=""
__DOMAIN_HELPERS_LAST_EFFECTIVE=""
__DOMAIN_HELPERS_MANUAL_PATH=""

_domain_helpers_expand_path() {
    local path="$1"
    if [[ -z "$path" ]]; then
        echo ""
        return 0
    fi
    if [[ "$path" == ~* ]]; then
        if [[ -n "${HOME:-}" ]]; then
            path="${path/#\~/$HOME}"
        else
            path="${path/#\~/}"
        fi
    fi
    echo "$path"
}

_domain_helpers_manual_patterns_path() {
    if [[ -n "$__DOMAIN_HELPERS_MANUAL_PATH" ]]; then
        echo "$__DOMAIN_HELPERS_MANUAL_PATH"
        return 0
    fi

    local config_json
    config_json=$(load_config "quality-gate" 2>/dev/null || echo '{}')
    local path
    path=$(echo "$config_json" | jq -r '.manual_stakeholder_patterns.config_path // ""' 2>/dev/null || echo "")

    if [[ -z "$path" || "$path" == "null" ]]; then
        if [[ -n "${CCONDUCTOR_USER_CONFIG_DIR:-}" ]]; then
            path="$CCONDUCTOR_USER_CONFIG_DIR/stakeholder-patterns.json"
        else
            path="$HOME/.config/cconductor/stakeholder-patterns.json"
        fi
    fi

    path=$(_domain_helpers_expand_path "$path")
    __DOMAIN_HELPERS_MANUAL_PATH="$path"
    echo "$path"
}

_domain_helpers_merge_manual_patterns() {
    local heuristics_json="$1"
    local manual_path
    manual_path=$(_domain_helpers_manual_patterns_path)

    if [[ -z "$heuristics_json" ]]; then
        echo '{}'
        return 0
    fi

    if [[ -z "$manual_path" || ! -f "$manual_path" ]]; then
        printf '%s' "$heuristics_json"
        return 0
    fi

    if ! jq empty "$manual_path" >/dev/null 2>&1; then
        log_warn "domain-helpers: invalid manual stakeholder patterns at $manual_path"
        printf '%s' "$heuristics_json"
        return 0
    fi

    local tmp_heuristics
    tmp_heuristics=$(mktemp)
    printf '%s' "$heuristics_json" >"$tmp_heuristics"

    local merged
    merged=$(jq -n \
        --slurpfile heur "$tmp_heuristics" \
        --slurpfile manual "$manual_path" '
            ($heur[0] // {}) as $h |
            ($manual[0].additional_patterns // {}) as $extra |
            if ($extra | length) == 0 then
                $h
            else
                $h * {
                    stakeholder_categories: (
                        ($h.stakeholder_categories // {}) as $existing |
                        reduce ($extra | to_entries[]) as $entry ($existing;
                            . + {
                                ($entry.key): (
                                    ($existing[$entry.key] // {
                                        description: "Manually added stakeholder patterns",
                                        importance: "medium",
                                        domain_patterns: [],
                                        keyword_patterns: []
                                    }) as $base |
                                    $base + {
                                        domain_patterns: ((($base.domain_patterns // []) + ($entry.value.domain_patterns // []))
                                            | map(select(. != null and . != "")) | unique),
                                        keyword_patterns: ((($base.keyword_patterns // []) + ($entry.value.keyword_patterns // []))
                                            | map(select(. != null and . != "")) | unique)
                                    }
                                )
                            }
                        )
                    )
                }
            end
        ' 2>/dev/null || printf '%s' "$heuristics_json")

    rm -f "$tmp_heuristics"
    printf '%s' "$merged"
}

_domain_helpers_effective_heuristics() {
    local heuristics_json="$1"
    if [[ -z "$heuristics_json" || "$heuristics_json" == "null" ]]; then
        echo '{}'
        return 0
    fi

    if [[ "$heuristics_json" == "$__DOMAIN_HELPERS_LAST_INPUT" && -n "$__DOMAIN_HELPERS_LAST_EFFECTIVE" ]]; then
        printf '%s' "$__DOMAIN_HELPERS_LAST_EFFECTIVE"
        return 0
    fi

    local merged
    merged=$(_domain_helpers_merge_manual_patterns "$heuristics_json")
    __DOMAIN_HELPERS_LAST_INPUT="$heuristics_json"
    __DOMAIN_HELPERS_LAST_EFFECTIVE="$merged"
    printf '%s' "$merged"
}

_domain_helpers_extract_domain() {
    local url="$1"
    if [[ -z "$url" || "$url" == "null" ]]; then
        echo ""
        return 0
    fi
    local domain="${url#*://}"
    domain="${domain%%/*}"
    domain="${domain#www.}"
    printf '%s' "$domain"
}

map_source_to_stakeholder() {
    local source_json="$1"
    local heuristics_json="$2"

    local effective
    effective=$(_domain_helpers_effective_heuristics "$heuristics_json")
    if [[ -z "$effective" || "$effective" == "null" ]]; then
        echo "uncategorized"
        return 0
    fi

    local url title domain
    url=$(echo "$source_json" | jq -r '.url // ""' 2>/dev/null || echo "")
    title=$(echo "$source_json" | jq -r '.title // ""' 2>/dev/null || echo "")
    domain=$(_domain_helpers_extract_domain "$url")
    local domain_lc="${domain,,}"

    while IFS=$'\t' read -r category category_data; do
        [[ -z "$category" || -z "$category_data" ]] && continue

        local matched=false

        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == "null" ]] && continue
            local pattern_lc="${pattern,,}"
            if [[ -n "$domain_lc" && "$domain_lc" == *"$pattern_lc"* ]]; then
                echo "$category"
                return 0
            fi
        done < <(echo "$category_data" | jq -r '.domain_patterns[]?' 2>/dev/null || echo "")

        while IFS= read -r keyword; do
            [[ -z "$keyword" || "$keyword" == "null" ]] && continue
            if printf '%s' "$title" | grep -qiF -- "$keyword"; then
                matched=true
                break
            fi
        done < <(echo "$category_data" | jq -r '.keyword_patterns[]?' 2>/dev/null || echo "")

        if [[ "$matched" == true ]]; then
            echo "$category"
            return 0
        fi
    done < <(echo "$effective" | jq -r '.stakeholder_categories | to_entries[]? | "\(.key)\t\(.value | tojson)"' 2>/dev/null || echo "")

    echo "uncategorized"
}

infer_claim_topic() {
    local claim_statement="$1"
    local heuristics_json="$2"

    local effective
    effective=$(_domain_helpers_effective_heuristics "$heuristics_json")
    if [[ -z "$effective" || "$effective" == "null" ]]; then
        echo "unclassified"
        return 0
    fi

    while IFS=$'\t' read -r topic keywords; do
        [[ -z "$topic" || -z "$keywords" ]] && continue
        while IFS= read -r keyword; do
            [[ -z "$keyword" || "$keyword" == "null" ]] && continue
            if printf '%s' "$claim_statement" | grep -qiF -- "$keyword"; then
                echo "$topic"
                return 0
            fi
        done <<< "$keywords"
    done < <(echo "$effective" | jq -r '.freshness_requirements[]? | "\(.topic)\t\(.topic_keywords | join("\n"))"' 2>/dev/null || echo "")

    echo "unclassified"
}

match_watch_item() {
    local watch_item_json="$1"
    local claim_json="$2"

    local statement
    statement=$(echo "$claim_json" | jq -r '.statement // ""' 2>/dev/null || echo "")
    local canonical
    canonical=$(echo "$watch_item_json" | jq -r '.canonical // ""' 2>/dev/null || echo "")

    if [[ -n "$canonical" ]] && printf '%s' "$statement" | grep -qiF -- "$canonical"; then
        return 0
    fi

    while IFS= read -r variant; do
        [[ -z "$variant" || "$variant" == "null" ]] && continue
        if printf '%s' "$statement" | grep -qiF -- "$variant"; then
            return 0
        fi
    done < <(echo "$watch_item_json" | jq -r '.variants[]?' 2>/dev/null || echo "")

    local sources_json
    sources_json=$(echo "$claim_json" | jq -c '.sources[]?' 2>/dev/null || echo "")
    if [[ -n "$sources_json" ]]; then
        while IFS= read -r hint; do
            [[ -z "$hint" || "$hint" == "null" ]] && continue
            while IFS= read -r source; do
                [[ -z "$source" || "$source" == "null" ]] && continue
                if echo "$source" | jq -e --arg hint "$hint" '.url // "" | contains($hint)' >/dev/null 2>&1; then
                    return 0
                fi
            done <<< "$sources_json"
        done < <(echo "$watch_item_json" | jq -r '.source_hints[]?' 2>/dev/null || echo "")
    fi

    return 1
}

export -f map_source_to_stakeholder
export -f infer_claim_topic
export -f match_watch_item
