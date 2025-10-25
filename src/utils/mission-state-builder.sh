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

build_mission_state() {
    local session_dir="$1"

    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        log_error "Invalid session directory"
        return 1
    fi

    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    local heuristics_file="$meta_dir/domain-heuristics.json"
    local kg_json
    kg_json=$(cat "$kg_file" 2>/dev/null || echo '{}')

    local claims_count entities_count sources_count
    claims_count=$(echo "$kg_json" | jq '.claims | length' 2>/dev/null || echo '0')
    entities_count=$(echo "$kg_json" | jq '.entities | length' 2>/dev/null || echo '0')
    sources_count=$(echo "$kg_json" | jq '[.claims[]? | .sources[]?] | unique_by(.url) | length' 2>/dev/null || echo '0')

    local spent_usd="0"
    local spent_invocations="0"
    if command -v budget_status >/dev/null 2>&1; then
        local budget_state
        budget_state=$(budget_status "$session_dir" 2>/dev/null || echo '{}')
        spent_usd=$(echo "$budget_state" | jq -r '.spent.cost_usd // 0' 2>/dev/null || echo '0')
        spent_invocations=$(echo "$budget_state" | jq -r '.spent.agent_invocations // 0' 2>/dev/null || echo '0')
    else
        local budget_file="$meta_dir/budget.json"
        if [[ -f "$budget_file" ]]; then
            spent_usd=$(json_get_field "$budget_file" '.spent.cost_usd' '0')
            spent_invocations=$(json_get_field "$budget_file" '.spent.agent_invocations' '0')
        fi
    fi

    local qg_summary="$session_dir/artifacts/quality-gate-summary.json"
    local qg_status="not_run"
    if [[ -f "$qg_summary" ]]; then
        qg_status=$(json_get_field "$qg_summary" '.status' 'unknown')
    fi

    local compliance_json='{}'
    if [[ -f "$heuristics_file" && -f "$SCRIPT_DIR/domain-compliance-check.sh" ]]; then
        compliance_json=$(bash "$SCRIPT_DIR/domain-compliance-check.sh" "$session_dir" 2>/dev/null || echo '{}')
    fi

    local orch_log="$session_dir/logs/orchestration.jsonl"
    local recent_decisions='[]'
    if [[ -f "$orch_log" ]]; then
        recent_decisions=$(tail -5 "$orch_log" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')
    fi

    local tmp_file="$meta_dir/mission_state.json.tmp"
    jq -n \
        --argjson claims "$claims_count" \
        --argjson entities "$entities_count" \
        --argjson sources "$sources_count" \
        --arg spent "$spent_usd" \
        --argjson spent_inv "$spent_invocations" \
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
                spent_invocations: ($spent_inv | tonumber)
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
