#!/usr/bin/env bash
# Export the materialised Argument Event Graph to AIF-compliant JSON-LD.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/file-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/materialize-argument-graph.sh"

export_aif_usage() {
    cat <<'EOF'
Usage: export-aif.sh --session <session_dir> [--output <file>] [--pretty]
EOF
}

export_aif() {
    local session_dir="$1"
    local output_path="$2"
    local pretty="$3"

    materialize_argument_graph "$session_dir" 0

    local argument_dir="${session_dir}/argument"
    local graph_path="${argument_dir}/aeg.graph.json"

    if [[ ! -f "$graph_path" ]]; then
        log_error "AIF export requires ${graph_path}"
        return 1
    fi

    local session_name
    session_name="$(basename "$session_dir")"
    local base_iri="mission://${session_name}/"

    local jq_filter
    read -r -d '' jq_filter <<'JQ' || true
def encode_id:
  gsub("[:/ ]"; "_");

def node_iri($base; $id):
  $base + "nodes/" + ($id | encode_id);

def scheme_iri($base; $sid):
  $base + "schemes/" + ($sid | encode_id);

def source_iri($base; $sid):
  $base + "sources/" + ($sid | encode_id);

def directed_edge($base):
  {
    "@type": "aif:DirectedEdge",
    "aif:from": {"@id": node_iri($base; .from)},
    "aif:to": {"@id": node_iri($base; .to)},
    "cc:role": .role
  };

. as $graph
| def node_payload($base):
    if .type == "I" then
      {
        "@id": node_iri($base; .id),
        "@type": "aif:I-node",
        "aif:claimText": (.text // .statement),
        "cc:claimId": (.claim_id // .evidence_id),
        "cc:role": (.role // null),
        "cc:status": (.status // null),
        "cc:domain": (.domain // null),
        "cc:confidence": (.confidence // null),
        "cc:quality": (.quality // null),
        "cc:agent": (.agent // null),
        "cc:missionStep": (.mission_step // null),
        "cc:timestamp": (.timestamp // null)
      } | with_entries(select(.value != null))
    elif .type == "RA" then
      {
        "@id": node_iri($base; .id),
        "@type": "aif:RA-node",
        "aif:scheme": scheme_iri($base; (.scheme_id // "supporting-evidence")),
        "aif:premise": [(.premises[]? | {"@id": node_iri($base; ("I:" + .) )})],
        "aif:conclusion": {"@id": node_iri($base; ("I:" + .claim_id))},
        "cc:agent": (.agent // null),
        "cc:missionStep": (.mission_step // null),
        "cc:timestamp": (.timestamp // null)
      } | with_entries(select(.value != null))
    elif .type == "CA" then
      {
        "@id": node_iri($base; .id),
        "@type": "aif:CA-node",
        "aif:attacker": {"@id": node_iri($base; ("I:" + (.attacker_claim_id // "")))},
        "aif:target": {"@id": node_iri($base; ("I:" + (.target_claim_id // "")))},
        "cc:scheme": scheme_iri($base; (.scheme_id // "contradiction")),
        "cc:basis": (.basis // null),
        "cc:explanation": (.explanation // null),
        "cc:agent": (.agent // null),
        "cc:missionStep": (.mission_step // null),
        "cc:timestamp": (.timestamp // null)
      } | with_entries(select(.value != null))
    elif .type == "PA" then
      {
        "@id": node_iri($base; .id),
        "@type": "aif:PA-node",
        "cc:criteria": (.criteria // null),
        "cc:weight": (.weight // null),
        "cc:explanation": (.explanation // null),
        "cc:agent": (.agent // null),
        "cc:missionStep": (.mission_step // null),
        "cc:timestamp": (.timestamp // null),
        "cc:preferredClaim": node_iri($base; ("I:" + (.preferred_claim_id // ""))),
        "cc:dispreferredClaim": node_iri($base; ("I:" + (.dispreferred_claim_id // "")))
      } | with_entries(select(.value != null))
    else empty
    end;

{
  "@context": [
    "https://www.arg.tech/aif-schema.jsonld",
    {"cc": ($base_context)}
  ],
  "@id": ($base_graph),
  "@type": "aif:ArgumentGraph",
  "aif:nodes": [ $graph.nodes[]? | node_payload($base_root) ],
  "aif:edges": [ $graph.edges[]? | directed_edge($base_root) ],
  "cc:sources": [
    ($graph.sources // {} | to_entries[]? |
      {
        "@id": source_iri($base_root; .key),
        "@type": "aif:F-node",
        "cc:sourceId": .key,
        "cc:title": (.value.title // null),
        "cc:url": (.value.url // null),
        "cc:published": (.value.published // null)
      } | with_entries(select(.value != null))
    )
  ],
  "cc:metrics": ($graph.metrics // {}),
  "cc:violations": ($graph.violations // [])
}
JQ

    local base_context="${base_iri}context#"
    local base_graph="${base_iri}graph"
    local base_root="$base_iri"

    local export_json
    export_json=$(jq \
        --arg base_context "$base_context" \
        --arg base_graph "$base_graph" \
        --arg base_root "$base_root" \
        "$jq_filter" \
        "$graph_path")

    if [[ -n "$output_path" ]]; then
        if [[ "$pretty" == "1" ]]; then
            printf '%s\n' "$export_json" | jq '.' > "$output_path"
        else
            printf '%s\n' "$export_json" > "$output_path"
        fi
    else
        if [[ "$pretty" == "1" ]]; then
            printf '%s\n' "$export_json" | jq '.'
        else
            printf '%s\n' "$export_json"
        fi
    fi
}

export_aif_cli() {
    local session=""
    local output=""
    local pretty=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session="$2"
                shift 2
                ;;
            --output)
                output="$2"
                shift 2
                ;;
            --pretty)
                pretty=1
                shift
                ;;
            --help|-h)
                export_aif_usage
                return 0
                ;;
            *)
                log_error "Unknown argument: $1"
                export_aif_usage
                return 1
                ;;
        esac
    done

    if [[ -z "$session" ]]; then
        log_error "--session is required"
        return 1
    fi

    export_aif "$session" "$output" "$pretty"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    export_aif_cli "$@"
fi

export -f export_aif
