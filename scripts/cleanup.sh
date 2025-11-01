#!/usr/bin/env bash
# CConductor Cleanup Script
# Cleans up old sessions, processes, and temporary files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

SESSION_UTILS_PATH="$PROJECT_ROOT/src/utils/session-utils.sh"
if [ -f "$SESSION_UTILS_PATH" ]; then
    # shellcheck disable=SC1090
    source "$SESSION_UTILS_PATH"
fi

readonly PROCESS_GROUPS=(
    "CConductor CLI|cconductor|"
    "Claude CLI|claude|claude-runtime"
    "Mission HTTP server|http.server|"
)

TERMINATED_COUNT=0

print_header() {
    cat <<'EOF'
╔═══════════════════════════════════════════════════════════╗
║                 CCONDUCTOR - CLEANUP SCRIPT               ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo ""
}

collect_pids() {
    local include="$1"
    local exclude="${2:-}"
    local -a found=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local pid="${line%% *}"
        local cmd="${line#* }"
        [[ -z "$pid" || -z "$cmd" ]] && continue

        if [[ "$cmd" != *"$include"* ]]; then
            continue
        fi

        if [[ -n "$exclude" && "$cmd" == *"$exclude"* ]]; then
            continue
        fi

        if [[ "$pid" != "$$" ]]; then
            found+=("$pid")
        fi
    done < <(ps ax -o pid=,command= 2>/dev/null)

    printf '%s\n' "${found[@]}"
}

