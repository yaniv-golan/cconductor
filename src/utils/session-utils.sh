#!/usr/bin/env bash
# Session utilities shared by CLI and TUI

set -euo pipefail

SESSION_UTILS_ROOT="${CCONDUCTOR_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck disable=SC1091
if [ -f "$SESSION_UTILS_ROOT/src/utils/json-helpers.sh" ]; then
    source "$SESSION_UTILS_ROOT/src/utils/json-helpers.sh"
fi

session_utils_primary_dir() {
    if [ -n "${SESSION_UTILS_PRIMARY_DIR:-}" ]; then
        echo "$SESSION_UTILS_PRIMARY_DIR"
        return
    fi
    if [ -f "$SESSION_UTILS_ROOT/src/utils/path-resolver.sh" ]; then
        # shellcheck disable=SC1091
        source "$SESSION_UTILS_ROOT/src/utils/path-resolver.sh" 2>/dev/null || true
        if resolved_dir=$(resolve_path "session_dir" 2>/dev/null); then
            SESSION_UTILS_PRIMARY_DIR="$resolved_dir"
            echo "$SESSION_UTILS_PRIMARY_DIR"
            return
        fi
    fi
    SESSION_UTILS_PRIMARY_DIR="$SESSION_UTILS_ROOT/research-sessions"
    echo "$SESSION_UTILS_PRIMARY_DIR"
}

session_utils_candidate_dirs() {
    local primary
    primary=$(session_utils_primary_dir)
    [ -n "$primary" ] && echo "$primary"
    local fallback="$SESSION_UTILS_ROOT/research-sessions"
    if [ "$fallback" != "$primary" ]; then
        echo "$fallback"
    fi
}

