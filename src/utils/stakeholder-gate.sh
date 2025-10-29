#!/usr/bin/env bash
if [[ -z ${BASH_VERSINFO:-} || ${BASH_VERSINFO[0]} -lt 4 ]]; then
    if [[ -n ${CCONDUCTOR_BASH_RUNTIME:-} && -x ${CCONDUCTOR_BASH_RUNTIME} ]]; then
        exec "${CCONDUCTOR_BASH_RUNTIME}" "$0" "$@"
    elif command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    else
        echo "$(basename "$0") requires bash >= 4" >&2
        exit 1
    fi
fi


set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/domain-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null || true

usage() {
    cat <<'USAGE'
Usage: stakeholder-gate.sh <session_dir>

Evaluates stakeholder classification coverage for the given session directory
and emits machine-readable and human-readable reports under session/.
USAGE
}

append_check() {
    local name="$1"
    local check_status="$2"
    local detail="$3"
    # shellcheck disable=SC2178
    local -n checks_ref="$4"
    local ref_name="$5"
    # shellcheck disable=SC2178
    local -n overall_ref="$ref_name"

    checks_ref+=("$(jq -n --arg name "$name" --arg status "$check_status" --arg detail "$detail" '{name: $name, status: $status, detail: $detail}')")
    if [[ "$check_status" == "failed" ]]; then
        # shellcheck disable=SC2034  # overall_ref is a nameref updated for caller state
        overall_ref="failed"
    fi
}

