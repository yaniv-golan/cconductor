#!/usr/bin/env bash
# PDF Reader Utility
#
# Purpose: Prepares PDFs for reading with Claude's native Read tool
#
# This utility does NOT extract text directly. Instead, it:
# 1. Fetches and caches PDFs from URLs
# 2. Provides file paths for Claude's Read tool
# 3. Generates structured metadata and templates
#
# For actual PDF text extraction, use Claude's read_file tool which
# provides superior text and visual analysis capabilities.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/pdf-cache.sh"

# =============================================================================
# PDF INFORMATION RETRIEVAL
# =============================================================================

# Get PDF read information for Claude's Read tool
#
# This function does NOT extract text. It returns information needed
# to read the PDF with Claude's native Read tool.
#
# Args:
#   pdf_path: Path to cached PDF file
#   output_format: text|json (default: text)
#
# Returns:
#   Information about the PDF and instructions for Read tool
get_pdf_read_info() {
    local pdf_path="$1"
    local output_format="${2:-text}"

    if [ ! -f "$pdf_path" ]; then
        echo "Error: PDF file not found: $pdf_path" >&2
        return 1
    fi

    case "$output_format" in
        text)
            echo "PDF File: $pdf_path"
            echo ""
            echo "Instructions:"
            echo "  Use Claude's read_file tool with this path to read the PDF."
            echo ""
            echo "Capabilities:"
            echo "  • Page-by-page text extraction"
            echo "  • Visual content analysis (figures, tables, equations)"
            echo "  • Document structure recognition"
            echo ""
            echo "Usage:"
            echo "  read_file(target_file='$pdf_path')"
            ;;
        json)
            cat <<EOF
{
  "file_path": "$pdf_path",
  "file_size": $(stat -f%z "$pdf_path" 2>/dev/null || stat -c%s "$pdf_path" 2>/dev/null || echo 0),
  "instructions": "Use Claude's read_file tool with target_file: $pdf_path",
  "note": "Claude's Read tool handles PDFs natively with text and visual extraction"
}
EOF
            ;;
        *)
            echo "Error: Unknown format: $output_format" >&2
            echo "Supported formats: text, json" >&2
            return 1
            ;;
    esac
}

# Get PDF metadata using pdfinfo (if available)
#
# This function DOES extract metadata (title, author, pages) using pdfinfo.
# If pdfinfo is not available, returns basic file information.
#
# Args:
#   pdf_path: Path to PDF file
#
# Returns:
#   PDF metadata in text format
get_pdf_metadata_info() {
    local pdf_path="$1"

    if [ ! -f "$pdf_path" ]; then
        echo "Error: PDF file not found: $pdf_path" >&2
        return 1
    fi

    # Use pdfinfo if available, otherwise basic file info
    if command -v pdfinfo &> /dev/null; then
        pdfinfo "$pdf_path" 2>/dev/null | grep -E "^(Title|Author|Subject|Keywords|CreationDate|Pages):" || true
    else
        echo "Title: $(basename "$pdf_path" .pdf)"
        echo "Pages: Unknown"
        echo ""
        echo "Note: Install poppler-utils (pdfinfo) for detailed PDF metadata"
        echo "  macOS: brew install poppler"
        echo "  Linux: apt-get install poppler-utils"
    fi
}

# =============================================================================
# PDF PREPARATION FOR CLAUDE
# =============================================================================

# Prepare PDF from URL for reading with Claude's Read tool
#
# This function:
# 1. Fetches PDF from URL (or retrieves from cache)
# 2. Caches it locally
# 3. Returns structured information for Claude to read it
#
# Args:
#   url: PDF URL to fetch
#   title: PDF title (optional, default: Unknown)
#   source: PDF source (optional, default: Unknown)
#
# Returns:
#   JSON with cached path and reading instructions
prepare_pdf_for_read() {
    local url="$1"
    local title="${2:-Unknown}"
    local source="${3:-Unknown}"

    # Fetch and cache if not already cached
    local cached_path
    if is_pdf_cached "$url"; then
        cached_path=$(get_cached_pdf_path "$url")
        echo "Using cached PDF: $cached_path" >&2
    else
        echo "Fetching PDF from: $url" >&2
        cached_path=$(fetch_and_cache_pdf "$url" "$title" "$source")
    fi

    # Get metadata from cache
    local metadata
    metadata=$(get_pdf_metadata "$url")

    # Output structured info for agent to use
    cat <<EOF
{
  "pdf_url": "$url",
  "cached_path": "$cached_path",
  "title": "$title",
  "source": "$source",
  "metadata": $metadata,
  "instructions": "Use read_file tool with target_file: $cached_path",
  "note": "Claude's Read tool handles PDFs natively with page-by-page processing"
}
EOF
}

# =============================================================================
# ACADEMIC PAPER HELPERS
# =============================================================================

# Get academic paper structure template
#
# This function does NOT extract sections from the PDF. It returns
# a template of sections commonly found in academic papers for Claude
# to use when reading the PDF.
#
# Args:
#   pdf_path: Path to academic paper PDF
#
# Returns:
#   JSON template with expected academic paper sections
get_paper_structure_template() {
    local pdf_path="$1"

    cat <<EOF
{
  "pdf_path": "$pdf_path",
  "extraction_strategy": "academic_paper",
  "expected_sections": [
    "Abstract",
    "Introduction",
    "Methodology/Methods",
    "Results",
    "Discussion",
    "Conclusion",
    "References"
  ],
  "instructions": "Use Claude's read_file tool to read the PDF and identify these sections",
  "note": "The Read tool can process academic PDFs page by page and extract structured content"
}
EOF
}

