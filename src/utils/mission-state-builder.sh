#!/usr/bin/env bash
# Mission State Builder - Produces a slim mission summary for orchestrator prompts

set -euo pipefail

build_mission_state() {
    local session_dir="$1"

    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        echo "Usage: build_mission_state <session_dir>" >&2
        return 1
    fi

    local knowledge_dir="$session_dir/knowledge"
    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"

    local kg_file="$knowledge_dir/knowledge-graph.json"
    local coverage='{"total_claims":0,"high_confidence":0,"total_gaps":0,"high_priority_gaps":0}'
    if [[ -f "$kg_file" ]]; then
        coverage=$(jq '{
                total_claims: ((.claims // []) | length),
                high_confidence: ([(.claims // [])[]? | select((.confidence // 0) >= 0.8)] | length),
                total_gaps: ((.gaps // []) | length),
                high_priority_gaps: ([(.gaps // [])[]? | select((.priority // 0) >= 8)] | length)
            }' "$kg_file" 2>/dev/null || echo "$coverage")
    fi

    local orch_log="$session_dir/logs/orchestration.jsonl"
    local recent_decisions='[]'
    if [[ -f "$orch_log" ]]; then
        recent_decisions=$(tail -5 "$orch_log" 2>/dev/null | jq -s '.' 2>/dev/null || echo '[]')
    fi

    local budget_file="$meta_dir/budget.json"
    local budget_summary='{"spent":{},"limits":{},"invocation_count":0}'
    if [[ -f "$budget_file" ]]; then
        budget_summary=$(jq '{
            spent: (.spent // {}),
            limits: (.limits // {}),
            invocation_count: (.invocations // [] | length)
        }' "$budget_file" 2>/dev/null || echo "$budget_summary")
    fi

    local quality_gate_status='not_run'
    local quality_gate_file="$session_dir/artifacts/quality-gate-summary.json"
    if [[ -f "$quality_gate_file" ]]; then
        quality_gate_status=$(jq -r '.status // "unknown"' "$quality_gate_file" 2>/dev/null || echo "unknown")
    fi

    jq -n \
        --argjson coverage "$coverage" \
        --argjson decisions "$recent_decisions" \
        --argjson budget "$budget_summary" \
        --arg qg "$quality_gate_status" \
        '{
            coverage: $coverage,
            last_5_decisions: $decisions,
            budget_summary: $budget,
            quality_gate_status: $qg,
            kg_path: "knowledge/knowledge-graph.json",
            full_log_path: "logs/orchestration.jsonl"
        }' > "$meta_dir/mission_state.json"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    build_mission_state "$1"
fi