classify_records() {
    local classifications_file="$1"
    # shellcheck disable=SC2178
    local -n category_counts_ref="$2"
    # shellcheck disable=SC2178
    local -n uncategorized_ref="$3"
    # shellcheck disable=SC2178
    local -n suggestion_counts_ref="$4"
    # shellcheck disable=SC2178
    local -n suggestion_samples_ref="$5"

    category_counts_ref=()
    uncategorized_ref=0
    suggestion_counts_ref=()
    suggestion_samples_ref=()

    [[ -f "$classifications_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        jq empty <<<"$line" >/dev/null 2>&1 || continue

        local category
        category=$(jq -r '.resolved_category // ""' <<<"$line")
        local url
        url=$(jq -r '.url // ""' <<<"$line")

        if [[ -z "$category" || "$category" == "null" ]]; then
            category="needs_review"
        fi

        if [[ "$category" == "needs_review" || "$category" == "uncategorized" ]]; then
            uncategorized_ref=$((uncategorized_ref + 1))
        fi

        local key="$category"
        local current=${category_counts_ref[$key]:-0}
        # shellcheck disable=SC2004
        category_counts_ref[$key]=$((current + 1))

        local suggestion
        suggestion=$(jq -c '.suggest_alias // null' <<<"$line")
        if [[ -n "$suggestion" && "$suggestion" != "null" ]]; then
            local alias_name alias_category
            alias_name=$(jq -r '.alias // empty' <<<"$suggestion")
            alias_category=$(jq -r '.category // empty' <<<"$suggestion")
            if [[ -n "$alias_name" && -n "$alias_category" ]]; then
                local suggestion_key="${alias_name}|${alias_category}"
                local s_count=${suggestion_counts_ref[$suggestion_key]:-0}
                # shellcheck disable=SC2004
                suggestion_counts_ref[$suggestion_key]=$((s_count + 1))
                if [[ -z "${suggestion_samples_ref[$suggestion_key]:-}" ]]; then
                    # shellcheck disable=SC2004
                    suggestion_samples_ref[$suggestion_key]="$url"
                fi
            fi
        fi
    done < "$classifications_file"
}

build_category_json() {
    # shellcheck disable=SC2178
    local -n counts_ref="$1"
    local json='{}'
    local key
    for key in "${!counts_ref[@]}"; do
        json=$(jq --arg cat "$key" --argjson count "${counts_ref[$key]}" '. + {($cat): $count}' <<<"$json")
    done
    printf '%s' "$json"
}

build_checks_json() {
    # shellcheck disable=SC2178
    local -n checks_ref="$1"
    if [[ ${#checks_ref[@]} -eq 0 ]]; then
        printf '[]'
        return
    fi
    printf '%s\n' "${checks_ref[@]}" | jq -s '.'
}

build_suggestions_json() {
    # shellcheck disable=SC2178
    local -n counts_ref="$1"
    # shellcheck disable=SC2178
    local -n samples_ref="$2"
    if [[ ${#counts_ref[@]} -eq 0 ]]; then
        printf '[]'
        return
    fi

    local entries_tmp
    entries_tmp=$(mktemp)
    local key alias category
    for key in "${!counts_ref[@]}"; do
        alias="${key%%|*}"
        category="${key##*|}"
        jq -n \
            --arg alias "$alias" \
            --arg category "$category" \
            --argjson occurrences "${counts_ref[$key]}" \
            --arg sample "${samples_ref[$key]:-}" \
            '{alias: $alias, category: $category, occurrences: $occurrences, sample_url: $sample}' >>"$entries_tmp"
    done
    jq -s '.' "$entries_tmp"
    rm -f "$entries_tmp"
}

write_markdown_report() {
    local report_file="$1"
    local status="$2"
    local total_sources="$3"
    local categorized_sources="$4"
    local uncategorized_sources="$5"
    local uncategorized_pct="$6"
    # shellcheck disable=SC2178
    local -n category_counts_ref="$7"
    # shellcheck disable=SC2178
    local -n critical_requirements_ref="$8"
    # shellcheck disable=SC2178
    local -n suggestion_counts_ref="$9"
    # shellcheck disable=SC2178
    local -n suggestion_samples_ref="${10}"

    {
        printf '# Stakeholder Coverage Report\n\n'
        printf '* Status: **%s**\n' "$status"
        printf '* Total sources: %d\n' "$total_sources"
        printf '* Categorized sources: %d\n' "$categorized_sources"
        printf '* Uncategorized (needs review): %d (%.1f%%)\n\n' "$uncategorized_sources" "$uncategorized_pct"

        printf '## Category Breakdown\n\n'
        printf '| Category | Count |\n'
        printf '| --- | ---: |\n'
        local category
        for category in "${!category_counts_ref[@]}"; do
            printf '| %s | %d |\n' "$category" "${category_counts_ref[$category]}"
        done
        printf '\n'

        printf '## Critical Coverage\n\n'
        local requirement
        for requirement in "${critical_requirements_ref[@]}"; do
            printf -- '- %s\n' "$requirement"
        done
        printf '\n'

        if [[ ${#suggestion_counts_ref[@]} -gt 0 ]]; then
            printf '## Alias Suggestions\n\n'
            local key alias category occurrences sample
            for key in "${!suggestion_counts_ref[@]}"; do
                alias="${key%%|*}"
                category="${key##*|}"
                occurrences="${suggestion_counts_ref[$key]}"
                sample="${suggestion_samples_ref[$key]:-}"
                printf -- "- \`%s\` → \`%s\` (seen %d×%s)\n" "$alias" "$category" "$occurrences" "${sample:+, sample: $sample}"
            done
            printf '\n'
        fi
    } >"$report_file"
}

stakeholder_gate_main() {
    local session_dir="${1:-}"
    if [[ -z "$session_dir" ]]; then
        usage >&2
        return 1
    fi

    if [[ ! -d "$session_dir" ]]; then
        log_error "stakeholder-gate: session directory not found: $session_dir"
        return 1
    fi

    local session_meta="$session_dir/meta/session.json"
    local mission_name
    mission_name=$(safe_jq_from_file "$session_meta" '.mission_name // ""' "" "$session_dir" "stakeholder_gate.mission" "true" || echo "")
    [[ -z "$mission_name" ]] && mission_name="general-research"

    local policy_json
    policy_json=$(domain_helpers_get_stakeholder_policy "$session_dir" "$mission_name")

    local classifications_file="$session_dir/session/stakeholder-classifications.jsonl"
    declare -A category_counts
    # shellcheck disable=SC2034
    declare -A suggestion_counts
    # shellcheck disable=SC2034
    declare -A suggestion_samples
    local uncategorized=0
    classify_records "$classifications_file" category_counts uncategorized suggestion_counts suggestion_samples

    local total_sources=0
    local key
    for key in "${!category_counts[@]}"; do
        total_sources=$((total_sources + category_counts[$key]))
    done
    local categorized_sources=$((total_sources - uncategorized))
    local uncategorized_pct=0
    if (( total_sources > 0 )); then
        uncategorized_pct=$(awk -v a="$uncategorized" -v b="$total_sources" 'BEGIN { printf "%.1f", (b == 0 ? 0 : (a / b) * 100) }')
    fi

    local min_per_critical
    min_per_critical=$(jq -r '.gate.min_sources_per_critical // 1' <<<"$policy_json")
    local min_total_sources
    min_total_sources=$(jq -r '.gate.min_total_sources // 0' <<<"$policy_json")
    local max_uncategorized_pct
    max_uncategorized_pct=$(jq -r '.gate.uncategorized_max_pct // 1' <<<"$policy_json")

    local -a critical_categories=()
    mapfile -t critical_categories < <(jq -r '.categories | to_entries[]? | select(.value.importance == "critical") | .key' <<<"$policy_json")

    local status="passed"
    # shellcheck disable=SC2034
    local -a check_results=()
    local -a critical_requirements=()

    if (( total_sources < min_total_sources )); then
        append_check "Total sources" "failed" "Collected $total_sources sources (requires at least $min_total_sources)." check_results status
    else
        append_check "Total sources" "passed" "Collected $total_sources sources." check_results status
    fi

    local critical_category
    for critical_category in "${critical_categories[@]}"; do
        local count=${category_counts[$critical_category]:-0}
        if (( count < min_per_critical )); then
            append_check "Critical: $critical_category" "failed" "Only $count sources (requires $min_per_critical)." check_results status
            critical_requirements+=("❌ $critical_category — $count / $min_per_critical")
        else
            append_check "Critical: $critical_category" "passed" "$count sources (threshold $min_per_critical)." check_results status
            critical_requirements+=("✅ $critical_category — $count / $min_per_critical")
        fi
    done

    local unc_fail_detail
    if (( total_sources == 0 )); then
        unc_fail_detail="No sources classified"
    else
        unc_fail_detail=$(printf '%.1f%% of sources remain uncategorized (allowed %.1f%%).' "$uncategorized_pct" "$max_uncategorized_pct")
    fi

    if (( total_sources == 0 )) || awk -v pct="$uncategorized_pct" -v max="$max_uncategorized_pct" 'BEGIN { exit !(pct > max) }'; then
        append_check "Uncategorized share" "failed" "$unc_fail_detail" check_results status
    else
        append_check "Uncategorized share" "passed" "$unc_fail_detail" check_results status
    fi

    local categories_json
    categories_json=$(build_category_json category_counts)
    local checks_json
    checks_json=$(build_checks_json check_results)
    local suggestions_json
    suggestions_json=$(build_suggestions_json suggestion_counts suggestion_samples)

    local totals_json
    totals_json=$(jq -n \
        --argjson total "$total_sources" \
        --argjson categorized "$categorized_sources" \
        --argjson unc "$uncategorized" \
        --argjson pct "$uncategorized_pct" \
        '{total_sources: $total, categorized_sources: $categorized, uncategorized_sources: $unc, uncategorized_pct: $pct}')

    local summary_json
    summary_json=$(jq -n \
        --arg status "$status" \
        --arg mission "$mission_name" \
        --arg time "$(get_timestamp)" \
        --arg policy_version "$(jq -r '.version // "unknown"' <<<"$policy_json")" \
        --argjson totals "$totals_json" \
        --argjson categories "$categories_json" \
        --argjson checks "$checks_json" \
        --argjson suggestions "$suggestions_json" \
        '{status: $status, mission: $mission, run_timestamp: $time, policy_version: $policy_version, totals: $totals, category_counts: $categories, checks: $checks, alias_suggestions: $suggestions}')

    local report_dir="$session_dir/session"
    mkdir -p "$report_dir"
    local json_report="$report_dir/stakeholder-gate.json"
    local md_report="$report_dir/stakeholder-gate-report.md"

    printf '%s' "$summary_json" | jq '.' >"$json_report"

    write_markdown_report "$md_report" "$status" "$total_sources" "$categorized_sources" "$uncategorized" "$uncategorized_pct" category_counts critical_requirements suggestion_counts suggestion_samples

    if [[ -z ${CCONDUCTOR_DISABLE_EVENT_LOG:-} ]] && command -v log_event &>/dev/null; then
        log_event "$session_dir" "stakeholder_gate" "$summary_json"
    fi

    [[ "$status" == "passed" ]]
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    stakeholder_gate_main "$@"
fi
