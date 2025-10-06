#!/usr/bin/env bash
# Dashboard Generator - Creates dashboard.html for each session
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Generate dashboard for session
generate_dashboard() {
    local session_dir="$1"
    
    local template="$PROJECT_ROOT/src/templates/dashboard-template.html"
    local js_template="$PROJECT_ROOT/src/templates/dashboard.js"
    
    if [ ! -f "$template" ]; then
        echo "Error: Dashboard template not found: $template" >&2
        return 1
    fi
    
    if [ ! -f "$js_template" ]; then
        echo "Error: Dashboard JS not found: $js_template" >&2
        return 1
    fi
    
    # Copy template and JS to session directory
    cp "$template" "$session_dir/dashboard.html"
    cp "$js_template" "$session_dir/dashboard.js"
    
    echo "$session_dir/dashboard.html"
}

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir>" >&2
        exit 1
    fi
    
    generate_dashboard "$1"
fi