session_utils_stat_mtime() {
    local path="$1"
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        stat -f '%m' "$path" 2>/dev/null || echo 0
    elif stat -c '%Y' "$path" >/dev/null 2>&1; then
        stat -c '%Y' "$path" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

session_utils_list_with_mtime() {
    local dir="$1"
    [ -d "$dir" ] || return
    local pattern
    for pattern in mission_* session_* mission_session_*; do
        for path in "$dir"/$pattern; do
            [ -d "$path" ] || continue
            local mtime
            mtime=$(session_utils_stat_mtime "$path")
            printf '%s::%s\n' "$mtime" "$path"
        done
    done
}

session_utils_safe_meta_value() {
    local session_path="$1"
    local jq_filter="$2"
    local fallback="$3"
    local context="$4"
    local meta_file="$session_path/meta/session.json"
    local value="$fallback"

    if [[ ! -f "$meta_file" ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    local extracted
    if extracted=$(safe_jq_from_file "$meta_file" "$jq_filter" "$fallback" "$session_path" "session_utils.${context}" "true"); then
        value="$extracted"
    fi

    printf '%s' "$value"
    return 0
}

session_utils_format_timestamp() {
    local path="$1"
    if stat -f '%m' "$path" >/dev/null 2>&1; then
        local epoch
        epoch=$(stat -f '%m' "$path" 2>/dev/null || echo "")
        if [ -n "$epoch" ]; then
            date -r "$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo ""
        fi
    elif stat -c '%Y' "$path" >/dev/null 2>&1; then
        local epoch
        epoch=$(stat -c '%Y' "$path" 2>/dev/null || echo "")
        if [ -n "$epoch" ]; then
            date -d "@$epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || echo ""
        fi
    fi
}

session_utils_pretty_timestamp() {
    local raw="$1"
    if [ -z "$raw" ] || [ "$raw" = "null" ]; then
        echo ""
        return
    fi

    local normalized="$raw"

    if [[ "$normalized" =~ \.[0-9]+Z$ ]]; then
        normalized="${normalized%Z}"
        normalized="${normalized%%.*}Z"
    elif [[ "$normalized" =~ \.[0-9]+([+-][0-9]{2}:[0-9]{2})$ ]]; then
        normalized="${normalized%%.*}${BASH_REMATCH[1]}"
    fi

    if [[ "$normalized" =~ [+-][0-9]{2}:[0-9]{2}$ ]]; then
        normalized="${normalized:0:${#normalized}-3}${normalized:${#normalized}-2}"
    fi

    if [[ "$normalized" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local epoch="${normalized%%.*}"
        if date -r "$epoch" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -r "$epoch" "+%b %d, %H:%M"
            return
        elif date -d "@$epoch" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -d "@$epoch" "+%b %d, %H:%M"
            return
        fi
    fi

    if date --version >/dev/null 2>&1; then
        if date -u -d "$normalized" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -u -d "$normalized" "+%b %d, %H:%M"
            return
        fi
        if date -u -d "${normalized}Z" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -u -d "${normalized}Z" "+%b %d, %H:%M"
            return
        fi
        if date -u -d "$normalized UTC" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -u -d "$normalized UTC" "+%b %d, %H:%M"
            return
        fi
    else
        local formats=(
            "%Y-%m-%dT%H:%M:%SZ"
            "%Y-%m-%dT%H:%M:%S%z"
            "%Y-%m-%d %H:%M"
        )
        local fmt
        for fmt in "${formats[@]}"; do
            if date -u -j -f "$fmt" "$normalized" "+%b %d, %H:%M" >/dev/null 2>&1; then
                date -u -j -f "$fmt" "$normalized" "+%b %d, %H:%M"
                return
            fi
        done
        if date -u -j -f "%s" "$normalized" "+%b %d, %H:%M" >/dev/null 2>&1; then
            date -u -j -f "%s" "$normalized" "+%b %d, %H:%M"
            return
        fi
    fi

    echo "$raw"
}

session_utils_clean_text() {
    local text="$1"
    text=$(echo "$text" | tr '\n\r\t' ' ' | sed 's/  */ /g' | sed 's/^ *//; s/ *$//')
    echo "$text"
}

session_utils_emit_row() {
    local path="$1"
    local mission_id
    mission_id=$(basename "$path")

    local created=""
    local objective=""
    local status="In progress"

    if [ -f "$path/meta/session.json" ]; then
        created=$(session_utils_safe_meta_value "$path" '.created_at // .started_at // ""' "" "created")
        objective=$(session_utils_safe_meta_value "$path" '.objective // .research_question // ""' "" "objective")
        status=$(session_utils_safe_meta_value "$path" '.status // ""' "" "status")
    fi

    if [ -z "$created" ] || [ "$created" = "null" ]; then
        created=$(session_utils_format_timestamp "$path")
    fi
    created=${created:-N/A}

    if [ "$status" = "completed_with_advisory" ]; then
        status="Complete (advisory)"
    elif [ "$status" = "completed" ]; then
        status="Complete"
    elif [ -z "$status" ] || [ "$status" = "null" ]; then
        status="In progress"
    fi

    if [ -f "$path/report/mission-report.md" ] && [ "$status" != "Complete (advisory)" ]; then
        status="Complete"
    fi

    objective=$(session_utils_clean_text "${objective:-No objective recorded}")
    [ -z "$objective" ] && objective="No objective recorded"

    local short_id="$mission_id"
    short_id=${short_id#mission_}
    short_id=${short_id#session_}

    printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$short_id" "$created" "$status" "$objective"
}

session_utils_collect_sessions() {
    declare -A seen_paths=()
    declare -a combined=()

    while read -r dir; do
        [ -d "$dir" ] || continue
        local lines
        lines=$(session_utils_list_with_mtime "$dir")
        [ -n "$lines" ] || continue
        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            local mtime path
            mtime=${entry%%::*}
            path=${entry#*::}
            [ -n "$path" ] || continue
            if [ -n "${seen_paths[$path]:-}" ]; then
                continue
            fi
            seen_paths["$path"]=1
            combined+=("$mtime::$path")
        done <<< "$lines"
    done < <(session_utils_candidate_dirs)

    if [ ${#combined[@]} -eq 0 ]; then
        return
    fi

    printf '%s\n' "${combined[@]}" | sort -r | while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        local path
        path=${entry#*::}
        session_utils_emit_row "$path"
    done
}

session_utils_generate_status_report() {
    local pids
    pids=$(pgrep -f "cconductor-mission.sh" || true)

    if [ -z "$pids" ]; then
        echo "No active sessions"
        return
    fi

    local count=0
    for pid in $pids; do
        local ppid
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        local parent_cmd
        parent_cmd=$(ps -o command= -p "$ppid" 2>/dev/null || true)

        if ! echo "$parent_cmd" | grep -q "cconductor-mission.sh"; then
            count=$((count + 1))
            local start_time
            start_time=$(ps -o lstart= -p "$pid" 2>/dev/null)
            echo "Active Session #$count:"
            echo "  PID: $pid (Parent PID: $ppid)"
            [ -n "$start_time" ] && echo "  Started: $start_time"

            local child_count
            child_count=$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$child_count" -gt 0 ]; then
                echo "  Status: Running ($child_count child process(es))"
            else
                echo "  Status: Idle"
            fi
            echo ""
        fi
    done

    if [ $count -eq 0 ]; then
        echo "No active sessions (only child processes found)"
    fi
}

session_utils_collect_active_processes() {
    local pids
    pids=$(pgrep -f "cconductor-mission.sh" || true)
    [ -n "$pids" ] || return

    local pid
    for pid in $pids; do
        local ppid
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        local parent_cmd
        parent_cmd=$(ps -o command= -p "$ppid" 2>/dev/null || true)
        if echo "$parent_cmd" | grep -q "cconductor-mission.sh"; then
            continue
        fi

        local session_dir=""
        if command -v lsof >/dev/null 2>&1; then
            session_dir=$(lsof -a -d cwd -p "$pid" -Fn 2>/dev/null | awk -F'n' '/^n/ {print substr($0,2); exit}')
        elif command -v pwdx >/dev/null 2>&1; then
            session_dir=$(pwdx "$pid" 2>/dev/null | awk '{print $2}')
        fi

        if [ -z "$session_dir" ] || [ ! -d "$session_dir" ]; then
            continue
        fi

        local children
        children=$(pgrep -P "$pid" 2>/dev/null || true)
        local child_count=0
        if [ -n "$children" ]; then
            child_count=$(echo "$children" | wc -l | tr -d ' ')
        fi
        local state="idle"
        if [ "$child_count" -gt 0 ]; then
            state="running"
        fi

        printf '%s\t%s\t%s\t%s\n' "$session_dir" "$pid" "$state" "$child_count"
    done
}
