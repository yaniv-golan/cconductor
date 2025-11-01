#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/bash-runtime.sh"

ensure_modern_bash "$@"
resolve_cconductor_bash_runtime >/dev/null

set -euo pipefail

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/domain-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-parser.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/agent-registry.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/budget-tracker.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/event-logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Optional agent invocation helper (loaded lazily)
INVOKE_AGENT_LOADED=0
load_invoke_agent() {
    if [[ $INVOKE_AGENT_LOADED -eq 0 ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/invoke-agent.sh"
        INVOKE_AGENT_LOADED=1
    fi
}

usage() {
    cat <<'USAGE'
Usage: stakeholder-classifier.sh <session_dir>

Classifies knowledge-graph sources into mission-defined stakeholder categories.
Deterministic matching (patterns, aliases, heuristics) runs first, followed by an
optional Claude tail for unresolved items. Results persist to
session/stakeholder-classifications.jsonl.
USAGE
}

# -----------------------------------------------------------------------------
# Shared caches prepared per run
# -----------------------------------------------------------------------------
declare -gA CLASSIFIER_ALIAS_MAP=()
declare -gA CLASSIFIER_POLICY_FLAGS=()
declare -ga CLASSIFIER_PATTERNS=()
declare -ga CLASSIFIER_PATTERN_CATEGORIES=()

declare -gA CLASSIFIER_EXISTING_IDS=()
STAKEHOLDER_PASS_NEW_WRITTEN=0
STAKEHOLDER_PASS_NEEDS_REVIEW=0
STAKEHOLDER_PASS_TOTAL_SOURCES=0
STAKEHOLDER_PASS_PENDING=0
STAKEHOLDER_PASS_CLASSIFIED_TOTAL=0

policy_has_category() {
    local key="${1:-}"
    [[ -n "$key" && -n "${CLASSIFIER_POLICY_FLAGS[$key]:-}" ]]
}

policy_first_available() {
    local candidate
    for candidate in "$@"; do
        if policy_has_category "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

prepare_classification_maps() {
    local resolver_json="$1"
    local policy_json="$2"

    CLASSIFIER_ALIAS_MAP=()
    CLASSIFIER_POLICY_FLAGS=()
    CLASSIFIER_PATTERNS=()
    CLASSIFIER_PATTERN_CATEGORIES=()

    while IFS=$'\t' read -r alias category; do
        [[ -z "$alias" || -z "$category" ]] && continue
        CLASSIFIER_ALIAS_MAP["${alias,,}"]="$category"
    done < <(jq -r '.aliases | to_entries[]? | "\(.key)\t\(.value)"' <<<"$resolver_json")

    while IFS=$'\t' read -r pattern category; do
        [[ -z "$pattern" || -z "$category" ]] && continue
        CLASSIFIER_PATTERNS+=("${pattern,,}")
        CLASSIFIER_PATTERN_CATEGORIES+=("$category")
    done < <(jq -r '.patterns[]? | "\(.pattern)\t\(.category)"' <<<"$resolver_json")

    while IFS= read -r category; do
        [[ -z "$category" ]] && continue
        CLASSIFIER_POLICY_FLAGS["$category"]=1
    done < <(jq -r '.categories | keys[]?' <<<"$policy_json")
}

ensure_session_config() {
    local session_dir="$1"
    local mission_name="$2"
    local suffix="$3" # policy | resolver

    local session_file
    case "$suffix" in
        policy) session_file="$session_dir/meta/stakeholder-policy.json" ;;
        resolver) session_file="$session_dir/meta/stakeholder-resolver.json" ;;
        *) return 1 ;;
    esac

    mkdir -p "$session_dir/meta"

    if [[ -f "$session_file" ]] && jq empty "$session_file" >/dev/null 2>&1; then
        return 0
    fi

    local mission_file="$PROJECT_ROOT/config/missions/$mission_name/$suffix.json"
    if [[ -f "$mission_file" ]] && jq empty "$mission_file" >/dev/null 2>&1; then
        cp "$mission_file" "$session_file"
        return 0
    fi

    local fallback
    if [[ "$suffix" == "policy" ]]; then
        fallback=$(load_config "stakeholder-policy")
    else
        fallback=$(load_config "stakeholder-resolver")
    fi
    printf '%s' "$fallback" | jq '.' >"$session_file"
}

