#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq program strings intentionally use single quotes for literal $vars
# Knowledge Graph Manager
# Manages the shared knowledge graph for adaptive research

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load debug utility if not already loaded
if ! declare -F debug >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/utils/debug.sh" 2>/dev/null || true
fi

debug "knowledge-graph.sh: Starting to source dependencies"

# Source shared-state for atomic operations
debug "knowledge-graph.sh: Sourcing shared-state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/shared-state.sh"
debug "knowledge-graph.sh: Sourcing json-parser.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils/json-parser.sh"
debug "knowledge-graph.sh: Sourcing validation.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils/validation.sh"
debug "knowledge-graph.sh: Sourcing event-logger.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils/event-logger.sh" || true
debug "knowledge-graph.sh: All dependencies sourced"

# Initialize a new knowledge graph
kg_init() {
    local session_dir="$1"
    local research_objective="$2"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "research_objective" "$research_objective" || return 1

    local kg_file="$session_dir/knowledge/knowledge-graph.json"

    # Use jq to safely construct JSON (prevents injection attacks)
    jq -n \
        --arg objective "$research_objective" \
        --arg started "$(get_timestamp)" \
        --arg updated "$(get_timestamp)" \
        '{
            schema_version: "1.0",
            research_objective: $objective,
            started_at: $started,
            last_updated: $updated,
            iteration: 0,
            entities: [],
            claims: [],
            relationships: [],
            citations: [],
            gaps: [],
            contradictions: [],
            promising_leads: [],
            confidence_scores: {
                overall: 0.0,
                by_category: {}
            },
            coverage: {
                aspects_identified: 0,
                aspects_well_covered: 0,
                aspects_partially_covered: 0,
                aspects_not_covered: 0
            },
            stats: {
                total_entities: 0,
                total_claims: 0,
                total_relationships: 0,
                total_citations: 0,
                total_gaps: 0,
                unresolved_gaps: 0,
                total_contradictions: 0,
                unresolved_contradictions: 0,
                total_leads: 0,
                explored_leads: 0,
                total_sources: 0
            }
        }' > "$kg_file"

    echo "$kg_file"
}

# Get knowledge graph path
kg_get_path() {
    local session_dir="$1"
    echo "$session_dir/knowledge/knowledge-graph.json"
}

