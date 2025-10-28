#!/usr/bin/env bash
# TUI - Interactive text user interface for CConductor
# Provides dialog-based and simple fallback interfaces

set -euo pipefail

# Guard against direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This script should be sourced, not executed" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# Source core helpers (when available)
if [[ -n "${CCONDUCTOR_ROOT:-}" ]] && [[ -f "$CCONDUCTOR_ROOT/src/utils/core-helpers.sh" ]]; then
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/core-helpers.sh"
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/error-messages.sh"
fi

# shellcheck disable=SC1091
if [[ -n "${CCONDUCTOR_ROOT:-}" ]] && [[ -f "$CCONDUCTOR_ROOT/src/utils/json-helpers.sh" ]]; then
    source "$CCONDUCTOR_ROOT/src/utils/json-helpers.sh"
fi

# shellcheck disable=SC1091
source "$CCONDUCTOR_ROOT/src/utils/session-utils.sh"

tui_safe_json() {
    local file_path="$1"
    local jq_filter="$2"
    local fallback="${3:-}"
    local context="${4:-tui}"
    local session_dir="${CCONDUCTOR_SESSION_DIR:-}"
    local value="$fallback"

    if [[ -z "$file_path" || ! -f "$file_path" ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    local extracted
    if extracted=$(safe_jq_from_file "$file_path" "$jq_filter" "$fallback" "$session_dir" "tui.${context}" "true"); then
        value="$extracted"
    else
        value="$fallback"
    fi

    printf '%s' "$value"
    return 0
}

# shellcheck disable=SC2034
declare -a TUI_SESSION_PATHS=()
declare -a TUI_SESSION_LABELS=()

truncate_text() {
    local text="$1"
    local max="${2:-60}"
    text=$(echo "$text" | tr '

	' ' ' | sed 's/  */ /g' | sed 's/^ *//; s/ *$//')
    if [ "${#text}" -gt "$max" ]; then
        printf '%s…' "${text:0:max-1}"
    else
        printf '%s' "$text"
    fi
}

session_short_status_label() {
    local status="$1"
    case "$status" in
        "In progress"|"In Progress")
            echo "In Progress"
            ;;
        "Complete (advisory)")
            echo "Advisory"
            ;;
        "Complete")
            echo "Complete"
            ;;
        "Error"|"Failed"|"Failure")
            echo "Error"
            ;;
        "Aborted"|"Cancelled"|"Canceled")
            echo "Aborted"
            ;;
        ""|"null"|"N/A")
            echo "Unknown"
            ;;
        *)
            echo "$status"
            ;;
    esac
}

session_status_field() {
    local label
    label=$(session_short_status_label "$1")
    if [ "${#label}" -gt 11 ]; then
        label="${label:0:11}"
    fi
    printf ' %-11s ' "$label"
}

session_status_emoji() {
    local process_state="$1"
    local status="$2"

    case "$process_state" in
        running)
            echo "🟢"
            return
            ;;
        idle)
            echo "🟡"
            return
            ;;
    esac

    case "$status" in
        "Complete"|"Complete (advisory)")
            echo "✅"
            ;;
        "In progress"|"In Progress")
            echo "🔴"
            ;;
        "Advisory")
            echo "✅"
            ;;
        "Error"|"Failed"|"Failure"|"Aborted"|"Cancelled"|"Canceled")
            echo "⚠️"
            ;;
        *)
            echo "⚪"
            ;;
    esac
}