load_unique_sources() {
    local kg_file="${1:-}"
    local session_dir="${2:-}"

    if [[ -z "$kg_file" || ! -f "$kg_file" ]]; then
        echo '[]'
        return 0
    fi

    safe_jq_from_file \
        "$kg_file" \
        '[.claims[]? | .sources[]? | {url: (.url // ""), title: (.title // ""), statement: (.statement // "")}]
         | map(select(.url != ""))
         | unique_by(.url)' \
        '[]' \
        "$session_dir" \
        "stakeholder_classifier.load_unique_sources" \
        "true" \
        "false"
}

build_raw_tags() {
    local host="$1"
    local title="$2"
    local -n tags_ref="$3"

    declare -A seen=()
    add_tag() {
        local tag="${1,,}"
        [[ -z "$tag" ]] && return
        if [[ -z "${seen[$tag]:-}" ]]; then
            tags_ref+=("$tag")
            seen["$tag"]=1
        fi
    }

    add_tag "$host"
    IFS='.-' read -r -a host_parts <<<"$host"
    for part in "${host_parts[@]}"; do
        [[ ${#part} -lt 2 ]] && continue
        add_tag "$part"
    done

    local cleaned
    cleaned=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ')
    for word in $cleaned; do
        [[ ${#word} -lt 3 ]] && continue
        add_tag "$word"
    done
}

raw_tags_to_json() {
    # shellcheck disable=SC2178
    local -n tags_ref="$1"
    printf '%s\n' "${tags_ref[@]}" | jq -R -s 'split("\n") | map(select(. != ""))'
}

register_existing_records() {
    local classifications_file="$1"
    CLASSIFIER_EXISTING_IDS=()
    [[ -f "$classifications_file" ]] || return 0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        jq empty <<<"$line" >/dev/null 2>&1 || continue
        local source_id
        source_id=$(jq -r '.source_id // empty' <<<"$line")
        [[ -z "$source_id" ]] && continue
        CLASSIFIER_EXISTING_IDS["$source_id"]=1
    done < "$classifications_file"
}

append_classification_record() {
    local session_dir="$1"
    local classifications_file="$2"
    local record_json="$3"

    mkdir -p "$(dirname "$classifications_file")"
    local lock_dir="$session_dir/session/.locks"
    mkdir -p "$lock_dir"
    local lock_path="$lock_dir/stakeholder-classifications.lock"

    if simple_lock_acquire "$lock_path" 5; then
        printf '%s\n' "$record_json" >>"$classifications_file"
        simple_lock_release "$lock_path"
    else
        log_warn "stakeholder-classifier: lock timeout, appending without lock"
        printf '%s\n' "$record_json" >>"$classifications_file"
    fi
}

pattern_match_category() {
    local host_lower="$1"
    local i
    for i in "${!CLASSIFIER_PATTERNS[@]}"; do
        local pattern="${CLASSIFIER_PATTERNS[$i]}"
        local category="${CLASSIFIER_PATTERN_CATEGORIES[$i]}"
        [[ -z "$pattern" || -z "$category" ]] && continue
        # shellcheck disable=SC2254
        case "$host_lower" in
            $pattern)
                printf '%s\tpattern:%s' "$category" "$pattern"
                return 0
                ;;
        esac
    done
    return 1
}

alias_match_category() {
    # shellcheck disable=SC2178
    local -n tags_ref="$1"
    local tag
    for tag in "${tags_ref[@]}"; do
        local mapped="${CLASSIFIER_ALIAS_MAP[$tag]:-}"
        if [[ -n "$mapped" ]]; then
            printf '%s\talias:%s' "$mapped" "$tag"
            return 0
        fi
    done
    return 1
}

heuristic_match_category() {
    local host_lower="$1"
    # shellcheck disable=SC2178
    local -n tags_ref="$2"

    local category
    if [[ "$host_lower" == *".gov" || "$host_lower" == *.gov.* || "$host_lower" == *.gouv.* ]]; then
        if category=$(policy_first_available regulator government government_body); then
            printf '%s\theuristic:gov-domain' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *.edu || "$host_lower" == *.ac.* || "$host_lower" == *.sch.* ]]; then
        if category=$(policy_first_available academic peer_reviewed research_institute); then
            printf '%s\theuristic:academic-domain' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *.doi.org || "$host_lower" == *.ieee.org || "$host_lower" == *.acm.org ]]; then
        if category=$(policy_first_available peer_reviewed academic); then
            printf '%s\theuristic:scholarly-domain' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *investor* || "$host_lower" == ir.* || "$host_lower" == *.ir.* ]]; then
        if category=$(policy_first_available company_source company_statement company_primary vendor_primary competitor_primary); then
            printf '%s\theuristic:investor-host' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *pitchbook* || "$host_lower" == *cbinsights* || "$host_lower" == *crunchbase* ]]; then
        if category=$(policy_first_available benchmark_provider market_intelligence industry_analysis independent_research); then
            printf '%s\theuristic:market-data-host' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *gartner* || "$host_lower" == *forrester* || "$host_lower" == *idc* || "$host_lower" == *mckinsey* || "$host_lower" == *bain* || "$host_lower" == *bcg* ]]; then
        if category=$(policy_first_available industry_analysis industry_analyst independent_research); then
            printf '%s\theuristic:analyst-host' "$category"
            return 0
        fi
    fi

    if [[ "$host_lower" == *news* || "$host_lower" == *press* || "$host_lower" == *journal* ]]; then
        if category=$(policy_first_available news_report press_coverage media trade_press news_digest); then
            printf '%s\theuristic:press-host' "$category"
            return 0
        fi
    fi

    local token
    for token in "${tags_ref[@]}"; do
        case "$token" in
            whitepaper|datasheet|manual|specification)
                if category=$(policy_first_available vendor_primary industry_whitepaper company_source); then
                    printf '%s\theuristic:title:%s' "$category" "$token"
                    return 0
                fi
                ;;
            regulator|authority|commission)
                if category=$(policy_first_available regulator government government_body); then
                    printf '%s\theuristic:title:%s' "$category" "$token"
                    return 0
                fi
                ;;
            benchmark|index|dataset)
                if category=$(policy_first_available benchmark_provider independent_analysis independent_research); then
                    printf '%s\theuristic:title:%s' "$category" "$token"
                    return 0
                fi
                ;;
            journal|proceedings|conference)
                if category=$(policy_first_available peer_reviewed academic research_institute); then
                    printf '%s\theuristic:title:%s' "$category" "$token"
                    return 0
                fi
                ;;
        esac
    done

    return 1
}

