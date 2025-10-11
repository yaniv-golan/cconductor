#!/usr/bin/env bash
# Knowledge Graph Artifact Processor
# Processes agent-produced artifacts and merges them into knowledge-graph.json

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

# Source dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/debug.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/verbose.sh" 2>/dev/null || true

# Fallback functions if dependencies not available
if ! command -v debug &> /dev/null; then
    debug() { :; }
fi
if ! command -v verbose &> /dev/null; then
    verbose() { echo "$@"; }
fi

# Validate artifact metadata files
# Args: session_dir, agent_name
# Returns: 0 if valid, 1 if invalid
validate_artifact_metadata() {
    local session_dir="$1"
    local agent_name="$2"
    local artifact_dir="$session_dir/artifacts/$agent_name"
    
    debug "Validating artifacts for $agent_name in $artifact_dir"
    
    # Check artifact directory exists
    if [ ! -d "$artifact_dir" ]; then
        echo "ERROR: Artifact directory not found: $artifact_dir" >&2
        return 1
    fi
    
    # Find all JSON files
    local json_files
    json_files=$(find "$artifact_dir" -maxdepth 1 -name "*.json" 2>/dev/null || true)
    
    if [ -z "$json_files" ]; then
        echo "ERROR: No JSON files found in $artifact_dir" >&2
        return 1
    fi
    
    # Validate each JSON file
    local file
    while IFS= read -r file; do
        # Check file size (must be < 64KB)
        local size
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS stat
            size=$(stat -f%z "$file" 2>/dev/null || echo "0")
        else
            # Linux stat
            size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        fi
        
        if [ "$size" -gt 65536 ]; then
            echo "ERROR: Artifact file too large (${size} bytes): $file" >&2
            return 1
        fi
        
        # Validate JSON syntax
        if ! jq -e . "$file" >/dev/null 2>&1; then
            echo "ERROR: Invalid JSON in artifact file: $file" >&2
            return 1
        fi
        
        debug "Validated artifact file: $(basename "$file") (${size} bytes)"
    done <<< "$json_files"
    
    verbose "✓ Validated artifacts for $agent_name"
    return 0
}

# Create retry instructions for orchestrator
# Args: session_dir, agent_name, error_reason
create_retry_instructions() {
    local session_dir="$1"
    local agent_name="$2"
    local error_reason="$3"
    local instructions_file="$session_dir/${agent_name}.retry-instructions.json"
    
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$instructions_file" <<EOF
{
  "agent": "$agent_name",
  "error": "$error_reason",
  "timestamp": "$timestamp",
  "instructions": [
    "The $agent_name produced artifacts that failed validation.",
    "Error: $error_reason",
    "The lockfile has been renamed to ${agent_name}.kg.lock.error",
    "On the next cycle, the orchestrator should:",
    "1. Review artifacts in artifacts/$agent_name/",
    "2. Check for JSON syntax errors or files exceeding 64KB",
    "3. Decide whether to re-invoke $agent_name or continue without artifacts"
  ],
  "artifact_location": "artifacts/$agent_name/",
  "lock_file_renamed_to": "${agent_name}.kg.lock.error"
}
EOF
    
    echo "Created retry instructions: $instructions_file" >&2
    verbose "  To retry: Remove .error extension from lockfile after fixing artifacts"
}

