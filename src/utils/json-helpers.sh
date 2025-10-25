#!/usr/bin/env bash
# JSON Helpers - Specialized JSON manipulation utilities
# These functions build on shared-state.sh for atomic operations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

# Source shared-state for atomic operations
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Safely merge two JSON files
# Usage: json_merge_files file1.json file2.json output.json [jq_merge_expression]
json_merge_files() {
    local file1="$1"
    local file2="$2"
    local output="$3"
    # shellcheck disable=SC2016
    local merge_expr="${4:-'. * $file2'}"  # Default: merge with file2 taking precedence (jq expression)
    
    if [[ ! -f "$file1" ]]; then
        log_error "First JSON file not found: $file1"
        return 1
    fi
    
    if [[ ! -f "$file2" ]]; then
        log_error "Second JSON file not found: $file2"
        return 1
    fi
    
    # Validate both files are valid JSON
    if ! jq empty "$file1" 2>/dev/null; then
        log_error "Invalid JSON in file: $file1"
        return 1
    fi
    
    if ! jq empty "$file2" 2>/dev/null; then
        log_error "Invalid JSON in file: $file2"
        return 1
    fi
    
    # Merge using jq
    local temp_file="${output}.tmp"
    if jq -s --slurpfile file2 "$file2" "$merge_expr" "$file1" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$output"
        return 0
    else
        log_error "Failed to merge JSON files"
        rm -f "$temp_file"
        return 1
    fi
}

# Extract field from JSON with fallback
# Usage: json_get_field file.json ".path.to.field" "default_value"
json_get_field() {
    local file="$1"
    local field="$2"
    local default="${3:-}"
    
    if [[ ! -f "$file" ]]; then
        echo "$default"
        return 1
    fi
    
    local value
    value=$(jq -r "$field // empty" "$file" 2>/dev/null || echo "")
    
    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "$default"
        return 1
    fi
    
    echo "$value"
    return 0
}

# Check if field exists in JSON
# Usage: json_has_field file.json ".path.to.field"
json_has_field() {
    local file="$1"
    local field="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if jq -e "$field" "$file" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Atomically append to JSON array
# Usage: json_array_append file.json ".array.path" '{"new": "item"}'
json_array_append() {
    local file="$1"
    local array_path="$2"
    local item="$3"
    
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    # Validate item is valid JSON
    if ! echo "$item" | jq empty 2>/dev/null; then
        log_error "Item is not valid JSON"
        return 1
    fi
    
    # Use atomic_json_update from shared-state
    atomic_json_update "$file" --argjson item "$item" \
        "${array_path} += [\$item]"
}

# Atomically update JSON field
# Usage: json_set_field file.json ".path.to.field" "new_value"
json_set_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    # Use atomic_json_update from shared-state
    atomic_json_update "$file" --arg value "$value" \
        "${field} = \$value"
}

# Validate JSON structure against simple schema
# Usage: json_validate_structure file.json ".required.field1" ".required.field2" ...
json_validate_structure() {
    local file="$1"
    shift
    local required_fields=("$@")
    
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    # Check each required field
    for field in "${required_fields[@]}"; do
        if ! jq -e "$field" "$file" >/dev/null 2>&1; then
            log_error "Missing required field: $field in $file"
            return 1
        fi
    done
    
    return 0
}

# Pretty-print JSON file
# Usage: json_pretty file.json [output.json]
json_pretty() {
    local file="$1"
    local output="${2:-}"
    
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    if [[ -z "$output" ]]; then
        # Print to stdout
        jq . "$file"
    else
        # Write to output file
        jq . "$file" > "$output"
    fi
}

# Compact JSON file (remove whitespace)
# Usage: json_compact file.json [output.json]
json_compact() {
    local file="$1"
    local output="${2:-}"
    
    if [[ ! -f "$file" ]]; then
        log_error "JSON file not found: $file"
        return 1
    fi
    
    if [[ -z "$output" ]]; then
        # Print to stdout
        jq -c . "$file"
    else
        # Write to output file
        jq -c . "$file" > "$output"
    fi
}

# Safely slurp JSON objects from file into array
# Usage: json_slurp_array file.json ["[]"]
# Returns: JSON array on success, fallback value on failure (default: '[]')
json_slurp_array() {
    local file="$1"
    local fallback="${2:-[]}"
    
    # Empty or missing file
    if [[ ! -s "$file" ]]; then
        echo "$fallback"
        return 0
    fi
    
    # Attempt slurp with validation
    local result
    if result=$(jq -s '.' "$file" 2>/dev/null) && [[ -n "$result" ]]; then
        # Validate it's actually JSON
        if echo "$result" | jq empty 2>/dev/null; then
            echo "$result"
            return 0
        fi
    fi
    
    # Fallback on any error
    log_warn "json_slurp_array: failed to parse $file, using fallback"
    echo "$fallback"
    return 1
}

# Export functions
export -f json_merge_files
export -f json_get_field
export -f json_has_field
export -f json_array_append
export -f json_set_field
export -f json_validate_structure
export -f json_pretty
export -f json_compact
export -f json_slurp_array

