#!/bin/bash
# PDF Cache Manager
# Caches fetched PDFs locally with metadata to avoid redundant downloads
#
# Features:
# - Thread-safe cache index updates with file locking
# - Deduplication to prevent duplicate entries
# - Comprehensive error handling with user-friendly messages
# - Automatic cache validation and repair

set -euo pipefail

# Get project root and source path resolver
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/path-resolver.sh"

# Configuration
PDF_CACHE_DIR=$(resolve_path "pdf_cache")
PDF_METADATA_DIR="${PDF_CACHE_DIR}/metadata"
LOCK_FILE="$PDF_CACHE_DIR/.cache-index.lock"
LOCK_TIMEOUT=10  # seconds
MAX_PDF_SIZE_MB=100
DOWNLOAD_TIMEOUT=60

# Load PDF configuration if available
PDF_CONFIG_FILE="$PROJECT_ROOT/config/pdf-config.json"
if [ -f "$PDF_CONFIG_FILE" ]; then
    MAX_CACHE_SIZE_MB=$(jq -r '.cache.max_size_mb // 5000' "$PDF_CONFIG_FILE" 2>/dev/null || echo "5000")
    MAX_AGE_DAYS=$(jq -r '.cache.max_age_days // 90' "$PDF_CONFIG_FILE" 2>/dev/null || echo "90")
    CLEANUP_ON_INIT=$(jq -r '.cache.cleanup_on_init // false' "$PDF_CONFIG_FILE" 2>/dev/null || echo "false")
    EVICTION_POLICY=$(jq -r '.cache.eviction_policy // "lru"' "$PDF_CONFIG_FILE" 2>/dev/null || echo "lru")
else
    MAX_CACHE_SIZE_MB=5000
    MAX_AGE_DAYS=90
    CLEANUP_ON_INIT=false
    EVICTION_POLICY="lru"
fi

# =============================================================================
# LOCKING FUNCTIONS
# =============================================================================

# Acquire lock on cache index
# Returns: 0 on success, 1 on timeout
acquire_cache_lock() {
    local timeout="${1:-$LOCK_TIMEOUT}"
    local elapsed=0
    
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            echo "Error: Could not acquire cache lock after ${timeout}s" >&2
            echo "       If no other process is running, remove: $LOCK_FILE" >&2
            return 1
        fi
        sleep 0.1
        elapsed=$((elapsed + 1))
    done
    
    # Store PID for debugging
    echo $$ > "$LOCK_FILE/pid"
    
    # Set trap to release lock on exit
    trap release_cache_lock EXIT INT TERM
    
    return 0
}

