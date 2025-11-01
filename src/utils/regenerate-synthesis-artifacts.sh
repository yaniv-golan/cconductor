#!/usr/bin/env bash
# regenerate-synthesis-artifacts.sh - Rebuild synthesis artifact skeletons when outputs are missing or malformed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

usage() {
    cat <<'USAGE' >&2
Usage: regenerate-synthesis-artifacts.sh [--force] <session_dir>

Re-creates schema-compliant skeletons for synthesis artifacts under
<session_dir>/artifacts/synthesis-agent/.

Options:
  --force     Overwrite existing files instead of skipping them.
USAGE
}

force_overwrite=0
session_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            force_overwrite=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            session_dir="$1"
            shift
            ;;
    esac
done

if [[ -z "$session_dir" ]]; then
    echo "Error: session directory not provided." >&2
    usage
    exit 1
fi

if [[ ! -d "$session_dir" ]]; then
    echo "Error: session directory not found: $session_dir" >&2
    exit 1
fi

session_dir="$(cd "$session_dir" && pwd)"
artifacts_dir="$session_dir/artifacts/synthesis-agent"
mkdir -p "$artifacts_dir"

kg_file="$session_dir/knowledge/knowledge-graph.json"
iteration="0"
claim_count="0"
entity_count="0"
source_count="0"

if [[ -f "$kg_file" ]]; then
    iteration=$(safe_jq_from_file "$kg_file" '.iteration // 0' '0' "$session_dir" "regen_synthesis.iteration")
    claim_count=$(safe_jq_from_file "$kg_file" '.claims | length' '0' "$session_dir" "regen_synthesis.claims")
    entity_count=$(safe_jq_from_file "$kg_file" '.entities | length' '0' "$session_dir" "regen_synthesis.entities")
    source_count=$(safe_jq_from_file "$kg_file" '[.claims[]? | .sources[]?] | length' '0' "$session_dir" "regen_synthesis.sources" "true")
fi

[[ -z "$iteration" ]] && iteration="0"
[[ -z "$claim_count" ]] && claim_count="0"
[[ -z "$entity_count" ]] && entity_count="0"
[[ -z "$source_count" ]] && source_count="0"

timestamp="$(get_timestamp)"

write_json_file() {
    local target="$1"
    local payload="$2"

    mkdir -p "$(dirname "$target")"
    local tmp
    tmp="$(mktemp "${target}".tmp.XXXXXX)"
    printf '%s\n' "$payload" >"$tmp"
    mv "$tmp" "$target"
}

validate_with_schema() {
    local schema="$PROJECT_ROOT/config/schemas/artifacts/synthesis/$1.schema.json"
    local data="$artifacts_dir/$1.json"
    CCONDUCTOR_SESSION_DIR="$session_dir" json_validate_with_schema "$schema" "$data"
}

maybe_write_artifact() {
    local name="$1"
    local content="$2"
    local path="$artifacts_dir/$name.json"

    if [[ -f "$path" && $force_overwrite -eq 0 ]]; then
        echo "• Skipping $name.json (exists; use --force to overwrite)"
        return 0
    fi

    write_json_file "$path" "$content"
    if validate_with_schema "$name"; then
        echo "✓ Wrote $name.json"
        return 0
    else
        echo "✗ Schema validation failed for $name.json" >&2
        return 1
    fi
}

completion_json=$(jq -n \
    --arg timestamp "$timestamp" \
    --argjson iteration "$iteration" \
    --argjson claims "$claim_count" \
    --argjson entities "$entity_count" \
    --argjson sources "$source_count" \
    '{
        synthesized_at: $timestamp,
        synthesis_iteration: ($iteration | tonumber? // 0),
        report_generated: false,
        report_path: "report/mission-report.md",
        knowledge_graph_path: "knowledge/knowledge-graph.json",
        quality_gate_status: "pending",
        total_claims_synthesized: ($claims | tonumber? // 0),
        total_entities_referenced: ($entities | tonumber? // 0),
        total_sources_cited: ($sources | tonumber? // 0)
    }')

key_findings_json=$(jq -n '{
    well_supported_claims: [],
    partially_supported_claims: [],
    contradicted_claims: [],
    promise_vs_implementation_gaps: [],
    engineering_verdict: {}
}')

coverage_json=$(jq -n '{
    aspects_identified: 0,
    aspects_well_covered: 0,
    aspects_partially_covered: 0,
    aspects_not_covered: 0,
    well_covered: [],
    partially_covered: [],
    not_covered: [],
    research_objectives_met: [],
    critical_distinction_addressed: false,
    missing_watch_topics: []
}')

confidence_scores_json=$(jq -n '{
    overall: 0.0,
    by_category: {},
    methodology: "Regenerated skeleton pending synthesis detail",
    limitations: []
}')

failures=0
maybe_write_artifact "completion" "$completion_json" || failures=1
maybe_write_artifact "key-findings" "$key_findings_json" || failures=1
maybe_write_artifact "coverage" "$coverage_json" || failures=1
maybe_write_artifact "confidence-scores" "$confidence_scores_json" || failures=1

if (( failures > 0 )); then
    echo "Artifact regeneration completed with errors." >&2
    exit 1
fi

echo "All synthesis artifacts are present and schema-compliant."
