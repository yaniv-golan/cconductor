#!/usr/bin/env bash
# File Helpers - File operation utilities with safety features

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

# Safely copy file with backup
# Usage: safe_copy source dest [backup_suffix]
safe_copy() {
    local source="$1"
    local dest="$2"
    local backup_suffix="${3:-.bak}"
    
    if [[ ! -f "$source" ]]; then
        log_error "Source file not found: $source"
        return 1
    fi
    
    # If destination exists, create backup
    if [[ -f "$dest" ]]; then
        local backup="${dest}${backup_suffix}"
        cp "$dest" "$backup" || {
            log_error "Failed to create backup: $backup"
            return 1
        }
        log_debug "Created backup: $backup"
    fi
    
    # Copy source to dest
    if cp "$source" "$dest"; then
        log_debug "Copied $source -> $dest"
        return 0
    else
        log_error "Failed to copy $source -> $dest"
        return 1
    fi
}

# Atomically write file via temp file
# Usage: atomic_write_file target_file "content"
atomic_write_file() {
    local target="$1"
    local content="$2"
    
    local temp_file="${target}.tmp.$$"
    
    # Write to temp file
    if ! echo "$content" > "$temp_file"; then
        log_error "Failed to write temp file: $temp_file"
        rm -f "$temp_file"
        return 1
    fi
    
    # Atomic move
    if mv "$temp_file" "$target"; then
        log_debug "Atomically wrote: $target"
        return 0
    else
        log_error "Failed to move temp file to target: $target"
        rm -f "$temp_file"
        return 1
    fi
}

# Ensure directory exists (create if missing)
# Usage: ensure_dir /path/to/directory [mode]
ensure_dir() {
    local dir="$1"
    local mode="${2:-0755}"
    
    if [[ -d "$dir" ]]; then
        return 0
    fi
    
    if mkdir -p "$dir"; then
        chmod "$mode" "$dir" 2>/dev/null || true
        log_debug "Created directory: $dir"
        return 0
    else
        log_error "Failed to create directory: $dir"
        return 1
    fi
}

# Clean old files from directory
# Usage: clean_old_files directory max_age_days [pattern]
clean_old_files() {
    local dir="$1"
    local max_age_days="$2"
    local pattern="${3:-*}"
    
    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi
    
    if [[ ! "$max_age_days" =~ ^[0-9]+$ ]]; then
        log_error "Invalid age (must be number): $max_age_days"
        return 1
    fi
    
    local count=0
    # Find and delete files older than max_age_days
    while IFS= read -r -d '' file; do
        rm -f "$file" && ((count++)) || true
    done < <(find "$dir" -name "$pattern" -type f -mtime +"$max_age_days" -print0 2>/dev/null)
    
    if [[ $count -gt 0 ]]; then
        log_info "Cleaned $count old files from $dir"
    fi
    
    return 0
}

# Get file size in bytes
# Usage: get_file_size file.txt
get_file_size() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi
    
    # Cross-platform file size
    if command -v stat >/dev/null 2>&1; then
        if stat -f%z "$file" 2>/dev/null; then
            # BSD stat (macOS)
            return 0
        elif stat -c%s "$file" 2>/dev/null; then
            # GNU stat (Linux)
            return 0
        fi
    fi
    
    # Fallback: use wc
    wc -c < "$file" | tr -d ' '
}

# Check if file is older than N days
# Usage: file_older_than file.txt 7  # returns 0 if file is >7 days old
file_older_than() {
    local file="$1"
    local days="$2"
    
    if [[ ! -f "$file" ]]; then
        return 1
    fi
    
    if [[ ! "$days" =~ ^[0-9]+$ ]]; then
        log_error "Invalid days (must be number): $days"
        return 1
    fi
    
    # Use find to check age
    if find "$file" -mtime +"$days" 2>/dev/null | grep -q .; then
        return 0  # File is older
    else
        return 1  # File is newer
    fi
}

# Rotate file (file.log -> file.log.1, file.log.1 -> file.log.2, etc.)
# Usage: rotate_file file.log [max_rotations]
rotate_file() {
    local file="$1"
    local max_rotations="${2:-5}"
    
    if [[ ! -f "$file" ]]; then
        return 0  # Nothing to rotate
    fi
    
    # Remove oldest rotation if it exists
    [[ -f "${file}.${max_rotations}" ]] && rm -f "${file}.${max_rotations}"
    
    # Rotate existing files
    for ((i=max_rotations-1; i>=1; i--)); do
        if [[ -f "${file}.${i}" ]]; then
            mv "${file}.${i}" "${file}.$((i+1))"
        fi
    done
    
    # Rotate main file
    mv "$file" "${file}.1"
    log_debug "Rotated file: $file"
}

# Create temporary file with cleanup trap
# Usage: temp_file=$(create_temp_file) ; trap "rm -f $temp_file" EXIT
create_temp_file() {
    local prefix="${1:-tmp}"
    local temp_file
    
    temp_file=$(mktemp "/tmp/${prefix}.XXXXXX") || {
        log_error "Failed to create temporary file"
        return 1
    }
    
    echo "$temp_file"
}

# Create temporary directory with cleanup trap
# Usage: temp_dir=$(create_temp_dir) ; trap "rm -rf $temp_dir" EXIT
create_temp_dir() {
    local prefix="${1:-tmp}"
    local temp_dir
    
    temp_dir=$(mktemp -d "/tmp/${prefix}.XXXXXX") || {
        log_error "Failed to create temporary directory"
        return 1
    }
    
    echo "$temp_dir"
}

# Export functions
export -f safe_copy
export -f atomic_write_file
export -f ensure_dir
export -f clean_old_files
export -f get_file_size
export -f file_older_than
export -f rotate_file
export -f create_temp_file
export -f create_temp_dir

