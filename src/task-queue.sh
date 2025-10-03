#!/bin/bash
# Task Queue System
# Manages dynamic priority-based task queue for adaptive research

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared-state for atomic operations
# shellcheck disable=SC1091
source "$SCRIPT_DIR/shared-state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/utils/validation.sh"

# Initialize task queue
tq_init() {
    local session_dir="$1"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1

    local queue_file="$session_dir/task-queue.json"

    # Use jq to safely construct JSON (prevents injection attacks)
    jq -n \
        --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg updated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
            schema_version: "1.0",
            created_at: $created,
            last_updated: $updated,
            tasks: [],
            stats: {
                total_tasks: 0,
                completed: 0,
                in_progress: 0,
                pending: 0,
                failed: 0
            }
        }' > "$queue_file"

    echo "$queue_file"
}

# Get queue path
tq_get_path() {
    local session_dir="$1"
    echo "$session_dir/task-queue.json"
}

# Read entire queue
tq_read() {
    local session_dir="$1"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    if [ ! -f "$queue_file" ]; then
        echo "Error: Task queue not found: $queue_file" >&2
        return 1
    fi

    cat "$queue_file"
}

# Add task
tq_add_task() {
    local session_dir="$1"
    local task_json="$2"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_json "task_json" "$task_json" || return 1
    validate_json_field "$task_json" "type" "string" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    lock_acquire "$queue_file" || {
        echo "Error: Failed to acquire lock for adding task" >&2
        return 1
    }

    # Get max existing task ID to prevent collisions
    local max_id
    max_id=$(jq '[.tasks[] | .id | ltrimstr("t") | tonumber] | max // -1' "$queue_file")
    local task_id="t$((max_id + 1))"

    jq --argjson task "$task_json" \
       --arg id "$task_id" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.tasks += [($task + {id: $id, status: "pending", created_at: $date})] |
        .stats.total_tasks += 1 |
        .stats.pending += 1 |
        .last_updated = $date' \
       "$queue_file" > "${queue_file}.tmp"

    mv "${queue_file}.tmp" "$queue_file"
    lock_release "$queue_file"

    echo "$task_id"
}

# Add multiple tasks
tq_add_tasks() {
    local session_dir="$1"
    local tasks_json="$2"  # JSON array

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_json "tasks_json" "$tasks_json" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    # Add each task
    echo "$tasks_json" | jq -c '.[]' | while read -r task; do
        tq_add_task "$session_dir" "$task" >/dev/null
    done

    # Return updated queue
    tq_read "$session_dir"
}

# Get next task (highest priority pending task)
tq_get_next_task() {
    local session_dir="$1"
    local agent_filter="${2:-}"  # Optional: filter by agent type

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    if [ -n "$agent_filter" ]; then
        jq --arg agent "$agent_filter" \
           '.tasks | map(select(.status == "pending" and .agent == $agent)) |
            sort_by(-.priority) | .[0] // null' \
           "$queue_file"
    else
        jq '.tasks | map(select(.status == "pending")) |
            sort_by(-.priority) | .[0] // null' \
           "$queue_file"
    fi
}

# Get all pending tasks
tq_get_pending() {
    local session_dir="$1"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | map(select(.status == "pending")) | sort_by(-.priority)' "$queue_file"
}

# Get pending tasks by agent type
tq_get_pending_by_agent() {
    local session_dir="$1"
    local agent_type="$2"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq --arg agent "$agent_type" \
       '.tasks | map(select(.status == "pending" and .agent == $agent)) | sort_by(-.priority)' \
       "$queue_file"
}