# Release lock on cache index
release_cache_lock() {
    rm -rf "$LOCK_FILE" 2>/dev/null || true
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize cache directories
init_pdf_cache() {
    mkdir -p "$PDF_CACHE_DIR" || {
        echo "Error: Could not create cache directory: $PDF_CACHE_DIR" >&2
        return 1
    }
    
    mkdir -p "$PDF_METADATA_DIR" || {
        echo "Error: Could not create metadata directory: $PDF_METADATA_DIR" >&2
        return 1
    }

    # Create cache index if it doesn't exist
    local index_file="$PDF_CACHE_DIR/cache-index.json"
    if [ ! -f "$index_file" ]; then
        echo '{"pdfs": [], "last_updated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' > "$index_file" || {
            echo "Error: Could not create cache index file" >&2
            return 1
        }
    fi
    
    # Optional auto-cleanup on initialization
    if [ "$CLEANUP_ON_INIT" = "true" ]; then
        auto_cleanup_if_needed
    fi
    
    return 0
}

# =============================================================================
# CACHE KEY FUNCTIONS
# =============================================================================

# Generate cache key from URL (hash)
get_cache_key() {
    local url="$1"
    echo -n "$url" | shasum -a 256 | cut -d' ' -f1
}

# Check if PDF is already cached
is_pdf_cached() {
    local url="$1"
    local cache_key=$(get_cache_key "$url")
    local pdf_file="$PDF_CACHE_DIR/${cache_key}.pdf"

    [ -f "$pdf_file" ]
}

# Get cached PDF path
get_cached_pdf_path() {
    local url="$1"
    local cache_key=$(get_cache_key "$url")
    echo "$PDF_CACHE_DIR/${cache_key}.pdf"
}

# Get PDF metadata path
get_pdf_metadata_path() {
    local url="$1"
    local cache_key=$(get_cache_key "$url")
    echo "$PDF_METADATA_DIR/${cache_key}.json"
}

# =============================================================================
# CACHE MANAGEMENT
# =============================================================================

# Save PDF to cache with metadata
cache_pdf() {
    local url="$1"
    local pdf_path="$2"
    local title="${3:-Unknown}"
    local source="${4:-Unknown}"

    init_pdf_cache || return 1

    # Validate input PDF exists
    if [ ! -f "$pdf_path" ]; then
        echo "Error: Source PDF file not found: $pdf_path" >&2
        return 1
    fi

    local cache_key=$(get_cache_key "$url")
    local cached_pdf="$PDF_CACHE_DIR/${cache_key}.pdf"
    local metadata_file="$PDF_METADATA_DIR/${cache_key}.json"

    # Copy PDF to cache with error handling
    if ! cp "$pdf_path" "$cached_pdf" 2>/dev/null; then
        echo "Error: Failed to copy PDF to cache (check disk space)" >&2
        return 1
    fi

    # Get file metadata
    local file_size=$(stat -f%z "$cached_pdf" 2>/dev/null || stat -c%s "$cached_pdf" 2>/dev/null || echo 0)
    local sha256=$(shasum -a 256 "$cached_pdf" | cut -d' ' -f1)

    # Create metadata using jq (prevents injection attacks)
    if ! jq -n \
        --arg url "$url" \
        --arg title "$title" \
        --arg source "$source" \
        --arg cache_key "$cache_key" \
        --arg cached_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson file_size "$file_size" \
        --arg file_path "$cached_pdf" \
        --arg sha256 "$sha256" \
        '{
            url: $url,
            title: $title,
            source: $source,
            cache_key: $cache_key,
            cached_at: $cached_at,
            file_size: $file_size,
            file_path: $file_path,
            sha256: $sha256
        }' > "$metadata_file" 2>/dev/null; then
        echo "Error: Failed to create metadata file (jq error)" >&2
        rm -f "$cached_pdf"  # Cleanup
        return 1
    fi

    # Update cache index with locking and deduplication
    if ! update_cache_index "$url" "$cache_key" "$title"; then
        echo "Warning: Failed to update cache index" >&2
        # Don't fail - PDF is cached, just index update failed
    fi

    echo "$cached_pdf"
    return 0
}

# Update cache index with new entry (with locking and deduplication)
update_cache_index() {
    local url="$1"
    local cache_key="$2"
    local title="$3"

    local index_file="$PDF_CACHE_DIR/cache-index.json"

    # Acquire lock
    acquire_cache_lock $LOCK_TIMEOUT || return 1

    # Critical section: update index with deduplication
    if ! jq --arg url "$url" \
       --arg key "$cache_key" \
       --arg title "$title" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '
       # Check if entry exists
       if (.pdfs | map(.url) | index($url)) then
         # Update existing entry
         .pdfs = [.pdfs[] | if .url == $url then {url: $url, cache_key: $key, title: $title, cached_at: $date} else . end]
       else
         # Add new entry
         .pdfs += [{url: $url, cache_key: $key, title: $title, cached_at: $date}]
       end | .last_updated = $date
       ' \
       "$index_file" > "${index_file}.tmp" 2>/dev/null; then
        release_cache_lock
        echo "Error: Failed to update cache index (jq error)" >&2
        return 1
    fi

    mv "${index_file}.tmp" "$index_file" || {
        release_cache_lock
        echo "Error: Failed to update cache index file" >&2
        return 1
    }

    # Release lock
    release_cache_lock

    return 0
}

# =============================================================================
# URL VALIDATION
# =============================================================================

