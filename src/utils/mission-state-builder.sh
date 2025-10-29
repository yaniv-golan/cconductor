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
    if [[ -f "$kg_file" ]]; then
        claims_count=$(safe_jq_from_file "$kg_file" '.claims | length' '0' "$session_dir" "mission_state.claims")
        entities_count=$(safe_jq_from_file "$kg_file" '.entities | length' '0' "$session_dir" "mission_state.entities")
        sources_count=$(safe_jq_from_file "$kg_file" '[.claims[]? | .sources[]?] | unique_by(.url) | length' '0' "$session_dir" "mission_state.sources" "false")
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
        --arg kg_path "$kg_file" \
        --arg log_path "$orch_log" \
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
            kg_path: $kg_path,
            full_log_path: $log_path
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