load_sessions_into_arrays() {
    TUI_SESSION_PATHS=()
    TUI_SESSION_LABELS=()

    declare -A process_state_map=()
    while IFS=$'\t' read -r proc_path _proc_pid proc_state _proc_children; do
        [ -n "$proc_path" ] || continue
        process_state_map["$proc_path"]="$proc_state"
    done < <(session_utils_collect_active_processes || true)

    while IFS=$'\t' read -r path _mission_id created status objective; do
        [ -n "$path" ] || continue
        TUI_SESSION_PATHS+=("$path")
        local excerpt label pretty_created status_field emoji session_id_display process_state
        excerpt=$(truncate_text "$objective" 60)
        pretty_created=$(session_utils_pretty_timestamp "$created")
        [ -n "$pretty_created" ] || pretty_created="$created"
        status_field=$(session_status_field "$status")
        process_state="${process_state_map[$path]:-}"
        emoji=$(session_status_emoji "$process_state" "$status")
        session_id_display=$(basename "$path")
        session_id_display=${session_id_display#mission_}
        session_id_display=${session_id_display#session_}
        label=$(printf '%s %s | %s |%s| "%s"' "$emoji" "$session_id_display" "$pretty_created" "$status_field" "$excerpt")
        TUI_SESSION_LABELS+=("$label")
    done < <(session_utils_collect_sessions)
}

# Session details formatter shared by interfaces
session_details_collect() {
    local session_path="$1"

    if [ ! -f "$session_path/meta/session.json" ]; then
        return 1
    fi

    local session_id
    session_id=$(basename "$session_path")

    local objective
    objective=$(jq -r '.objective // "N/A"' "$session_path/meta/session.json" 2>/dev/null)
    local created
    created=$(jq -r '.created_at // "N/A"' "$session_path/meta/session.json" 2>/dev/null)
    local mission
    mission=$(jq -r '.mission_name // "general-research"' "$session_path/meta/session.json" 2>/dev/null)
    local status_value
    status_value=$(tui_safe_json "$session_path/meta/session.json" '.status // ""' "" "session.status")

    local created_display
    created_display=$(session_utils_pretty_timestamp "$created")
    [ -n "$created_display" ] || created_display="$created"

    local status_display="$status_value"
    case "$status_value" in
        completed_with_advisory) status_display="Complete (quality advisory)" ;;
        completed) status_display="Complete" ;;
        in_progress|"")
            status_display="In progress"
            ;;
        null) status_display="Unknown" ;;
        *)
            status_display=${status_value//_/ }
            ;;
    esac
    [ -n "$status_display" ] || status_display="Unknown"

    local total_cost=""
    if [ -f "$session_path/meta/mission-metrics.json" ]; then
        total_cost=$(tui_safe_json "$session_path/meta/mission-metrics.json" '.total_cost_usd // empty' "" "mission_metrics.total_cost")
    fi

    local budget_cost=""
    local invocations=""
    local elapsed_minutes=""
    if [ -f "$session_path/meta/budget.json" ]; then
        budget_cost=$(tui_safe_json "$session_path/meta/budget.json" '.spent.cost_usd // empty' "" "budget.cost")
        invocations=$(tui_safe_json "$session_path/meta/budget.json" '.spent.agent_invocations // empty' "" "budget.agent_invocations")
        elapsed_minutes=$(tui_safe_json "$session_path/meta/budget.json" '.spent.elapsed_minutes // empty' "" "budget.elapsed_minutes")
    fi

    local cost_display=""
    if [ -n "$total_cost" ] && [ "$total_cost" != "null" ]; then
        cost_display="$total_cost"
    elif [ -n "$budget_cost" ] && [ "$budget_cost" != "null" ]; then
        cost_display="$budget_cost"
    fi

    if [ -n "$cost_display" ]; then
        if [[ "$cost_display" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            printf -v cost_display '%.2f' "$cost_display"
        fi
    fi

    local budget_value
    if [ -n "$cost_display" ]; then
        budget_value="\$$cost_display"
    else
        budget_value="Unknown"
    fi

    local budget_meta=()
    if [ -n "$invocations" ] && [ "$invocations" != "null" ]; then
        budget_meta+=("$invocations invocations")
    fi
    if [ -n "$elapsed_minutes" ] && [ "$elapsed_minutes" != "null" ]; then
        budget_meta+=("${elapsed_minutes} min elapsed")
    fi
    if [ "${#budget_meta[@]}" -gt 0 ]; then
        budget_value+=" ($(IFS=', '; echo "${budget_meta[*]}"))"
    fi

    local iterations=""
    if [ -f "$session_path/viewer/dashboard-metrics.json" ]; then
        iterations=$(tui_safe_json "$session_path/viewer/dashboard-metrics.json" '.iteration // empty' "" "dashboard.iteration")
    fi
    local iterations_display="$iterations"
    if [ -z "$iterations_display" ] || [ "$iterations_display" = "null" ]; then
        iterations_display="Unknown"
    fi

    local report_path=""
    local report_status="Not yet available"
    if [ -f "$session_path/report/mission-report.md" ]; then
        report_path="$session_path/report/mission-report.md"
        if [ "$status_value" = "completed_with_advisory" ]; then
            report_status="Complete (quality advisory)"
        else
            report_status="Complete"
        fi
    fi

    local journal_path=""
    if [ -f "$session_path/report/research-journal.md" ]; then
        journal_path="$session_path/report/research-journal.md"
    fi

    local lines=()
    lines+=("Session Overview")
    lines+=("  Session ID: $session_id")
    lines+=("  Objective: $objective")
    lines+=("  Mission: $mission")
    lines+=("  Created: $created_display")
    lines+=("  Status: $status_display")
    lines+=("")
    lines+=("Progress")
    lines+=("  Budget spent: $budget_value")
    lines+=("  Iterations: $iterations_display")
    lines+=("")
    lines+=("Artifacts")
    lines+=("  Report: $report_status")
    if [ -n "$report_path" ]; then
        lines+=("  Report path: $report_path")
    fi
    if [ -n "$journal_path" ]; then
        lines+=("  Research journal: $journal_path")
    else
        lines+=("  Research journal: Not yet generated")
    fi

    printf '%s\n' "${lines[@]}"
}

# Helper: Show session details (CLI)
show_session_details() {
    local session_path="$1"
    local details
    if ! details=$(session_details_collect "$session_path"); then
        echo "Invalid session directory"
        return 1
    fi

    echo ""
    echo "Session Details"
    echo "==============="
    echo ""
    printf '%s\n' "$details"
    echo ""
}

show_session_process_status() {
    local session_path="$1"
    local session_id
    session_id=$(basename "$session_path")

    local report=""
    local found=0

    while IFS=$'\t' read -r proc_path pid state child_count; do
        [ -n "$proc_path" ] || continue
        if [ "$proc_path" != "$session_path" ]; then
            continue
        fi
        found=1
        local ppid
        ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        local start_time
        start_time=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^ *//')
        local status_line="Idle"
        if [ "$state" = "running" ]; then
            status_line="Running (${child_count} child process(es))"
        fi

        report+="Mission process for $session_id\n"
        report+="===============================\n"
        report+=$'\n'
        report+="PID: $pid"$'\n'
        report+="Parent PID: ${ppid:-unknown}"$'\n'
        [ -n "$start_time" ] && report+="Started: $start_time"$'\n'
        report+="Status: $status_line"$'\n'
        break
    done < <(session_utils_collect_active_processes || true)

    if [ "$found" -eq 0 ]; then
        report+="No active mission process for $session_id."$'\n'
        local status_value
        status_value=$(tui_safe_json "$session_path/meta/session.json" '.status // ""' "" "session.status")
        if [ "$status_value" = "in_progress" ] || [ -z "$status_value" ] || [ "$status_value" = "running" ]; then
            report+="Session metadata indicates it may still be in progress."$'\n'
        fi
    fi

    local pid_file
    for pid_file in "$session_path"/.event-tailer.pid "$session_path"/.dashboard-server.pid; do
        [ -f "$pid_file" ] || continue
        local pid_value
        pid_value=$(cat "$pid_file" 2>/dev/null || echo "")
        [ -n "$pid_value" ] || continue
        local label
        case "$(basename "$pid_file")" in
            .event-tailer.pid) label="Event tailer" ;;
            .dashboard-server.pid) label="Dashboard server" ;;
            *) label=$(basename "$pid_file") ;;
        esac
        local state="stopped"
        if kill -0 "$pid_value" 2>/dev/null; then
            state="running"
        fi
        report+=$'\n'"${label^} PID: $pid_value ($state)"
    done

    echo "$report"
}

