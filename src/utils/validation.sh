#!/usr/bin/env bash
# Input Validation Utilities
# Reusable validation functions for defensive programming

set -euo pipefail

# Validate that a parameter is not empty
# Usage: validate_required "param_name" "$param_value"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_required() {
    local param_name="$1"
    local param_value="${2:-}"

    if [ -z "$param_value" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    return 0
}

# Validate that a directory exists
# Usage: validate_directory "param_name" "$directory_path"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_directory() {
    local param_name="$1"
    local directory_path="${2:-}"

    if [ -z "$directory_path" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    if [ ! -d "$directory_path" ]; then
        echo "Error: $param_name directory does not exist: $directory_path" >&2
        return 1
    fi

    return 0
}

# Validate that a file exists
# Usage: validate_file "param_name" "$file_path"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_file() {
    local param_name="$1"
    local file_path="${2:-}"

    if [ -z "$file_path" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    if [ ! -f "$file_path" ]; then
        echo "Error: $param_name file does not exist: $file_path" >&2
        return 1
    fi

    return 0
}

# Validate JSON syntax
# Usage: validate_json "param_name" "$json_string"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_json() {
    local param_name="$1"
    local json_string="${2:-}"

    if [ -z "$json_string" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    if ! echo "$json_string" | jq '.' >/dev/null 2>&1; then
        echo "Error: $param_name is not valid JSON" >&2
        echo "Received: ${json_string:0:200}..." >&2
        return 1
    fi

    return 0
}

# Validate that JSON contains required field
# Usage: validate_json_field "$json_string" "field_name" "field_type"
# field_type: string, number, array, object, boolean
# Returns: 0 if valid, 1 if invalid (with error message)
validate_json_field() {
    local json_string="$1"
    local field_name="$2"
    local field_type="${3:-}"

    # Check field exists
    local field_value
    field_value=$(echo "$json_string" | jq -r ".${field_name} // \"__MISSING__\"")

    if [ "$field_value" = "__MISSING__" ] || [ "$field_value" = "null" ]; then
        echo "Error: JSON must have '$field_name' field" >&2
        return 1
    fi

    # Check field type if specified
    if [ -n "$field_type" ]; then
        local actual_type
        actual_type=$(echo "$json_string" | jq -r ".${field_name} | type")

        if [ "$actual_type" != "$field_type" ]; then
            echo "Error: JSON field '$field_name' must be type '$field_type', got '$actual_type'" >&2
            return 1
        fi
    fi

    return 0
}

# Validate session directory structure
# Usage: validate_session_dir "$session_dir"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_session_dir() {
    local session_dir="${1:-}"

    if ! validate_directory "session_dir" "$session_dir"; then
        return 1
    fi

    # Check for knowledge graph file
    local kg_file="$session_dir/knowledge-graph.json"
    if [ ! -f "$kg_file" ]; then
        echo "Error: session_dir missing knowledge-graph.json: $session_dir" >&2
        return 1
    fi

    return 0
}

# Validate integer parameter
# Usage: validate_integer "param_name" "$value" [min] [max]
# Returns: 0 if valid, 1 if invalid (with error message)
validate_integer() {
    local param_name="$1"
    local value="${2:-}"
    local min="${3:-}"
    local max="${4:-}"

    if [ -z "$value" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    # Check if integer
    if ! [[ "$value" =~ ^-?[0-9]+$ ]]; then
        echo "Error: $param_name must be an integer, got: $value" >&2
        return 1
    fi

    # Check min bound
    if [ -n "$min" ] && [ "$value" -lt "$min" ]; then
        echo "Error: $param_name must be >= $min, got: $value" >&2
        return 1
    fi

    # Check max bound
    if [ -n "$max" ] && [ "$value" -gt "$max" ]; then
        echo "Error: $param_name must be <= $max, got: $value" >&2
        return 1
    fi

    return 0
}

# Validate float/decimal parameter
# Usage: validate_float "param_name" "$value" [min] [max]
# Returns: 0 if valid, 1 if invalid (with error message)
validate_float() {
    local param_name="$1"
    local value="${2:-}"
    local min="${3:-}"
    local max="${4:-}"

    if [ -z "$value" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    # Check if float (using awk for cross-platform compatibility)
    if ! awk -v val="$value" 'BEGIN { if (val != val+0) exit 1 }'; then
        echo "Error: $param_name must be a number, got: $value" >&2
        return 1
    fi

    # Check min bound
    if [ -n "$min" ]; then
        if awk -v val="$value" -v min="$min" 'BEGIN { exit !(val < min) }'; then
            echo "Error: $param_name must be >= $min, got: $value" >&2
            return 1
        fi
    fi

    # Check max bound
    if [ -n "$max" ]; then
        if awk -v val="$value" -v max="$max" 'BEGIN { exit !(val > max) }'; then
            echo "Error: $param_name must be <= $max, got: $value" >&2
            return 1
        fi
    fi

    return 0
}

# Validate enum value (one of allowed values)
# Usage: validate_enum "param_name" "$value" "option1" "option2" "option3"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_enum() {
    local param_name="$1"
    local value="$2"
    shift 2
    local allowed_values=("$@")

    if [ -z "$value" ]; then
        echo "Error: $param_name parameter is required" >&2
        return 1
    fi

    # Check if value is in allowed list
    local found=0
    for allowed in "${allowed_values[@]}"; do
        if [ "$value" = "$allowed" ]; then
            found=1
            break
        fi
    done

    if [ $found -eq 0 ]; then
        local allowed_str
        allowed_str=$(IFS=", "; echo "${allowed_values[*]}")
        echo "Error: $param_name must be one of: $allowed_str (got: $value)" >&2
        return 1
    fi

    return 0
}

# Validate command exists with helpful error
# Usage: validate_command "jq" "JSON processor"
# Returns: 0 if command exists, 1 if not (with error message)
validate_command() {
    local command_name="$1"
    local command_description="${2:-$command_name}"
    
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Error: $command_description is required but not installed" >&2
        echo "Command: $command_name" >&2
        echo "Install with: brew install $command_name (macOS) or apt install $command_name (Linux)" >&2
        return 1
    fi
    
    return 0
}

# Validate agent metadata structure
# Usage: validate_agent_metadata "$metadata_file"
# Returns: 0 if valid, 1 if invalid (with error message)
validate_agent_metadata() {
    local metadata_file="${1:-}"
    
    # Validate file exists
    validate_file "agent metadata" "$metadata_file" || return 1
    
    # Read metadata
    local metadata
    metadata=$(cat "$metadata_file")
    
    # Validate JSON syntax
    validate_json "agent metadata" "$metadata" || return 1
    
    # Validate required fields
    validate_json_field "$metadata" "name" "string" || return 1
    validate_json_field "$metadata" "capabilities" "array" || return 1
    
    return 0
}

# Export functions for use in other scripts
export -f validate_required
export -f validate_directory
export -f validate_file
export -f validate_json
export -f validate_json_field
export -f validate_session_dir
export -f validate_integer
export -f validate_float
export -f validate_enum
export -f validate_command
export -f validate_agent_metadata
