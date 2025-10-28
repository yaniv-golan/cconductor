#!/usr/bin/env bash
# Session README Generator - Creates user-facing README.md at session root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/utils/core-helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

sanitize_number() {
    local value="${1:-}"
    local fallback="${2:-0}"

    if [[ -z "$value" || "$value" == "null" ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

generate_readme() {
    local session_dir="$1"

    if [ ! -d "$session_dir" ]; then
        echo "ERROR: Session directory not found: $session_dir" >&2
        return 1
    fi

    local session_json="$session_dir/meta/session.json"
    if [ ! -f "$session_json" ]; then
        echo "ERROR: meta/session.json not found" >&2
        return 1
    fi

    local meta_rel="meta"
    local report_rel="report"
    local viewer_rel="viewer"
    local knowledge_rel="knowledge"
    local artifacts_rel="artifacts"
    local logs_rel="logs"
    local inputs_rel="inputs"
    local work_rel="work"
    local cache_rel="cache"

    local session_id session_title objective created_at status mission_name
    session_id=$(basename "$session_dir")
    session_title="$session_id"
    if [[ "$session_id" == mission_* ]]; then
        session_title="Mission ${session_id#mission_}"
    elif [[ "$session_id" == session_* ]]; then
        session_title="Session ${session_id#session_}"
    fi

    session_field() {
        local filter="$1"
        local fallback="$2"
        local context="$3"
        safe_jq_from_file "$session_json" "$filter" "$fallback" "$session_dir" "session_readme.$context"
    }

    objective=$(session_field '.objective // .research_question // "N/A"' "N/A" "objective")
    created_at=$(session_field '.created_at // "unknown"' "unknown" "created_at")
    status=$(session_field '.status // "unknown"' "unknown" "status")
    mission_name=$(session_field '.mission_name // "research"' "research" "mission_name")

    local kg_entities=0
    local kg_claims=0
    local kg_sources=0
    local knowledge_file="$session_dir/$knowledge_rel/knowledge-graph.json"
    if [ -f "$knowledge_file" ]; then
        kg_entities=$(safe_jq_from_file "$knowledge_file" '.stats.total_entities // 0' "0" "$session_dir" "knowledge.entities")
        kg_claims=$(safe_jq_from_file "$knowledge_file" '.stats.total_claims // 0' "0" "$session_dir" "knowledge.claims")
        local kg_sources_filter='(
                [
                    (.claims // [])[]?.sources[]? |
                    ((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // ""))
                ] +
                [
                    (.citations // [])[]? |
                    ((.url // "") + "|" + (.title // "") + "|" + (.excerpt // ""))
                ]
            )
            | map(select(. != "")) | unique | length'
        kg_sources=$(safe_jq_from_file "$knowledge_file" "$kg_sources_filter" "0" "$session_dir" "knowledge.sources" "false")
    fi
    kg_entities=$(sanitize_number "$kg_entities")
    kg_claims=$(sanitize_number "$kg_claims")
    kg_sources=$(sanitize_number "$kg_sources")

    local artifact_count=0
    if [ -d "$session_dir/$artifacts_rel" ]; then
        artifact_count=$(find "$session_dir/$artifacts_rel" -type f -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
    fi
    artifact_count=$(sanitize_number "$artifact_count")

    local event_count=0
    local events_file="$session_dir/$logs_rel/events.jsonl"
    if [ -f "$events_file" ]; then
        event_count=$(wc -l < "$events_file" 2>/dev/null | tr -d ' ')
    fi
    event_count=$(sanitize_number "$event_count")

    local report_exists=false
    if [ -f "$session_dir/$report_rel/mission-report.md" ]; then
        report_exists=true
    fi

    cat > "$session_dir/README.md" <<EOF
# $session_title

**Mission**: $mission_name  
**Status**: $status  
**Created**: $created_at  
**Objective**: $objective

## Start Here

1. **Final Report** — <code>${report_rel}/mission-report.md</code>
   ~~~bash
   cat $report_rel/mission-report.md
   open $report_rel/mission-report.md  # macOS quick look
   ~~~
2. **Research Journal** — <code>${report_rel}/research-journal.md</code>
   ~~~bash
   cat $report_rel/research-journal.md
   ~~~
3. **Interactive Viewer** — <code>${viewer_rel}/index.html</code>
   ~~~bash
   ./cconductor viewer $session_id
   # or open $viewer_rel/index.html
   ~~~

## Explore the Evidence

- **Knowledge Graph** (<code>$knowledge_rel/knowledge-graph.json</code>): structured entities, claims, and citations.
- **Artifacts** (<code>$artifacts_rel/</code>): agent-level outputs, manifests, and diagnostics.
- **Logs** (<code>$logs_rel/</code>): orchestration events, tool traces, and remediation notes.

## Session Map

| Folder | What you’ll find |
| --- | --- |
| <code>${meta_rel}/</code> | Session metadata, provenance, runtime settings |
| <code>${inputs_rel}/</code> | Normalized prompt, parameters, user-provided files |
| <code>${cache_rel}/</code> | Live web/search cache artifacts reused within the mission |
| <code>${work_rel}/</code> | Agent scratch space, intermediate findings |
| <code>${knowledge_rel}/</code> | Canonical knowledge graph plus merged summaries |
| <code>${artifacts_rel}/</code> | Structured outputs referenced in reports or gates |
| <code>${logs_rel}/</code> | Events, orchestration decisions, quality reports |
| <code>${report_rel}/</code> | Final report, research journal, supporting assets |
| <code>${viewer_rel}/</code> | Static dashboard bundle powered by the above data |

## Resume or Reuse

~~~bash
./cconductor resume $session_id
~~~

Need a different export? Use <code>src/utils/export-journal.sh</code> or rebuild the dashboard with <code>./cconductor viewer $session_id</code>.

## Snapshot

- **Entities**: $kg_entities
- **Claims**: $kg_claims
- **Unique sources**: $kg_sources
- **Artifacts**: $artifact_count
- **Logged events**: $event_count
EOF

    if [ "$report_exists" = false ]; then
        cat >> "$session_dir/README.md" <<EOF

> ⚠️ Final report not found yet. Check <code>${logs_rel}/</code> for blockers or resume the mission to finish synthesis.
EOF
    fi

    echo "Generated session README.md"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi

    generate_readme "$1"
fi