# Update task status
tq_update_status() {
    local session_dir="$1"
    local task_id="$2"
    local new_status="$3"  # pending, in_progress, completed, failed

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "task_id" "$task_id" || return 1
    validate_enum "new_status" "$new_status" "pending" "in_progress" "completed" "failed" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    lock_acquire "$queue_file" || {
        echo "Error: Failed to acquire lock for updating task status" >&2
        return 1
    }

    # Get current status
    local old_status
    old_status=$(jq -r --arg id "$task_id" \
                          '.tasks[] | select(.id == $id) | .status' \
                          "$queue_file")

    if [ -z "$old_status" ]; then
        echo "Error: Task not found: $task_id" >&2
        lock_release "$queue_file"
        return 1
    fi

    # Build single jq expression for all updates (atomic)
    local timestamp_update=""
    # shellcheck disable=SC2016
    case "$new_status" in
        # Single quotes intentional - these are jq expressions with literal $id and $date
        in_progress) timestamp_update='| (.tasks[] | select(.id == $id)) |= (. + {started_at: $date})' ;;
        completed|failed) timestamp_update='| (.tasks[] | select(.id == $id)) |= (. + {completed_at: $date})' ;;
    esac

    local stats_old_dec=""
    case "$old_status" in
        pending) stats_old_dec='| .stats.pending -= 1' ;;
        in_progress) stats_old_dec='| .stats.in_progress -= 1' ;;
        completed) stats_old_dec='| .stats.completed -= 1' ;;
        failed) stats_old_dec='| .stats.failed -= 1' ;;
    esac

    local stats_new_inc=""
    case "$new_status" in
        pending) stats_new_inc='| .stats.pending += 1' ;;
        in_progress) stats_new_inc='| .stats.in_progress += 1' ;;
        completed) stats_new_inc='| .stats.completed += 1' ;;
        failed) stats_new_inc='| .stats.failed += 1' ;;
    esac

    # Single atomic update
    jq --arg id "$task_id" \
       --arg status "$new_status" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       "(.tasks[] | select(.id == \$id)) |= (. + {status: \$status, updated_at: \$date}) |
        .last_updated = \$date
        $stats_old_dec
        $stats_new_inc
        $timestamp_update" \
       "$queue_file" > "${queue_file}.tmp"

    mv "${queue_file}.tmp" "$queue_file"
    lock_release "$queue_file"
}

# Mark task as started
tq_start_task() {
    local session_dir="$1"
    local task_id="$2"

    tq_update_status "$session_dir" "$task_id" "in_progress"
}

# Mark task as completed
tq_complete_task() {
    local session_dir="$1"
    local task_id="$2"
    local findings_file="$3"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "task_id" "$task_id" || return 1
    validate_required "findings_file" "$findings_file" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    # Single atomic operation to update status and add findings (prevents race condition)
    lock_acquire "$queue_file" || {
        echo "Error: Failed to acquire lock for completing task" >&2
        return 1
    }

    # Get current status to update stats correctly
    local old_status
    old_status=$(jq -r --arg id "$task_id" \
                          '.tasks[] | select(.id == $id) | .status' \
                          "$queue_file")

    if [ -z "$old_status" ]; then
        echo "Error: Task not found: $task_id" >&2
        lock_release "$queue_file"
        return 1
    fi

    # Build stats updates
    local stats_old_dec=""
    case "$old_status" in
        pending) stats_old_dec='| .stats.pending -= 1' ;;
        in_progress) stats_old_dec='| .stats.in_progress -= 1' ;;
        completed) stats_old_dec='| .stats.completed -= 1' ;;
        failed) stats_old_dec='| .stats.failed -= 1' ;;
    esac

    # Single atomic jq operation
    jq --arg id "$task_id" \
       --arg findings "$findings_file" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       "(.tasks[] | select(.id == \$id)) |= (. + {status: \"completed\", findings_file: \$findings, completed_at: \$date, updated_at: \$date}) |
        .last_updated = \$date
        $stats_old_dec
        | .stats.completed += 1" \
       "$queue_file" > "${queue_file}.tmp"

    mv "${queue_file}.tmp" "$queue_file"
    lock_release "$queue_file"
}

# Mark task as failed
tq_fail_task() {
    local session_dir="$1"
    local task_id="$2"
    local error_message="$3"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "task_id" "$task_id" || return 1
    validate_required "error_message" "$error_message" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    # Update status first (which handles locking)
    tq_update_status "$session_dir" "$task_id" "failed"

    # Then add error message (with its own lock)
    lock_acquire "$queue_file" || {
        echo "Error: Failed to acquire lock for failing task" >&2
        return 1
    }

    jq --arg id "$task_id" \
       --arg error "$error_message" \
       '(.tasks[] | select(.id == $id)) |= (. + {error: $error})' \
       "$queue_file" > "${queue_file}.tmp"

    mv "${queue_file}.tmp" "$queue_file"
    lock_release "$queue_file"
}

# Update task priority
tq_update_priority() {
    local session_dir="$1"
    local task_id="$2"
    local new_priority="$3"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "task_id" "$task_id" || return 1
    validate_integer "new_priority" "$new_priority" 0 10 || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    lock_acquire "$queue_file" || {
        echo "Error: Failed to acquire lock for updating task priority" >&2
        return 1
    }

    jq --arg id "$task_id" \
       --arg priority "$new_priority" \
       --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '(.tasks[] | select(.id == $id)) |= (. + {priority: ($priority | tonumber), updated_at: $date}) |
        .last_updated = $date' \
       "$queue_file" > "${queue_file}.tmp"

    mv "${queue_file}.tmp" "$queue_file"
    lock_release "$queue_file"
}

