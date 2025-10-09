#!/usr/bin/env bash
# JSON Parser - Battle-tested patterns for handling Claude Code output
# Extracted from cconductor-adaptive.sh and invoke-agent.sh
#
# Claude Code's JSON output can vary widely:
# - May be wrapped in markdown code blocks (```json ... ```)
# - May have prose before/after the JSON
# - May have nested objects
# - May be a JSON string vs JSON object
#
# This module provides robust extraction and validation utilities.

set -euo pipefail

# Parse JSON from markdown text
# Handles: code blocks, prose before/after, nested objects
# Uses awk with brace counting for robust extraction
parse_json_from_markdown() {
    local text="$1"
    
    # Strip markdown fences first
    text=$(echo "$text" | sed -e 's/^```json$//' -e 's/^```$//')
    
    # Extract JSON using awk with proper brace balancing
    # This handles Claude adding prose before the JSON object
    local parsed_json
    parsed_json=$(echo "$text" | awk '
        BEGIN { depth=0; started=0 }
        /{/ && !started { 
            # Remove everything before first {
            sub(/^[^{]*/, "")
            started=1
        }
        started {
            # Count braces on this line
            open_count = gsub(/{/, "{")
            close_count = gsub(/}/, "}")
            
            print
            
            depth += (open_count - close_count)
            
            # Exit when we close the root object
            if (depth == 0) exit
        }
    ' | sed '/^```$/d')
    
    echo "$parsed_json"
}

# Extract JSON from agent output file
# Handles: .result wrapper, markdown code blocks, prose, nested objects
#
# Usage: extract_json_from_agent_output OUTPUT_FILE [allow_non_json]
#   OUTPUT_FILE: Path to agent output JSON file
#   allow_non_json: If "true", return raw text if JSON extraction fails
#
# Returns: Extracted JSON on stdout, or empty string on failure
extract_json_from_agent_output() {
    local output_file="$1"
    local allow_non_json="${2:-false}"
    
    # Step 1: Get .result field
    local result
    result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)
    
    if [[ -z "$result" ]]; then
        if [[ "$allow_non_json" == "true" ]]; then
            # Return whole file
            cat "$output_file" 2>/dev/null || echo ""
            return 0
        fi
        return 1
    fi
    
    # Step 2: Check if result is a JSON string (quoted) vs JSON object
    local raw_result
    if [[ "$result" == \"*\" ]] && echo "$result" | jq empty 2>/dev/null; then
        # It's a JSON string - extract the content
        raw_result=$(echo "$result" | jq -r '.')
    else
        raw_result="$result"
    fi
    
    # Step 3: Try to parse as JSON directly
    if echo "$raw_result" | jq empty 2>/dev/null; then
        echo "$raw_result"
        return 0
    fi
    
    # Step 4: Extract from markdown code blocks with brace balancing
    local extracted
    extracted=$(parse_json_from_markdown "$raw_result")
    
    # Step 5: Validate extracted JSON
    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi
    
    # Step 6: Fallback
    if [[ "$allow_non_json" == "true" ]]; then
        echo "$raw_result"
        return 0
    fi
    
    return 1
}

# Extract JSON from markdown code block in text
# Similar to extract_json_from_agent_output but works on text, not file
#
# Usage: extract_json_from_text TEXT
extract_json_from_text() {
    local text="$1"
    
    # Try direct parsing first
    if echo "$text" | jq empty 2>/dev/null; then
        echo "$text"
        return 0
    fi
    
    # Try markdown extraction
    local extracted
    extracted=$(parse_json_from_markdown "$text")
    
    if [[ -n "$extracted" ]] && echo "$extracted" | jq empty 2>/dev/null; then
        echo "$extracted"
        return 0
    fi
    
    return 1
}

# Safe jq field access with default value
# Usage: safe_jq_get JSON_STRING JQ_PATH DEFAULT_VALUE
#
# Examples:
#   safe_jq_get "$json" ".field" "default"
#   safe_jq_get "$json" ".cost" "0"
#   safe_jq_get "$json" ".items[]?" "[]"
safe_jq_get() {
    local json="$1"
    local path="$2"
    local default="${3:-}"
    
    local result
    result=$(echo "$json" | jq -r "${path} // empty" 2>/dev/null)
    
    # Check for empty or "null" string
    if [[ -z "$result" ]] || [[ "$result" == "null" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

# Validate JSON structure
# Returns 0 if valid, 1 if invalid
# Usage: validate_json JSON_STRING
validate_json() {
    local json="$1"
    
    if [[ -z "$json" ]]; then
        return 1
    fi
    
    if echo "$json" | jq empty 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Validate JSON file
# Returns 0 if valid, 1 if invalid
# Usage: validate_json_file FILE_PATH
validate_json_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if jq empty "$file" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Export functions for use in subshells
export -f parse_json_from_markdown
export -f extract_json_from_agent_output
export -f extract_json_from_text
export -f safe_jq_get
export -f validate_json
export -f validate_json_file