# Merge artifacts into knowledge graph
# Args: session_dir, agent_name
# Returns: 0 if successful, 1 if failed
merge_artifacts_to_kg() {
    local session_dir="$1"
    local agent_name="$2"
    local artifact_dir="$session_dir/artifacts/$agent_name"
    local kg_file="$session_dir/knowledge-graph.json"
    local lock_dir="$session_dir/.kg-merge.lock"
    
    debug "Merging artifacts from $agent_name into knowledge graph"
    
    # Acquire lock (macOS-compatible with mkdir)
    local lock_timeout=30
    local lock_wait=0
    while ! mkdir "$lock_dir" 2>/dev/null; do
        if [ "$lock_wait" -ge "$lock_timeout" ]; then
            echo "ERROR: Timeout waiting for knowledge graph lock" >&2
            return 1
        fi
        sleep 1
        lock_wait=$((lock_wait + 1))
    done
    
    # Ensure lock is removed on exit
    trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
    
    # Read and merge all JSON artifacts into single object
    local merged_artifacts
    if ! merged_artifacts=$(jq -s 'reduce .[] as $item ({}; . * $item)' \
        "$artifact_dir"/*.json 2>&1); then
        echo "ERROR: Failed to merge artifact JSON files: $merged_artifacts" >&2
        rmdir "$lock_dir"
        return 1
    fi
    
    # Read current knowledge graph
    if [ ! -f "$kg_file" ]; then
        echo "ERROR: Knowledge graph not found: $kg_file" >&2
        rmdir "$lock_dir"
        return 1
    fi
    
    # Merge artifacts under agent namespace into KG
    local temp_kg="$session_dir/knowledge-graph.json.tmp"
    if ! jq --arg agent "$agent_name" \
            --argjson artifacts "$merged_artifacts" \
            '. + {($agent): $artifacts}' \
            "$kg_file" > "$temp_kg" 2>&1; then
        echo "ERROR: Failed to merge artifacts into knowledge graph" >&2
        rm -f "$temp_kg"
        rmdir "$lock_dir"
        return 1
    fi
    
    # Validate merged result
    if ! jq -e . "$temp_kg" >/dev/null 2>&1; then
        echo "ERROR: Merged knowledge graph is invalid JSON" >&2
        rm -f "$temp_kg"
        rmdir "$lock_dir"
        return 1
    fi
    
    # Atomic move
    mv "$temp_kg" "$kg_file"
    
    # Release lock
    rmdir "$lock_dir"
    trap - EXIT
    
    verbose "✓ Merged $agent_name artifacts into knowledge graph"
    debug "  Artifacts stored under key: $agent_name"
    
    return 0
}

# Process knowledge graph artifacts for one or all agents
# Args: session_dir, agent_name (or "all" for all pending locks)
# Returns: 0 if all successful, 1 if any failed
process_kg_artifacts() {
    local session_dir="$1"
    local agent_filter="${2:-all}"
    
    debug "Processing KG artifacts in $session_dir (filter: $agent_filter)"
    
    # Find lock files
    local lockfile
    local agent
    local success_count=0
    local fail_count=0
    
    for lockfile in "$session_dir"/*.kg.lock; do
        # Check if glob matched nothing
        [ -e "$lockfile" ] || continue
        
        agent=$(basename "$lockfile" .kg.lock)
        
        # Apply filter
        if [ "$agent_filter" != "all" ] && [ "$agent_filter" != "$agent" ]; then
            continue
        fi
        
        verbose "Processing artifacts from $agent..."
        
        # Validate artifacts
        if validate_artifact_metadata "$session_dir" "$agent"; then
            # Merge into knowledge graph
            if merge_artifacts_to_kg "$session_dir" "$agent"; then
                # Success - remove lockfile
                rm "$lockfile"
                success_count=$((success_count + 1))
                verbose "✓ Successfully processed $agent artifacts"
            else
                # Merge failed
                create_retry_instructions "$session_dir" "$agent" "merge_failed"
                mv "$lockfile" "${lockfile}.error"
                fail_count=$((fail_count + 1))
                echo "ERROR: ✗ Failed to merge $agent artifacts" >&2
            fi
        else
            # Validation failed
            create_retry_instructions "$session_dir" "$agent" "validation_failed"
            mv "$lockfile" "${lockfile}.error"
            fail_count=$((fail_count + 1))
            echo "ERROR: ✗ Failed to validate $agent artifacts" >&2
        fi
    done
    
    if [ "$success_count" -gt 0 ]; then
        verbose "Processed $success_count agent artifact(s) successfully"
    fi
    
    if [ "$fail_count" -gt 0 ]; then
        echo "ERROR: Failed to process $fail_count agent artifact(s)" >&2
        return 1
    fi
    
    return 0
}

# If script is executed directly (for testing)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir> [agent_name]" >&2
        echo "  agent_name: specific agent or 'all' (default: all)" >&2
        exit 1
    fi
    
    process_kg_artifacts "$@"
fi