# Recalculate stats.total_sources from all entities, claims, and citations
# Called after any mutation that can affect source lists
# Returns: 0 on success, 1 on error
kg_recalculate_source_stats() {
    local session_dir="$1"
    
    validate_session_dir "$session_dir" || return 1
    
    local kg_file
    kg_file=$(kg_get_path "$session_dir")
    
    # Single atomic update that counts unique sources across all collections
    # Deduplicates by: url|title|relevant_quote (for entities/claims) or url|title|excerpt (for citations)
    # Handles both string sources (URLs) and object sources (full metadata)
    atomic_json_update "$kg_file" \
        '.stats.total_sources = (
            [
                ((.entities // [])[]?.sources[]? |
                    if type == "string" then . else ((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // "")) end),
                ((.claims // [])[]?.sources[]? |
                    if type == "string" then . else ((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // "")) end),
                ((.citations // [])[]? |
                    ((.url // "") + "|" + (.title // "") + "|" + (.excerpt // "")))
            ]
            | map(select(. != "")) | unique | length
        )'
}

# Read entire knowledge graph
kg_read() {
    local session_dir="$1"
    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    if [ ! -f "$kg_file" ]; then
        echo "Error: Knowledge graph not found: $kg_file" >&2
        return 1
    fi

    atomic_read "$kg_file"
}

# Update iteration number
kg_increment_iteration() {
    local session_dir="$1"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Single quotes intentional - this is a jq expression with literal $date
    # shellcheck disable=SC2016
    atomic_json_update "$kg_file" \
        --arg date "$(get_timestamp)" \
        '.iteration += 1 | .last_updated = $date'
}

# Add entity
kg_add_entity() {
    local session_dir="$1"
    local entity_json="$2"  # JSON object

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "entity_json" "$entity_json" || return 1
    validate_json_field "$entity_json" "name" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Check if entity already exists (by name) - read-only check
    local entity_name
    entity_name=$(echo "$entity_json" | jq -r '.name')
    local exists
    exists=$(jq --arg name "$entity_name" \
                     '.entities[] | select(.name == $name) | .id' \
                     "$kg_file" 2>/dev/null | head -1)

    local entity_id=""
    if [ -n "$exists" ]; then
        # Update existing entity using atomic operation
        atomic_json_update "$kg_file" \
            --argjson entity "$entity_json" \
            --arg name "$entity_name" \
            --arg date "$(get_timestamp)" \
            '(.entities[] | select(.name == $name)) |= (. + $entity + {last_updated: $date}) |
             .last_updated = $date'
    else
        # Add new entity using atomic operation
        entity_id="e$(jq '.stats.total_entities' "$kg_file" 2>/dev/null || echo "0")"
        atomic_json_update "$kg_file" \
            --argjson entity "$entity_json" \
            --arg id "$entity_id" \
            --arg date "$(get_timestamp)" \
            '.entities += [($entity + {id: $id, added_at: $date})] |
             .stats.total_entities += 1 |
             .last_updated = $date'
    fi
    
    # Recalculate source stats after entity mutation
    kg_recalculate_source_stats "$session_dir" || true
    
    # Phase 2: Log entity added (only for new entities)
    if [ -z "$exists" ] && command -v log_entity_added &>/dev/null; then
        log_entity_added "$session_dir" "${entity_id:-unknown}" "$entity_name" || true
    fi
}

# Add claim
kg_add_claim() {
    local session_dir="$1"
    local claim_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "claim_json" "$claim_json" || return 1
    validate_json_field "$claim_json" "statement" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Check for existing similar claim - read operation
    local statement
    statement=$(echo "$claim_json" | jq -r '.statement // empty')
    local existing_id=""
    if [[ -n "$statement" ]]; then
        existing_id=$(python3 - "$kg_file" "$statement" <<'PY'
import json, sys, re
kg_path, incoming_stmt = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(kg_path))
except Exception:
    print("")
    sys.exit(0)

def tokenize(text: str) -> set[str]:
    tokens = {tok for tok in re.split(r'[^a-z0-9]+', text.lower()) if len(tok) >= 4}
    return tokens

incoming_tokens = tokenize(incoming_stmt)
if not incoming_tokens:
    print("")
    sys.exit(0)

best_id = ""
best_score = 0.0
best_id_value = None
for claim in data.get("claims", []):
    existing_stmt = claim.get("statement") or ""
    if not existing_stmt:
        continue
    tokens = tokenize(existing_stmt)
    if not tokens:
        continue
    intersection = incoming_tokens & tokens
    if not intersection:
        continue
    union = incoming_tokens | tokens
    jaccard = len(intersection) / len(union)
    coverage_incoming = len(intersection) / len(incoming_tokens)
    coverage_existing = len(intersection) / len(tokens)
    if jaccard >= 0.45 or coverage_incoming >= 0.7 or coverage_existing >= 0.7:
        score = max(jaccard, coverage_incoming, coverage_existing)
        claim_id = claim.get("id") or ""
        try:
            claim_numeric = int(re.sub(r'[^0-9]', '', claim_id) or "0")
        except Exception:
            claim_numeric = 0
        if (score > best_score) or (abs(score - best_score) < 1e-6 and (best_id_value is None or claim_numeric < best_id_value)):
            best_score = score
            best_id = claim_id
            best_id_value = claim_numeric

print(best_id)
PY
)
        existing_id=${existing_id//$'\r'/}
        existing_id=${existing_id//$'\n'/}
        if [[ -z "$existing_id" ]]; then
            existing_id=$(jq -r --arg stmt "$statement" '.claims[]? | select(.statement == $stmt) | .id' "$kg_file" 2>/dev/null | head -n 1)
        fi
    fi

    local timestamp
    timestamp="$(get_timestamp)"

    if [[ -n "$existing_id" ]]; then
        # Update existing claim using atomic operation
        atomic_json_update "$kg_file" \
            --arg id "$existing_id" \
            --argjson claim "$claim_json" \
            --arg date "$timestamp" \
            '
            .claims = (.claims | map(
              if .id == $id then
                ( . as $old |
                  $claim as $incoming |
                  (
                    $old + ($incoming | del(.id, .added_at, .updated_at))
                  )
                  | .sources = (
                      (
                        (($old.sources // []) + ($incoming.sources // []))
                        | map(select(. != null))
                        | unique_by((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // ""))
                      )
                    )
                  | .related_entities = (
                      (
                        (($old.related_entities // []) + ($incoming.related_entities // []))
                        | map(select(. != null))
                        | unique
                      )
                    )
                  | .confidence = (
                      ([
                          ($old.confidence // null),
                          ($incoming.confidence // null)
                        ]
                        | map(select(. != null))
                        | if length > 0 then max else ($old.confidence // 0) end)
                    )
                  | .evidence_quality = ($incoming.evidence_quality // $old.evidence_quality)
                  | .verification_type = ($incoming.verification_type // $old.verification_type)
                  | .verified = ((($old.verified // false) or ($incoming.verified // false)))
                  | .source_context = (
                      if ($incoming.source_context // null) != null
                      then $incoming.source_context
                      else $old.source_context
                      end
                    )
                  | .updated_at = $date
                )
             else .
             end
            )) |
            .last_updated = $date
            '
        # Recalculate source stats after claim mutation
        kg_recalculate_source_stats "$session_dir" || true
        kg_merge_similar_claims_locked "$session_dir" "$existing_id" "$statement" "$timestamp" || true
        return 0
    fi

    # Add new claim using atomic operation
    local claim_id
    claim_id="c$(jq '.stats.total_claims' "$kg_file" 2>/dev/null || echo "0")"

    atomic_json_update "$kg_file" \
        --argjson claim "$claim_json" \
        --arg id "$claim_id" \
        --arg date "$timestamp" \
        '.claims += [($claim + {id: $id, added_at: $date, verified: ($claim.verified // false)})] |
         .stats.total_claims += 1 |
         .last_updated = $date'
    
    # Recalculate source stats after claim mutation
    kg_recalculate_source_stats "$session_dir" || true
    
    # Phase 2: Log claim added
    if command -v log_claim_added &>/dev/null; then
        local confidence
        confidence=$(echo "$claim_json" | jq -r '.confidence // 0.5')
        log_claim_added "$session_dir" "$claim_id" "$confidence" || true
    fi
}

# Merge similar claims into an existing claim (expects caller to hold KG lock)
kg_merge_similar_claims_locked() {
    # TODO: Implement deduplication of similar claims if needed.
    # Current remediation flow already updates claims in place, so no-op.
    :
}

# Add relationship
kg_add_relationship() {
    local session_dir="$1"
    local relationship_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "relationship_json" "$relationship_json" || return 1
    validate_json_field "$relationship_json" "from" "string" || return 1
    validate_json_field "$relationship_json" "to" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Pre-compute ID
    local rel_id
    rel_id="r$(jq '.stats.total_relationships' "$kg_file" 2>/dev/null || echo "0")"

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson rel "$relationship_json" \
        --arg id "$rel_id" \
        --arg date "$(get_timestamp)" \
        '.relationships += [($rel + {id: $id, added_at: $date})] |
         .stats.total_relationships += 1 |
         .last_updated = $date'
}

# Add gap
kg_add_gap() {
    local session_dir="$1"
    local gap_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "gap_json" "$gap_json" || return 1
    validate_json_field "$gap_json" "description" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Pre-compute ID and iteration
    local gap_id
    gap_id="g$(jq '.stats.total_gaps' "$kg_file" 2>/dev/null || echo "0")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file" 2>/dev/null || echo "0")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson gap "$gap_json" \
        --arg id "$gap_id" \
        --arg iter "$iteration" \
        --arg date "$(get_timestamp)" \
        '.gaps += [($gap + {id: $id, detected_at_iteration: ($iter | tonumber), status: "pending", added_at: $date})] |
         .stats.total_gaps += 1 |
         .stats.unresolved_gaps += 1 |
         .last_updated = $date'
    
    # Phase 2: Log gap detected
    if command -v log_gap_detected &>/dev/null; then
        local priority
        priority=$(echo "$gap_json" | jq -r '.priority // "medium"')
        log_gap_detected "$session_dir" "$gap_id" "$priority" || true
    fi
}

# Update gap status
kg_update_gap_status() {
    local session_dir="$1"
    local gap_id="$2"
    local status="$3"  # pending, investigating, resolved

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_required "gap_id" "$gap_id" || return 1
    validate_enum "status" "$status" "pending" "investigating" "resolved" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Check if gap was unresolved - read operation
    local was_unresolved
    was_unresolved=$(jq --arg id "$gap_id" \
                              '.gaps[] | select(.id == $id and .status != "resolved") | .id' \
                              "$kg_file" 2>/dev/null | wc -l | xargs)

    # Use atomic_json_update with conditional logic
    if [ "$status" = "resolved" ] && [ "$was_unresolved" -gt 0 ]; then
        atomic_json_update "$kg_file" \
            --arg id "$gap_id" \
            --arg status "$status" \
            --arg date "$(get_timestamp)" \
            '(.gaps[] | select(.id == $id)) |= (. + {status: $status, updated_at: $date}) |
             .stats.unresolved_gaps -= 1 |
             .last_updated = $date'
    else
        atomic_json_update "$kg_file" \
            --arg id "$gap_id" \
            --arg status "$status" \
            --arg date "$(get_timestamp)" \
            '(.gaps[] | select(.id == $id)) |= (. + {status: $status, updated_at: $date}) |
             .last_updated = $date'
    fi
}

# Add contradiction
kg_add_contradiction() {
    local session_dir="$1"
    local contradiction_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "contradiction_json" "$contradiction_json" || return 1
    validate_json_field "$contradiction_json" "description" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Pre-compute ID and iteration
    local con_id
    con_id="con$(jq '.stats.total_contradictions' "$kg_file" 2>/dev/null || echo "0")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file" 2>/dev/null || echo "0")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson con "$contradiction_json" \
        --arg id "$con_id" \
        --arg iter "$iteration" \
        --arg date "$(get_timestamp)" \
        '.contradictions += [($con + {id: $id, detected_at_iteration: ($iter | tonumber), status: "unresolved", added_at: $date})] |
         .stats.total_contradictions += 1 |
         .stats.unresolved_contradictions += 1 |
         .last_updated = $date'
}

# Resolve contradiction
kg_resolve_contradiction() {
    local session_dir="$1"
    local con_id="$2"
    local resolution="$3"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_required "con_id" "$con_id" || return 1
    validate_required "resolution" "$resolution" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --arg id "$con_id" \
        --arg resolution "$resolution" \
        --arg date "$(get_timestamp)" \
        '(.contradictions[] | select(.id == $id)) |= (. + {status: "resolved", resolution: $resolution, resolved_at: $date}) |
         .stats.unresolved_contradictions -= 1 |
         .last_updated = $date'
}

# Add promising lead
kg_add_lead() {
    local session_dir="$1"
    local lead_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "lead_json" "$lead_json" || return 1
    validate_json_field "$lead_json" "description" "string" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Pre-compute ID and iteration
    local lead_id
    lead_id="l$(jq '.stats.total_leads' "$kg_file" 2>/dev/null || echo "0")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file" 2>/dev/null || echo "0")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson lead "$lead_json" \
        --arg id "$lead_id" \
        --arg iter "$iteration" \
        --arg date "$(get_timestamp)" \
        '.promising_leads += [($lead + {id: $id, detected_at_iteration: ($iter | tonumber), status: "pending", added_at: $date})] |
         .stats.total_leads += 1 |
         .last_updated = $date'
}

# Mark lead as explored
kg_mark_lead_explored() {
    local session_dir="$1"
    local lead_id="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_required "lead_id" "$lead_id" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --arg id "$lead_id" \
        --arg date "$(get_timestamp)" \
        '(.promising_leads[] | select(.id == $id)) |= (. + {status: "explored", explored_at: $date}) |
         .stats.explored_leads += 1 |
         .last_updated = $date'
}

# Update confidence scores
kg_update_confidence() {
    local session_dir="$1"
    local confidence_json="$2"  # {overall: 0.85, by_category: {...}}

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "confidence_json" "$confidence_json" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson conf "$confidence_json" \
        --arg date "$(get_timestamp)" \
        '.confidence_scores = $conf | .last_updated = $date'
}

# Update coverage
kg_update_coverage() {
    local session_dir="$1"
    local coverage_json="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_json "coverage_json" "$coverage_json" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    # Use atomic_json_update for thread-safe operation
    atomic_json_update "$kg_file" \
        --argjson cov "$coverage_json" \
        --arg date "$(get_timestamp)" \
        '.coverage = $cov | .last_updated = $date'
}

# Get high-priority gaps
kg_get_high_priority_gaps() {
    local session_dir="$1"
    local min_priority="${2:-7}"
    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    jq --arg min "$min_priority" \
       '.gaps | map(select(.status != "resolved" and (.priority | tonumber) >= ($min | tonumber)))' \
       "$kg_file"
}

# Get unresolved contradictions
kg_get_unresolved_contradictions() {
    local session_dir="$1"
    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    jq '.contradictions | map(select(.status == "unresolved"))' "$kg_file"
}

# Get unexplored leads
kg_get_unexplored_leads() {
    local session_dir="$1"
    local min_priority="${2:-6}"
    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    jq --arg min "$min_priority" \
       '.promising_leads | map(select(.status == "pending" and (.priority | tonumber) >= ($min | tonumber)))' \
       "$kg_file"
}

# Get summary statistics
kg_get_summary() {
    local session_dir="$1"
    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    jq '{
        iteration: .iteration,
        confidence: .confidence_scores.overall,
        entities: .stats.total_entities,
        claims: .stats.total_claims,
        relationships: .stats.total_relationships,
        citations: .stats.total_citations,
        gaps: .stats.total_gaps,
        unresolved_gaps: .stats.unresolved_gaps,
        contradictions: .stats.total_contradictions,
        unresolved_contradictions: .stats.unresolved_contradictions,
        leads: .stats.total_leads,
        unexplored_leads: (.stats.total_leads - .stats.explored_leads),
        coverage: .coverage
    }' "$kg_file"
}

# Bulk update from coordinator output
kg_bulk_update() {
    local session_dir="$1"
    local coordinator_output_file="$2"

    # Validate inputs
    validate_session_dir "$session_dir" || return 1
    validate_file "coordinator_output_file" "$coordinator_output_file" || return 1

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    lock_acquire "$kg_file" 60 || {
        echo "Error: Failed to acquire lock for bulk update" >&2
        return 1
    }

    local output
    output=$(cat "$coordinator_output_file")

    # Validate JSON content
    if ! echo "$output" | jq '.' >/dev/null 2>&1; then
        lock_release "$kg_file"
        echo "Error: coordinator_output_file contains invalid JSON" >&2
        return 1
    fi
    local date
    date="$(get_timestamp)"
    local iteration
    iteration=$(jq -r '.iteration // 0' "$kg_file")

    # Single atomic jq operation that processes ALL updates at once
    jq --argjson new_data "$output" \
       --arg date "$date" \
       --argjson iter "$iteration" \
       '
       # Get existing entity names for duplicate detection
       (.entities | map(.name)) as $existing_names |
       
       # Get max existing entity ID to prevent collisions
       ([.entities[] | .id | ltrimstr("e") | tonumber] | max // -1) as $max_entity_id |

       # Add new entities (avoid duplicates by name)
       .entities += (
           ($new_data.knowledge_graph_updates.entities_discovered // []) |
           map(select(.name as $n | $existing_names | contains([$n]) | not)) |
           to_entries |
           map(.value + {
               id: ("e" + (($max_entity_id + 1 + .key) | tostring)),
               added_at: $date
           })
       ) |

       # Get max existing claim ID to prevent collisions
       ([.claims[] | .id | ltrimstr("c") | tonumber] | max // -1) as $max_claim_id |
       
       # Add new claims with generated IDs
       .claims += (
           ($new_data.knowledge_graph_updates.claims // []) |
           to_entries |
           map(.value + {
               id: ("c" + (($max_claim_id + 1 + .key) | tostring)),
               added_at: $date,
               verified: false
           })
       ) |

       # Get max existing relationship ID to prevent collisions
       ([.relationships[] | .id | ltrimstr("r") | tonumber] | max // -1) as $max_rel_id |
       
       # Add new relationships with generated IDs
       .relationships += (
           ($new_data.knowledge_graph_updates.relationships_discovered // []) |
           to_entries |
           map(.value + {
               id: ("r" + (($max_rel_id + 1 + .key) | tostring)),
               added_at: $date
           })
       ) |

       # Get max existing gap ID to prevent collisions
       ([.gaps[] | .id | ltrimstr("g") | tonumber] | max // -1) as $max_gap_id |
       
       # Add new gaps
       .gaps += (
           ($new_data.knowledge_graph_updates.gaps_detected // []) |
           to_entries |
           map(.value + {
               id: ("g" + (($max_gap_id + 1 + .key) | tostring)),
               detected_at_iteration: $iter,
               status: "pending",
               added_at: $date
           })
       ) |

       # Get max existing contradiction ID to prevent collisions
       ([.contradictions[] | .id | ltrimstr("con") | tonumber] | max // -1) as $max_con_id |
       
       # Add new contradictions
       .contradictions += (
           ($new_data.knowledge_graph_updates.contradictions_detected // []) |
           to_entries |
           map(.value + {
               id: ("con" + (($max_con_id + 1 + .key) | tostring)),
               detected_at_iteration: $iter,
               status: "unresolved",
               added_at: $date
           })
       ) |

       # Get max existing lead ID to prevent collisions
       ([.promising_leads[] | .id | ltrimstr("l") | tonumber] | max // -1) as $max_lead_id |
       
       # Add new leads
       .promising_leads += (
           ($new_data.knowledge_graph_updates.leads_identified // []) |
           to_entries |
           map(.value + {
               id: ("l" + (($max_lead_id + 1 + .key) | tostring)),
               detected_at_iteration: $iter,
               status: "pending",
               added_at: $date
           })
       ) |

       # Extract citations from sources in entities and claims
       (
           # Collect all unique sources from entities
           [($new_data.knowledge_graph_updates.entities_discovered // [])[] | 
            .sources[]? | 
            if type == "string" then {url: .} 
            elif type == "object" then . 
            else empty end
           ] +
           # Collect all unique sources from claims
           [($new_data.knowledge_graph_updates.claims // [])[] | 
            .sources[]? | 
            if type == "string" then {url: .}
            elif type == "object" and .url then .
            else empty end
           ] +
           # Also include explicit citations if provided
           ($new_data.citations // [])
       ) as $all_sources |
       
       # Add new citations (deduplicate by DOI or URL)
       (.citations | map(.doi // .url)) as $existing_identifiers |
       # Get max existing citation ID (extract number from cite_N format)
       ([.citations[] | .id | ltrimstr("cite_") | tonumber] | max // -1) as $max_cite_id |
       
       .citations += (
           $all_sources |
           map(select((.doi // .url) as $id | $existing_identifiers | contains([$id]) | not)) |
           unique_by(.doi // .url) |
           to_entries |
           map(.value + {
               id: ("cite_" + (($max_cite_id + 1 + .key) | tostring)),
               added_at: $date,
               cited_by_claims: [],
               type: (if .doi then "doi" elif .url then "url" else "unknown" end)
           })
       ) |

       # Update confidence if provided
       .confidence_scores = (
           if ($new_data.knowledge_graph_updates.confidence_scores != null)
           then $new_data.knowledge_graph_updates.confidence_scores
           else .confidence_scores
           end
       ) |

       # Update coverage if provided
       .coverage = (
           if ($new_data.knowledge_graph_updates.coverage != null)
           then $new_data.knowledge_graph_updates.coverage
           else .coverage
           end
       ) |

       # Recalculate all stats
       .stats.total_entities = (.entities | length) |
       .stats.total_claims = (.claims | length) |
       .stats.total_relationships = (.relationships | length) |
       .stats.total_citations = (.citations | length) |
       .stats.total_gaps = (.gaps | length) |
       .stats.unresolved_gaps = ([.gaps[] | select(.status != "resolved")] | length) |
       .stats.total_contradictions = (.contradictions | length) |
       .stats.unresolved_contradictions = ([.contradictions[] | select(.status == "unresolved")] | length) |
       .stats.total_leads = (.promising_leads | length) |
       .stats.explored_leads = ([.promising_leads[] | select(.status == "explored")] | length) |
       .stats.total_sources = (
           [
               ((.entities // [])[]?.sources[]? |
                   if type == "string" then . else ((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // "")) end),
               ((.claims // [])[]?.sources[]? |
                   if type == "string" then . else ((.url // "") + "|" + (.title // "") + "|" + (.relevant_quote // "")) end),
               ((.citations // [])[]? |
                   ((.url // "") + "|" + (.title // "") + "|" + (.excerpt // "")))
           ]
           | map(select(. != "")) | unique | length
       ) |

       # Update timestamp
       .last_updated = $date
       ' "$kg_file" > "${kg_file}.tmp"

    local jq_exit=$?

    if [ $jq_exit -eq 0 ]; then
        mv "${kg_file}.tmp" "$kg_file"
        lock_release "$kg_file"
        return 0
    else
        rm -f "${kg_file}.tmp"
        lock_release "$kg_file"
        echo "Error: Bulk update failed" >&2
        return 1
    fi
}

# Summarize existing knowledge for a specific source URL
kg_find_source_by_url() {
    local session_dir="$1"
    local url="$2"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    if [ ! -f "$kg_file" ]; then
        echo ""
        return 0
    fi

    local kg_content
    if ! kg_content=$(atomic_read "$kg_file"); then
        echo ""
        return 0
    fi

    local summary
    summary=$(echo "$kg_content" | jq -r --arg url "$url" '
        [
            (.claims // [] | map(select((.sources // []) | map(.url) | index($url))) |
                map("- Claim " + ((.id // "unknown")) + ": " + (.statement // ""))),
            (.entities // [] | map(select((.sources // []) | map(.url) | index($url))) |
                map("- Entity " + (.name // "unknown") + " (" + (.type // "entity") + ")"))
        ]
        | add
        | unique
        | if length == 0 then empty else join("\n") end
    ' 2>/dev/null || echo "")

    echo "$summary"
}

kg_merge_evidence_claims() {
    local session_dir="$1"
    local evidence_file="$session_dir/evidence/evidence.json"

    if [ ! -f "$evidence_file" ]; then
        return 0
    fi

    local kg_file
    kg_file=$(kg_get_path "$session_dir")

    python3 - "$kg_file" "$evidence_file" <<'PY'
import json, re, sys
from datetime import datetime, timezone
from pathlib import Path

kg_path = Path(sys.argv[1])
evidence_path = Path(sys.argv[2])

try:
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

claims_data = evidence.get("claims") or []
sources_data = evidence.get("sources") or []
if not claims_data or not sources_data:
    sys.exit(0)

try:
    kg = json.loads(kg_path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

now = datetime.now(timezone.utc).isoformat()

kg.setdefault("claims", [])
kg.setdefault("citations", [])
stats = kg.setdefault("stats", {})
stats.setdefault("total_claims", len(kg["claims"]))
stats.setdefault("total_citations", len(kg["citations"]))

sources_by_id = {s.get("id"): s for s in sources_data if isinstance(s, dict) and s.get("id")}
if not sources_by_id:
    sys.exit(0)

def tokenize(text: str) -> set[str]:
    return {tok for tok in re.split(r"[^a-z0-9]+", (text or "").lower()) if len(tok) >= 4}

def source_key(src: dict) -> tuple[str, str, str]:
    return (
        (src.get("url") or "").strip(),
        (src.get("deep_link") or "").strip(),
        (src.get("quote") or "").strip(),
    )

def claim_source_key(payload: dict) -> tuple[str, str, str]:
    return (
        (payload.get("url") or "").strip(),
        (payload.get("deep_link") or "").strip(),
        (payload.get("relevant_quote") or "").strip(),
    )

def convert_source_for_claim(src: dict) -> dict:
    payload = {
        "url": src.get("url"),
        "title": src.get("title"),
        "relevant_quote": src.get("quote"),
        "deep_link": src.get("deep_link"),
        "retrieved_at": src.get("retrieved_at"),
        "paragraph_index": src.get("paragraph_index"),
        "char_span": src.get("char_span"),
    }
    return {k: v for k, v in payload.items() if v is not None}

def build_citation(src: dict) -> dict:
    payload = {
        "url": src.get("url"),
        "title": src.get("title"),
        "quote": src.get("quote"),
        "deep_link": src.get("deep_link"),
        "retrieved_at": src.get("retrieved_at"),
        "paragraph_index": src.get("paragraph_index"),
        "char_span": src.get("char_span"),
        "type": "url",
    }
    return {k: v for k, v in payload.items() if v is not None}

existing_claims = kg["claims"]

def claim_numeric_id(claim_id: str) -> int:
    try:
        return int(re.sub(r"[^0-9]", "", claim_id) or "0")
    except ValueError:
        return 0

def find_best_claim(statement: str):
    tokens = tokenize(statement)
    if not tokens:
        return None
    best = None
    best_score = 0.0
    best_numeric = None
    for claim in existing_claims:
        existing_statement = claim.get("statement") or claim.get("claim") or ""
        existing_tokens = tokenize(existing_statement)
        if not existing_tokens:
            continue
        intersection = tokens & existing_tokens
        if not intersection:
            continue
        union = tokens | existing_tokens
        jaccard = len(intersection) / len(union)
        coverage_incoming = len(intersection) / len(tokens)
        coverage_existing = len(intersection) / len(existing_tokens)
        if jaccard >= 0.45 or coverage_incoming >= 0.7 or coverage_existing >= 0.7:
            score = max(jaccard, coverage_incoming, coverage_existing)
            cid = claim.get("id") or ""
            numeric = claim_numeric_id(cid)
            if score > best_score or (abs(score - best_score) < 1e-6 and (best_numeric is None or numeric < best_numeric)):
                best = claim
                best_score = score
                best_numeric = numeric
    return best

next_claim_id = max((claim_numeric_id(c.get("id", "")) for c in existing_claims), default=-1) + 1

claims_by_citation = {}
citation_inputs = {}
source_to_citation_map = {}
modified = False

for evidence_claim in claims_data:
    statement = evidence_claim.get("claim_text")
    if not statement:
        continue

    source_ids = evidence_claim.get("sources") or []
    claim_sources = []
    source_keys = []
    source_originals = []
    for source_id in source_ids:
        src = sources_by_id.get(source_id)
        if not src:
            continue
        converted = convert_source_for_claim(src)
        if not converted.get("url"):
            continue
        key = source_key(src)
        claim_sources.append(converted)
        source_keys.append(key)
        source_originals.append(src)
    if not claim_sources:
        continue

    # Build support entry - will translate source_ids to citation IDs after citations are created
    support_entry = {
        "marker": evidence_claim.get("marker"),
        "why_supported": evidence_claim.get("why_supported"),
        "source_ids": [sid for sid in source_ids if sid in sources_by_id],
    }
    support_entry = {k: v for k, v in support_entry.items() if v}

    match = find_best_claim(statement)
    if match is not None:
        claim_id = match.get("id") or ""
        existing_sources = match.setdefault("sources", [])
        source_map = {claim_source_key(s): s for s in existing_sources if isinstance(s, dict)}
        for payload, key in zip(claim_sources, source_keys):
            existing = source_map.get(key)
            if existing:
                existing.update({k: v for k, v in payload.items() if v is not None})
            else:
                existing_sources.append(payload)
                source_map[key] = payload
            if claim_id:
                claims_by_citation.setdefault(key, set()).add(claim_id)
        if support_entry:
            support_list = match.setdefault("evidence_support", [])
            if support_entry not in support_list:
                support_list.append(support_entry)
        if evidence_claim.get("why_supported"):
            match["why_supported"] = evidence_claim["why_supported"]
        if evidence_claim.get("confidence") is not None:
            try:
                match["confidence"] = max(float(evidence_claim["confidence"]), float(match.get("confidence", 0.0)))
            except Exception:
                match["confidence"] = max(0.0, float(match.get("confidence", 0.0)))
        else:
            match["confidence"] = max(0.65, float(match.get("confidence", 0.0)))
        match["updated_at"] = now
        modified = True
    else:
        claim_id = f"c{next_claim_id}"
        next_claim_id += 1
        new_claim = {
            "id": claim_id,
            "statement": statement,
            "sources": claim_sources,
            "confidence": float(evidence_claim.get("confidence", 0.7)),
            "added_at": now,
            "verified": False,
        }
        if evidence_claim.get("why_supported"):
            new_claim["why_supported"] = evidence_claim["why_supported"]
        if evidence_claim.get("marker"):
            new_claim["evidence_marker"] = evidence_claim["marker"]
        if support_entry:
            new_claim["evidence_support"] = [support_entry]
        existing_claims.append(new_claim)
        for key in source_keys:
            if key[0]:
                claims_by_citation.setdefault(key, set()).add(claim_id)
        modified = True

    for key, src in zip(source_keys, source_originals):
        if not key[0]:
            continue
        current = citation_inputs.get(key)
        if not current or len([v for v in current.values() if v]) < len([v for v in src.values() if v]):
            citation_inputs[key] = src

if not modified:
    sys.exit(0)

stats["total_claims"] = len(existing_claims)

existing_citations = kg.get("citations", [])
existing_map = {}
order_keys = []
max_cite_id = -1

for citation in existing_citations:
    key = source_key(citation)
    existing_map[key] = citation
    order_keys.append(key)
    match = re.search(r'(\d+)$', str(citation.get("id") or ""))
    if match:
        try:
            max_cite_id = max(max_cite_id, int(match.group(1)))
        except ValueError:
            pass
    claims_list = citation.get("cited_by_claims")
    if isinstance(claims_list, list):
        citation["cited_by_claims"] = sorted({cid for cid in claims_list if cid})

for key, src in citation_inputs.items():
    claims_for_key = sorted(claims_by_citation.get(key, []))
    if key in existing_map:
        citation = existing_map[key]
        updated = build_citation(src)
        updated["id"] = citation.get("id")
        updated["added_at"] = citation.get("added_at", now)
        existing_claim_refs = citation.get("cited_by_claims") or []
        combined = sorted(set(existing_claim_refs) | set(claims_for_key))
        if combined:
            updated["cited_by_claims"] = combined
        existing_map[key] = updated
        # Map all source_ids for this key to this citation ID
        for sid, s in sources_by_id.items():
            if source_key(s) == key:
                source_to_citation_map[sid] = citation.get("id")
    else:
        max_cite_id += 1
        citation_id = f"cite_{max_cite_id}"
        new_citation = build_citation(src)
        new_citation["id"] = citation_id
        new_citation["added_at"] = now
        if claims_for_key:
            new_citation["cited_by_claims"] = claims_for_key
        existing_map[key] = new_citation
        order_keys.append(key)
        # Map all source_ids for this key to this citation ID
        for sid, s in sources_by_id.items():
            if source_key(s) == key:
                source_to_citation_map[sid] = citation_id

updated_citations = []
seen = set()
for key in order_keys:
    if key in seen:
        continue
    citation = existing_map.get(key)
    if citation:
        updated_citations.append(citation)
        seen.add(key)

kg["citations"] = updated_citations
stats["total_citations"] = len(updated_citations)

# Now translate source_ids in evidence_support to citation IDs
for claim in existing_claims:
    evidence_support = claim.get("evidence_support", [])
    for support in evidence_support:
        if "source_ids" in support:
            translated_ids = [source_to_citation_map.get(sid, sid) for sid in support["source_ids"]]
            support["source_ids"] = translated_ids

kg["last_updated"] = now

kg_path.write_text(json.dumps(kg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# Shell out to recalculate source stats using the canonical helper
# This keeps the dedupe logic in one place (jq) rather than reimplementing in Python
import subprocess
session_dir = str(kg_path.parent.parent)
script_dir = str(kg_path.parent.parent.parent / "src")
subprocess.run(
    ["bash", "-c", f"source '{script_dir}/knowledge-graph.sh' && kg_recalculate_source_stats '{session_dir}'"],
    capture_output=True,
    check=False
)
PY
}

# Export functions
export -f kg_init
export -f kg_get_path
export -f kg_recalculate_source_stats
export -f kg_read
export -f kg_increment_iteration
export -f kg_add_entity
export -f kg_add_claim
export -f kg_add_relationship
export -f kg_add_gap
export -f kg_update_gap_status
export -f kg_add_contradiction
export -f kg_resolve_contradiction
export -f kg_add_lead
export -f kg_mark_lead_explored
export -f kg_update_confidence
export -f kg_update_coverage
export -f kg_get_high_priority_gaps
export -f kg_get_unresolved_contradictions
export -f kg_get_unexplored_leads
export -f kg_get_summary
export -f kg_bulk_update
export -f kg_find_source_by_url
export -f kg_merge_evidence_claims

# Integrate agent findings into knowledge graph
# Usage: kg_integrate_agent_output <session_dir> <agent_output_file>
# Returns: 0 on success, 1 if no findings found or integration failed
kg_integrate_agent_output() {
    local session_dir="$1"
    local agent_output_file="$2"
    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    
    if [ ! -f "$kg_file" ]; then
        echo "Error: Knowledge graph not found at $kg_file" >&2
        return 1
    fi
    
    # Backup knowledge graph before any writes
    if [ -f "$kg_file" ]; then
        cp "$kg_file" "${kg_file}.backup" 2>/dev/null || true
        local backup_path="${kg_file}.backup"
        # Remove backup automatically on successful return
        trap 'status=$?; if [ $status -eq 0 ]; then rm -f -- "$backup_path" 2>/dev/null || true; fi' RETURN
    fi
    
    # Tier 0: Extract structured JSON directly from agent output using json-parser.sh
    # This handles agents that output {entities_discovered, claims, ...} directly,
    # including markdown-wrapped JSON, prose before/after, etc.
    local agent_data
    agent_data=$(extract_json_from_agent_output "$agent_output_file" false 2>/dev/null || echo "")
    
    if [[ -n "$agent_data" ]]; then
        # Check if data has entities_discovered/claims
        local has_structured_data
        has_structured_data=$(echo "$agent_data" | jq -e 'has("entities_discovered") or has("claims")' >/dev/null 2>&1 && echo "true" || echo "false")
        
        # If we found structured data, integrate it
        if [[ "$has_structured_data" == "true" ]]; then
            local entity_count=0
            local claim_count=0
            
            # Extract entities
            local entities
            entities=$(echo "$agent_data" | jq -c '.entities_discovered // []' 2>/dev/null)
            entity_count=$(echo "$entities" | jq 'length' 2>/dev/null || echo "0")
            
            # Extract claims
            local claims
            claims=$(echo "$agent_data" | jq -c '.claims // []' 2>/dev/null)
            claim_count=$(echo "$claims" | jq 'length' 2>/dev/null || echo "0")
            
            # If we have data, integrate it
            if [[ "$entity_count" -gt 0 ]] || [[ "$claim_count" -gt 0 ]]; then
                echo "  Found $entity_count entities, $claim_count claims in agent output" >&2
                
                local integrated=0
                
                # Add entities to KG
                if [[ "$entity_count" -gt 0 ]]; then
                    echo "$entities" | jq -c '.[]' | while IFS= read -r entity; do
                        local entity_name
                        entity_name=$(echo "$entity" | jq -r '.name // empty')
                        if [[ -n "$entity_name" ]]; then
                            kg_add_entity "$session_dir" "$entity" >/dev/null 2>&1 && integrated=$((integrated + 1))
                        fi
                    done
                fi
                
                # Add claims to KG
                if [[ "$claim_count" -gt 0 ]]; then
                    echo "$claims" | jq -c '.[]' | while IFS= read -r claim; do
                        local claim_text
                        claim_text=$(echo "$claim" | jq -r '.statement // .claim // empty')
                        if [[ -n "$claim_text" ]]; then
                            kg_add_claim "$session_dir" "$claim" >/dev/null 2>&1 && integrated=$((integrated + 1))
                        fi
                    done
                fi
                
                kg_merge_evidence_claims "$session_dir" >/dev/null 2>&1 || true

                echo "  ✓ Integrated structured findings into knowledge graph" >&2
                return 0
            fi
        fi
    fi
    
    # Tier 1: Extract findings files list from agent output manifest
    # Try multiple extraction paths to be resilient to output variations
    local findings_files=""
    
    # Tier 1a: Try root level .findings_files[] (legacy/direct format)
    findings_files=$(jq -r '.findings_files[]? // empty' "$agent_output_file" 2>/dev/null)
    
    # Tier 1b: Try parsing .result as JSON string, then extract findings_files
    if [ -z "$findings_files" ]; then
        findings_files=$(jq -r '.result // empty' "$agent_output_file" 2>/dev/null | \
                        jq -r '.findings_files[]? // empty' 2>/dev/null)
    fi
    
    # Tier 1c: Try parsing .result as JSON string (if it's a string), then extract
    if [ -z "$findings_files" ]; then
        local result_content
        result_content=$(jq -r '.result // empty' "$agent_output_file" 2>/dev/null)
        if [[ -n "$result_content" ]]; then
            # Try to parse result_content as JSON
            findings_files=$(echo "$result_content" | jq -r '.findings_files[]? // empty' 2>/dev/null)
        fi
    fi
    
    # Tier 1d: Try .result.findings_files[] if .result is already an object
    if [ -z "$findings_files" ]; then
        findings_files=$(jq -r '.result.findings_files[]? // empty' "$agent_output_file" 2>/dev/null)
    fi
    
    if [ -z "$findings_files" ]; then
        # Tier 2: Filesystem fallback - look in work/ and session root
        # Look for patterns: work/*/findings-*.json, *-findings.json, *findings*.json
        local found_files=""
        
        # Check work/ directory (v0.4.0 structure)
        if [ -d "$session_dir/work" ]; then
            for f in "$session_dir/work"/*/findings-*.json "$session_dir/work"/*/*findings*.json; do
                [ -f "$f" ] && found_files="${found_files}${f}"$'\n'
            done
        fi
        
        # Check session root
        for f in "$session_dir"/*-findings.json "$session_dir"/*findings*.json; do
            [ -f "$f" ] && found_files="${found_files}${f}"$'\n'
        done
        
        findings_files=$(echo "$found_files" | grep -v '^$')
    fi
    
    if [ -z "$findings_files" ]; then
        # No findings to integrate - this is OK, not all agents produce findings files
        return 0
    fi
    
    # Process each findings file
    local integrated=0
    while IFS= read -r findings_file; do
        # Resolve path: handle both absolute and relative paths
        # Relative paths are resolved relative to session_dir
        if [[ "$findings_file" != /* ]]; then
            findings_file="$session_dir/$findings_file"
        fi
        
        [ -f "$findings_file" ] || continue
        [ ! -s "$findings_file" ] && continue  # Skip empty files
        
        # Validate JSON
        if ! jq empty "$findings_file" 2>/dev/null; then
            echo "Warning: Invalid JSON in findings file $findings_file" >&2
            continue
        fi
        
        # Extract and integrate entities
        local entities_json
        entities_json=$(jq -c '.entities_discovered[]? // empty' "$findings_file" 2>/dev/null)
        if [ -n "$entities_json" ]; then
            while IFS= read -r entity; do
                local name
                name=$(echo "$entity" | jq -r '.name // empty')
                
                if [ -n "$name" ]; then
                    # Pass the entire entity JSON object to kg_add_entity
                    kg_add_entity "$session_dir" "$entity" >/dev/null 2>&1
                    integrated=$((integrated + 1))
                fi
            done <<< "$entities_json"
        fi
        
        # Extract and integrate claims
        local claims_json
        claims_json=$(jq -c '.claims[]? // empty' "$findings_file" 2>/dev/null)
        if [ -n "$claims_json" ]; then
            while IFS= read -r claim; do
                local statement
                statement=$(echo "$claim" | jq -r '.statement // empty')
                
                if [ -n "$statement" ]; then
                    # Pass the entire claim JSON object to kg_add_claim
                    kg_add_claim "$session_dir" "$claim" >/dev/null 2>&1
                    integrated=$((integrated + 1))
                fi
            done <<< "$claims_json"
        fi
        
        # Note: Citations are typically already in the KG via entity/claim sources
        # If there's a separate citations array, we could process it here
        
    done <<< "$findings_files"

    kg_merge_evidence_claims "$session_dir" >/dev/null 2>&1 || true

    # Validate knowledge graph after integration
    if ! jq empty "$kg_file" 2>/dev/null; then
        echo "ERROR: Knowledge graph corrupted after integration. Restoring backup." >&2
        if [ -f "${kg_file}.backup" ]; then
            cp "${kg_file}.backup" "$kg_file"
            echo "  ✓ Backup restored successfully" >&2
        fi
        return 1
    fi
    
    if [ "$integrated" -gt 0 ]; then
        return 0
    else
        # No data was integrated but findings files exist - could be empty or malformed
        return 0  # Don't fail, just return success with no-op
    fi
}
export -f kg_integrate_agent_output

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        init)
            kg_init "$2" "$3"
            ;;
        read)
            kg_read "$2"
            ;;
        summary)
            kg_get_summary "$2"
            ;;
        gaps)
            kg_get_high_priority_gaps "$2" "${3:-7}"
            ;;
        contradictions)
            kg_get_unresolved_contradictions "$2"
            ;;
        leads)
            kg_get_unexplored_leads "$2" "${3:-6}"
            ;;
        *)
            echo "Usage: $0 {init|read|summary|gaps|contradictions|leads} <session_dir> [args]"
            echo ""
            echo "Commands:"
            echo "  init <session_dir> <question>     - Initialize new knowledge graph"
            echo "  read <session_dir>                 - Read entire knowledge graph"
            echo "  summary <session_dir>              - Get summary statistics"
            echo "  gaps <session_dir> [min_priority]  - Get high-priority gaps"
            echo "  contradictions <session_dir>       - Get unresolved contradictions"
            echo "  leads <session_dir> [min_priority] - Get unexplored leads"
            ;;
    esac
fi
