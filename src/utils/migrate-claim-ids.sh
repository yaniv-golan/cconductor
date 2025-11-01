#!/usr/bin/env bash
# Migrates claim identifiers inside AEG logs to deterministic sequential IDs.

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

migrate_usage() {
    cat <<'EOF'
Usage: migrate-claim-ids.sh --session <session_dir> [--dry-run] [--dedupe]
EOF
}

# shellcheck disable=SC1009,SC1046,SC1047,SC1072,SC1073
migrate_claim_ids() {
    local session_dir="$1"
    local dry_run="$2"
    local dedupe="$3"

    local log_path="${session_dir}/argument/aeg.log.jsonl"
    if [[ ! -f "$log_path" ]]; then
        log_error "No argument log found at $log_path"
        return 1
    fi

    local jq_filter
    # shellcheck disable=SC1009,SC1046,SC1047,SC1072,SC1073
    jq_filter=$(cat <<'JQ'
def pad4:
  (("0000" + (tostring)) | (.[-4:]));

def claim_entries:
  [ .[] | select(.event_type == "claim" and (.payload.claim_id // "") != "") | {id: .payload.claim_id, text: (.payload.text // "")} ];

def canonical($dedupe):
  if $dedupe == 1 then
    reduce (claim_entries[]) as $c (
      {by_text: {}, map: {}, order: []};
      if ($c.text | length) == 0 then
        if (.map[$c.id]? == null) then
          .order += [$c.id]
        else .
        end
        | .map[$c.id] = $c.id
      elif (.by_text[$c.text]? != null) then
        .map[$c.id] = .by_text[$c.text]
      else
        .by_text[$c.text] = $c.id
        | .order += [$c.id]
        | .map[$c.id] = $c.id
      end
    )
  else
    reduce (claim_entries[]) as $c (
      {map: {}, order: []};
      if (.map[$c.id]? == null) then
        .order += [$c.id]
      else .
      end
      | .map[$c.id] = $c.id
    )
  end
  | {map: .map, order: (.order | unique)};

canonical($dedupe) as $canon
| ($canon.order | unique) as $order
| (reduce range(0; ($order|length)) as $i ({}; .[$order[$i]] = ("clm-" + (($i + 1)|pad4)))) as $seq_map
| (reduce ($canon.map | to_entries[]) as $entry ({}; .[$entry.key] = ($seq_map[$entry.value] // $entry.value))) as $full_map
| {
    mapping: $full_map,
    events: (
      [ .[] |
        if .event_type == "claim" then
          (.payload.claim_id) as $old
          | .payload.claim_id = ($full_map[$old] // $old)
          | if (.payload.premises // null) != null then
              .payload.premises = (.payload.premises | map(if type == "string" then ($full_map[.] // .) else . end))
            else .
            end
        elif .event_type == "evidence" then
          .payload.claim_id = ($full_map[.payload.claim_id] // .payload.claim_id)
        elif .event_type == "contradiction" then
          .payload.attacker_claim_id = ($full_map[.payload.attacker_claim_id] // .payload.attacker_claim_id)
          | .payload.target_claim_id = ($full_map[.payload.target_claim_id] // .payload.target_claim_id)
        elif .event_type == "preference" then
          .payload.preferred_claim_id = ($full_map[.payload.preferred_claim_id] // .payload.preferred_claim_id)
          | .payload.dispreferred_claim_id = ($full_map[.payload.dispreferred_claim_id] // .payload.dispreferred_claim_id)
        elif .event_type == "retraction" then
          .payload.target_id = ($full_map[.payload.target_id] // .payload.target_id)
          | .payload.replacing_claim_id = ($full_map[.payload.replacing_claim_id] // .payload.replacing_claim_id)
        else .
        end
      ]
    )
  }
JQ
)

    local result_json
    result_json=$(jq -s --argjson dedupe "$dedupe" "$jq_filter" "$log_path")

    if [[ "$dry_run" == "1" ]]; then
        printf '%s\n' "$result_json" | jq '.mapping'
        return 0
    fi

    local tmp_log="${log_path}.tmp"
    printf '%s\n' "$result_json" | jq -c '.events[]' > "$tmp_log"
    mv "$tmp_log" "$log_path"

    materialize_argument_graph "$session_dir" 1
}

migrate_cli() {
    local session=""
    local dry_run=0
    local dedupe=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --session)
                session="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --dedupe)
                dedupe=1
                shift
                ;;
            --help|-h)
                migrate_usage
                return 0
                ;;
            *)
                log_error "Unknown argument: $1"
                migrate_usage
                return 1
                ;;
        esac
    done

    if [[ -z "$session" ]]; then
        log_error "--session is required"
        return 1
    fi

    migrate_claim_ids "$session" "$dry_run" "$dedupe"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    migrate_cli "$@"
fi

export -f migrate_claim_ids
