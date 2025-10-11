#!/usr/bin/env bash
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
    local research_question="$2"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "research_question" "$research_question" || return 1

    local kg_file="$session_dir/knowledge-graph.json"

    # Use jq to safely construct JSON (prevents injection attacks)
    jq -n \
        --arg question "$research_question" \
        --arg started "$(get_timestamp)" \
        --arg updated "$(get_timestamp)" \
        '{
            schema_version: "1.0",
            research_question: $question,
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
                explored_leads: 0
            }
        }' > "$kg_file"

    echo "$kg_file"
}

# Get knowledge graph path
kg_get_path() {
    local session_dir="$1"
    echo "$session_dir/knowledge-graph.json"
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

    cat "$kg_file"
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

    # Acquire lock for atomic operation
    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding entity" >&2
        return 1
    }

    # Check if entity already exists (by name)
    local entity_name
    entity_name=$(echo "$entity_json" | jq -r '.name')
    local exists
    exists=$(jq --arg name "$entity_name" \
                     '.entities[] | select(.name == $name) | .id' \
                     "$kg_file" | head -1)

    if [ -n "$exists" ]; then
        # Update existing entity
        jq --argjson entity "$entity_json" \
           --arg name "$entity_name" \
           --arg date "$(get_timestamp)" \
           '(.entities[] | select(.name == $name)) |= ($entity + {last_updated: $date}) |
            .last_updated = $date' \
           "$kg_file" > "${kg_file}.tmp"
    else
        # Add new entity
        local entity_id
        entity_id="e$(jq '.stats.total_entities' "$kg_file")"
        jq --argjson entity "$entity_json" \
           --arg id "$entity_id" \
           --arg date "$(get_timestamp)" \
           '.entities += [($entity + {id: $id, added_at: $date})] |
            .stats.total_entities += 1 |
            .last_updated = $date' \
           "$kg_file" > "${kg_file}.tmp"
    fi

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
    
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

    # Acquire lock for atomic operation
    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding claim" >&2
        return 1
    }

    local claim_id
    claim_id="c$(jq '.stats.total_claims' "$kg_file")"

    jq --argjson claim "$claim_json" \
       --arg id "$claim_id" \
       --arg date "$(get_timestamp)" \
       '.claims += [($claim + {id: $id, added_at: $date, verified: false})] |
        .stats.total_claims += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
    
    # Phase 2: Log claim added
    if command -v log_claim_added &>/dev/null; then
        local confidence
        confidence=$(echo "$claim_json" | jq -r '.confidence // 0.5')
        log_claim_added "$session_dir" "$claim_id" "$confidence" || true
    fi
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding relationship" >&2
        return 1
    }

    local rel_id
    rel_id="r$(jq '.stats.total_relationships' "$kg_file")"

    jq --argjson rel "$relationship_json" \
       --arg id "$rel_id" \
       --arg date "$(get_timestamp)" \
       '.relationships += [($rel + {id: $id, added_at: $date})] |
        .stats.total_relationships += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding gap" >&2
        return 1
    }

    local gap_id
    gap_id="g$(jq '.stats.total_gaps' "$kg_file")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file")

    jq --argjson gap "$gap_json" \
       --arg id "$gap_id" \
       --arg iter "$iteration" \
       --arg date "$(get_timestamp)" \
       '.gaps += [($gap + {id: $id, detected_at_iteration: ($iter | tonumber), status: "pending", added_at: $date})] |
        .stats.total_gaps += 1 |
        .stats.unresolved_gaps += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
    
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for updating gap status" >&2
        return 1
    }

    local was_unresolved
    was_unresolved=$(jq --arg id "$gap_id" \
                              '.gaps[] | select(.id == $id and .status != "resolved") | .id' \
                              "$kg_file" | wc -l | xargs)

    # Combine both updates in one jq command to maintain atomicity
    if [ "$status" = "resolved" ] && [ "$was_unresolved" -gt 0 ]; then
        jq --arg id "$gap_id" \
           --arg status "$status" \
           --arg date "$(get_timestamp)" \
           '(.gaps[] | select(.id == $id)) |= (. + {status: $status, updated_at: $date}) |
            .stats.unresolved_gaps -= 1 |
            .last_updated = $date' \
           "$kg_file" > "${kg_file}.tmp"
    else
        jq --arg id "$gap_id" \
           --arg status "$status" \
           --arg date "$(get_timestamp)" \
           '(.gaps[] | select(.id == $id)) |= (. + {status: $status, updated_at: $date}) |
            .last_updated = $date' \
           "$kg_file" > "${kg_file}.tmp"
    fi

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding contradiction" >&2
        return 1
    }

    local con_id
    con_id="con$(jq '.stats.total_contradictions' "$kg_file")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file")

    jq --argjson con "$contradiction_json" \
       --arg id "$con_id" \
       --arg iter "$iteration" \
       --arg date "$(get_timestamp)" \
       '.contradictions += [($con + {id: $id, detected_at_iteration: ($iter | tonumber), status: "unresolved", added_at: $date})] |
        .stats.total_contradictions += 1 |
        .stats.unresolved_contradictions += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for resolving contradiction" >&2
        return 1
    }

    jq --arg id "$con_id" \
       --arg resolution "$resolution" \
       --arg date "$(get_timestamp)" \
       '(.contradictions[] | select(.id == $id)) |= (. + {status: "resolved", resolution: $resolution, resolved_at: $date}) |
        .stats.unresolved_contradictions -= 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for adding lead" >&2
        return 1
    }

    local lead_id
    lead_id="l$(jq '.stats.total_leads' "$kg_file")"
    local iteration
    iteration=$(jq '.iteration' "$kg_file")

    jq --argjson lead "$lead_json" \
       --arg id "$lead_id" \
       --arg iter "$iteration" \
       --arg date "$(get_timestamp)" \
       '.promising_leads += [($lead + {id: $id, detected_at_iteration: ($iter | tonumber), status: "pending", added_at: $date})] |
        .stats.total_leads += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for marking lead explored" >&2
        return 1
    }

    jq --arg id "$lead_id" \
       --arg date "$(get_timestamp)" \
       '(.promising_leads[] | select(.id == $id)) |= (. + {status: "explored", explored_at: $date}) |
        .stats.explored_leads += 1 |
        .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for updating confidence" >&2
        return 1
    }

    jq --argjson conf "$confidence_json" \
       --arg date "$(get_timestamp)" \
       '.confidence_scores = $conf | .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

    lock_acquire "$kg_file" || {
        echo "Error: Failed to acquire lock for updating coverage" >&2
        return 1
    }

    jq --argjson cov "$coverage_json" \
       --arg date "$(get_timestamp)" \
       '.coverage = $cov | .last_updated = $date' \
       "$kg_file" > "${kg_file}.tmp"

    mv "${kg_file}.tmp" "$kg_file"
    lock_release "$kg_file"
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

# Export functions
export -f kg_init
export -f kg_get_path
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

# Integrate agent findings into knowledge graph
# Usage: kg_integrate_agent_output <session_dir> <agent_output_file>
# Returns: 0 on success, 1 if no findings found or integration failed
kg_integrate_agent_output() {
    local session_dir="$1"
    local agent_output_file="$2"
    local kg_file="$session_dir/knowledge-graph.json"
    
    if [ ! -f "$kg_file" ]; then
        echo "Error: Knowledge graph not found at $kg_file" >&2
        return 1
    fi
    
    # Tier 1: Extract findings files list from agent output manifest
    local findings_files
    findings_files=$(jq -r '.findings_files[]? // empty' "$agent_output_file" 2>/dev/null)
    
    if [ -z "$findings_files" ]; then
        # Tier 2: Filesystem fallback - look in raw/ and session root
        # Look for patterns: raw/findings-*.json, *-findings.json, *findings*.json
        local found_files=""
        
        # Check raw/ directory
        if [ -d "$session_dir/raw" ]; then
            for f in "$session_dir/raw"/findings-*.json "$session_dir/raw"/*findings*.json; do
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
