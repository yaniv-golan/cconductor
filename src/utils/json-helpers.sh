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
    if value=$(safe_jq_from_file "$file" "$field // empty" "$default" "${CCONDUCTOR_SESSION_DIR:-}" "json_get_field" "true"); then
        if [[ -z "$value" || "$value" == "null" ]]; then
            echo "$default"
            return 1
        fi
        echo "$value"
        return 0
    fi

    echo "$default"
    return 1
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
    if ! jq_validate_json "$item"; then
        log_error "Item is not valid JSON"
        return 1
    fi

    # Use atomic_json_update from shared-state with validated payload
    # lint-allow: jq_argjson_safe reason="json_array_append validates item with jq_validate_json before --argjson"
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

# ============================================================================
# jq Safety Layer - Validation and safe argument building
# Added per jq-encapsulation-layer plan to prevent jq failures
# ============================================================================

# Validate that a value is valid JSON
# Usage: jq_validate_json "$value"
# Returns: 0 if valid JSON, 1 if invalid
# Note: Uses printf instead of echo to preserve whitespace and avoid escape sequence issues
jq_validate_json() {
    local value="$1"
    
    # Empty string is not valid JSON
    if [[ -z "$value" ]]; then
        return 1
    fi
    
    # Use printf to avoid echo's escape sequence interpretation
    # Handles multi-line JSON correctly, preserves whitespace
    if printf '%s' "$value" | jq empty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Escape a shell string to JSON string literal
# Usage: json_str=$(jq_escape_string "my string")
# Returns: JSON-escaped string on stdout
jq_escape_string() {
    local string="$1"
    
    # Use jq itself to safely escape the string
    jq -n --arg val "$string" '$val'
}

# Build --argjson argument safely with validation
# Usage: jq_build_argjson ARRAY_NAME var_name json_value
# Appends the validated `--argjson` tuple to the provided array by name.
jq_build_argjson() {
    local array_name="$1"
    shift
    local var_name="$1"
    shift
    local value="$1"
    local session_dir="${CCONDUCTOR_SESSION_DIR:-}"

    if [[ -z "$array_name" || ! "$array_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_error "[jq_build_argjson] Invalid array name: '$array_name'"
        return 1
    fi

    if ! jq_validate_json "$value"; then
        if [[ -n "$session_dir" ]] && command -v log_system_error &>/dev/null; then
            log_system_error "$session_dir" "jq_build_argjson" \
                "Invalid JSON for --argjson '$var_name'" \
                "value: ${value:0:200}"
        else
            log_error "[jq_build_argjson] Invalid JSON for '$var_name': ${value:0:200}"
        fi
        return 1
    fi

    local var_quoted value_quoted
    printf -v var_quoted '%q' "$var_name"
    printf -v value_quoted '%q' "$value"

    eval "$array_name+=(\"--argjson\" $var_quoted $value_quoted)"
    return 0
}

# Alias for json_slurp_array (consistent naming)
# Usage: jq_slurp_array file.json ["[]"]
jq_slurp_array() {
    json_slurp_array "$@"
}

# Validate JSON file against a schema definition stored under config/schemas/artifacts
# Usage: json_validate_with_schema schema_path data_path
json_validate_with_schema() {
    local schema_path="$1"
    local data_path="$2"

    if [[ -z "$schema_path" || -z "$data_path" ]]; then
        log_error "json_validate_with_schema requires schema and data paths"
        return 1
    fi

    if [[ ! -f "$schema_path" ]]; then
        log_error "Schema file not found: $schema_path"
        return 1
    fi

    if [[ ! -f "$data_path" ]]; then
        log_error "JSON data file not found: $data_path"
        return 1
    fi

    local validator="$PROJECT_ROOT/src/utils/schema-validator.py"
    if [[ ! -x "$validator" ]]; then
        log_error "Schema validator missing or not executable: $validator"
        return 1
    fi

    if ! python3 "$validator" "$schema_path" "$data_path" >/dev/null 2>&1; then
        if [[ -n "${CCONDUCTOR_SESSION_DIR:-}" ]] && command -v log_system_error &>/dev/null; then
            log_system_error "$CCONDUCTOR_SESSION_DIR" "schema_validation_failed" \
                "Schema validation failed for $data_path" \
                "schema=$schema_path"
        else
            log_error "Schema validation failed for $data_path (schema: $schema_path)"
        fi
        return 1
    fi

    return 0
}

# Read JSON object from file with fallback
# Usage: jq_read_object file.json ['{}']
# Returns: JSON object on success, fallback value on failure (default: '{}')
jq_read_object() {
    local file="$1"
    local fallback="${2:-\{\}}"
    
    # Empty or missing file
    if [[ ! -s "$file" ]]; then
        echo "$fallback"
        return 0
    fi
    
    # Attempt read with validation
    local result
    if result=$(jq '.' "$file" 2>/dev/null) && [[ -n "$result" ]]; then
        # Validate it's actually a JSON object (not array)
        local type
        type=$(echo "$result" | jq -r 'type' 2>/dev/null)
        if [[ "$type" == "object" ]]; then
            echo "$result"
            return 0
        elif [[ "$type" == "array" ]]; then
            log_warn "jq_read_object: $file contains array, not object; using fallback"
            echo "$fallback"
            return 1
        else
            log_warn "jq_read_object: $file contains $type, not object; using fallback"
            echo "$fallback"
            return 1
        fi
    fi
    
    # Fallback on any error
    log_warn "jq_read_object: failed to parse $file, using fallback"
    echo "$fallback"
    return 1
}

# Safely evaluate jq against a JSON string with validation and logging
# Usage: safe_jq_from_json "$json" '<jq_filter>' '<fallback>' [session_dir] [context] [raw_output=true] [strict=false]
safe_jq_from_json() {
    local json_payload="$1"
    local jq_filter="$2"
    local fallback="$3"
    local session_dir="${4:-}"
    local context="${5:-jq_safe_json}"
    local raw_output="${6:-true}"
    local strict_mode="${7:-false}"
    local -a jq_args=()

    [[ "$raw_output" == "true" ]] && jq_args+=(-r)

    if jq_validate_json "$json_payload"; then
        if [[ "${#jq_args[@]}" -gt 0 ]]; then
            printf '%s' "$json_payload" | jq "${jq_args[@]}" "$jq_filter"
        else
            printf '%s' "$json_payload" | jq "$jq_filter"
        fi
        return 0
    fi

    if [[ -n "$session_dir" ]] && command -v log_system_warning &>/dev/null; then
        log_system_warning "$session_dir" "jq_json_parse_failure" "$context" "payload_snippet=${json_payload:0:200}"
    else
        log_warn "[jq_json_parse_failure] $context: ${json_payload:0:200}"
    fi
    printf '%s' "$fallback"
    if [[ "$strict_mode" == "true" ]]; then
        return 1
    fi
    return 0
}

# Safely evaluate jq against a JSON file (ensures file exists + valid JSON)
# Usage: safe_jq_from_file path '<jq_filter>' '<fallback>' [session_dir] [context] [raw_output=true] [strict=false]
safe_jq_from_file() {
    local file_path="$1"
    local jq_filter="$2"
    local fallback="$3"
    local session_dir="${4:-}"
    local context="${5:-jq_safe_file}"
    local raw_output="${6:-true}"
    local strict_mode="${7:-false}"
    local -a jq_args=()

    [[ "$raw_output" == "true" ]] && jq_args+=(-r)

    if [[ -f "$file_path" ]] && jq empty "$file_path" >/dev/null 2>&1; then
        if [[ "${#jq_args[@]}" -gt 0 ]]; then
            jq "${jq_args[@]}" "$jq_filter" "$file_path"
        else
            jq "$jq_filter" "$file_path"
        fi
        return 0
    fi

    if [[ -n "$session_dir" ]] && command -v log_system_warning &>/dev/null; then
        log_system_warning "$session_dir" "jq_file_parse_failure" "$context" "file=$file_path"
    else
        log_warn "[jq_file_parse_failure] $context: $file_path"
    fi
    printf '%s' "$fallback"
    if [[ "$strict_mode" == "true" ]]; then
        return 1
    fi
    return 0
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
export -f jq_validate_json
export -f jq_escape_string
export -f jq_build_argjson
export -f json_validate_with_schema
export -f jq_slurp_array
export -f jq_read_object
export -f safe_jq_from_json
export -f safe_jq_from_file
