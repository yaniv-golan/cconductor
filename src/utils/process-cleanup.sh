#!/usr/bin/env bash
# Runtime Process Cleanup Utilities
# Provides helper functions to detect and reap orphaned agent-related processes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers when available
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/core-helpers.sh" 2>/dev/null; then
    log_warn() { printf 'WARN: %s\n' "$*" >&2; }
    log_info() { printf 'INFO: %s\n' "$*" >&2; }
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh" 2>/dev/null || true

# Internal helper: reap processes whose PPID is 1 and command contains the given pattern.
_reap_by_pattern() {
    local pattern="$1"
    local description="$2"
    local ps_format="pid=,ppid=,etimes=,command="
    local uses_human_time=0

    if ! ps -o etimes= -p "$$" >/dev/null 2>&1; then
        ps_format="pid=,ppid=,etime=,command="
        uses_human_time=1
    fi

    local reclaimed=0
    while IFS='|' read -r pid ppid age cmd; do
        [[ -n "$pid" && "$pid" != "$$" ]] || continue
        [[ "$ppid" == "1" ]] || continue
        [[ -n "$cmd" ]] || continue

        if ! kill -0 "$pid" 2>/dev/null; then
            continue
        fi

        local age_label="$age"
        if [[ "$uses_human_time" -eq 0 ]]; then
            age_label="${age}s"
        fi

        log_warn "Reaping orphaned $description (pid=$pid, age=${age_label}, pattern=$pattern)"
        kill -TERM "$pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$pid" 2>/dev/null || true
        reclaimed=$((reclaimed + 1))
    done < <(ps -eo "$ps_format" 2>/dev/null | awk -v pat="$pattern" '
        {
            pid=$1
            ppid=$2
            age=$3
            cmd=""
            for (i=4; i<=NF; i++) {
                cmd = cmd $i
                if (i < NF) {
                    cmd = cmd " "
                }
            }
            if (ppid == 1 && index(cmd, pat) > 0) {
                printf "%s|%s|%s|%s\n", pid, ppid, age, cmd
            }
        }
    ')

    printf '%s\n' "$reclaimed"
}

# Public helper: reap all known orphaned agent processes (invoke-agent, watchdog, event tailer, claude).
cleanup_orphan_agent_processes() {
    local total=0
    local reclaimed

    reclaimed=$(_reap_by_pattern "invoke-agent.sh" "invoke-agent shell")
    total=$((total + reclaimed))

    reclaimed=$(_reap_by_pattern "agent-watchdog.sh" "agent watchdog")
    total=$((total + reclaimed))

    reclaimed=$(_reap_by_pattern "event-tailer.sh" "event tailer")
    total=$((total + reclaimed))

    # Catch stray claude CLI runs spawned by invoke-agent
    reclaimed=$(_reap_by_pattern "claude --print" "Claude CLI session")
    total=$((total + reclaimed))

    if [[ "$total" -gt 0 ]]; then
        log_info "Reclaimed $total orphaned agent-related process(es)"
    fi

    return 0
}

# CLI usage
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        ""|-h|--help)
            cat <<'USAGE'
Usage: process-cleanup.sh [--reap]

Options:
  --reap    Immediately reap orphaned invoke-agent, watchdog, event tailer, and Claude CLI processes.
USAGE
            ;;
        --reap)
            cleanup_orphan_agent_processes
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
fi

export -f cleanup_orphan_agent_processes
