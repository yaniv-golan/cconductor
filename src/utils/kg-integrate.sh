#!/usr/bin/env bash
# KG Integration Wrapper
# Standalone script to integrate agent findings into knowledge graph
# Handles all dependencies internally for reliable execution

set -euo pipefail

# Save paths before sourcing other scripts (they may overwrite SCRIPT_DIR)
WRAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_ROOT="$(cd "$WRAPPER_DIR/.." && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$WRAPPER_DIR/core-helpers.sh"

# Check for jq dependency using helper
require_command "jq" "brew install jq" "apt install jq" || exit 1

# Source dependencies in correct order with explicit error handling
# Use saved paths to avoid conflicts with sourced scripts that set SCRIPT_DIR
# shellcheck disable=SC1091
source "$WRAPPER_DIR/debug.sh" || exit 1
# shellcheck disable=SC1091
source "$WRAPPER_ROOT/shared-state.sh" || exit 1
# shellcheck disable=SC1091
source "$WRAPPER_DIR/validation.sh" || exit 1
# shellcheck disable=SC1091
source "$WRAPPER_DIR/event-logger.sh" || {
    # Provide stub functions if event-logger unavailable (truly optional)
    log_event() { :; }
}
# shellcheck disable=SC1091
source "$WRAPPER_ROOT/knowledge-graph.sh" || exit 1

# Main integration function
kg_integrate() {
    local session_dir="$1"
    local agent_output_file="$2"
    
    debug "Starting KG integration for $agent_output_file"
    
    # Validate inputs
    if [ ! -d "$session_dir" ]; then
        error "Session directory not found: $session_dir"
        return 1
    fi
    
    if [ ! -f "$agent_output_file" ]; then
        warn "Agent output file not found: $agent_output_file"
        return 0  # Not an error - agent may not have created output yet
    fi
    
    # Call the integration function
    if kg_integrate_agent_output "$session_dir" "$agent_output_file"; then
        info "✓ KG integration completed successfully"
        return 0
    else
        warn "⚠ KG integration completed with warnings (check logs)"
        return 0  # Defensive: don't break execution
    fi
}

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    kg_integrate "$1" "$2"
fi