# Helper: Resume session interactively
resume_session_interactive() {
    local session_path="$1"
    
    echo ""
    echo "Resume Session"
    echo "=============="
    show_session_details "$session_path"
    
    # Check if session is completed/exhausted
    local status_value
    status_value=$(tui_safe_json "$session_path/meta/session.json" '.status // ""' "" "session.status")
    
    local extend_iterations=""
    local extend_time=""
    
    if [[ "$status_value" == "completed" ]] || [[ "$status_value" == "completed_with_advisory" ]]; then
        echo ""
        echo "This session has completed. You can extend it with additional resources:"
        echo ""
        echo "Add more iterations? [Enter number or press Enter to skip]"
        read -r extend_iterations
        
        echo "Add more time (minutes)? [Enter number or press Enter to skip]"
        read -r extend_time
        
        # Validate inputs
        if [[ -n "$extend_iterations" ]] && ! [[ "$extend_iterations" =~ ^[0-9]+$ ]]; then
            echo "Invalid iterations value, ignoring"
            extend_iterations=""
        fi
        if [[ -n "$extend_time" ]] && ! [[ "$extend_time" =~ ^[0-9]+$ ]]; then
            echo "Invalid time value, ignoring"
            extend_time=""
        fi
    fi
    
    echo ""
    echo "Would you like to add refinement guidance? [y/N]"
    read -r add_refinement
    
    local refinement=""
    if [[ "$add_refinement" =~ ^[Yy] ]]; then
        echo ""
        echo "Enter refinement guidance (press Ctrl+D when done):"
        refinement=$(cat)
    fi
    
    # Build resume command with optional flags
    local resume_args=("--session" "$session_path")
    
    if [[ -n "$extend_iterations" ]]; then
        resume_args+=("--extend-iterations" "$extend_iterations")
    fi
    
    if [[ -n "$extend_time" ]]; then
        resume_args+=("--extend-time" "$extend_time")
    fi
    
    if [[ -n "$refinement" ]]; then
        resume_args+=("--refine" "$refinement")
    fi
    
    "$CCONDUCTOR_ROOT/src/cconductor-mission.sh" resume "${resume_args[@]}"
}