# Validate PDF URL format and security
validate_pdf_url() {
    local url="$1"
    
    # Basic format check
    if ! [[ "$url" =~ ^https?:// ]]; then
        echo "Error: Invalid URL format (must start with http:// or https://)" >&2
        return 1
    fi
    
    # Warn about HTTP (not blocking, just warning)
    if [[ "$url" =~ ^http:// ]]; then
        echo "Warning: Using insecure HTTP connection (consider HTTPS)" >&2
    fi
    
    return 0
}

# =============================================================================
# DOWNLOAD AND FETCH
# =============================================================================

# Fetch PDF from URL and cache it (with comprehensive error handling)
fetch_and_cache_pdf() {
    local url="$1"
    local title="${2:-Unknown}"
    local source="${3:-Unknown}"

    # Initialize cache
    init_pdf_cache || return 1

    # Check if already cached
    if is_pdf_cached "$url"; then
        echo "$(get_cached_pdf_path "$url")"
        return 0
    fi

    # Validate URL
    validate_pdf_url "$url" || return 1

    # Check disk space (require 200MB free for safety)
    if command -v df &> /dev/null; then
        local free_space=$(df -k "$PDF_CACHE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "999999999")
        if [ "$free_space" -lt 204800 ]; then
            echo "Error: Insufficient disk space in cache directory" >&2
            echo "       Need at least 200MB free, have $(( free_space / 1024 ))MB" >&2
            return 1
        fi
    fi

    # Download with timeout and size limit
    local temp_pdf=$(mktemp /tmp/pdf-XXXXXX.pdf)
    local max_size_bytes=$((MAX_PDF_SIZE_MB * 1024 * 1024))
    
    echo "Downloading PDF from: $url" >&2

    if ! curl -L -s -f \
         --max-time $DOWNLOAD_TIMEOUT \
         --max-filesize $max_size_bytes \
         -o "$temp_pdf" \
         "$url" 2>/dev/null; then
        rm -f "$temp_pdf"
        echo "Error: Failed to download PDF (network error, timeout, or size > ${MAX_PDF_SIZE_MB}MB)" >&2
        echo "       URL: $url" >&2
        return 1
    fi

    # Check file exists and has content
    if [ ! -s "$temp_pdf" ]; then
        rm -f "$temp_pdf"
        echo "Error: Downloaded file is empty" >&2
        return 1
    fi

    # Verify it's a PDF
    if ! file "$temp_pdf" | grep -q "PDF"; then
        rm -f "$temp_pdf"
        echo "Error: Downloaded file is not a valid PDF" >&2
        echo "       URL may point to HTML page or other content" >&2
        return 1
    fi

    # Cache it
    local cached_path
    if ! cached_path=$(cache_pdf "$url" "$temp_pdf" "$title" "$source"); then
        rm -f "$temp_pdf"
        echo "Error: Failed to cache PDF" >&2
        return 1
    fi

    rm -f "$temp_pdf"
    echo "$cached_path"
    return 0
}

# =============================================================================
# METADATA AND LISTING
# =============================================================================

# Get PDF metadata
get_pdf_metadata() {
    local url="$1"
    local metadata_file=$(get_pdf_metadata_path "$url")

    if [ -f "$metadata_file" ]; then
        cat "$metadata_file"
    else
        echo '{"error": "PDF not found in cache"}'
    fi
}

# List all cached PDFs
list_cached_pdfs() {
    init_pdf_cache || return 1
    
    if [ -f "$PDF_CACHE_DIR/cache-index.json" ]; then
        cat "$PDF_CACHE_DIR/cache-index.json"
    else
        echo '{"pdfs": [], "last_updated": null}'
    fi
}

# =============================================================================
# CACHE UTILITIES
# =============================================================================

# Clear entire cache
clear_pdf_cache() {
    local confirm="${1:-no}"

    if [ "$confirm" = "yes" ]; then
        rm -rf "$PDF_CACHE_DIR"
        echo "PDF cache cleared"
    else
        echo "Warning: This will delete all cached PDFs"
        echo "Use: $0 clear yes"
    fi
}

# Get cache statistics
get_cache_stats() {
    init_pdf_cache || return 1

    local pdf_count=$(find "$PDF_CACHE_DIR" -name "*.pdf" 2>/dev/null | wc -l | tr -d ' ')
    local total_size=$(du -sh "$PDF_CACHE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    local size_mb=$(get_cache_size_mb)
    local limit_mb="$MAX_CACHE_SIZE_MB"
    local usage_percent=$(( (size_mb * 100) / limit_mb ))

    cat <<EOF
{
  "cached_pdfs": $pdf_count,
  "total_size": "$total_size",
  "size_mb": $size_mb,
  "limit_mb": $limit_mb,
  "usage_percent": $usage_percent,
  "cache_location": "$PDF_CACHE_DIR"
}
EOF
}

# Deduplicate cache index entries
deduplicate_cache_index() {
    local index_file="$PDF_CACHE_DIR/cache-index.json"
    
    if [ ! -f "$index_file" ]; then
        echo "Error: Cache index not found" >&2
        return 1
    fi
    
    echo "Deduplicating cache index..." >&2
    
    acquire_cache_lock $LOCK_TIMEOUT || return 1
    
    # Remove duplicates, keeping most recent entry per URL
    if ! jq '.pdfs = [.pdfs | group_by(.url) | .[] | sort_by(.cached_at) | last] | .last_updated = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' \
       "$index_file" > "${index_file}.tmp" 2>/dev/null; then
        release_cache_lock
        echo "Error: Failed to deduplicate index" >&2
        return 1
    fi
    
    mv "${index_file}.tmp" "$index_file"
    
    release_cache_lock
    
    local count=$(jq '.pdfs | length' "$index_file")
    echo "Index deduplicated: $count unique entries" >&2
    return 0
}

# Verify cache integrity
verify_cache_integrity() {
    echo "Verifying cache integrity..." >&2
    
    init_pdf_cache || return 1
    
    local issues=0
    local total=0
    local index_file="$PDF_CACHE_DIR/cache-index.json"
    
    if [ ! -f "$index_file" ]; then
        echo "Error: Cache index not found" >&2
        return 1
    fi
    
    # Get array of cache keys
    local cache_keys_array=($(jq -r '.pdfs[].cache_key' "$index_file" 2>/dev/null))
    
    # Check each indexed PDF exists
    for cache_key in "${cache_keys_array[@]}"; do
        [ -z "$cache_key" ] && continue
        total=$((total + 1))
        local pdf_file="$PDF_CACHE_DIR/${cache_key}.pdf"
        local metadata_file="$PDF_METADATA_DIR/${cache_key}.json"
        
        if [ ! -f "$pdf_file" ]; then
            echo "  ✗ Missing PDF: $cache_key" >&2
            issues=$((issues + 1))
        elif [ ! -f "$metadata_file" ]; then
            echo "  ✗ Missing metadata: $cache_key" >&2
            issues=$((issues + 1))
        else
            # Verify file integrity with stored hash
            local stored_hash=$(jq -r '.sha256' "$metadata_file" 2>/dev/null || echo "")
            if [ -n "$stored_hash" ]; then
                local actual_hash=$(shasum -a 256 "$pdf_file" | cut -d' ' -f1)
                
                if [ "$stored_hash" != "$actual_hash" ]; then
                    echo "  ✗ Hash mismatch: $cache_key" >&2
                    issues=$((issues + 1))
                fi
            fi
        fi
    done
    
    echo "" >&2
    echo "Verification complete:" >&2
    echo "  Total entries: $total" >&2
    echo "  Issues found: $issues" >&2
    
    if [ $issues -gt 0 ]; then
        echo "" >&2
        echo "Run '$0 repair' to fix issues" >&2
        return 1
    fi
    
    echo "  ✓ Cache is healthy" >&2
    return 0
}

# Rebuild cache index from metadata files
rebuild_cache_index() {
    echo "Rebuilding cache index..." >&2
    
    init_pdf_cache || return 1
    
    local index_file="$PDF_CACHE_DIR/cache-index.json"
    
    acquire_cache_lock $LOCK_TIMEOUT || return 1
    
    # Create new index from existing metadata
    local new_index='{"pdfs": [], "last_updated": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'
    
    for metadata_file in "$PDF_METADATA_DIR"/*.json; do
        [ -f "$metadata_file" ] || continue
        if [ -f "$metadata_file" ]; then
            local cache_key=$(basename "$metadata_file" .json)
            local pdf_file="$PDF_CACHE_DIR/${cache_key}.pdf"
            
            # Only include if PDF exists
            if [ -f "$pdf_file" ]; then
                local url=$(jq -r '.url' "$metadata_file" 2>/dev/null || echo "")
                local title=$(jq -r '.title' "$metadata_file" 2>/dev/null || echo "Unknown")
                local cached_at=$(jq -r '.cached_at' "$metadata_file" 2>/dev/null || echo "")
                
                if [ -n "$url" ]; then
                    new_index=$(echo "$new_index" | jq \
                        --arg url "$url" \
                        --arg key "$cache_key" \
                        --arg title "$title" \
                        --arg date "$cached_at" \
                        '.pdfs += [{url: $url, cache_key: $key, title: $title, cached_at: $date}]')
                fi
            fi
        fi
    done
    
    echo "$new_index" > "$index_file"
    
    release_cache_lock
    
    local count=$(echo "$new_index" | jq '.pdfs | length')
    echo "Index rebuilt: $count entries" >&2
    return 0
}

# Cleanup orphaned metadata files
cleanup_orphaned_metadata() {
    echo "Cleaning orphaned metadata..." >&2
    
    local removed=0
    
    for metadata_file in "$PDF_METADATA_DIR"/*.json; do
        [ -f "$metadata_file" ] || continue
        
        local cache_key=$(basename "$metadata_file" .json)
        local pdf_file="$PDF_CACHE_DIR/${cache_key}.pdf"
        
        if [ ! -f "$pdf_file" ]; then
            rm -f "$metadata_file"
            ((removed++))
        fi
    done
    
    echo "Removed $removed orphaned metadata files" >&2
    return 0
}

# Repair cache issues
repair_cache() {
    echo "Repairing cache..." >&2
    
    cleanup_orphaned_metadata
    rebuild_cache_index
    deduplicate_cache_index
    
    echo "Cache repaired successfully" >&2
    return 0
}

# =============================================================================
# CACHE SIZE MANAGEMENT
# =============================================================================

# Get cache size in MB
get_cache_size_mb() {
    init_pdf_cache || return 1
    
    local size_kb=$(du -sk "$PDF_CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    echo $((size_kb / 1024))
}

# Cleanup cache by eviction policy
cleanup_cache() {
    local policy="${1:-$EVICTION_POLICY}"
    local target_size_mb="${2:-$MAX_CACHE_SIZE_MB}"
    
    init_pdf_cache || return 1
    
    echo "Starting cache cleanup (policy: $policy, target: ${target_size_mb}MB)..." >&2
    
    local current_size=$(get_cache_size_mb)
    echo "Current cache size: ${current_size}MB" >&2
    
    if [ "$current_size" -le "$target_size_mb" ]; then
        echo "Cache size OK, no cleanup needed" >&2
        return 0
    fi
    
    local to_remove_mb=$((current_size - target_size_mb))
    echo "Need to free: ${to_remove_mb}MB" >&2
    
    case "$policy" in
        lru)
            cleanup_lru "$to_remove_mb"
            ;;
        age)
            cleanup_by_age "$MAX_AGE_DAYS"
            ;;
        *)
            echo "Error: Unknown eviction policy: $policy" >&2
            return 1
            ;;
    esac
    
    # Cleanup orphaned metadata and rebuild index
    cleanup_orphaned_metadata
    rebuild_cache_index
    
    local new_size=$(get_cache_size_mb)
    echo "Cleanup complete. New size: ${new_size}MB" >&2
    return 0
}

# Cleanup by LRU (Least Recently Used)
cleanup_lru() {
    local target_mb="$1"
    local freed_mb=0
    
    echo "  Using LRU eviction..." >&2
    
    # Find PDFs sorted by access time (oldest first)
    find "$PDF_CACHE_DIR" -name "*.pdf" -type f -exec stat -f '%a %N' {} \; 2>/dev/null | \
        sort -n | while read -r access_time pdf_path; do
        
        if [ "$freed_mb" -ge "$target_mb" ]; then
            break
        fi
        
        local size_mb=$(du -m "$pdf_path" 2>/dev/null | cut -f1)
        local filename=$(basename "$pdf_path")
        
        rm -f "$pdf_path"
        echo "  Removed: $filename (${size_mb}MB, freed so far: $((freed_mb + size_mb))MB)" >&2
        
        # Remove metadata
        local cache_key="${filename%.pdf}"
        rm -f "$PDF_METADATA_DIR/${cache_key}.json"
        
        freed_mb=$((freed_mb + size_mb))
    done
    
    echo "  Freed ${freed_mb}MB using LRU policy" >&2
    return 0
}

# Cleanup by age
cleanup_by_age() {
    local max_days="$1"
    
    echo "  Removing PDFs older than $max_days days..." >&2
    
    local removed=0
    find "$PDF_CACHE_DIR" -name "*.pdf" -type f -mtime +$max_days 2>/dev/null | while read -r pdf_path; do
        local filename=$(basename "$pdf_path")
        local cache_key="${filename%.pdf}"
        
        rm -f "$pdf_path"
        rm -f "$PDF_METADATA_DIR/${cache_key}.json"
        
        removed=$((removed + 1))
        echo "  Removed: $filename" >&2
    done
    
    echo "  Removed $removed old PDF(s)" >&2
    return 0
}

# Auto cleanup if cache exceeds limit
auto_cleanup_if_needed() {
    local current_size=$(get_cache_size_mb)
    
    if [ "$current_size" -gt "$MAX_CACHE_SIZE_MB" ]; then
        echo "Cache size (${current_size}MB) exceeds limit (${MAX_CACHE_SIZE_MB}MB)" >&2
        # Clean to 80% of limit to avoid constant cleanup
        local target=$((MAX_CACHE_SIZE_MB * 80 / 100))
        cleanup_cache "$EVICTION_POLICY" "$target"
    fi
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export functions
export -f init_pdf_cache
export -f get_cache_key
export -f is_pdf_cached
export -f get_cached_pdf_path
export -f get_pdf_metadata_path
export -f cache_pdf
export -f update_cache_index
export -f fetch_and_cache_pdf
export -f get_pdf_metadata
export -f list_cached_pdfs
export -f clear_pdf_cache
export -f get_cache_stats
export -f deduplicate_cache_index
export -f verify_cache_integrity
export -f rebuild_cache_index
export -f repair_cache
export -f get_cache_size_mb
export -f cleanup_cache
export -f cleanup_lru
export -f cleanup_by_age
export -f auto_cleanup_if_needed

# =============================================================================
# CLI INTERFACE
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        fetch)
            if [ -z "${2:-}" ]; then
                echo "Error: URL required" >&2
                echo "Usage: $0 fetch <url> [title] [source]" >&2
                exit 1
            fi
            fetch_and_cache_pdf "$2" "${3:-Unknown}" "${4:-Unknown}"
            ;;
        check)
            if [ -z "${2:-}" ]; then
                echo "Error: URL required" >&2
                echo "Usage: $0 check <url>" >&2
                exit 1
            fi
            if is_pdf_cached "$2"; then
                echo "Cached: $(get_cached_pdf_path "$2")"
            else
                echo "Not cached"
            fi
            ;;
        metadata)
            if [ -z "${2:-}" ]; then
                echo "Error: URL required" >&2
                echo "Usage: $0 metadata <url>" >&2
                exit 1
            fi
            get_pdf_metadata "$2"
            ;;
        list)
            list_cached_pdfs
            ;;
        stats)
            get_cache_stats
            ;;
        clear)
            clear_pdf_cache "${2:-no}"
            ;;
        dedupe)
            deduplicate_cache_index
            ;;
        verify)
            verify_cache_integrity
            ;;
        rebuild)
            rebuild_cache_index
            ;;
        repair)
            repair_cache
            ;;
        size)
            size_mb=$(get_cache_size_mb)
            echo "Cache size: ${size_mb}MB / ${MAX_CACHE_SIZE_MB}MB"
            ;;
        cleanup)
            if [ -z "${2:-}" ]; then
                cleanup_cache "$EVICTION_POLICY" "$MAX_CACHE_SIZE_MB"
            else
                cleanup_cache "$2" "${3:-$MAX_CACHE_SIZE_MB}"
            fi
            ;;
        help|--help|-h)
            cat <<EOF
PDF Cache Manager - Manage cached PDF files

Usage: $0 <command> [args]

Commands:
  fetch <url> [title] [source]  Fetch and cache PDF from URL
  check <url>                    Check if PDF is cached
  metadata <url>                 Get cached PDF metadata
  list                           List all cached PDFs (JSON)
  stats                          Show cache statistics with size/limit
  clear yes                      Clear entire cache (requires 'yes')
  
  dedupe                         Remove duplicate cache entries
  verify                         Verify cache integrity
  rebuild                        Rebuild cache index from metadata
  repair                         Repair cache (cleanup + rebuild + dedupe)
  
  size                           Show current cache size
  cleanup [policy] [target_mb]   Clean cache (policies: lru, age)
  
  help                           Show this help message

Examples:
  # Fetch and cache a PDF
  $0 fetch https://arxiv.org/pdf/1706.03762.pdf "Attention Paper" "arXiv"
  
  # Check cache status
  $0 stats
  
  # Cleanup using LRU policy
  $0 cleanup lru
  
  # Cleanup to specific size
  $0 cleanup lru 1000
  
  # Verify and repair if needed
  $0 verify || $0 repair

Configuration:
  Max size: ${MAX_CACHE_SIZE_MB}MB
  Max age: ${MAX_AGE_DAYS} days
  Policy: $EVICTION_POLICY
  Auto-cleanup: $CLEANUP_ON_INIT
  
Cache Location: $PDF_CACHE_DIR
EOF
            ;;
        *)
            echo "Error: Unknown command: $1" >&2
            echo "Run '$0 help' for usage information" >&2
            exit 1
            ;;
    esac
fi
