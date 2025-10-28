#!/usr/bin/env bash
# Meta Manifest Generator - Creates INDEX.json and READ_ME_FIRST.md inside metadata folder

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=src/utils/core-helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

hash_file() {
    if [ -x "$SCRIPT_DIR/hash-file.sh" ]; then
        "$SCRIPT_DIR/hash-file.sh" "$1" 2>/dev/null || echo ""
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" 2>/dev/null | awk '{print $1}' || echo ""
    else
        shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || echo ""
    fi
}

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

generate_manifest() {
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
    local inputs_rel="inputs"
    local cache_rel="cache"
    local work_rel="work"
    local knowledge_rel="knowledge"
    local artifacts_rel="artifacts"
    local logs_rel="logs"
    local report_rel="report"
    local viewer_rel="viewer"
    local meta_dir="$session_dir/$meta_rel"

    local session_id objective created_at status
    session_id=$(basename "$session_dir")

    session_field() {
        local filter="$1"
        local fallback="$2"
        local context="$3"
        safe_jq_from_file "$session_json" "$filter" "$fallback" "$session_dir" "meta_manifest.$context"
    }

    objective=$(session_field '.objective // .research_question // "N/A"' "N/A" "objective")
    created_at=$(session_field '.created_at // "unknown"' "unknown" "created_at")
    status=$(session_field '.status // "unknown"' "unknown" "status")

    local kg_entities=0
    local kg_claims=0
    local kg_sources=0
    local kg_checksum=""
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
        kg_checksum=$(hash_file "$knowledge_file")
    fi
    kg_entities=$(sanitize_number "$kg_entities")
    kg_claims=$(sanitize_number "$kg_claims")
    kg_sources=$(sanitize_number "$kg_sources")

    local report_exists=false
    local report_file="$session_dir/$report_rel/mission-report.md"
    if [ -f "$report_file" ]; then
        report_exists=true
    fi

    local journal_checksum=""
    local journal_file="$session_dir/$report_rel/research-journal.md"
    if [ -f "$journal_file" ]; then
        journal_checksum=$(hash_file "$journal_file")
    fi

    local report_checksum=""
    if [ -f "$report_file" ]; then
        report_checksum=$(hash_file "$report_file")
    fi

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

    jq -n \
        --arg id "$session_id" \
        --arg created "$created_at" \
        --arg status "$status" \
        --arg objective "$objective" \
        --argjson entities "$kg_entities" \
        --argjson claims "$kg_claims" \
        --argjson sources "$kg_sources" \
        --argjson artifacts "$artifact_count" \
        --argjson events "$event_count" \
        --arg kg_checksum "$kg_checksum" \
        --arg report_checksum "$report_checksum" \
        --arg journal_checksum "$journal_checksum" \
        --argjson report_exists "$report_exists" \
        --arg meta_rel "$meta_rel" \
        --arg inputs_rel "$inputs_rel" \
        --arg cache_rel "$cache_rel" \
        --arg work_rel "$work_rel" \
        --arg knowledge_rel "$knowledge_rel" \
        --arg artifacts_rel "$artifacts_rel" \
        --arg logs_rel "$logs_rel" \
        --arg report_rel "$report_rel" \
        --arg viewer_rel "$viewer_rel" \
        '{
            id: $id,
            created_at: $created,
            status: $status,
            mission: "research",
            objective: $objective,
            statistics: {
                entities: $entities,
                claims: $claims,
                sources: $sources,
                artifacts: $artifacts,
                events: $events
            },
            paths: {
                meta: ($meta_rel + "/"),
                inputs: ($inputs_rel + "/"),
                cache: ($cache_rel + "/"),
                work: ($work_rel + "/"),
                knowledge: ($knowledge_rel + "/"),
                artifacts: ($artifacts_rel + "/"),
                logs: ($logs_rel + "/"),
                report: ($report_rel + "/"),
                viewer: ($viewer_rel + "/")
            },
            deliverables: {
                report: ($report_exists | if . then ($report_rel + "/mission-report.md") else null end),
                journal: ($report_rel + "/research-journal.md"),
                knowledge_graph: ($knowledge_rel + "/knowledge-graph.json"),
                dashboard: ($viewer_rel + "/index.html")
            },
            checksums: {
                knowledge_graph: $kg_checksum,
                report: $report_checksum,
                journal: $journal_checksum
            }
        }' > "$session_dir/INDEX.json"

    mkdir -p "$meta_dir"
    cat > "$meta_dir/READ_ME_FIRST.md" <<EOF
# Research Session: $session_id

**Status**: $status  
**Created**: $created_at  
**Objective**: $objective

## Quick Navigation

EOF

    if [ "$report_exists" = "true" ]; then
        cat >> "$meta_dir/READ_ME_FIRST.md" <<EOF
### 📄 Final Report
~~~bash
cat $report_rel/mission-report.md
open $report_rel/mission-report.md
~~~

EOF
    fi

    cat >> "$meta_dir/READ_ME_FIRST.md" <<EOF
### 📖 Research Journal
~~~bash
cat $report_rel/research-journal.md
~~~

### 📊 Dashboard Viewer
~~~bash
./cconductor viewer $session_id
# or open $viewer_rel/index.html in browser
~~~

### 🧠 Knowledge Graph
~~~bash
jq . $knowledge_rel/knowledge-graph.json | less
~~~

## Session Statistics

- **Entities**: $kg_entities
- **Claims**: $kg_claims
- **Sources**: $kg_sources
- **Artifacts**: $artifact_count
- **Events**: $event_count

## Directory Structure

- <code>${meta_rel}/</code> - Session metadata, provenance
- <code>${inputs_rel}/</code> - Original research question and parameters
- <code>${cache_rel}/</code> - Live mission cache artifacts
- <code>${work_rel}/</code> - Agent working directories
- <code>${knowledge_rel}/</code> - Knowledge graph and session knowledge files
- <code>${artifacts_rel}/</code> - Agent-produced artifacts
- <code>${logs_rel}/</code> - Events, orchestration decisions, quality gate results
- <code>${report_rel}/</code> - Final mission report and research journal
- <code>${viewer_rel}/</code> - Interactive dashboard

## Resume Research

~~~bash
./cconductor resume $session_id
~~~

## Session Manifest

See <code>INDEX.json</code> at session root for complete file listing and checksums.
EOF

    echo "Generated INDEX.json and $meta_rel/READ_ME_FIRST.md"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi

    generate_manifest "$1"
fi
