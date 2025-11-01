#!/usr/bin/env bash
# Mission State Builder - Constructs mission state summary for orchestrator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/budget-tracker.sh" 2>/dev/null || true

BASH_RUNTIME="${CCONDUCTOR_BASH_RUNTIME:-$(command -v bash)}"

to_session_relative() {
    local path="$1"
    local session_dir="$2"
    if [[ -z "$path" || "$path" == "null" ]]; then
        echo ""
        return 0
    fi
    if [[ "$path" != /* ]]; then
        echo "$path"
        return 0
    fi
    local normalized_session="${session_dir%/}"
    if [[ "$path" == "$normalized_session" ]]; then
        echo "."
        return 0
    fi
    if [[ "$path" == "$normalized_session/"* ]]; then
        local rel="${path#"$normalized_session/"}"
        printf '%s\n' "${rel:-.}"
        return 0
    fi
    echo "$path"
}

stat_mtime() {
    local path="$1"
    if [[ ! -e "$path" ]]; then
        echo ""
        return 0
    fi
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        stat -f '%m' "$path" 2>/dev/null || echo ""
    elif stat -c '%Y' "$path" >/dev/null 2>&1; then
        stat -c '%Y' "$path" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

epoch_to_iso8601() {
    local epoch="$1"
    if [[ -z "$epoch" || "$epoch" == "0" || "$epoch" == "null" ]]; then
        echo ""
        return 0
    fi
    if date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    elif date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
        date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    else
        echo ""
    fi
}

build_mission_state() {
    local session_dir="$1"

    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        log_system_error "${session_dir:-unknown}" "build_mission_state" "Invalid session directory"
        return 1
    fi

    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    local heuristics_file="$meta_dir/domain-heuristics.json"

    local claims_count="0"
    local entities_count="0"
    local sources_count="0"
    local kg_iteration="0"
    local kg_confidence_overall=""
    local kg_confidence_by_category="{}"
    if [[ -f "$kg_file" ]]; then
        claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' '0' "$session_dir" "mission_state.claims")
        entities_count=$(safe_jq_from_file "$kg_file" '.entities | length' '0' "$session_dir" "mission_state.entities")
        sources_count=$(safe_jq_from_file "$kg_file" '[.claims[]? | .sources[]?] | unique_by(.url) | length' '0' "$session_dir" "mission_state.sources" "false")
        kg_iteration=$(safe_jq_from_file "$kg_file" '.iteration // 0' '0' "$session_dir" "mission_state.kg_iteration")
        kg_confidence_overall=$(safe_jq_from_file "$kg_file" '.confidence_scores.overall // ""' "" "$session_dir" "mission_state.confidence_overall")
        kg_confidence_by_category=$(safe_jq_from_file "$kg_file" '.confidence_scores.by_category // {}' '{}' "$session_dir" "mission_state.confidence_by_category" "false")
    fi
    local sources_total_numeric="${sources_count:-0}"
    sources_total_numeric=$((sources_total_numeric + 0))
    local kg_mtime_local
    kg_mtime_local=$(stat_mtime "$kg_file")

    local waivers_file="$meta_dir/watch-topic-waivers.json"
    declare -A watch_topic_waivers=()
    if [[ -f "$waivers_file" ]]; then
        while IFS= read -r waiver_id; do
            [[ -z "$waiver_id" || "$waiver_id" == "null" ]] && continue
            watch_topic_waivers["$waiver_id"]=1
        done < <(jq -r '.[]?' "$waivers_file" 2>/dev/null || printf '')
    fi

    local kg_claims_json="[]"
    local -a kg_claim_entries=()
    if [[ -f "$kg_file" ]]; then
        kg_claims_json=$(safe_jq_from_file "$kg_file" '
            (.claims // []) | map({
                id: (.id // ""),
                statement: (.statement // "")
            })
        ' '[]' "$session_dir" "mission_state.claims_payload" false)
        if [[ -n "$kg_claims_json" && "$kg_claims_json" != "[]" ]]; then
            while IFS= read -r claim_entry; do
                [[ -z "$claim_entry" || "$claim_entry" == "null" ]] && continue
                kg_claim_entries+=("$claim_entry")
            done < <(jq -c '.[]' <<< "$kg_claims_json")
        fi
    fi

    local watch_status_json="[]"
    if [[ -f "$heuristics_file" ]]; then
        local watch_topics_source
        watch_topics_source=$(safe_jq_from_file "$heuristics_file" '.watch_topics // []' '[]' "$session_dir" "mission_state.watch_topics" false)

        if [[ -n "$watch_topics_source" && "$watch_topics_source" != "[]" ]]; then
            local -a watch_status_entries=()

            while IFS= read -r topic_json; do
                [[ -z "$topic_json" || "$topic_json" == "null" ]] && continue

                local topic_importance
                topic_importance=$(safe_jq_from_json "$topic_json" '.importance // ""' "" "$session_dir" "mission_state.watch_topic.importance")
                if [[ "${topic_importance,,}" != "critical" ]]; then
                    continue
                fi

                local topic_id
                topic_id=$(safe_jq_from_json "$topic_json" '.id // ""' "" "$session_dir" "mission_state.watch_topic.id")
                local canonical
                canonical=$(safe_jq_from_json "$topic_json" '.canonical // ""' "" "$session_dir" "mission_state.watch_topic.canonical")
                local variants_json
                variants_json=$(safe_jq_from_json "$topic_json" '.variants // []' '[]' "$session_dir" "mission_state.watch_topic.variants" false)

                local -a variant_terms=()
                if [[ -n "$canonical" ]]; then
                    variant_terms+=("${canonical,,}")
                fi
                if [[ -n "$variants_json" && "$variants_json" != "[]" ]]; then
                    while IFS= read -r variant_term; do
                        [[ -z "$variant_term" || "$variant_term" == "null" ]] && continue
                        variant_terms+=("${variant_term,,}")
                    done < <(jq -r '.[]?' <<< "$variants_json")
                fi

                local status="pending"
                local -a matched_claim_ids=()
                if [[ -n "$topic_id" && -n "${watch_topic_waivers["$topic_id"]:-}" ]]; then
                    status="waived"
                else
                    for claim_entry in "${kg_claim_entries[@]}"; do
                        local claim_statement
                        claim_statement=$(safe_jq_from_json "$claim_entry" '.statement // ""' "" "$session_dir" "mission_state.watch_topic.claim_statement")
                        [[ -z "$claim_statement" ]] && continue
                        local claim_statement_lc="${claim_statement,,}"
                        for variant_term in "${variant_terms[@]}"; do
                            [[ -z "$variant_term" ]] && continue
                            if [[ "$claim_statement_lc" == *"$variant_term"* ]]; then
                                status="covered"
                                local claim_id
                                claim_id=$(safe_jq_from_json "$claim_entry" '.id // ""' "" "$session_dir" "mission_state.watch_topic.claim_id")
                                if [[ -n "$claim_id" ]]; then
                                    matched_claim_ids+=("$claim_id")
                                fi
                                break 2
                            fi
                        done
                    done
                fi

                local matches_json="[]"
                if (( ${#matched_claim_ids[@]} > 0 )); then
                    matches_json=$(printf '%s\n' "${matched_claim_ids[@]}" | jq -R 'select(length>0)' | jq -s '.')
                fi

                local entry
                entry=$(jq -n \
                    --arg id "$topic_id" \
                    --arg canonical "$canonical" \
                    --arg importance "$topic_importance" \
                    --arg status "$status" \
                    --argjson matches "$matches_json" \
                    '{
                        id: $id,
                        canonical: $canonical,
                        importance: $importance,
                        status: $status,
                        matched_claim_ids: (if $matches == null then [] else $matches end)
                    }')
                watch_status_entries+=("$entry")
            done < <(jq -c '.[]' <<< "$watch_topics_source")

            if (( ${#watch_status_entries[@]} > 0 )); then
                watch_status_json=$(printf '%s\n' "${watch_status_entries[@]}" | jq -s '.')
            fi
        fi
    fi

    local classifier_file="$session_dir/session/stakeholder-classifications.jsonl"
    local classifier_path_rel=""
    local classifier_mtime=""
    local classifier_exists=0
    if [[ -f "$classifier_file" ]]; then
        classifier_exists=1
        classifier_path_rel="${classifier_file#"$session_dir/"}"
        if [[ "$classifier_path_rel" == "$classifier_file" ]]; then
            classifier_path_rel="$classifier_file"
        fi
        classifier_mtime=$(stat_mtime "$classifier_file")
    fi
    local classifier_updated_iso=""
    local classifier_total="0"
    local classifier_pending="$sources_total_numeric"
    local classifier_status="stale"
    if (( classifier_exists )); then
        classifier_total=$(jq -s 'map(select(.source_id != null)) | length' "$classifier_file" 2>/dev/null || echo "0")
        classifier_total=$((classifier_total + 0))
        classifier_pending=$((sources_total_numeric - classifier_total))
        if (( classifier_pending < 0 )); then
            classifier_pending=0
        fi
        if (( classifier_pending == 0 )) && [[ -z "$kg_mtime_local" || -z "$classifier_mtime" || "$classifier_mtime" -ge "$kg_mtime_local" ]]; then
            classifier_status="fresh"
        fi
        classifier_updated_iso=$(epoch_to_iso8601 "$classifier_mtime")
    fi

    local spent_usd="0"
    local spent_invocations="0"
    local elapsed_minutes="0"
    local budget_limit="0"
    local time_limit="9999"
    local invocation_limit="9999"
    if command -v budget_status >/dev/null 2>&1; then
        local budget_state
        budget_state=$(budget_status "$session_dir" 2>/dev/null || echo '{}')
        spent_usd=$(safe_jq_from_json "$budget_state" '.spent.cost_usd // 0' '0' "$session_dir" "mission_state.spent_usd")
        spent_invocations=$(safe_jq_from_json "$budget_state" '.spent.agent_invocations // 0' '0' "$session_dir" "mission_state.spent_invocations")
        elapsed_minutes=$(safe_jq_from_json "$budget_state" '.spent.elapsed_minutes // 0' '0' "$session_dir" "mission_state.elapsed_minutes")
        budget_limit=$(safe_jq_from_json "$budget_state" '.limits.budget_usd // 0' '0' "$session_dir" "mission_state.budget_limit")
        time_limit=$(safe_jq_from_json "$budget_state" '.limits.max_time_minutes // 9999' '9999' "$session_dir" "mission_state.max_time_minutes")
        invocation_limit=$(safe_jq_from_json "$budget_state" '.limits.max_agent_invocations // 9999' '9999' "$session_dir" "mission_state.max_invocations")
    else
        local budget_file="$meta_dir/budget.json"
        if [[ -f "$budget_file" ]]; then
            spent_usd=$(json_get_field "$budget_file" '.spent.cost_usd' '0')
            spent_invocations=$(json_get_field "$budget_file" '.spent.agent_invocations' '0')
            elapsed_minutes=$(json_get_field "$budget_file" '.spent.elapsed_minutes' '0')
            budget_limit=$(json_get_field "$budget_file" '.limits.budget_usd' '0')
            time_limit=$(json_get_field "$budget_file" '.limits.max_time_minutes' '9999')
            invocation_limit=$(json_get_field "$budget_file" '.limits.max_agent_invocations' '9999')
        fi
    fi

    local qg_summary="$session_dir/artifacts/quality-gate-summary.json"
    local qg_status="not_run"
    if [[ -f "$qg_summary" ]]; then
        qg_status=$(json_get_field "$qg_summary" '.status' 'unknown')
    fi

    local compliance_json='{}'
    if [[ -f "$heuristics_file" && -f "$SCRIPT_DIR/domain-compliance-check.sh" ]]; then
        compliance_json=$("$BASH_RUNTIME" "$SCRIPT_DIR/domain-compliance-check.sh" "$session_dir" 2>/dev/null || echo '{}')
    fi

    local orch_log="$session_dir/logs/orchestration.jsonl"
    local recent_decisions='[]'
    if [[ -f "$orch_log" ]]; then
        local decision_tail
        decision_tail=$(tail -5 "$orch_log" 2>/dev/null || true)
        if [ -n "$decision_tail" ]; then
            if recent_decisions=$(printf '%s\n' "$decision_tail" | jq -s '.' 2>/dev/null); then
                :
            else
                recent_decisions='[]'
            fi
        else
            recent_decisions='[]'
        fi
    fi

    local tmp_file="$meta_dir/mission_state.json.tmp"
    local kg_path_rel
    kg_path_rel=$(to_session_relative "$kg_file" "$session_dir")
    local log_path_rel
    log_path_rel=$(to_session_relative "$orch_log" "$session_dir")
    jq -n \
        --argjson claims "$claims_count" \
        --argjson entities "$entities_count" \
        --argjson sources "$sources_count" \
        --arg spent "$spent_usd" \
        --argjson spent_inv "$spent_invocations" \
        --arg elapsed_min "$elapsed_minutes" \
        --arg budget_limit "$budget_limit" \
        --arg time_limit "$time_limit" \
        --arg invocation_limit "$invocation_limit" \
        --arg qg "$qg_status" \
        --argjson compliance "$compliance_json" \
        --argjson decisions "$recent_decisions" \
        --arg iteration_value "$kg_iteration" \
        --arg confidence_overall "$kg_confidence_overall" \
        --argjson confidence_by_category "$kg_confidence_by_category" \
        --argjson watch_topics "$watch_status_json" \
        --arg classifier_path "${classifier_path_rel:-}" \
        --arg classifier_status "${classifier_status:-stale}" \
        --arg classifier_updated_iso "${classifier_updated_iso:-}" \
        --arg classifier_updated_epoch "${classifier_mtime:-}" \
        --argjson classifier_total "${classifier_total:-0}" \
        --argjson classifier_pending "${classifier_pending:-0}" \
        --arg kg_path "$kg_path_rel" \
        --arg kg_path_abs "$kg_file" \
        --arg log_path "$log_path_rel" \
        --arg log_path_abs "$orch_log" \
        '{
            coverage: {
                claims: ($claims | tonumber),
                entities: ($entities | tonumber),
                sources: ($sources | tonumber)
            },
            budget_summary: {
                spent_usd: ($spent | tonumber),
                spent_invocations: ($spent_inv | tonumber),
                elapsed_minutes: ($elapsed_min | tonumber),
                budget_usd: ($budget_limit | tonumber),
                max_time_minutes: ($time_limit | tonumber),
                max_agent_invocations: ($invocation_limit | tonumber)
            },
            quality_gate_status: $qg,
            domain_compliance: $compliance,
            last_5_decisions: $decisions,
            knowledge_progress: {
                iteration: ($iteration_value | tonumber? // 0),
                confidence: {
                    overall: (if ($confidence_overall | length) == 0 then null else ($confidence_overall | tonumber? // null) end),
                    by_category: $confidence_by_category
                }
            },
            stakeholder_classifier: {
                status: $classifier_status,
                classifications_file: (if $classifier_path == "" then null else $classifier_path end),
                total_classifications: $classifier_total,
                pending_sources: $classifier_pending,
                updated_at: (if $classifier_updated_iso == "" then null else $classifier_updated_iso end),
                updated_epoch: (if $classifier_updated_epoch == "" then null else ($classifier_updated_epoch | tonumber) end)
            },
            critical_watch_topics: $watch_topics,
            kg_path: $kg_path,
            kg_path_absolute: (if $kg_path_abs == "" then null else $kg_path_abs end),
            full_log_path: $log_path,
            full_log_path_absolute: (if $log_path_abs == "" then null else $log_path_abs end)
        }' >"$tmp_file"

    mv "$tmp_file" "$meta_dir/mission_state.json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    build_mission_state "$1"
fi
