#!/usr/bin/env bash
# Materialise the Argument Event Graph from the append-only event log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/file-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/verbose.sh" 2>/dev/null; then
    verbose() { :; }
    export -f verbose
fi

SCHEMA_VERSION="2025-10-30"

materialize_usage() {
    cat <<'EOF'
Usage: materialize-argument-graph.sh --session <session_dir> [--force]
EOF
}

materialize_argument_graph() {
    local session_dir="$1"
    local force="${2:-0}"

    local argument_dir="${session_dir}/argument"
    ensure_dir "$argument_dir"

    local log_path="${argument_dir}/aeg.log.jsonl"
    local graph_path="${argument_dir}/aeg.graph.json"
    local quality_path="${argument_dir}/aeg.quality.json"

    if [[ ! -f "$log_path" ]]; then
        : > "$log_path"
    fi

    if [[ "$force" != "1" && -f "$graph_path" && "$graph_path" -nt "$log_path" ]]; then
        verbose "materialize-argument-graph: graph up to date"
        return 0
    fi

    local generated_at
    generated_at=$(get_timestamp)

    read -r -d '' JQ_FILTER <<'JQ' || true
def ensure_array($x):
  if $x == null then [] elif ($x|type) == "array" then $x else [$x] end;

def unique_nonempty:
  [ .[] | tostring | select(length > 0) ] | unique;

reduce .[] as $e (
  {
    claims: {},
    evidence: {},
    contradictions: [],
    preferences: [],
    retractions: {}
  };
  if ($e.event_type // "") == "claim" and ($e.payload.claim_id // "") != "" then
    .claims[$e.payload.claim_id] = {
      id: $e.payload.claim_id,
      text: $e.payload.text,
      modality: $e.payload.modality,
      confidence: $e.payload.confidence,
      domain: $e.payload.domain,
      tags: ensure_array($e.payload.tags),
      sources: ensure_array($e.payload.sources),
      premises: ensure_array($e.payload.premises),
      hash_strategy: $e.payload.hash_strategy,
      agent: $e.agent,
      mission_step: $e.mission_step,
      timestamp: $e.timestamp
    }
  elif ($e.event_type // "") == "evidence" and ($e.payload.evidence_id // "") != "" then
    .evidence[$e.payload.evidence_id] = {
      id: $e.payload.evidence_id,
      claim_id: $e.payload.claim_id,
      role: ($e.payload.role // "support"),
      statement: $e.payload.statement,
      source: $e.payload.source,
      quality: ($e.payload.quality // "unknown"),
      numeric: $e.payload.numeric,
      agent: $e.agent,
      mission_step: $e.mission_step,
      timestamp: $e.timestamp
    }
  elif ($e.event_type // "") == "contradiction" then
    .contradictions += [
      ($e.payload + {agent: $e.agent, mission_step: $e.mission_step, timestamp: $e.timestamp})
    ]
  elif ($e.event_type // "") == "preference" then
    .preferences += [
      ($e.payload + {agent: $e.agent, mission_step: $e.mission_step, timestamp: $e.timestamp})
    ]
  elif ($e.event_type // "") == "retraction" and ($e.payload.target_id // "") != "" then
    .retractions[$e.payload.target_id] = {
      target_type: ($e.payload.target_type // "claim"),
      reason: $e.payload.reason,
      replacing_claim_id: $e.payload.replacing_claim_id,
      timestamp: $e.timestamp
    }
  else .
  end
)
| . as $state
| $state
| .claim_nodes = (
    $state.claims
    | to_entries
    | map(
        .key as $cid
        | .value as $claim
        | {
            id: ("I:" + $cid),
            type: "I",
            claim_id: $cid,
            text: $claim.text,
            modality: $claim.modality,
            confidence: $claim.confidence,
            domain: $claim.domain,
            tags: $claim.tags,
            status: (if $state.retractions[$cid]? then "retracted" else "active" end),
            agent: $claim.agent,
            mission_step: $claim.mission_step,
            timestamp: $claim.timestamp
        }
    )
  )
| .evidence_nodes = (
    $state.evidence
    | to_entries
    | map(
        .key as $eid
        | .value as $evid
        | {
            id: ("I:" + $eid),
            type: "I",
            evidence_id: $eid,
            claim_id: $evid.claim_id,
            role: $evid.role,
            statement: $evid.statement,
            source_id: (if ($evid.source|type) == "object" then $evid.source.source_id else $evid.source end),
            quality: $evid.quality,
            numeric: $evid.numeric,
            agent: $evid.agent,
            mission_step: $evid.mission_step,
            timestamp: $evid.timestamp
        }
    )
  )
| .ra_nodes = (
    $state.claims
    | to_entries
    | map(
        .key as $cid
        | .value as $claim
        | (
            (ensure_array($claim.premises) | map(tostring))
            +
            ($state.evidence
              | to_entries
              | map(select(.value.claim_id == $cid) | .key)
            )
          ) as $raw_premises
        | ($raw_premises | unique_nonempty) as $premises
        | select(($premises | length) > 0)
        | {
            id: ("RA:" + $cid + ":000"),
            type: "RA",
            claim_id: $cid,
            premises: $premises,
            scheme_id: "supporting-evidence",
            agent: $claim.agent,
            mission_step: $claim.mission_step,
            timestamp: $claim.timestamp
        }
    )
  )
| .ca_nodes = (
    $state.contradictions
    | map(
        .contradiction_id as $cid
        | {
            id: ("CA:" + (($cid // (.attacker_claim_id + "-" + .target_claim_id)))),
            type: "CA",
            contradiction_id: ($cid // (.attacker_claim_id + "-" + .target_claim_id)),
            attacker_claim_id: .attacker_claim_id,
            target_claim_id: .target_claim_id,
            basis: .basis,
            explanation: .explanation,
            sources: ensure_array(.sources),
            agent: .agent,
            mission_step: .mission_step,
            timestamp: .timestamp
        }
    )
  )
| .pa_nodes = (
    $state.preferences
    | map(
        .preference_id as $pid
        | {
            id: ("PA:" + (($pid // (.preferred_claim_id + "-" + .dispreferred_claim_id)))),
            type: "PA",
            preference_id: ($pid // (.preferred_claim_id + "-" + .dispreferred_claim_id)),
            preferred_claim_id: .preferred_claim_id,
            dispreferred_claim_id: .dispreferred_claim_id,
            criteria: .criteria,
            weight: .weight,
            valid_from_seq: .valid_from_seq,
            explanation: .explanation,
            agent: .agent,
            mission_step: .mission_step,
            timestamp: .timestamp
        }
    )
  )
| .nodes = (.claim_nodes + .evidence_nodes + .ra_nodes + .ca_nodes + .pa_nodes)
| .edges = (
    (
      (.ra_nodes // [])
      | map(
          . as $ra
          | ([
              ($ra.premises[]? | {
                  from: ("I:" + .),
                  to: $ra.id,
                  role: "premise"
              })
          ] + [
              {
                  from: $ra.id,
                  to: ("I:" + $ra.claim_id),
                  role: "conclusion"
              }
          ])
      )
      | add // []
    )
    +
    (
      (.ca_nodes // [])
      | map(
          [
            {
              from: ("I:" + (.attacker_claim_id // "")),
              to: .id,
              role: "attacker"
            },
            {
              from: .id,
              to: ("I:" + (.target_claim_id // "")),
              role: "target"
            }
          ]
      )
      | add // []
    )
    +
    (
      (.pa_nodes // [])
      | map(
          [
            {
              from: ("I:" + (.preferred_claim_id // "")),
              to: .id,
              role: "preferred"
            },
            {
              from: .id,
              to: ("I:" + (.dispreferred_claim_id // "")),
              role: "dispreferred"
            }
          ]
      )
      | add // []
    )
  )
| .sources = (
    reduce ($state.claims | to_entries[]) as $c ({};
        reduce (ensure_array($c.value.sources)[]) as $src (.;
            if ($src|type) == "object" then
                if ($src.source_id // "") != "" then
                    .[$src.source_id] = $src
                else .
                end
            else
                .
            end
        )
    )
    | reduce ($state.evidence | to_entries[]) as $e (.;
        if ($e.value.source|type) == "object" then
            if ($e.value.source.source_id // "") != "" then
                .[$e.value.source.source_id] = $e.value.source
            else .
            end
        else
            .
        end
    )
  )
| .metrics = {
    claims_total: ($state.claims | length),
    claims_with_ra: ((.ra_nodes // []) | length),
    claim_coverage: (if ($state.claims | length) > 0 then ((.ra_nodes // []) | length) / ($state.claims | length) else 1 end),
    contradictions_total: ($state.contradictions | length),
    preferences_total: ($state.preferences | length),
    retracted_nodes: ($state.retractions | length)
  }
| .violations = (
    $state.claims
    | to_entries
    | map(
        .key as $cid
        | .value as $claim
        | (
            (ensure_array($claim.premises) | length) == 0
            and (
                $state.evidence
                | to_entries
                | map(select(.value.claim_id == $cid))
                | length
            ) == 0
        ) as $missing
        | select($missing)
        | {
            code: "S8.MISSING_RA",
            claim_id: $cid,
            description: "Claim lacks supporting evidence"
        }
    )
  )
| {
    schema_version: $schema_version,
    generated_at: $generated_at,
    nodes: .nodes,
    edges: .edges,
    metrics: .metrics,
    violations: .violations,
    sources: .sources
  }
JQ

    local graph_json
    graph_json=$(jq -s \
        --arg generated_at "$generated_at" \
        --arg schema_version "$SCHEMA_VERSION" \
        "$JQ_FILTER" \
        "$log_path")

    printf '%s\n' "$graph_json" | jq '.' > "${graph_path}.tmp"
    mv "${graph_path}.tmp" "$graph_path"

    printf '%s\n' "$graph_json" | jq '{schema_version, generated_at, metrics, violations}' > "${quality_path}.tmp"
    mv "${quality_path}.tmp" "$quality_path"
}

materialize_cli() {
    local session=""
    local force=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session="$2"
                shift 2
                ;;
            --force)
                force=1
                shift
                ;;
            --help|-h)
                materialize_usage
                return 0
                ;;
            *)
                log_error "Unknown argument: $1"
                materialize_usage
                return 1
                ;;
        esac
    done

    if [[ -z "$session" ]]; then
        log_error "--session is required"
        return 1
    fi

    materialize_argument_graph "$session" "$force"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    materialize_cli "$@"
fi
