#!/usr/bin/env bash
# Quality Surface Sync
# Merges quality gate results into knowledge graph

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source shared state for atomic operations
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Source knowledge graph utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/knowledge-graph.sh"

# Source core helpers for timestamp
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null || true

# Sync quality gate results into knowledge graph
# Parameters:
#   $1 - session_dir
#   $2 - gate_report_path (typically artifacts/quality-gate.json)
# Returns: 0 on success, 1 on error
sync_quality_surfaces_to_kg() {
    local session_dir="$1"
    local gate_report_path="$2"
    
    # Validate inputs
    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        echo "Error: Invalid session directory: $session_dir" >&2
        return 1
    fi
    
    if [[ -z "$gate_report_path" ]]; then
        echo "Error: Gate report path not provided" >&2
        return 1
    fi
    
    # Resolve full path to gate report
    if [[ "$gate_report_path" != /* ]]; then
        gate_report_path="$session_dir/$gate_report_path"
    fi
    
    if [[ ! -f "$gate_report_path" ]]; then
        echo "Warning: Gate report not found: $gate_report_path" >&2
        return 0  # Not an error - gate may not have run yet
    fi
    
    # Get knowledge graph path
    local kg_file
    kg_file=$(kg_get_path "$session_dir")
    
    if [[ ! -f "$kg_file" ]]; then
        echo "Warning: Knowledge graph not found: $kg_file" >&2
        return 0  # Not an error - KG may not exist yet
    fi
    
    # Extract claim results from gate report
    local claim_results
    claim_results=$(jq -c '.claim_results // []' "$gate_report_path" 2>/dev/null)
    
    if [[ -z "$claim_results" || "$claim_results" == "[]" || "$claim_results" == "null" ]]; then
        echo "No claim results in gate report" >&2
        return 0  # Empty report is OK
    fi
    
    # Validate JSON before passing to atomic_json_update
    if ! echo "$claim_results" | jq -e '.' >/dev/null 2>&1; then
        echo "Warning: Invalid JSON in claim_results, skipping KG sync" >&2
        return 0
    fi
    
    # Use atomic_json_update to merge gate data into KG claims
    # This is thread-safe and reuses existing locking infrastructure
    atomic_json_update "$kg_file" \
        --argjson gate_results "$claim_results" \
        '
        # Build lookup map of gate results by claim ID
        ($gate_results | map({(.id): .}) | add) as $gate_map |
        
        # Update each claim that has gate results
        .claims = (.claims | map(
            if $gate_map[.id] then
                . + {
                    quality_gate_assessment: $gate_map[.id].confidence_surface
                }
            else
                .
            end
        )) |
        
        # Update last_updated timestamp
        .last_updated = (now | todate)
        '
    
    local sync_status=$?
    
    if [[ $sync_status -eq 0 ]]; then
        echo "✓ Synced quality surfaces to knowledge graph" >&2
    else
        echo "Warning: Failed to sync quality surfaces to KG" >&2
    fi
    
    return $sync_status
}

# Record quality gate run in session metadata
# Parameters:
#   $1 - session_dir
#   $2 - timestamp (ISO 8601)
#   $3 - claims_assessed_count
#   $4 - report_path (relative to session dir)
# Returns: 0 on success, 1 on error
record_quality_gate_run() {
    local session_dir="$1"
    local timestamp="$2"
    local claims_count="$3"
    local report_path="$4"
    
    # Validate inputs
    if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
        echo "Error: Invalid session directory: $session_dir" >&2
        return 1
    fi
    
    if [[ -z "$timestamp" ]]; then
        timestamp=$(get_timestamp 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi
    
    local meta_dir="$session_dir/meta"
    mkdir -p "$meta_dir"
    
    local metadata_file="$meta_dir/session-metadata.json"
    
    # Initialize metadata file if it doesn't exist
    if [[ ! -f "$metadata_file" ]]; then
        echo '{"quality_gate_runs":[]}' > "$metadata_file"
    fi
    
    # Validate claims_count is a number (default to 0 if invalid)
    if ! [[ "$claims_count" =~ ^[0-9]+$ ]]; then
        claims_count=0
    fi
    
    # Create new gate run record
    local gate_run_record
    gate_run_record=$(jq -n \
        --arg timestamp "$timestamp" \
        --argjson claims "$claims_count" \
        --arg report "$report_path" \
        '{
            timestamp: $timestamp,
            claims_assessed: $claims,
            report_path: $report,
            status: "completed"
        }')
    
    # Append to quality_gate_runs array using atomic write
    local tmp_file="${metadata_file}.tmp.$$"
    
    if jq --argjson run "$gate_run_record" \
        '.quality_gate_runs += [$run]' \
        "$metadata_file" > "$tmp_file"; then
        mv "$tmp_file" "$metadata_file"
        echo "✓ Recorded quality gate run in session metadata" >&2
        return 0
    else
        rm -f "$tmp_file"
        echo "Warning: Failed to record quality gate run" >&2
        return 1
    fi
}

# Export functions for use by orchestrator
export -f sync_quality_surfaces_to_kg
export -f record_quality_gate_run

# CLI interface for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        sync)
            sync_quality_surfaces_to_kg "$2" "$3"
            ;;
        record)
            record_quality_gate_run "$2" "$3" "$4" "$5"
            ;;
        *)
            echo "Usage: $0 {sync|record} <args>"
            echo ""
            echo "Commands:"
            echo "  sync <session_dir> <gate_report_path>     - Sync gate results to KG"
            echo "  record <session_dir> <timestamp> <count> <path> - Record gate run"
            ;;
    esac
fi