# Get task by ID
tq_get_task() {
    local session_dir="$1"
    local task_id="$2"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1
    validate_required "task_id" "$task_id" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq --arg id "$task_id" \
       '.tasks[] | select(.id == $id)' \
       "$queue_file"
}

# Get completed tasks
tq_get_completed() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | map(select(.status == "completed"))' "$queue_file"
}

# Get in-progress tasks
tq_get_in_progress() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | map(select(.status == "in_progress"))' "$queue_file"
}

# Get failed tasks
tq_get_failed() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | map(select(.status == "failed"))' "$queue_file"
}

# Get queue statistics
tq_get_stats() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.stats' "$queue_file"
}

# Get queue summary (for display)
tq_get_summary() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '{
        total: .stats.total_tasks,
        completed: .stats.completed,
        in_progress: .stats.in_progress,
        pending: .stats.pending,
        failed: .stats.failed,
        completion_rate: (if .stats.total_tasks > 0 then (.stats.completed / .stats.total_tasks) else 0 end),
        pending_tasks: [.tasks[] | select(.status == "pending") | {id, type, agent, priority, query: (.query[:50] + "...")}]
    }' "$queue_file"
}

# Count tasks by type
tq_count_by_type() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | group_by(.type) | map({type: .[0].type, count: length}) | from_entries' "$queue_file"
}

# Count tasks by agent
tq_count_by_agent() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '.tasks | group_by(.agent) | map({agent: .[0].agent, count: length}) | from_entries' "$queue_file"
}

# Check if queue has pending tasks
tq_has_pending() {
    local session_dir="$1"

    # Validate inputs
    validate_directory "session_dir" "$session_dir" || return 1

    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    local count
    count=$(jq '.stats.pending' "$queue_file")
    [ "$count" -gt 0 ]
}

# Get average task completion time
tq_get_avg_completion_time() {
    local session_dir="$1"
    local queue_file
    queue_file=$(tq_get_path "$session_dir")

    jq '[.tasks[] | select(.status == "completed" and .started_at and .completed_at) |
         (((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)) / 60)] |
        if length > 0 then (add / length) else 0 end' \
       "$queue_file"
}

# Export functions
export -f tq_init
export -f tq_get_path
export -f tq_read
export -f tq_add_task
export -f tq_add_tasks
export -f tq_get_next_task
export -f tq_get_pending
export -f tq_get_pending_by_agent
export -f tq_update_status
export -f tq_start_task
export -f tq_complete_task
export -f tq_fail_task
export -f tq_update_priority
export -f tq_get_task
export -f tq_get_completed
export -f tq_get_in_progress
export -f tq_get_failed
export -f tq_get_stats
export -f tq_get_summary
export -f tq_count_by_type
export -f tq_count_by_agent
export -f tq_has_pending
export -f tq_get_avg_completion_time

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        init)
            tq_init "$2"
            ;;
        read)
            tq_read "$2"
            ;;
        summary)
            tq_get_summary "$2"
            ;;
        next)
            tq_get_next_task "$2" "${3:-}"
            ;;
        pending)
            tq_get_pending "$2"
            ;;
        add)
            # Expect JSON task as $3
            tq_add_task "$2" "$3"
            ;;
        start)
            tq_start_task "$2" "$3"
            ;;
        complete)
            tq_complete_task "$2" "$3" "$4"
            ;;
        fail)
            tq_fail_task "$2" "$3" "$4"
            ;;
        stats)
            tq_get_stats "$2"
            ;;
        *)
            echo "Usage: $0 {init|read|summary|next|pending|add|start|complete|fail|stats} <session_dir> [args]"
            echo ""
            echo "Commands:"
            echo "  init <session_dir>                        - Initialize new task queue"
            echo "  read <session_dir>                        - Read entire queue"
            echo "  summary <session_dir>                     - Get queue summary"
            echo "  next <session_dir> [agent]                - Get next highest priority task"
            echo "  pending <session_dir>                     - Get all pending tasks"
            echo "  add <session_dir> <task_json>             - Add task to queue"
            echo "  start <session_dir> <task_id>             - Mark task as in progress"
            echo "  complete <session_dir> <task_id> <file>   - Mark task as completed"
            echo "  fail <session_dir> <task_id> <error>      - Mark task as failed"
            echo "  stats <session_dir>                       - Get queue statistics"
            ;;
    esac
fi
