#!/usr/bin/env bash
# Cleanup Dashboard Servers - Stops stale HTTP servers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Cleanup stale dashboard HTTP servers
# A server is considered stale if:
# 1. Its PID file exists but the process is dead, OR
# 2. Its session is marked as "completed", OR
# 3. Its session directory no longer exists
cleanup_stale_dashboard_servers() {
    local sessions_dir="${1:-$PROJECT_ROOT/research-sessions}"
    local killed=0
    
    if [ ! -d "$sessions_dir" ]; then
        return 0
    fi
    
    # Find all .dashboard-server.pid files
    while IFS= read -r -d '' pid_file; do
        local session_dir
        session_dir=$(dirname "$pid_file")
        local session_id
        session_id=$(basename "$session_dir")
        
        if [ ! -f "$pid_file" ]; then
            continue
        fi
        
        local server_pid
        server_pid=$(cat "$pid_file" 2>/dev/null || echo "")
        
        if [ -z "$server_pid" ]; then
            rm -f "$pid_file"
            continue
        fi
        
        local is_stale=false
        local reason=""
        
        # Check if process is still running
        if ! kill -0 "$server_pid" 2>/dev/null; then
            is_stale=true
            reason="process not running"
        # Check if session is completed
        elif [ -f "$session_dir/session.json" ]; then
            local status
            status=$(jq -r '.status // "active"' "$session_dir/session.json" 2>/dev/null || echo "active")
            if [ "$status" = "completed" ]; then
                is_stale=true
                reason="session completed"
            fi
        fi
        
        if [ "$is_stale" = true ]; then
            echo "  → Stopping stale HTTP server for $session_id (PID: $server_pid, reason: $reason)"
            kill "$server_pid" 2>/dev/null || true
            rm -f "$pid_file"
            killed=$((killed + 1))
        fi
    done < <(find "$sessions_dir" -name ".dashboard-server.pid" -type f -print0 2>/dev/null)
    
    if [ "$killed" -gt 0 ]; then
        echo "  ✓ Stopped $killed stale HTTP server(s)"
    fi
    
    return 0
}

# If run directly, perform cleanup
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Cleaning up stale dashboard servers..."
    cleanup_stale_dashboard_servers "${1:-}"
fi

# Export function if sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    export -f cleanup_stale_dashboard_servers 2>/dev/null || true
fi
