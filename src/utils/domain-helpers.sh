#!/usr/bin/env bash
# Domain Helpers - Shared utilities for domain-aware quality enforcement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-loader.sh" 2>/dev/null || true
safe_domain_json() {
    local payload="$1"
    local filter="$2"
    local fallback="$3"
    local context="$4"
    safe_jq_from_json "$payload" "$filter" "$fallback" "" "domain_helpers.${context:-payload}" "true"
}

safe_domain_json_raw() {
    local payload="$1"
    local filter="$2"
    local fallback="$3"
    local context="$4"
    safe_jq_from_json "$payload" "$filter" "$fallback" "" "domain_helpers.${context:-payload}" "false"
}
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# Internal caches to avoid recomputing manual merges for every call
__DOMAIN_HELPERS_LAST_INPUT=""
__DOMAIN_HELPERS_LAST_EFFECTIVE=""
__DOMAIN_HELPERS_MANUAL_PATH=""
__STAKEHOLDER_POLICY_CACHE=""
__STAKEHOLDER_POLICY_SOURCE=""
__STAKEHOLDER_RESOLVER_CACHE=""
__STAKEHOLDER_RESOLVER_SOURCE=""

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
    path=$(safe_domain_json "$config_json" '.manual_stakeholder_patterns.config_path // ""' "" "manual_config_path")

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
    if merged=$(jq -n \
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
        ');
    then
        :
    else
        log_warn "domain-helpers: failed to merge manual stakeholder patterns, using base heuristics"
        merged="$heuristics_json"
    fi

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
    domain="${domain%%:*}"
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
    url=$(safe_domain_json "$source_json" '.url // ""' "" "source.url")
    title=$(safe_domain_json "$source_json" '.title // ""' "" "source.title")
    domain=$(_domain_helpers_extract_domain "$url")
    local domain_lc="${domain,,}"

    local category_entries
    category_entries=$(safe_domain_json_raw "$effective" '.stakeholder_categories | to_entries' '[]' 'stakeholder_entries')

    while IFS= read -r entry; do
        local category
        category=$(safe_domain_json "$entry" '.key' "" "stakeholder_entry.key")
        [[ -z "$category" ]] && continue

        local matched=false

        local domain_patterns_json
        domain_patterns_json=$(safe_domain_json_raw "$entry" '.value.domain_patterns // []' '[]' "stakeholder_entry.domain_patterns")
        while IFS= read -r pattern; do
            [[ -z "$pattern" || "$pattern" == "null" ]] && continue
            local pattern_lc="${pattern,,}"
            if [[ -n "$domain_lc" && "$domain_lc" == *"$pattern_lc"* ]]; then
                echo "$category"
                return 0
            fi
        done < <(jq -r '.[]?' <<< "$domain_patterns_json")

        local keyword_patterns_json
        keyword_patterns_json=$(safe_domain_json_raw "$entry" '.value.keyword_patterns // []' '[]' "stakeholder_entry.keyword_patterns")
        while IFS= read -r keyword; do
            [[ -z "$keyword" || "$keyword" == "null" ]] && continue
            if printf '%s' "$title" | grep -qiF -- "$keyword"; then
                matched=true
                break
            fi
        done < <(jq -r '.[]?' <<< "$keyword_patterns_json")

        if [[ "$matched" == true ]]; then
            echo "$category"
            return 0
        fi
    done < <(jq -c '.[]' <<< "$category_entries")

    echo "uncategorized"
}

