#!/usr/bin/env bash
# Session Manifest Builder - Aggregates session metadata for orchestrator context

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

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

append_json_entry() {
    local array_json="$1"
    local entry_json="$2"
    jq -n --argjson base "$array_json" --argjson item "$entry_json" '
        ($base // []) + [$item]
    '
}

collect_artifact_entry() {
    local session_dir="$1"
    local path="$2"
    local kind="$3"
    if [[ ! -f "$path" ]]; then
        echo ""
        return 0
    fi
    local rel_path
    rel_path=$(to_session_relative "$path" "$session_dir")
    local mtime
    mtime=$(stat_mtime "$path")
    local iso
    iso=$(epoch_to_iso8601 "$mtime")
    jq -n \
        --arg kind "$kind" \
        --arg path "$rel_path" \
        --arg iso "${iso:-}" \
        --arg mtime "${mtime:-}" \
        '{
            kind: $kind,
            path: $path,
        updated_at: (if $iso == "" then null else $iso end),
        updated_epoch: (if $mtime == "" then null else ($mtime | tonumber) end)
        }'
}

collect_recent_agent_outputs() {
    local session_dir="$1"
    local limit="${2:-5}"
    local -a records=()
    if [[ -d "$session_dir/work" ]]; then
        while IFS= read -r agent_output; do
            [[ -z "$agent_output" ]] && continue
            local mtime
            mtime=$(stat_mtime "$agent_output")
            records+=("${mtime:-0}::${agent_output}")
        done < <(find "$session_dir/work" -mindepth 2 -maxdepth 2 -name 'output.json' -type f -print 2>/dev/null)
    fi
    if [[ "${#records[@]}" -eq 0 ]]; then
        echo "[]"
        return 0
    fi
    local sorted_entries
    sorted_entries=$(printf '%s\n' "${records[@]}" | sort -r)
    local count=0
    local result="[]"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        [[ $count -ge $limit ]] && break
        local mtime="${entry%%::*}"
        local path="${entry#*::}"
        local agent_dir
        agent_dir=$(dirname "$path")
        local agent_name
        agent_name=$(basename "$agent_dir")
        local rel_path
        rel_path=$(to_session_relative "$path" "$session_dir")
        local artifact_path=""
        if [[ -f "$session_dir/artifacts/$agent_name/output.md" ]]; then
            artifact_path="$session_dir/artifacts/$agent_name/output.md"
        elif [[ -f "$session_dir/artifacts/${agent_name}-output.md" ]]; then
            artifact_path="$session_dir/artifacts/${agent_name}-output.md"
        fi
        local rel_artifact=""
        [[ -n "$artifact_path" ]] && rel_artifact=$(to_session_relative "$artifact_path" "$session_dir")
        local iso
        iso=$(epoch_to_iso8601 "$mtime")
        local entry_json
        entry_json=$(jq -n \
            --arg agent "$agent_name" \
            --arg work_path "$rel_path" \
            --arg artifact_path "$rel_artifact" \
            --arg iso "${iso:-}" \
            --arg epoch "${mtime:-}" \
            '{
                agent: $agent,
                work_output: $work_path,
                artifact_output: (if $artifact_path == "" then null else $artifact_path end),
                updated_at: (if $iso == "" then null else $iso end),
                updated_epoch: (if $epoch == "" then null else ($epoch | tonumber) end)
            }')
        result=$(append_json_entry "$result" "$entry_json")
        count=$((count + 1))
    done <<< "$sorted_entries"
    printf '%s\n' "$result"
}