terminate_process_group() {
    local label="$1"
    local include="$2"
    local exclude="${3:-}"
    TERMINATED_COUNT=0

    mapfile -t pids < <(collect_pids "$include" "$exclude")
    if ((${#pids[@]} == 0)); then
        echo "  ✓ No ${label} processes to kill"
        return 0
    fi

    echo "  → Terminating ${label} processes: ${pids[*]}"
    log_warn "Terminating ${label} processes: ${pids[*]}"

    if ! kill "${pids[@]}" 2>/dev/null; then
        log_warn "SIGTERM failed for ${label}; escalating to SIGKILL"
    fi

    sleep 0.5
    mapfile -t remaining < <(collect_pids "$include" "$exclude")

    if ((${#remaining[@]} > 0)); then
        if ! kill -9 "${remaining[@]}" 2>/dev/null; then
            log_error "Failed to force terminate ${label} processes: ${remaining[*]}"
        else
            log_warn "Force killed ${label} processes: ${remaining[*]}"
        fi
    fi

    TERMINATED_COUNT=${#pids[@]}
    echo "  ✓ Killed ${TERMINATED_COUNT} process(es)"
}

kill_processes() {
    echo "→ Checking for running processes..."

    local total_killed=0
    local group
    for group in "${PROCESS_GROUPS[@]}"; do
        IFS='|' read -r label include exclude <<< "$group"
        terminate_process_group "$label" "$include" "$exclude"
        total_killed=$((total_killed + TERMINATED_COUNT))
    done

    if ((total_killed == 0)); then
        echo "  ✓ No processes to kill"
    fi
    echo ""
}

clean_sessions() {
    echo "→ Cleaning research sessions..."

    local session_root="$PROJECT_ROOT/research-sessions"
    local -a session_dirs=()

    if declare -f session_utils_list_session_dirs >/dev/null 2>&1; then
        mapfile -t session_dirs < <(session_utils_list_session_dirs)
    elif [ -d "$session_root" ]; then
        while IFS= read -r -d '' path; do
            session_dirs+=("$path")
        done < <(find "$session_root" -maxdepth 1 -type d -name "mission_*" -print0 2>/dev/null)
    fi

    local session_count=${#session_dirs[@]}
    local session_size="0"

    if ((session_count > 0)) && [ -d "$session_root" ]; then
        session_size=$(du -sh "$session_root" 2>/dev/null | awk '{print $1}')
    fi

    if ((session_count == 0)); then
        echo "  ✓ No sessions to clean"
        echo ""
        return
    fi

    echo "  → Found $session_count session(s) (Total: $session_size)"
    local response="n"
    if read -r -p "  → Delete all sessions? [y/N] " response; then
        :
    else
        response="n"
    fi

    if [[ "$response" =~ ^[Yy]$ ]]; then
        if ((${#session_dirs[@]} > 0)); then
            rm -rf "${session_dirs[@]}" 2>/dev/null || log_warn "Failed to remove one or more session directories."
        fi
        rm -f "$session_root/.latest" 2>/dev/null || true
        echo "  ✓ Deleted $session_count session(s)"
    else
        echo "  ⊘ Skipped session cleanup"
    fi
    echo ""
}

clean_temp_files() {
    echo "→ Cleaning temporary files..."

    local cleaned=0
    local session_root="$PROJECT_ROOT/research-sessions"

    if [ -L "$session_root/.latest" ] || [ -f "$session_root/.latest" ]; then
        rm -f "$session_root/.latest"
        echo "  ✓ Removed .latest symlink"
        cleaned=$((cleaned + 1))
    fi

    if [ -d "/tmp/test-agents" ]; then
        rm -rf "/tmp/test-agents"
        echo "  ✓ Removed /tmp/test-agents"
        cleaned=$((cleaned + 1))
    fi

    local -a backup_patterns=(
        "*.backup"
        "*.bak"
        "*~"
    )

    local backup_count=0
    local pattern
    for pattern in "${backup_patterns[@]}"; do
        while IFS= read -r -d '' file; do
            rm -f "$file" 2>/dev/null || true
            backup_count=$((backup_count + 1))
        done < <(find "$PROJECT_ROOT" -name "$pattern" -type f -print0 2>/dev/null)
    done

    if ((backup_count > 0)); then
        echo "  ✓ Removed $backup_count backup file(s)"
        cleaned=$((cleaned + backup_count))
    fi

    local log_dir="$PROJECT_ROOT/logs"
    if [ -d "$log_dir" ]; then
        local log_count=0
        while IFS= read -r -d '' _; do
            log_count=$((log_count + 1))
        done < <(find "$log_dir" -name "*.log" -type f -print0 2>/dev/null)

        if ((log_count > 0)); then
            local response="n"
            if read -r -p "  → Delete $log_count log file(s)? [y/N] " response; then
                :
            else
                response="n"
            fi

            if [[ "$response" =~ ^[Yy]$ ]]; then
                find "$log_dir" -name "*.log" -type f -exec rm -f {} + 2>/dev/null || true
                echo "  ✓ Removed $log_count log file(s)"
                cleaned=$((cleaned + log_count))
            else
                echo "  ⊘ Skipped log cleanup"
            fi
        fi
    fi

    if ((cleaned == 0)); then
        echo "  ✓ No temporary files to clean"
    fi
    echo ""
}

show_summary() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                   CLEANUP SUMMARY                         ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    local session_root="$PROJECT_ROOT/research-sessions"
    local remaining_sessions=0

    if [ -d "$session_root" ]; then
        while IFS= read -r -d '' _; do
            remaining_sessions=$((remaining_sessions + 1))
        done < <(find "$session_root" -maxdepth 1 -type d -name "mission_*" -print0 2>/dev/null)
    fi

    local remaining_procs=0
    local group
    for group in "${PROCESS_GROUPS[@]}"; do
        IFS='|' read -r _ include exclude <<< "$group"
        mapfile -t group_pids < <(collect_pids "$include" "$exclude")
        remaining_procs=$((remaining_procs + ${#group_pids[@]}))
    done

    echo "  Sessions remaining: $remaining_sessions"
    echo "  Processes running: $remaining_procs"

    if ((remaining_sessions == 0 && remaining_procs == 0)); then
        echo ""
        echo "  ✓ System is clean!"
    fi
    echo ""
}

main() {
    print_header
    kill_processes
    clean_sessions
    clean_temp_files
    show_summary
    echo "✓ Cleanup complete"
}

main