domain_helpers_get_stakeholder_policy() {
    local session_dir="${1:-}"
    local mission_name="${2:-}"

    local cache_key="${session_dir}::${mission_name}"
    if [[ "$cache_key" == "$__STAKEHOLDER_POLICY_SOURCE" && -n "$__STAKEHOLDER_POLICY_CACHE" ]]; then
        printf '%s' "$__STAKEHOLDER_POLICY_CACHE"
        return 0
    fi

    local policy_json=""
    local candidate=""

    if [[ -n "$session_dir" ]]; then
        candidate="$session_dir/meta/stakeholder-policy.json"
        if [[ -f "$candidate" ]] && jq empty "$candidate" 2>/dev/null; then
            policy_json=$(cat "$candidate")
        elif [[ -f "$candidate" ]]; then
            log_warn "domain-helpers: invalid session stakeholder policy at $candidate"
        fi
    fi

    if [[ -z "$policy_json" && -n "$mission_name" ]]; then
        candidate="$PROJECT_ROOT/config/missions/$mission_name/policy.json"
        if [[ -f "$candidate" ]] && jq empty "$candidate" 2>/dev/null; then
            policy_json=$(cat "$candidate")
        elif [[ -f "$candidate" ]]; then
            log_warn "domain-helpers: invalid mission stakeholder policy at $candidate"
        fi
    fi

    if [[ -z "$policy_json" ]]; then
        if policy_json=$(load_config "stakeholder-policy" 2>/dev/null); then
            :
        else
            policy_json="{}"
        fi
    fi

    if [[ -z "$policy_json" || "$policy_json" == "null" ]]; then
        policy_json="{}"
    fi

    __STAKEHOLDER_POLICY_CACHE="$policy_json"
    __STAKEHOLDER_POLICY_SOURCE="$cache_key"
    printf '%s' "$policy_json"
}

domain_helpers_get_stakeholder_resolver() {
    local session_dir="${1:-}"
    local mission_name="${2:-}"

    local cache_key="${session_dir}::${mission_name}"
    if [[ "$cache_key" == "$__STAKEHOLDER_RESOLVER_SOURCE" && -n "$__STAKEHOLDER_RESOLVER_CACHE" ]]; then
        printf '%s' "$__STAKEHOLDER_RESOLVER_CACHE"
        return 0
    fi

    local resolver_json=""
    local candidate=""

    if [[ -n "$session_dir" ]]; then
        candidate="$session_dir/meta/stakeholder-resolver.json"
        if [[ -f "$candidate" ]] && jq empty "$candidate" 2>/dev/null; then
            resolver_json=$(cat "$candidate")
        elif [[ -f "$candidate" ]]; then
            log_warn "domain-helpers: invalid session stakeholder resolver at $candidate"
        fi
    fi

    if [[ -z "$resolver_json" && -n "$mission_name" ]]; then
        candidate="$PROJECT_ROOT/config/missions/$mission_name/resolver.json"
        if [[ -f "$candidate" ]] && jq empty "$candidate" 2>/dev/null; then
            resolver_json=$(cat "$candidate")
        elif [[ -f "$candidate" ]]; then
            log_warn "domain-helpers: invalid mission stakeholder resolver at $candidate"
        fi
    fi

    if [[ -z "$resolver_json" ]]; then
        if resolver_json=$(load_config "stakeholder-resolver" 2>/dev/null); then
            :
        else
            resolver_json="{}"
        fi
    fi

    if [[ -z "$resolver_json" || "$resolver_json" == "null" ]]; then
        resolver_json="{}"
    fi

    __STAKEHOLDER_RESOLVER_CACHE="$resolver_json"
    __STAKEHOLDER_RESOLVER_SOURCE="$cache_key"
    printf '%s' "$resolver_json"
}

domain_helpers_extract_hostname() {
    _domain_helpers_extract_domain "$1"
}

__DOMAIN_HELPERS_SUFFIXES_LOADED=0
declare -a __DOMAIN_HELPERS_SUFFIXES=()
DOMAIN_HELPERS_SUFFIX_FILE="$PROJECT_ROOT/config/public-suffix.json"

