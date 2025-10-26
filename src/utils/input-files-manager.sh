#!/usr/bin/env bash
# Input Files Manager
# Discovers and processes user-provided files from --input-dir
#
# Features:
# - Discovers PDFs, markdown, and text files
# - Caches PDFs using content-addressed storage
# - Copies markdown/text to session knowledge directory
# - Creates session manifest (inputs/input-files.json) for tracking

set -euo pipefail

# Get script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh" 2>/dev/null || true

# shellcheck disable=SC1091
source "$SCRIPT_DIR/pdf-cache.sh"

# =============================================================================
# MANIFEST MANAGEMENT
# =============================================================================

# Initialize empty input files manifest
# Usage: init_input_manifest session_dir
init_input_manifest() {
    local session_dir="$1"
    local manifest="$session_dir/inputs/input-files.json"
    
    cat > "$manifest" <<EOF
{
  "input_dir": "",
  "processed_at": "$(get_timestamp)",
  "pdfs": [],
  "markdown": [],
  "text": []
}
EOF
}

# Finalize manifest with input directory path
# Usage: finalize_input_manifest session_dir input_dir
finalize_input_manifest() {
    local session_dir="$1"
    local input_dir="$2"
    local manifest="$session_dir/inputs/input-files.json"
    
    jq --arg dir "$input_dir" \
       '.input_dir = $dir' "$manifest" > "$manifest.tmp" && \
       mv "$manifest.tmp" "$manifest"
}

# Add PDF entry to manifest
# Usage: add_pdf_to_manifest session_dir original_name original_path content_hash cache_path file_size
add_pdf_to_manifest() {
    local session_dir="$1"
    local original_name="$2"
    local original_path="$3"
    local content_hash="$4"
    local cache_path="$5"
    local file_size="$6"
    
    local manifest="$session_dir/inputs/input-files.json"
    
    jq --arg name "$original_name" \
       --arg path "$original_path" \
       --arg hash "$content_hash" \
       --arg cache "$cache_path" \
       --arg size "$file_size" \
       --arg time "$(get_timestamp)" \
       '.pdfs += [{
         original_name: $name,
         original_path: $path,
         sha256: $hash,
         cache_key: $hash,
         cached_path: $cache,
         file_size: ($size | tonumber),
         added_at: $time,
         source_type: "user_provided"
       }]' "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
}

# Add text/markdown file entry to manifest
# Usage: add_text_to_manifest session_dir file_type original_name original_path session_path file_size
add_text_to_manifest() {
    local session_dir="$1"
    local file_type="$2"  # "markdown" or "text"
    local original_name="$3"
    local original_path="$4"
    local session_path="$5"
    local file_size="$6"
    
    local manifest="$session_dir/inputs/input-files.json"
    
    jq --arg name "$original_name" \
       --arg path "$original_path" \
       --arg spath "$session_path" \
       --arg size "$file_size" \
       --arg time "$(get_timestamp)" \
       ".${file_type} += [{
         original_name: \$name,
         original_path: \$path,
         session_path: \$spath,
         file_size: (\$size | tonumber),
         added_at: \$time
       }]" "$manifest" > "$manifest.tmp" && mv "$manifest.tmp" "$manifest"
}

# =============================================================================
# FILE PROCESSING
# =============================================================================

# Process single PDF file
# Usage: process_pdf file_path session_dir
process_pdf() {
    local file_path="$1"
    local session_dir="$2"
    
    local original_name
    original_name=$(basename "$file_path")
    local file_size
    file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo 0)
    
    # Compute content hash
    local content_hash
    content_hash=$(compute_file_hash "$file_path") || {
        if command -v log_error &>/dev/null; then
            log_error "Failed to hash PDF: $file_path"
        else
            echo "Error: Failed to hash PDF: $file_path" >&2
        fi
        return 1
    }
    
    # Check if already in cache (by content hash)
    local cache_path
    if cache_has_content_hash "$content_hash"; then
        echo "  ✓ $original_name - using cached version" >&2
        cache_path=$(get_cache_path_by_content_hash "$content_hash")
    else
        echo "  ✓ $original_name ($file_size bytes) - adding to cache" >&2
        # Add to cache using content-based hashing
        cache_path=$(cache_local_pdf "$file_path" "$original_name") || {
            if command -v log_error &>/dev/null; then
                log_error "Failed to cache PDF: $file_path"
            else
                echo "Error: Failed to cache PDF: $file_path" >&2
            fi
            return 1
        }
    fi
    
    # Add to session manifest
    add_pdf_to_manifest "$session_dir" "$original_name" "$file_path" \
                        "$content_hash" "$cache_path" "$file_size"
}

