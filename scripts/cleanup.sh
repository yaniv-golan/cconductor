#!/usr/bin/env bash
# CConductor Cleanup Script
# Cleans up old sessions, processes, and temporary files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║            CCONDUCTOR - CLEANUP SCRIPT                         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Function to kill processes
kill_processes() {
    echo "→ Checking for running processes..."
    
    # Find CConductor processes
    # shellcheck disable=SC2155,SC2009  # Combined declaration+assignment is intentional, ps+grep is portable
    local cconductor_pids=$(ps aux | grep -E "[d]elve|[D]ELVE" | awk '{print $2}' || true)
    
    # Find Claude processes
    # shellcheck disable=SC2155,SC2009
    local claude_pids=$(ps aux | grep "[c]laude" | grep -v "claude-runtime" | awk '{print $2}' || true)
    
    # Find HTTP server processes (from dashboard)
    # shellcheck disable=SC2155,SC2009
    local http_pids=$(ps aux | grep "[p]ython.*http.server" | awk '{print $2}' || true)
    
    local killed=0
    
    if [ -n "$cconductor_pids" ]; then
        echo "  → Killing CConductor processes: $cconductor_pids"
        echo "$cconductor_pids" | xargs kill -9 2>/dev/null || true
        killed=$((killed + $(echo "$cconductor_pids" | wc -w)))
    fi
    
    if [ -n "$claude_pids" ]; then
        echo "  → Killing Claude processes: $claude_pids"
        echo "$claude_pids" | xargs kill -9 2>/dev/null || true
        killed=$((killed + $(echo "$claude_pids" | wc -w)))
    fi
    
    if [ -n "$http_pids" ]; then
        echo "  → Killing HTTP server processes: $http_pids"
        echo "$http_pids" | xargs kill -9 2>/dev/null || true
        killed=$((killed + $(echo "$http_pids" | wc -w)))
    fi
    
    if [ "$killed" -eq 0 ]; then
        echo "  ✓ No processes to kill"
    else
        echo "  ✓ Killed $killed process(es)"
    fi
    echo ""
}

# Function to clean research sessions
clean_sessions() {
    echo "→ Cleaning research sessions..."
    
    cd "$PROJECT_ROOT"
    
    # Count sessions
    local session_count=0
    if [ -d "research-sessions" ]; then
        session_count=$(find research-sessions -maxdepth 1 -type d -name "session_*" 2>/dev/null | wc -l | tr -d ' ')
    fi
    
    # Calculate size
    local session_size="0"
    if [ "$session_count" -gt 0 ]; then
        session_size=$(du -sh research-sessions 2>/dev/null | awk '{print $1}')
    fi
    
    if [ "$session_count" -eq 0 ]; then
        echo "  ✓ No sessions to clean"
    else
        echo "  → Found $session_count session(s) (Total: $session_size)"
        read -r -p "  → Delete all sessions? [y/N] " response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf research-sessions/session_* 2>/dev/null || true
            rm -f research-sessions/.latest 2>/dev/null || true
            echo "  ✓ Deleted $session_count session(s)"
        else
            echo "  ⊘ Skipped session cleanup"
        fi
    fi
    echo ""
}

# Function to clean temporary files
clean_temp_files() {
    echo "→ Cleaning temporary files..."
    
    cd "$PROJECT_ROOT"
    
    local cleaned=0
    
    # Remove .latest symlink
    if [ -L "research-sessions/.latest" ] || [ -f "research-sessions/.latest" ]; then
        rm -f research-sessions/.latest
        echo "  ✓ Removed .latest symlink"
        cleaned=$((cleaned + 1))
    fi
    
    # Remove temp test directories
    if [ -d "/tmp/test-agents" ]; then
        rm -rf /tmp/test-agents
        echo "  ✓ Removed /tmp/test-agents"
        cleaned=$((cleaned + 1))
    fi
    
    # Remove any backup files
    # shellcheck disable=SC2155  # Combined declaration is intentional
    local backup_count=$(find . -name "*.backup" -o -name "*.bak" -o -name "*~" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$backup_count" -gt 0 ]; then
        # shellcheck disable=SC2146  # Delete each pattern separately
        find . -name "*.backup" -delete 2>/dev/null || true
        find . -name "*.bak" -delete 2>/dev/null || true
        find . -name "*~" -delete 2>/dev/null || true
        echo "  ✓ Removed $backup_count backup file(s)"
        cleaned=$((cleaned + backup_count))
    fi
    
    # Clean old logs (if logs directory exists and has .log files)
    if [ -d "logs" ]; then
        # shellcheck disable=SC2155  # Combined declaration is intentional
        local log_count=$(find logs -name "*.log" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$log_count" -gt 0 ]; then
            read -r -p "  → Delete $log_count log file(s)? [y/N] " response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                rm -f logs/*.log 2>/dev/null || true
                echo "  ✓ Removed $log_count log file(s)"
                cleaned=$((cleaned + log_count))
            else
                echo "  ⊘ Skipped log cleanup"
            fi
        fi
    fi
    
    if [ "$cleaned" -eq 0 ]; then
        echo "  ✓ No temporary files to clean"
    fi
    echo ""
}

# Function to show summary
show_summary() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                   CLEANUP SUMMARY                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
    
    # Check remaining sessions
    local remaining_sessions=0
    if [ -d "$PROJECT_ROOT/research-sessions" ]; then
        remaining_sessions=$(find "$PROJECT_ROOT/research-sessions" -maxdepth 1 -type d -name "session_*" 2>/dev/null | wc -l | tr -d ' ')
    fi
    
    # Check remaining processes
    local remaining_procs=0
    # shellcheck disable=SC2009,SC2126  # ps+grep is portable, grep -c doesn't work here
    remaining_procs=$(ps aux | grep -E "[d]elve|[c]laude|[p]ython.*http.server" | wc -l | tr -d ' ')
    
    echo "  Sessions remaining: $remaining_sessions"
    echo "  Processes running: $remaining_procs"
    
    if [ "$remaining_sessions" -eq 0 ] && [ "$remaining_procs" -eq 0 ]; then
        echo ""
        echo "  ✓ System is clean!"
    fi
    echo ""
}

# Main execution
main() {
    kill_processes
    clean_sessions
    clean_temp_files
    show_summary
    
    echo "✓ Cleanup complete"
}

# Run main
main

