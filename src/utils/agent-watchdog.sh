#!/usr/bin/env bash
# Agent Watchdog - Monitors agent heartbeat and enforces timeout
# Pure Bash implementation - no external dependencies required
#
# This watchdog monitors the .agent-heartbeat file and enforces
# both heartbeat freshness (5 min stale = hung) and absolute timeout.
#
# Exit codes:
#   0   - Agent completed normally
#   124 - Timeout reached or heartbeat stale (agent killed)

set -euo pipefail

# Validate arguments
if [ $# -ne 4 ]; then
    echo "Usage: $0 <session_dir> <agent_pid> <timeout_seconds> <agent_name>" >&2
    exit 1
fi

session_dir="$1"
agent_pid="$2"
timeout_seconds="$3"
agent_name="$4"

heartbeat_file="$session_dir/.agent-heartbeat"
check_interval=5  # Check every 5 seconds
max_heartbeat_age=600  # 10 minutes = stale (increased for synthesis-agent timeout fix)

# Convert timeout to deciseconds for integer arithmetic
timeout_deciseconds=$((timeout_seconds * 10))
elapsed_deciseconds=0
poll_deciseconds=$((check_interval * 10))

watchdog_mode="${CCONDUCTOR_WATCHDOG_MODE:-}"
legacy_disable="${CCONDUCTOR_DISABLE_WATCHDOG:-}"
legacy_enable="${CCONDUCTOR_ENABLE_WATCHDOG:-}"

if [[ -n "$legacy_disable" ]]; then
    watchdog_mode="disabled"
elif [[ -n "$legacy_enable" ]]; then
    watchdog_mode="enabled"
fi
watchdog_mode="${watchdog_mode,,}"

if [[ "$watchdog_mode" == "disabled" ]]; then
    # Passive wait to keep heartbeat updates consistent without enforcing termination
    while ps -p "$agent_pid" >/dev/null 2>&1; do
        sleep "$check_interval"
    done
    exit 0
fi

agent_timeout_mode="${CCONDUCTOR_AGENT_TIMEOUT_MODE:-}"
if [[ -z "$agent_timeout_mode" ]]; then
    if [[ -n "${CCONDUCTOR_DISABLE_AGENT_TIMEOUTS:-}" ]]; then
        agent_timeout_mode="disabled"
    elif [[ -n "${CCONDUCTOR_ENABLE_AGENT_TIMEOUTS:-}" ]]; then
        agent_timeout_mode="enabled"
    fi
fi
agent_timeout_mode="${agent_timeout_mode,,}"

timeouts_enforced=1
if [[ "$agent_timeout_mode" == "disabled" ]]; then
    timeouts_enforced=0
elif [[ "${CCONDUCTOR_AGENT_TIMEOUTS_ENABLED:-1}" == "0" ]]; then
    timeouts_enforced=0
fi

# Monitor loop
while true; do
    # Check if agent process still exists
    if ! ps -p "$agent_pid" >/dev/null 2>&1; then
        # Agent completed normally
        exit 0
    fi
    
    # Check heartbeat freshness
    if [ -f "$heartbeat_file" ]; then
        # Extract timestamp from heartbeat file (format: agent_name:timestamp)
        last_heartbeat=$(cut -d: -f2 "$heartbeat_file" 2>/dev/null || echo "0")
        if [[ ! "$last_heartbeat" =~ ^[0-9]+$ ]]; then
            last_heartbeat="$current_time"
        fi
        current_time=$(date +%s)
        staleness=$((current_time - last_heartbeat))
        
        # If heartbeat is stale, agent is hung
        if [ "$staleness" -gt "$max_heartbeat_age" ]; then
            echo "[WATCHDOG] Agent $agent_name stalled (no heartbeat for ${staleness}s)" >&2
            
            # Try graceful termination (SIGTERM)
            kill -TERM "$agent_pid" 2>/dev/null || true
            sleep 2
            
            # Force kill if still alive (SIGKILL)
            if ps -p "$agent_pid" >/dev/null 2>&1; then
                echo "[WATCHDOG] Process didn't respond to SIGTERM, forcing SIGKILL..." >&2
                kill -KILL "$agent_pid" 2>/dev/null || true
            fi
            
            exit 124
        fi
    fi

    if [[ $timeouts_enforced -eq 1 && $elapsed_deciseconds -ge $timeout_deciseconds ]]; then
        echo "[WATCHDOG] Agent $agent_name exceeded timeout (${timeout_seconds}s)" >&2

        # Try graceful termination (SIGTERM)
        kill -TERM "$agent_pid" 2>/dev/null || true
        sleep 2

        # Force kill if still alive (SIGKILL)
        if ps -p "$agent_pid" >/dev/null 2>&1; then
            echo "[WATCHDOG] Process didn't respond to SIGTERM, forcing SIGKILL..." >&2
            kill -KILL "$agent_pid" 2>/dev/null || true
        fi

        exit 124
    fi
    
    # Sleep and update elapsed time
    sleep "$check_interval"
    elapsed_deciseconds=$((elapsed_deciseconds + poll_deciseconds))
done