# Process text/markdown file
# Usage: process_text_file file_path session_dir
process_text_file() {
    local file_path="$1"
    local session_dir="$2"
    
    local original_name
    original_name=$(basename "$file_path")
    local file_size
    file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo 0)
    local session_path="knowledge/$original_name"
    
    # Create knowledge directory if needed
    mkdir -p "$session_dir/knowledge"
    
    # Copy to session knowledge directory
    if ! cp "$file_path" "$session_dir/knowledge/"; then
        log_system_error "$session_dir" "input_files_manager" "Failed to copy file to session knowledge" "file=$file_path"
        echo "Error: Failed to copy file to session knowledge: $file_path" >&2
        return 1
    fi
    
    echo "  ✓ $original_name - loaded to session knowledge" >&2
    
    # Determine type
    local file_type="text"
    [[ "$original_name" =~ \.md$ ]] && file_type="markdown"
    
    # Add to session manifest
    add_text_to_manifest "$session_dir" "$file_type" "$original_name" \
                        "$file_path" "$session_path" "$file_size"
}

# =============================================================================
# MAIN PROCESSING
# =============================================================================

# Discover and process all files in input directory
# Usage: process_input_directory input_dir session_dir
process_input_directory() {
    local input_dir="$1"
    local session_dir="$2"
    
    # Validate directory
    if [[ ! -d "$input_dir" ]]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$input_dir" "Input directory not found"
        else
            echo "Error: Input directory not found: $input_dir" >&2
        fi
        return 1
    fi
    
    # Convert to absolute path
    input_dir=$(cd "$input_dir" && pwd)
    
    # Initialize session manifest
    init_input_manifest "$session_dir"
    
    # Discover PDFs (flat, no recursion)
    local pdf_files=()
    while IFS= read -r -d '' file; do
        pdf_files+=("$file")
    done < <(find "$input_dir" -maxdepth 1 -type f -name "*.pdf" -print0 2>/dev/null || true)
    
    # Process each PDF
    for pdf in "${pdf_files[@]}"; do
        process_pdf "$pdf" "$session_dir" || {
            if command -v log_warn &>/dev/null; then
                log_warn "Failed to process PDF: $pdf"
            else
                echo "Warning: Failed to process PDF: $pdf" >&2
            fi
        }
    done
    
    # Discover markdown/text files (flat, no recursion)
    local text_files=()
    while IFS= read -r -d '' file; do
        text_files+=("$file")
    done < <(find "$input_dir" -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null || true)
    
    # Process each text file
    for txt in "${text_files[@]}"; do
        process_text_file "$txt" "$session_dir" || {
            if command -v log_warn &>/dev/null; then
                log_warn "Failed to process file: $txt"
            else
                echo "Warning: Failed to process file: $txt" >&2
            fi
        }
    done
    
    # Check for unsupported file types and warn
    local other_files
    other_files=$(find "$input_dir" -maxdepth 1 -type f ! -name "*.pdf" ! -name "*.md" ! -name "*.txt" 2>/dev/null || true)
    if [[ -n "$other_files" ]]; then
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                echo "  ⚠  $(basename "$file") - unsupported file type, skipping" >&2
            fi
        done <<< "$other_files"
    fi
    
    # Finalize manifest with input directory
    finalize_input_manifest "$session_dir" "$input_dir"
    
    # Print summary
    local pdf_count=${#pdf_files[@]}
    local text_count=${#text_files[@]}
    echo "" >&2
    echo "Processed $pdf_count PDF(s) and $text_count text/markdown file(s)" >&2
    
    return 0
}