# =============================================================================
# BATCH OPERATIONS
# =============================================================================

# Batch prepare multiple PDFs from a file
#
# Reads a file with URLs (one per line, pipe-separated: url|title|source)
# and prepares all PDFs for reading. Info files are saved to output directory.
#
# Args:
#   urls_file: Path to file containing URLs
#
# File format:
#   url|title|source
#   https://example.com/paper.pdf|Paper Title|Journal Name
#
# Returns:
#   Saves JSON info files for each PDF
batch_prepare_pdfs() {
    local urls_file="$1"

    if [ ! -f "$urls_file" ]; then
        echo "Error: URLs file not found: $urls_file" >&2
        return 1
    fi

    local output_dir
    output_dir="$(dirname "$urls_file")/pdf-cache-info"
    mkdir -p "$output_dir"

    echo "Batch preparing PDFs from: $urls_file" >&2
    echo "Output directory: $output_dir" >&2
    echo "" >&2

    local count=0
    local success=0
    local failed=0

    while IFS='|' read -r url title source; do
        # Skip empty lines or comments
        [[ -z "$url" || "$url" =~ ^# ]] && continue

        count=$((count + 1))
        echo "[$count] Processing: $title" >&2

        local info_file="$output_dir/pdf-$count.json"
        
        if prepare_pdf_for_read "$url" "$title" "$source" > "$info_file" 2>&1; then
            success=$((success + 1))
            echo "    ✓ Saved: $info_file" >&2
        else
            failed=$((failed + 1))
            echo "    ✗ Failed to process" >&2
        fi
        
        echo "" >&2
    done < "$urls_file"

    echo "Batch complete:" >&2
    echo "  Total: $count PDFs" >&2
    echo "  Success: $success" >&2
    echo "  Failed: $failed" >&2
    echo "  Output: $output_dir" >&2
}

# =============================================================================
# EXPORTS
# =============================================================================

# Export functions for use in other scripts
export -f get_pdf_read_info
export -f get_pdf_metadata_info
export -f prepare_pdf_for_read
export -f get_paper_structure_template
export -f batch_prepare_pdfs

# =============================================================================
# CLI INTERFACE
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        info)
            if [ -z "${2:-}" ]; then
                echo "Error: PDF path required" >&2
                echo "Usage: $0 info <pdf_path> [format]" >&2
                exit 1
            fi
            get_pdf_read_info "$2" "${3:-text}"
            ;;
        metadata)
            if [ -z "${2:-}" ]; then
                echo "Error: PDF path required" >&2
                echo "Usage: $0 metadata <pdf_path>" >&2
                exit 1
            fi
            get_pdf_metadata_info "$2"
            ;;
        prepare)
            if [ -z "${2:-}" ]; then
                echo "Error: URL required" >&2
                echo "Usage: $0 prepare <url> [title] [source]" >&2
                exit 1
            fi
            prepare_pdf_for_read "$2" "${3:-Unknown}" "${4:-Unknown}"
            ;;
        structure)
            if [ -z "${2:-}" ]; then
                echo "Error: PDF path required" >&2
                echo "Usage: $0 structure <pdf_path>" >&2
                exit 1
            fi
            get_paper_structure_template "$2"
            ;;
        batch)
            if [ -z "${2:-}" ]; then
                echo "Error: URLs file required" >&2
                echo "Usage: $0 batch <urls_file>" >&2
                exit 1
            fi
            batch_prepare_pdfs "$2"
            ;;
        help|--help|-h)
            cat <<EOF
PDF Reader Utility - Prepare PDFs for Claude's Read tool

Usage: $0 <command> <args>

Commands:
  info <pdf> [format]            Get PDF read information (format: text|json)
  metadata <pdf>                 Get PDF metadata (title, author, pages)
  prepare <url> [title] [source] Fetch, cache, and prepare PDF
  structure <pdf>                Get academic paper structure template
  batch <urls_file>              Process multiple PDFs from file
  
  help                           Show this help message

Important:
  This utility does NOT extract text from PDFs. It prepares PDFs
  for reading with Claude's native Read tool, which provides:
  
  • Superior text extraction
  • Visual content analysis (figures, tables, equations)
  • Document structure recognition
  • Page-by-page processing

Examples:
  # Get reading info for a cached PDF
  $0 info /path/to/cached.pdf
  
  # Get PDF metadata
  $0 metadata /path/to/paper.pdf
  
  # Fetch and prepare PDF from URL
  $0 prepare "https://arxiv.org/pdf/1706.03762.pdf" "Attention" "arXiv"
  
  # Get academic paper structure template
  $0 structure /path/to/paper.pdf
  
  # Batch process PDFs (file format: url|title|source per line)
  $0 batch urls.txt

Note: For actual PDF reading, use Claude's read_file tool with the
      cached PDF path returned by these commands.
EOF
            ;;
        *)
            echo "Error: Unknown command: $1" >&2
            echo "Run '$0 help' for usage information" >&2
            exit 1
            ;;
    esac
fi