create_record_json() {
    local source_id="$1"
    local url="$2"
    local title="$3"
    local tags_json="$4"
    local category="$5"
    local resolver_path="$6"
    local confidence="$7"
    local llm_attempted="$8"
    local suggestion_json="${9:-null}"

    jq -nc \
        --arg id "$source_id" \
        --arg url "$url" \
        --arg title "$title" \
        --arg category "$category" \
        --arg path "$resolver_path" \
        --arg llm "$llm_attempted" \
        --argjson tags "$tags_json" \
        --argjson conf "$confidence" \
        --argjson suggestion "$suggestion_json" \
        '{
            source_id: $id,
            url: $url,
            raw_tags: $tags,
            resolved_category: $category,
            resolver_path: $path,
            confidence: ($conf // 0),
            llm_attempted: ($llm == "true"),
            timestamp: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
            suggest_alias: $suggestion
        } | del(.suggest_alias | select(. == null))'
}

append_checkpoint() {
    local checkpoint_file="$1"
    local timestamp="$2"
    local kg_count="$3"
    local written="$4"
    local needs_review="$5"

    jq -n \
        --arg time "$timestamp" \
        --argjson count "$kg_count" \
        --argjson written "$written" \
        --argjson review "$needs_review" \
        '{
            last_run_timestamp: $time,
            kg_source_count: $count,
            classifications_written: $written,
            needs_review: $review
        }' >"$checkpoint_file"
}