# Simple interactive mode (fallback)
start_new_research_simple() {
    echo "🔍 CConductor - AI Research, Orchestrated"
    echo ""
    echo "What would you like to research?"
    read -r research_question

    if [ -z "$research_question" ]; then
        echo "No research question provided."
        read -r -p "Press Enter to return to the menu..." _
        return
    fi

    echo ""
    echo "Select mission type:"
    echo "  1) general-research (flexible for any topic)"
    echo "  2) academic-research (scholarly sources)"
    echo "  3) market-research (market sizing, trends)"
    echo "  4) competitive-analysis (competitor landscape)"
    echo "  5) technical-analysis (technical deep-dive)"
    echo ""
    echo -n "Choice [1-5] (default: 1): "
    read -r mission_choice

    local mission_name="general-research"
    case "${mission_choice:-1}" in
        1) mission_name="general-research" ;;
        2) mission_name="academic-research" ;;
        3) mission_name="market-research" ;;
        4) mission_name="competitive-analysis" ;;
        5) mission_name="technical-analysis" ;;
        *) echo "Invalid choice, using general-research"; mission_name="general-research" ;;
    esac

    echo ""
    echo "Starting research with $mission_name mission..."
    echo ""

    local mission_cmd=("$CCONDUCTOR_ROOT/src/cconductor-mission.sh" "run" "--mission" "$mission_name" "$research_question")
    "${mission_cmd[@]}"

    echo ""
    read -r -p "Press Enter to return to the menu..." _
}

