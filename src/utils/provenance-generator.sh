#!/usr/bin/env bash
# Provenance Generator - Creates meta/provenance.json
# Captures environment, tool versions, and configuration for reproducibility

set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=src/utils/core-helpers.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

# Main provenance generation function
generate_provenance() {
    local session_dir="$1"
    
    # Convert to absolute path if relative
    if [[ "$session_dir" != /* ]]; then
        session_dir="$(cd "$session_dir" 2>/dev/null && pwd)" || {
            echo "ERROR: Session directory not found: $1" >&2
            return 1
        }
    fi
    
    if [ ! -d "$session_dir" ]; then
        echo "ERROR: Session directory not found: $session_dir" >&2
        return 1
    fi
    
    # Get tool versions
    local cconductor_version
    cconductor_version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "unknown")
    
    local claude_version
    claude_version=$(claude --version 2>/dev/null || echo "unknown")
    
    local bash_version
    bash_version="${BASH_VERSION:-unknown}"
    
    local jq_version
    jq_version=$(jq --version 2>/dev/null || echo "unknown")
    
    local curl_version
    curl_version=$(curl --version 2>/dev/null | head -n 1 || echo "unknown")
    
    # Get Git information (if in repo)
    local git_commit=""
    local git_branch=""
    local git_dirty=false
    
    if [ -d "$PROJECT_ROOT/.git" ]; then
        git_commit=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "")
        git_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]; then
            git_dirty=true
        fi
    fi
    
    # Get configuration checksums
    local paths_checksum=""
    if [ -f "$PROJECT_ROOT/config/paths.default.json" ]; then
        paths_checksum=$("$SCRIPT_DIR/hash-file.sh" "$PROJECT_ROOT/config/paths.default.json" 2>/dev/null || echo "")
    fi
    
    local mcp_checksum=""
    if [ -f "$session_dir/.mcp.json" ]; then
        mcp_checksum=$("$SCRIPT_DIR/hash-file.sh" "$session_dir/.mcp.json" 2>/dev/null || echo "")
    fi
    
    # Get environment variables (non-sensitive)
    local seed="${CCONDUCTOR_SEED:-}"
    local verbose="${CCONDUCTOR_VERBOSE:-0}"
    local cache_enabled="${CCONDUCTOR_CACHE_ENABLED:-false}"
    
    # Get system information
    local os_type
    os_type=$(uname -s)
    
    local os_version
    os_version=$(uname -r)
    
    local architecture
    architecture=$(uname -m)
    
    local timestamp
    timestamp=$(get_timestamp)
    
    # Generate provenance.json
    jq -n \
        --arg timestamp "$timestamp" \
        --arg cconductor_version "$cconductor_version" \
        --arg claude_version "$claude_version" \
        --arg bash_version "$bash_version" \
        --arg jq_version "$jq_version" \
        --arg curl_version "$curl_version" \
        --arg git_commit "$git_commit" \
        --arg git_branch "$git_branch" \
        --argjson git_dirty "$git_dirty" \
        --arg paths_checksum "$paths_checksum" \
        --arg mcp_checksum "$mcp_checksum" \
        --arg seed "$seed" \
        --arg verbose "$verbose" \
        --arg cache_enabled "$cache_enabled" \
        --arg os_type "$os_type" \
        --arg os_version "$os_version" \
        --arg architecture "$architecture" \
        '{
            generated_at: $timestamp,
            cconductor: {
                version: $cconductor_version,
                git_commit: $git_commit,
                git_branch: $git_branch,
                git_dirty: $git_dirty
            },
            runtime: {
                claude_code: $claude_version,
                bash: $bash_version,
                jq: $jq_version,
                curl: $curl_version
            },
            configuration: {
                paths_checksum: $paths_checksum,
                mcp_config_checksum: $mcp_checksum
            },
            environment: {
                seed: $seed,
                verbose: $verbose,
                cache_enabled: $cache_enabled
            },
            system: {
                os: $os_type,
                os_version: $os_version,
                architecture: $architecture
            }
        }' > "$session_dir/meta/provenance.json"
    
    echo "Generated meta/provenance.json"
}

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    
    generate_provenance "$1"
fi
