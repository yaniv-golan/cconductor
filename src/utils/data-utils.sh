#!/usr/bin/env bash
# Data Transformation Utilities
# Safe JSON operations for orchestrator agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh" 2>/dev/null || true

# Merge multiple JSON files
merge_json() {
    local files=("$@")
    
    if [[ ${#files[@]} -eq 0 ]]; then
        jq -n --arg err "No files provided" '{error: $err}'
        return 1
    fi
    
    # Verify all files exist
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            jq -n --arg err "File not found: $file" '{error: $err}' >&2
            return 1
        fi
    done
    
    # Merge objects (later values override earlier ones)
    jq -s 'reduce .[] as $item ({}; . * $item)' "${files[@]}"
}

# Consolidate findings files into single array
consolidate_findings() {
    local pattern="${1:-findings-*.json}"
    
    # Use array to collect files
    local -a files
    mapfile -t files < <(find . -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        jq -n '{consolidated: [], total: 0, message: "No findings files found"}'
        return 0
    fi
    
    # Consolidate into single array
    jq -s '{
        consolidated: .,
        total: (. | length),
        files: [inputs | input_filename]
    }' "${files[@]}"
}

# Extract unique claims from findings
extract_unique_claims() {
    local pattern="${1:-findings-*.json}"
    
    local -a files
    mapfile -t files < <(find . -maxdepth 1 -name "$pattern" -type f 2>/dev/null)
    
    if [[ ${#files[@]} -eq 0 ]]; then
        jq -n '{unique_claims: [], total: 0}'
        return 0
    fi
    
    jq -s '{
        unique_claims: ([.[] | .claims // [] | .[]] | unique_by(.claim)),
        total: ([.[] | .claims // [] | .[]] | unique_by(.claim) | length)
    }' "${files[@]}"
}

# Convert JSON to CSV (for simple flat structures)
json_to_csv() {
    local json_file="$1"
    
    if [[ ! -f "$json_file" ]]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$json_file" "File not found"
        else
            echo "Error: File not found: $json_file" >&2
        fi
        return 1
    fi
    
    # Extract keys as headers, then values as rows
    jq -r '(.[0] | keys_unsorted) as $keys | 
           $keys, 
           (.[] | [.[ $keys[] ]] | @csv)' "$json_file"
}

# Create summary from JSON data
create_summary() {
    local json_file="$1"
    local title="${2:-Summary}"
    
    if [[ ! -f "$json_file" ]]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$json_file" "File not found"
        else
            echo "Error: File not found: $json_file" >&2
        fi
        return 1
    fi
    
    echo "# $title"
    echo ""
    jq -r 'to_entries[] | "- **\(.key)**: \(.value)"' "$json_file"
}

# Group items by field
group_by_field() {
    local json_file="$1"
    local field="$2"
    
    if [[ ! -f "$json_file" ]]; then
        jq -n --arg err "File not found: $json_file" '{error: $err}' >&2
        return 1
    fi
    
    jq --arg field "$field" '
        group_by(.[$field]) | 
        map({
            key: (.[0][$field] // "unknown"),
            count: length,
            items: .
        })' "$json_file"
}

# Export functions
export -f merge_json
export -f consolidate_findings
export -f extract_unique_claims
export -f json_to_csv
export -f create_summary
export -f group_by_field

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        merge)
            shift
            merge_json "$@"
            ;;
        consolidate)
            consolidate_findings "${2:-findings-*.json}"
            ;;
        extract-claims)
            extract_unique_claims "${2:-findings-*.json}"
            ;;
        to-csv)
            json_to_csv "$2"
            ;;
        summarize)
            create_summary "$2" "${3:-Summary}"
            ;;
        group-by)
            group_by_field "$2" "$3"
            ;;
        *)
            cat <<EOF
Data Transformation Utilities for LLM Agents
=============================================

Safe operations for working with research data files.

Usage: $0 <command> [args]

Commands:
  merge <file1> <file2> ...          - Merge JSON objects
  consolidate [pattern]              - Consolidate findings files
  extract-claims [pattern]           - Extract unique claims
  to-csv <json_file>                 - Convert JSON array to CSV
  summarize <json_file> [title]      - Create markdown summary
  group-by <json_file> <field>       - Group items by field

Examples:
  # Merge multiple analysis files
  $0 merge analysis1.json analysis2.json > combined.json
  
  # Consolidate all findings
  $0 consolidate "findings-*.json" > all-findings.json
  
  # Extract unique claims
  $0 extract-claims > unique-claims.json
  
  # Convert to CSV for export
  $0 to-csv data.json > data.csv
  
  # Create summary report
  $0 summarize stats.json "Research Statistics" > summary.md

Output: JSON or text format depending on command
EOF
            ;;
    esac
fi