sessions_browser_simple() {
    while true; do
        echo ""
        echo "Loading research sessions..."
        load_sessions_into_arrays

        if [ ${#TUI_SESSION_PATHS[@]} -eq 0 ]; then
            echo ""
            echo "No sessions found. Start your first research!"
            read -r -p "Press Enter to continue..." _
            return
        fi

        echo ""
        echo "Legend: 🟢 Running  🟡 Idle  ✅ Complete  🔴 In Progress  ⚪ Unknown"
        echo ""
        echo "Sessions (newest first):"
        local idx
        for idx in "${!TUI_SESSION_PATHS[@]}"; do
            printf "  %d) %s\n" "$((idx + 1))" "${TUI_SESSION_LABELS[$idx]}"
        done
        echo ""
        echo -n "Select a session number (or press Enter to go back): "
        local choice
        read -r choice
        if [ -z "$choice" ]; then
            return
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#TUI_SESSION_PATHS[@]}" ]; then
            echo "Invalid selection."
            continue
        fi

        local selected_idx=$((choice - 1))
        local session_path="${TUI_SESSION_PATHS[$selected_idx]}"

        local refresh_needed="false"
        while true; do
            echo ""
            echo "Session: ${TUI_SESSION_LABELS[$selected_idx]}"
            echo "  1) View details"
            echo "  2) View process status"
            echo "  3) Resume session"
            echo "  4) View journal"
            echo "  5) Back"
            echo -n "Choice: "
            local action
            read -r action
            case "$action" in
                1)
                    echo ""
                    show_session_details "$session_path"
                    read -r -p "Press Enter to continue..." _
                    ;;
                2)
                    echo ""
                    show_session_process_status "$session_path"
                    echo ""
                    read -r -p "Press Enter to continue..." _
                    ;;
                3)
                    resume_session_interactive "$session_path"
                    read -r -p "Press Enter to continue..." _
                    refresh_needed="true"
                    break
                    ;;
                4)
                    # shellcheck disable=SC1091
                    if source "$CCONDUCTOR_ROOT/src/utils/dashboard.sh" 2>/dev/null; then
                        dashboard_view "$session_path"
                    else
                        echo "Error: Dashboard utility not found"
                    fi
                    read -r -p "Press Enter to continue..." _
                    ;;
                5|"")
                    break
                    ;;
                *)
                    echo "Invalid selection."
                    ;;
            esac
        done

        if [ "$refresh_needed" = "true" ]; then
            continue
        fi
    done
}

resume_session_simple() {
    load_sessions_into_arrays

    if [ ${#TUI_SESSION_PATHS[@]} -eq 0 ]; then
        echo ""
        echo "No sessions found. Start your first research!"
        read -r -p "Press Enter to continue..." _
        return
    fi

    echo ""
    echo "Resume which session?"
    local idx
    for idx in "${!TUI_SESSION_PATHS[@]}"; do
        printf "  %d) %s\n" "$((idx + 1))" "${TUI_SESSION_LABELS[$idx]}"
    done
    echo ""
    echo -n "Select a session number (or press Enter to cancel): "
    local choice
    read -r choice
    if [ -z "$choice" ]; then
        return
    fi
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#TUI_SESSION_PATHS[@]}" ]; then
        echo "Invalid selection."
        read -r -p "Press Enter to continue..." _
        return
    fi

    local session_path="${TUI_SESSION_PATHS[$((choice - 1))]}"
    resume_session_interactive "$session_path"
    read -r -p "Press Enter to continue..." _
}

configure_simple() {
    echo ""
    if ! "$CCONDUCTOR_ROOT/cconductor" configure; then
        if command -v log_error &>/dev/null; then
            log_error "Unable to display configuration details."
        else
            echo "Error: Unable to display configuration details." >&2
        fi
    fi
    echo ""
    read -r -p "Press Enter to continue..." _
}

interactive_mode_simple() {
    while true; do
        echo ""
        echo "=============================="
        echo " CConductor Interactive Menu"
        echo "=============================="
        echo "1) Start new research"
        echo "2) View sessions"
        echo "3) Configure"
        echo "4) Exit"
        echo ""
        echo -n "Choice [1-4]: "
        local choice
        read -r choice
        case "$choice" in
            1) start_new_research_simple ;;
            2) sessions_browser_simple ;;
            3) configure_simple ;;
            4|"") return ;;
            *) echo "Invalid selection." ;;
        esac
    done
}

