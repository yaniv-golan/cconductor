#!/usr/bin/env bash
# Dashboard Viewer - Launches HTTP server for dashboard viewing
set -euo pipefail

# Launch dashboard viewer with HTTP server
# Usage: launch_dashboard_viewer <session_dir> [auto_open]
#   session_dir: Path to research session directory
#   auto_open: Optional, if "true" opens in browser (default: true)
# Returns: 0 on success, 1 on error
launch_dashboard_viewer() {
    local session_dir="$1"
    local auto_open="${2:-true}"
    
    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: $session_dir" >&2
        return 1
    fi
    
    # Check if dashboard exists, generate if needed
    local dashboard_file="$session_dir/dashboard.html"
    if [ ! -f "$dashboard_file" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$script_dir/dashboard-generator.sh" ]; then
            bash "$script_dir/dashboard-generator.sh" "$session_dir" >/dev/null 2>&1 || return 1
        else
            echo "Error: Dashboard generator not found" >&2
            return 1
        fi
    fi
    
    # Find an available port (8890-8899)
    local dashboard_port=""
    for p in {8890..8899}; do
        if ! lsof -i ":$p" >/dev/null 2>&1; then
            dashboard_port=$p
            break
        fi
    done
    
    if [ -z "$dashboard_port" ]; then
        echo "Error: No available ports in range 8890-8899" >&2
        echo "Try: pkill -f 'http-server'" >&2
        return 1
    fi
    
    # Start HTTP server in background
    cd "$session_dir"
    npx --yes http-server -p "$dashboard_port" --silent >/dev/null 2>&1 &
    local server_pid=$!
    cd - >/dev/null
    
    # Store PID for cleanup
    echo "$server_pid" > "$session_dir/.dashboard-server.pid"
    
    # Give server a moment to start
    sleep 1
    
    # Add session ID to URL to prevent caching
    local session_id
    session_id=$(basename "$session_dir")
    local viewer_url="http://localhost:$dashboard_port/dashboard.html?session=$session_id"
    
    echo "  ✓ Research Journal Viewer: $viewer_url"
    echo "     (HTTP server PID: $server_pid, port: $dashboard_port)"
    
    # Auto-open in browser if requested
    if [ "$auto_open" = "true" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open "$viewer_url" 2>/dev/null || true
        elif command -v xdg-open &> /dev/null; then
            xdg-open "$viewer_url" 2>/dev/null || true
        elif command -v explorer.exe &> /dev/null; then
            # WSL
            explorer.exe "$viewer_url" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# Export function if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f launch_dashboard_viewer 2>/dev/null || true
fi