llm_classify_batch() {
    local session_dir="$1"
    local policy_json="$2"
    local entries_array_file="$3"

    if ! agent_registry_exists "stakeholder-classifier"; then
        return 1
    fi

    load_invoke_agent

    local agent_file="$session_dir/.claude/agents/stakeholder-classifier.json"
    if [[ ! -f "$agent_file" ]]; then
        local metadata_file
        metadata_file=$(agent_registry_get "stakeholder-classifier") || return 1
        local agent_dir
        agent_dir=$(dirname "$metadata_file")
        local system_prompt
        system_prompt=$(cat "$agent_dir/system-prompt.md" 2>/dev/null || echo "")
        if [[ -z "$system_prompt" ]]; then
            log_warn "stakeholder-classifier: system prompt missing; cannot invoke LLM tail"
            return 1
        fi
        local agent_model
        agent_model=$(safe_jq_from_file "$metadata_file" '.model // "claude-haiku-4-5"' "claude-haiku-4-5" "$session_dir" "stakeholder_classifier.model")
        mkdir -p "$session_dir/.claude/agents"
        jq -n \
            --arg prompt "$system_prompt" \
            --arg model "$agent_model" \
            '{systemPrompt: $prompt, model: $model}' >"$agent_file"
    fi

    local payload_file output_file
    payload_file=$(mktemp)
    output_file=$(mktemp)

    local canonical_json
    if ! canonical_json=$(safe_jq_from_json "$policy_json" '.categories | keys' '[]' "$session_dir" "stakeholder_classifier.canonical_categories" "false"); then
        canonical_json='[]'
    fi
    if ! jq_validate_json "$canonical_json"; then
        log_warn "stakeholder-classifier: canonical category list invalid; using empty set"
        canonical_json='[]'
    fi

    local entries_json='[]'
    if [[ -s "$entries_array_file" ]]; then
        if entries_json=$(cat "$entries_array_file"); then
            if ! jq empty <<<"$entries_json" >/dev/null 2>&1; then
                log_warn "stakeholder-classifier: pending entry array invalid JSON; using empty set"
                entries_json='[]'
            fi
        else
            log_warn "stakeholder-classifier: failed reading pending entry array; using empty set"
            entries_json='[]'
        fi
    fi

    jq -n \
        --argjson canonical "$canonical_json" \
        --argjson entries "$entries_json" \
        '{
            canonical_categories: $canonical,
            sources: ($entries | map({url: (.url // ""), title: (.title // "")}))
        }' >"$payload_file"

    local status=0
    if invoke_agent_v2 "stakeholder-classifier" "$payload_file" "$output_file" 600 "$session_dir"; then
        :
    else
        status=$?
    fi

    local cost="0"
    if [[ $status -eq 0 ]]; then
        cost=$(extract_cost_from_output "$output_file")
    fi
    budget_record_invocation "$session_dir" "stakeholder-classifier" "$cost" 0 2>/dev/null || true

    rm -f "$payload_file"

    if [[ $status -ne 0 ]]; then
        rm -f "$output_file"
        return 1
    fi

    local extracted
    local raw_result=""
    raw_result=$(safe_jq_from_file "$output_file" '.result // ""' "" "$session_dir" "stakeholder_classifier.result" "true")
    if [[ -n "$raw_result" ]] && command -v extract_json_from_text &>/dev/null; then
        extracted=$(extract_json_from_text "$raw_result" 2>/dev/null || echo "")
    fi
    if [[ -z "${extracted:-}" ]]; then
        extracted=$(extract_json_from_result_output "$output_file")
    fi
    rm -f "$output_file"

    if [[ -z "$extracted" ]]; then
        return 2
    fi

    if ! jq empty <<<"$extracted" >/dev/null 2>&1; then
        return 2
    fi

    jq -c '.[]?' <<<"$extracted"
    return 0
}

process_pending_batch() {
    local session_dir="$1"
    local policy_json="$2"
    local classifications_file="$3"
    local -n queue_ref="$4"
    local -n map_ref="$5"
    local -n written_ref="$6"
    local -n needs_review_ref="$7"

    (( ${#queue_ref[@]} == 0 )) && return 0

    local entries_tmp entries_array
    entries_tmp=$(mktemp)
    entries_array=$(mktemp)

    local sid
    for sid in "${queue_ref[@]}"; do
        printf '%s\n' "${map_ref[$sid]}" >>"$entries_tmp"
    done
    jq -s '.' "$entries_tmp" >"$entries_array"
    rm -f "$entries_tmp"

    local -a llm_rows=()
    local llm_exit=0
    mapfile -t llm_rows < <(llm_classify_batch "$session_dir" "$policy_json" "$entries_array") || llm_exit=$?
    rm -f "$entries_array"

    declare -A resolved_map=()
    if [[ $llm_exit -eq 0 && ${#llm_rows[@]} -gt 0 ]]; then
        local row url id
        for row in "${llm_rows[@]}"; do
            url=$(jq -r '.url // empty' <<<"$row")
            [[ -z "$url" ]] && continue
            id=$(hash_source_id "$url")
            [[ -z "$id" ]] && continue
            resolved_map["$id"]="$row"
        done
    fi

    for sid in "${queue_ref[@]}"; do
        local entry_json="${map_ref[$sid]}"
        local url title host tags_json record
        url=$(jq -r '.url' <<<"$entry_json")
        title=$(jq -r '.title' <<<"$entry_json")
        host=$(jq -r '.host' <<<"$entry_json")
        tags_json=$(jq -c '.raw_tags' <<<"$entry_json")

        local result_row="${resolved_map[$sid]:-}"
        if [[ -n "$result_row" ]]; then
            local category confidence suggestion_json
            category=$(jq -r '.category // "needs_review"' <<<"$result_row")
            confidence=$(jq -r '.confidence // 0' <<<"$result_row")
            suggestion_json=$(jq -c '.suggest_alias // null' <<<"$result_row")
            record=$(create_record_json "$sid" "$url" "$title" "$tags_json" "$category" "llm" "$confidence" "true" "$suggestion_json")
            if [[ "$category" == "needs_review" ]]; then
                needs_review_ref=$((needs_review_ref + 1))
            fi
        else
            record=$(create_record_json "$sid" "$url" "$title" "$tags_json" "needs_review" "needs_review" "0" "false")
            needs_review_ref=$((needs_review_ref + 1))
        fi
        append_classification_record "$session_dir" "$classifications_file" "$record"
        CLASSIFIER_EXISTING_IDS["$sid"]=1
        written_ref=$((written_ref + 1))
        unset 'map_ref[$sid]'
    done

    queue_ref=()
}

stakeholder_classifier_single_pass() {
    local session_dir="$1"
    local mission_name="$2"

    ensure_session_config "$session_dir" "$mission_name" policy
    ensure_session_config "$session_dir" "$mission_name" resolver

    local policy_json resolver_json
    policy_json=$(domain_helpers_get_stakeholder_policy "$session_dir" "$mission_name")
    resolver_json=$(domain_helpers_get_stakeholder_resolver "$session_dir" "$mission_name")

    prepare_classification_maps "$resolver_json" "$policy_json"

    local classifications_file="$session_dir/session/stakeholder-classifications.jsonl"
    local checkpoint_file="$session_dir/session/stakeholder-classifier.checkpoint.json"
    register_existing_records "$classifications_file"

    local sources_json
    sources_json=$(load_unique_sources "$session_dir/knowledge/knowledge-graph.json" "$session_dir")
    local kg_source_count
    kg_source_count=$(jq 'length' <<<"$sources_json")

    local timestamp
    timestamp=$(get_timestamp)

    local classifications_written=0
    local needs_review=0

    local -a pending_queue=()
    # shellcheck disable=SC2034  # referenced via nameref in process_pending_batch
    declare -A pending_map=()
    local batch_limit=25

    while IFS= read -r source_json; do
        [[ -z "$source_json" || "$source_json" == "null" ]] && continue
        local url title
        url=$(jq -r '.url' <<<"$source_json")
        title=$(jq -r '.title // ""' <<<"$source_json")
        [[ -z "$url" ]] && continue

        local source_id
        source_id=$(hash_source_id "$url")
        [[ -z "$source_id" ]] && continue
        [[ -n "${CLASSIFIER_EXISTING_IDS[$source_id]:-}" ]] && continue

        local host
        host=$(domain_helpers_extract_hostname "$url")
        local host_lower="${host,,}"
        # shellcheck disable=SC2034  # populated via nameref consumers
        local -a raw_tags=()
        build_raw_tags "$host" "$title" raw_tags
        local tags_json
        tags_json=$(raw_tags_to_json raw_tags)

        local match=""
        if match=$(pattern_match_category "$host_lower"); then
            :
        elif match=$(alias_match_category raw_tags); then
            :
        elif match=$(heuristic_match_category "$host_lower" raw_tags); then
            :
        else
            local entry_json
            entry_json=$(jq -n \
                --arg id "$source_id" \
                --arg url "$url" \
                --arg title "$title" \
                --arg host "$host" \
                --argjson tags "$tags_json" \
                '{source_id: $id, url: $url, title: $title, host: $host, raw_tags: $tags}')
            pending_queue+=("$source_id")
            # shellcheck disable=SC2034  # stored for batch classification via nameref
            pending_map["$source_id"]="$entry_json"
            if (( ${#pending_queue[@]} >= batch_limit )); then
                process_pending_batch "$session_dir" "$policy_json" "$classifications_file" pending_queue pending_map classifications_written needs_review
            fi
            continue
        fi

        local category="${match%%$'\t'*}"
        local rationale="${match#*$'\t'}"
        local confidence
        case "$rationale" in
            pattern:*) confidence=0.98 ;;
            alias:*) confidence=0.92 ;;
            heuristic:*) confidence=0.75 ;;
            *) confidence=0.6 ;;
        esac
        local record
        record=$(create_record_json "$source_id" "$url" "$title" "$tags_json" "$category" "$rationale" "$confidence" "false")
        append_classification_record "$session_dir" "$classifications_file" "$record"
        CLASSIFIER_EXISTING_IDS["$source_id"]=1
        classifications_written=$((classifications_written + 1))
    done < <(jq -c '.[]?' <<<"$sources_json")

    process_pending_batch "$session_dir" "$policy_json" "$classifications_file" pending_queue pending_map classifications_written needs_review

    append_checkpoint "$checkpoint_file" "$timestamp" "$kg_source_count" "$classifications_written" "$needs_review"

    local total_classified="${#CLASSIFIER_EXISTING_IDS[@]}"
    local pending_sources=$((kg_source_count - total_classified))
    if (( pending_sources < 0 )); then
        pending_sources=0
    fi

    STAKEHOLDER_PASS_NEW_WRITTEN=$classifications_written
    STAKEHOLDER_PASS_NEEDS_REVIEW=$needs_review
    STAKEHOLDER_PASS_TOTAL_SOURCES=$kg_source_count
    STAKEHOLDER_PASS_PENDING=$pending_sources
    STAKEHOLDER_PASS_CLASSIFIED_TOTAL=$total_classified
}

stakeholder_classifier_run_loop() {
    local session_dir="$1"
    local mission_name="$2"

    local initial_sources_json
    initial_sources_json=$(load_unique_sources "$session_dir/knowledge/knowledge-graph.json" "$session_dir")
    local initial_source_count
    initial_source_count=$(jq 'length' <<<"$initial_sources_json")

    local started_at
    started_at=$(get_timestamp)
    if command -v log_event &>/dev/null; then
        log_event "$session_dir" "stakeholder_classifier_started" "$(jq -n \
            --arg mission "$mission_name" \
            --argjson sources "$initial_source_count" \
            --arg started "$started_at" \
            '{mission: $mission, total_sources: $sources, started_at: $started}')"
    fi

    local total_written=0
    local total_needs_review=0
    local total_sources="$initial_source_count"
    local pending=0
    local total_classified=0
    local pass=1

    while true; do
        stakeholder_classifier_single_pass "$session_dir" "$mission_name"
        local pass_written="$STAKEHOLDER_PASS_NEW_WRITTEN"
        local pass_needs="$STAKEHOLDER_PASS_NEEDS_REVIEW"
        total_sources="$STAKEHOLDER_PASS_TOTAL_SOURCES"
        pending="$STAKEHOLDER_PASS_PENDING"
        total_classified="$STAKEHOLDER_PASS_CLASSIFIED_TOTAL"
        total_written=$((total_written + pass_written))
        total_needs_review=$((total_needs_review + pass_needs))
        echo "Stakeholder classifier pass $pass: added $pass_written records (pending: $pending)."
        if (( pending <= 0 )) || (( pass_written == 0 )); then
            if (( pass_written == 0 )) && (( pending > 0 )); then
                log_warn "stakeholder-classifier: unable to classify $pending sources automatically; manual review required."
            fi
            break
        fi
        pass=$((pass + 1))
    done

    local completed_at
    completed_at=$(get_timestamp)
    if command -v log_event &>/dev/null; then
        log_event "$session_dir" "stakeholder_classifier_completed" "$(jq -n \
            --arg mission "$mission_name" \
            --argjson sources "$total_sources" \
            --argjson total_classifications "$total_classified" \
            --argjson new_classifications "$total_written" \
            --argjson needs "$total_needs_review" \
            --arg started "$started_at" \
            --arg completed "$completed_at" \
            --argjson pending "$pending" \
            '{mission: $mission, total_sources: $sources, total_classifications: $total_classifications, new_classifications: $new_classifications, needs_review: $needs, started_at: $started, completed_at: $completed, pending_sources: $pending}')"
    fi

    echo "Stakeholder classifier complete: total classifications $total_classified, pending $pending."
}

classify_stakeholders() {
    local session_dir="${1:-}"
    if [[ -z "$session_dir" ]]; then
        usage >&2
        return 1
    fi

    if [[ ! -d "$session_dir" ]]; then
        log_error "stakeholder-classifier: session directory not found: $session_dir"
        return 1
    fi

    if declare -f agent_registry_init >/dev/null 2>&1; then
        agent_registry_init
    fi

    local session_meta="$session_dir/meta/session.json"
    local mission_name
    mission_name=$(safe_jq_from_file "$session_meta" '.mission_name // ""' "" "$session_dir" "stakeholder_classifier.mission" "true" || echo "")
    [[ -z "$mission_name" ]] && mission_name="general-research"

    local lock_file="$session_dir/session/.locks/stakeholder-classifier.lock"
    mkdir -p "$(dirname "$lock_file")"

    if declare -F with_lock >/dev/null 2>&1; then
        with_lock "$lock_file" stakeholder_classifier_run_loop "$session_dir" "$mission_name"
    else
        stakeholder_classifier_run_loop "$session_dir" "$mission_name"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    classify_stakeholders "$@"
fi