# Advanced interactive mode with dialog
interactive_mode_advanced() {
    if command -v require_command &>/dev/null; then
        if ! require_command "dialog" "" "" "silent"; then
            interactive_mode_simple
            return
        fi
    elif ! command -v dialog &> /dev/null; then
        interactive_mode_simple
        return
    fi
    
    while true; do
        choice=$(dialog --clear --title "CConductor - AI Research System" \
            --ok-label "Choose" \
            --no-cancel \
            --menu "What would you like to do?" 16 60 4 \
            1 "Start New Research" \
            2 "View Sessions" \
            3 "Configure" \
            4 "Exit" \
            2>&1 >/dev/tty)

        clear
        case $choice in
            1) research_wizard ;;
            2) sessions_browser ;;
            3)
                local config_output
                if config_output=$("$CCONDUCTOR_ROOT/cconductor" configure 2>&1); then
                    dialog --title "Configuration" --msgbox "$config_output" 22 90
                else
                    dialog --title "Configuration" --msgbox "Unable to load configuration details." 7 60
                fi
                ;;
            4) break ;;
        esac
    done
}

# Research wizard for dialog TUI
research_wizard() {
    # Input method selection
    local input_method
    input_method=$(dialog --title "Research Input" \
        --menu "How would you like to provide your research question?" 12 60 3 \
        1 "Type question directly" \
        2 "Load from file" \
        3 "Back" \
        2>&1 >/dev/tty)
    
    clear
    local question=""
    case $input_method in
        1)
            question=$(dialog --title "Research Question" \
                --inputbox "What would you like to research?" 10 60 \
                2>&1 >/dev/tty)
            clear
            ;;
        2)
            local file
            file=$(dialog --title "Question File" \
                --fselect "$HOME/" 14 48 \
                2>&1 >/dev/tty)
            clear
            if [ -f "$file" ]; then
                question=$(cat "$file")
            fi
            ;;
        3|"") return ;;
    esac
    
    if [ -z "$question" ]; then return; fi
    
    # Input directory selection
    local use_input_dir
    use_input_dir=$(dialog --title "Input Directory" \
        --yesno "Do you have local files (PDFs, documents) to analyze?" 7 60 \
        2>&1 >/dev/tty && echo "yes" || echo "no")
    clear
    
    local input_dir=""
    if [ "$use_input_dir" = "yes" ]; then
        input_dir=$(dialog --title "Select Input Directory" \
            --dselect "$HOME/" 14 48 \
            2>&1 >/dev/tty)
        clear
    fi
    
    # Mission type selection
    local mission
    mission=$(dialog --title "Mission Type" \
        --menu "Select research mission type:" 15 70 5 \
        1 "General Research (flexible for any topic)" \
        2 "Academic Research (scholarly sources)" \
        3 "Market Research (market sizing, trends)" \
        4 "Competitive Analysis (competitor landscape)" \
        5 "Technical Analysis (technical deep-dive)" \
        2>&1 >/dev/tty)
    clear
    
    local mission_name="general-research"
    case $mission in
        1) mission_name="general-research" ;;
        2) mission_name="academic-research" ;;
        3) mission_name="market-research" ;;
        4) mission_name="competitive-analysis" ;;
        5) mission_name="technical-analysis" ;;
        *) return ;;
    esac
    
    # Advanced options
    local show_advanced
    show_advanced=$(dialog --title "Advanced Options" \
        --yesno "Configure advanced options (budget, time limits)?" 7 60 \
        2>&1 >/dev/tty && echo "yes" || echo "no")
    clear
    
    local budget=""
    local max_time=""
    local max_invocations=""
    
    if [ "$show_advanced" = "yes" ]; then
        budget=$(dialog --title "Budget Limit" \
            --inputbox "Budget limit in USD (leave empty for mission default):" 10 60 \
            2>&1 >/dev/tty)
        clear
        
        max_time=$(dialog --title "Time Limit" \
            --inputbox "Time limit in minutes (leave empty for mission default):" 10 60 \
            2>&1 >/dev/tty)
        clear
        
        max_invocations=$(dialog --title "Invocation Limit" \
            --inputbox "Max agent invocations (leave empty for mission default):" 10 60 \
            2>&1 >/dev/tty)
        clear
    fi
    
    # Build command
    local mission_cmd=("$CCONDUCTOR_ROOT/src/cconductor-mission.sh" "run" "--mission" "$mission_name")
    [ -n "$input_dir" ] && mission_cmd+=(--input-dir "$input_dir")
    [ -n "$budget" ] && mission_cmd+=(--budget "$budget")
    [ -n "$max_time" ] && mission_cmd+=(--max-time "$max_time")
    [ -n "$max_invocations" ] && mission_cmd+=(--max-invocations "$max_invocations")
    mission_cmd+=("$question")
    
    "${mission_cmd[@]}"
    
    read -r -p "Press Enter to continue..."
}