_domain_helpers_load_public_suffixes() {
    if [[ "$__DOMAIN_HELPERS_SUFFIXES_LOADED" -eq 1 ]]; then
        return 0
    fi

    if [[ -f "$DOMAIN_HELPERS_SUFFIX_FILE" ]] && command -v jq >/dev/null 2>&1; then
        mapfile -t __DOMAIN_HELPERS_SUFFIXES < <(jq -r '.publicSuffixes[]?' "$DOMAIN_HELPERS_SUFFIX_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    else
        __DOMAIN_HELPERS_SUFFIXES=()
    fi

    __DOMAIN_HELPERS_SUFFIXES_LOADED=1
}

domain_helpers_extract_etld1() {
    local url="$1"
    local host
    host=$(_domain_helpers_extract_domain "$url")
    if [[ -z "$host" ]]; then
        echo ""
        return 1
    fi

    local lowered="${host,,}"

    _domain_helpers_load_public_suffixes

    if [[ "${#__DOMAIN_HELPERS_SUFFIXES[@]}" -eq 0 ]]; then
        echo "$lowered"
        return 0
    fi

    local best_suffix=""
    for suffix in "${__DOMAIN_HELPERS_SUFFIXES[@]}"; do
        [[ -z "$suffix" ]] && continue
        if [[ "$lowered" == "$suffix" ]]; then
            best_suffix="$suffix"
            break
        fi
        if [[ "$lowered" == *".${suffix}" ]]; then
            if [[ ${#suffix} -gt ${#best_suffix} ]]; then
                best_suffix="$suffix"
            fi
        fi
    done

    if [[ -z "$best_suffix" ]]; then
        echo "$lowered"
        return 0
    fi

    local remainder="${lowered%."$best_suffix"}"
    if [[ -z "$remainder" || "$remainder" == "$lowered" ]]; then
        echo "$lowered"
        return 0
    fi

    local last_label="${remainder##*.}"
    if [[ -z "$last_label" ]]; then
        echo "$lowered"
        return 0
    fi

    echo "${last_label}.${best_suffix}"
}

hash_source_id() {
    local url="${1:-}"
    if [[ -z "$url" || "$url" == "null" ]]; then
        echo ""
        return 1
    fi

    local digest
    if ! digest=$("$SCRIPT_DIR/hash-string.sh" "$url" 2>/dev/null); then
        log_warn "domain-helpers: failed to hash url for source id"
        echo ""
        return 1
    fi

    printf '%s' "${digest:0:16}"
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

    local freshness_entries
    freshness_entries=$(safe_domain_json_raw "$effective" '.freshness_requirements // []' '[]' "freshness_requirements")

    while IFS= read -r entry; do
        local topic
        topic=$(safe_domain_json "$entry" '.topic // ""' "" "freshness.topic")
        [[ -z "$topic" ]] && continue
        local keywords_json
        keywords_json=$(safe_domain_json_raw "$entry" '.topic_keywords // []' '[]' "freshness.keywords")
        while IFS= read -r keyword; do
            [[ -z "$keyword" || "$keyword" == "null" ]] && continue
            if printf '%s' "$claim_statement" | grep -qiF -- "$keyword"; then
                echo "$topic"
                return 0
            fi
        done < <(jq -r '.[]?' <<< "$keywords_json")
    done < <(jq -c '.[]' <<< "$freshness_entries")

    echo "unclassified"
}

match_watch_item() {
    local watch_item_json="$1"
    local claim_json="$2"

    local statement
    statement=$(safe_domain_json "$claim_json" '.statement // ""' "" "claim.statement")
    local canonical
    canonical=$(safe_domain_json "$watch_item_json" '.canonical // ""' "" "watch_item.canonical")

    if [[ -n "$canonical" ]] && printf '%s' "$statement" | grep -qiF -- "$canonical"; then
        return 0
    fi

    local variants_json
    variants_json=$(safe_domain_json_raw "$watch_item_json" '.variants // []' '[]' "watch_item.variants")
    while IFS= read -r variant; do
        [[ -z "$variant" || "$variant" == "null" ]] && continue
        if printf '%s' "$statement" | grep -qiF -- "$variant"; then
            return 0
        fi
    done < <(jq -r '.[]?' <<< "$variants_json")

    local sources_json
    sources_json=$(safe_domain_json_raw "$claim_json" '.sources // []' '[]' "claim.sources")
    local source_hints_json
    source_hints_json=$(safe_domain_json_raw "$watch_item_json" '.source_hints // []' '[]' "watch_item.source_hints")
    while IFS= read -r hint; do
        [[ -z "$hint" || "$hint" == "null" ]] && continue
        while IFS= read -r source; do
            [[ -z "$source" || "$source" == "null" ]] && continue
            local source_url
            source_url=$(safe_domain_json "$source" '.url // ""' "" "source.url")
            if [[ -n "$source_url" ]] && printf '%s' "$source_url" | grep -q -- "$hint"; then
                return 0
            fi
        done < <(jq -c '.[]?' <<< "$sources_json")
    done < <(jq -r '.[]?' <<< "$source_hints_json")

    return 1
}

export -f map_source_to_stakeholder
export -f infer_claim_topic
export -f match_watch_item
export -f domain_helpers_get_stakeholder_policy
export -f domain_helpers_get_stakeholder_resolver
export -f domain_helpers_extract_hostname
export -f domain_helpers_extract_etld1
export -f hash_source_id