build_session_manifest() {
    local session_dir="$1"
    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        log_error "Invalid session directory for manifest: ${session_dir:-<empty>}"
        return 1
    fi

    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"

    local session_file="$meta_dir/session.json"
    local mission_id
    mission_id=$(basename "$session_dir")

    local objective
    objective=$(safe_jq_from_file "$session_file" '.objective // .mission_objective // ""' "" "$session_dir" "session_manifest.objective")
    local status
    status=$(safe_jq_from_file "$session_file" '.status // ""' "" "$session_dir" "session_manifest.status")
    local created_at
    created_at=$(safe_jq_from_file "$session_file" '.created_at // .started_at // ""' "" "$session_dir" "session_manifest.created_at")
    local updated_at
    updated_at=$(safe_jq_from_file "$session_file" '.completed_at // .updated_at // ""' "" "$session_dir" "session_manifest.updated_at")

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    local kg_path_rel
    kg_path_rel=$(to_session_relative "$kg_file" "$session_dir")
    local claims_count="0"
    local entities_count="0"
    local sources_count="0"
    local kg_high_priority_gaps="[]"
    if [[ -f "$kg_file" ]]; then
        claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' '0' "$session_dir" "session_manifest.kg_claims")
        entities_count=$(safe_jq_from_file "$kg_file" '.entities | length' '0' "$session_dir" "session_manifest.kg_entities")
        sources_count=$(safe_jq_from_file "$kg_file" '[.claims[]? | .sources[]?] | unique_by(.url) | length' '0' "$session_dir" "session_manifest.kg_sources" "false")
        kg_high_priority_gaps=$(safe_jq_from_file "$kg_file" '
            (.gaps // [])
            | map(select((.status // "unresolved") != "resolved"))
            | sort_by(-(.priority // 0))
            | .[:5]
            | map({
                description: .description,
                priority: (.priority // 0),
                status: (.status // "unresolved"),
                focus: (.focus // null)
            })
        ' '[]' "$session_dir" "session_manifest.kg_high_priority_gaps" "false")
    fi
    local sources_total_numeric="${sources_count:-0}"
    sources_total_numeric=$((sources_total_numeric + 0))
    local kg_mtime
    kg_mtime=$(stat_mtime "$kg_file")
    local kg_updated_iso
    kg_updated_iso=$(epoch_to_iso8601 "$kg_mtime")

    local classifier_file="$session_dir/session/stakeholder-classifications.jsonl"
    local classifier_path_rel
    classifier_path_rel=$(to_session_relative "$classifier_file" "$session_dir")
    local classifier_mtime
    classifier_mtime=$(stat_mtime "$classifier_file")
    local classifier_updated_iso=""
    local classifier_total="0"
    local classifier_pending="$sources_total_numeric"
    local classifier_status="stale"
    if [[ -n "$classifier_mtime" ]]; then
        classifier_total=$(jq -s 'map(select(.source_id != null)) | length' "$classifier_file" 2>/dev/null || echo "0")
        classifier_total=$((classifier_total + 0))
        classifier_pending=$((sources_total_numeric - classifier_total))
        if (( classifier_pending < 0 )); then
            classifier_pending=0
        fi
        if [[ -z "$kg_mtime" || "$classifier_mtime" -ge "$kg_mtime" ]]; then
            classifier_status="fresh"
        fi
        classifier_updated_iso=$(epoch_to_iso8601 "$classifier_mtime")
    fi
    if (( classifier_pending > 0 )); then
        log_warn "session-manifest: stakeholder classifications ${classifier_status}; pending_sources=${classifier_pending}"
    elif [[ "$classifier_status" != "fresh" ]] && (( classifier_total > 0 )); then
        log_warn "session-manifest: stakeholder classifications ${classifier_status}; pending_sources=${classifier_pending}"
    fi

    local quality_gate_summary_path="$session_dir/artifacts/quality-gate-summary.json"
    local quality_gate_details_path="$session_dir/artifacts/quality-gate.json"
    local quality_gate_status="not_run"
    local quality_gate_summary="{}"
    if [[ -f "$quality_gate_summary_path" ]]; then
        quality_gate_status=$(safe_jq_from_file "$quality_gate_summary_path" '.status // "unknown"' "unknown" "$session_dir" "session_manifest.quality_gate_status")
        quality_gate_summary=$(safe_jq_from_file "$quality_gate_summary_path" '.' '{}' "$session_dir" "session_manifest.quality_gate_summary" "false")
    fi

    local mission_state_file="$meta_dir/mission_state.json"
    local recent_decisions="[]"
    if [[ -f "$mission_state_file" ]]; then
        recent_decisions=$(safe_jq_from_file "$mission_state_file" '.last_5_decisions // []' '[]' "$session_dir" "session_manifest.recent_decisions" "false")
    fi

    local pending_tasks="$kg_high_priority_gaps"

    local domain_heuristics_entries="[]"
    local -a domain_heuristics_paths=(
        "$session_dir/meta/domain-heuristics.json::meta"
        "$session_dir/work/domain-heuristics/output.json::work"
        "$session_dir/artifacts/domain-heuristics/domain-heuristics.json::artifact"
    )
    for spec in "${domain_heuristics_paths[@]}"; do
        local file="${spec%%::*}"
        local kind="${spec##*::}"
        local entry
        entry=$(collect_artifact_entry "$session_dir" "$file" "$kind")
        [[ -z "$entry" ]] && continue
        domain_heuristics_entries=$(append_json_entry "$domain_heuristics_entries" "$entry")
    done

    local prompt_parser_entries="[]"
    local -a prompt_parser_paths=(
        "$session_dir/work/prompt-parser/output.json::work"
        "$session_dir/artifacts/prompt-parser/output.md::artifact"
    )
    for spec in "${prompt_parser_paths[@]}"; do
        local file="${spec%%::*}"
        local kind="${spec##*::}"
        local entry
        entry=$(collect_artifact_entry "$session_dir" "$file" "$kind")
        [[ -z "$entry" ]] && continue
        prompt_parser_entries=$(append_json_entry "$prompt_parser_entries" "$entry")
    done

    local recent_agent_outputs
    recent_agent_outputs=$(collect_recent_agent_outputs "$session_dir" 5)

    local manifest_rel
    manifest_rel=$(to_session_relative "$meta_dir/session-manifest.json" "$session_dir")

    local generated_at
    generated_at=$(get_timestamp)

    jq -n \
        --arg version "1" \
        --arg generated "$generated_at" \
        --arg session_id "$mission_id" \
        --arg objective "$objective" \
        --arg status "$status" \
        --arg created "$created_at" \
        --arg updated "$updated_at" \
        --arg kg_path "$kg_path_rel" \
        --arg kg_path_abs "$kg_file" \
        --arg kg_iso "${kg_updated_iso:-}" \
        --arg kg_epoch "${kg_mtime:-}" \
        --arg qg_status "$quality_gate_status" \
        --arg qg_summary_path "$(to_session_relative "$quality_gate_summary_path" "$session_dir")" \
        --arg qg_detail_path "$(to_session_relative "$quality_gate_details_path" "$session_dir")" \
        --arg manifest_path "$manifest_rel" \
        --arg classifier_path "$classifier_path_rel" \
        --arg classifier_status "$classifier_status" \
        --arg classifier_updated_iso "${classifier_updated_iso:-}" \
        --arg classifier_updated_epoch "${classifier_mtime:-}" \
        --argjson classifier_total "$classifier_total" \
        --argjson classifier_pending "$classifier_pending" \
        --argjson domain_heuristics "$domain_heuristics_entries" \
        --argjson prompt_parser "$prompt_parser_entries" \
        --argjson recent_outputs "$recent_agent_outputs" \
        --argjson recent_decisions "$recent_decisions" \
        --argjson pending_tasks "$pending_tasks" \
        --arg claims "$claims_count" \
        --arg entities "$entities_count" \
        --arg sources "$sources_count" \
        --arg events_path "$(to_session_relative "$session_dir/logs/events.jsonl" "$session_dir")" \
        --arg orch_log "$(to_session_relative "$session_dir/logs/orchestration.jsonl" "$session_dir")" \
        --arg mission_state_path "$(to_session_relative "$mission_state_file" "$session_dir")" \
        --arg manifest_file "$(to_session_relative "$meta_dir/session-manifest.json" "$session_dir")" \
        --argjson quality_summary "$quality_gate_summary" \
        --argjson gaps "$kg_high_priority_gaps" \
        '{
            version: ($version | tonumber),
            generated_at: $generated,
            session: {
                id: $session_id,
                objective: (if $objective == "" then null else $objective end),
                status: (if $status == "" then null else $status end),
                created_at: (if $created == "" then null else $created end),
                updated_at: (if $updated == "" then null else $updated end),
                manifest_path: $manifest_path
            },
            paths: {
                manifest: $manifest_file,
                mission_state: $mission_state_path,
                knowledge_graph: $kg_path,
                orchestration_log: $orch_log,
                events_log: $events_path
            },
            knowledge_graph: {
                file: $kg_path,
                file_absolute: (if $kg_path_abs == "" then null else $kg_path_abs end),
                claims: ($claims | tonumber),
                entities: ($entities | tonumber),
                sources: ($sources | tonumber),
                last_updated_at: (if $kg_iso == "" then null else $kg_iso end),
                last_updated_epoch: (if $kg_epoch == "" then null else ($kg_epoch | tonumber) end)
            },
            quality_gate: {
                status: $qg_status,
                summary_file: (if $qg_summary_path == "" then null else $qg_summary_path end),
                details_file: (if $qg_detail_path == "" then null else $qg_detail_path end),
                summary: $quality_summary,
                high_priority_gaps: $gaps
            },
            stakeholder_classifier: {
                status: $classifier_status,
                classifications_file: (if $classifier_path == "" then null else $classifier_path end),
                total_classifications: $classifier_total,
                pending_sources: $classifier_pending,
                updated_at: (if $classifier_updated_iso == "" then null else $classifier_updated_iso end),
                updated_epoch: (if $classifier_updated_epoch == "" then null else ($classifier_updated_epoch | tonumber) end)
            },
            artifacts: {
                domain_heuristics: $domain_heuristics,
                prompt_parser: $prompt_parser,
                recent_agent_outputs: $recent_outputs
            },
            recent_decisions: $recent_decisions,
            pending_tasks: $pending_tasks
        }' > "$meta_dir/session-manifest.json.tmp"

    mv "$meta_dir/session-manifest.json.tmp" "$meta_dir/session-manifest.json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    build_session_manifest "$1"
fi