# Sessions browser for dialog TUI
sessions_browser() {
    while true; do
        dialog --infobox "Loading research sessions..." 5 50
        sleep 0.1
        load_sessions_into_arrays

        if [ ${#TUI_SESSION_PATHS[@]} -eq 0 ]; then
            dialog --msgbox "No sessions found. Start your first research!" 7 50
            clear
            return
        fi

        local sessions=()
        local idx
        for idx in "${!TUI_SESSION_PATHS[@]}"; do
            sessions+=("$((idx + 1))" "${TUI_SESSION_LABELS[$idx]}")
        done
        local legend_text="Legend: 🟢 Running  🟡 Idle  ✅ Complete  🔴 In Progress  ⚪ Unknown"
        local menu_text=$'Select a session:\n\n'"$legend_text"

        local choice
        if ! choice=$(dialog --title "Research Sessions (Newest First)" \
            --cancel-label "Back" \
            --menu "$menu_text" 20 90 10 \
            "${sessions[@]}" \
            2>&1 >/dev/tty); then
            clear
            return
        fi

        clear
        [ -z "$choice" ] && continue

        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
            continue
        fi

        local selected_idx=$((choice - 1))
        if [ "$selected_idx" -lt 0 ] || [ "$selected_idx" -ge "${#TUI_SESSION_PATHS[@]}" ]; then
            continue
        fi

        local session_path="${TUI_SESSION_PATHS[$selected_idx]}"
        local refresh_needed="false"

        while true; do
            local action
            if ! action=$(dialog --title "Session Actions" \
                --menu "What would you like to do?" 14 70 5 \
                1 "View Details" \
                2 "View Process Status" \
                3 "Resume Research" \
                4 "View Journal" \
                5 "Back" \
                2>&1 >/dev/tty); then
                clear
                break
            fi

            clear
            case $action in
                1)
                    local detail_text
                    if detail_text=$(session_details_collect "$session_path"); then
                        dialog --title "Session Details" --msgbox "$detail_text" 22 90
                    else
                        dialog --msgbox "Unable to load session details." 7 60
                    fi
                    clear
                    ;;
                2)
                    local status_report
                    status_report=$(show_session_process_status "$session_path")
                    dialog --title "Process Status" --msgbox "${status_report:-No data available}" 20 80
                    clear
                    ;;
                3)
                    resume_session_interactive "$session_path"
                    read -r -p "Press Enter to continue..." _
                    refresh_needed="true"
                    clear
                    break
                    ;;
                4)
                    # shellcheck disable=SC1091
                    if source "$CCONDUCTOR_ROOT/src/utils/dashboard.sh" 2>/dev/null; then
                        dashboard_view "$session_path"
                    else
                        echo "Error: Dashboard utility not found" >&2
                    fi
                    read -r -p "Press Enter to return to actions..." _
                    clear
                    ;;
                5|"")
                    break
                    ;;
            esac
        done

        if [ "$refresh_needed" = "true" ]; then
            continue
        fi
    done
}

# Resume wizard (uses sessions browser)
resume_wizard() {
    sessions_browser
}

# Main interactive mode entry point
interactive_mode() {
    # Check for CI environment or non-TTY
    if [ -n "${CI:-}" ] || [ ! -t 0 ]; then
        if command -v log_error &>/dev/null; then
            log_error "Interactive mode requires a TTY"
            log_info "In CI or non-interactive environments, provide explicit arguments"
            log_info "Run: ./cconductor --help"
        else
            echo "Error: Interactive mode requires a TTY" >&2
            echo "In CI or non-interactive environments, provide explicit arguments" >&2
            echo "Run: ./cconductor --help" >&2
        fi
        return 1
    fi
    
    interactive_mode_advanced
}
