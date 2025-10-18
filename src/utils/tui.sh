#!/usr/bin/env bash
# TUI - Interactive text user interface for CConductor
# Provides dialog-based and simple fallback interfaces

set -euo pipefail

# Guard against direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This script should be sourced, not executed" >&2
    exit 1
fi

# Helper: Show session details
show_session_details() {
    local session_path="$1"
    
    if [ ! -f "$session_path/session.json" ]; then
        echo "Invalid session directory"
        return 1
    fi
    
    echo "Session Details:"
    echo "=================="
    echo ""
    
    local objective
    objective=$(jq -r '.objective // "N/A"' "$session_path/session.json" 2>/dev/null)
    local created
    created=$(jq -r '.created_at // "N/A"' "$session_path/session.json" 2>/dev/null)
    local mission
    mission=$(jq -r '.mission_name // "general-research"' "$session_path/session.json" 2>/dev/null)
    
    echo "Objective: $objective"
    echo "Mission: $mission"
    echo "Created: $created"
    echo ""
    
    # Budget info
    if [ -f "$session_path/budget.json" ]; then
        local spent
        spent=$(jq -r '.spent.cost_usd // 0' "$session_path/budget.json" 2>/dev/null)
        local invocations
        invocations=$(jq -r '.spent.agent_invocations // 0' "$session_path/budget.json" 2>/dev/null)
        echo "Budget spent: \$$spent ($invocations invocations)"
    fi
    
    # Iteration count
    if [ -f "$session_path/orchestration-log.jsonl" ]; then
        local iterations
        iterations=$(wc -l < "$session_path/orchestration-log.jsonl" | tr -d ' ')
        echo "Iterations: $iterations"
    fi
    
    # Report status
    if [ -f "$session_path/output/mission-report.md" ]; then
        local session_status
        if [ -f "$session_path/session.json" ]; then
            session_status=$(jq -r '.status // ""' "$session_path/session.json" 2>/dev/null || echo "")
        else
            session_status=""
        fi
        if [ "$session_status" = "completed_with_advisory" ]; then
            echo "Status: Complete (quality advisory)"
        else
            echo "Status: Complete (report available)"
        fi
    else
        echo "Status: In progress or incomplete"
    fi
    
    echo ""
}

# Helper: Resume session interactively
resume_session_interactive() {
    local session_path="$1"
    
    echo ""
    echo "Resume Session"
    echo "=============="
    show_session_details "$session_path"
    
    echo "Would you like to add refinement guidance? [y/N]"
    read -r add_refinement
    
    local refinement=""
    if [[ "$add_refinement" =~ ^[Yy] ]]; then
        echo ""
        echo "Enter refinement guidance (press Ctrl+D when done):"
        refinement=$(cat)
    fi
    
    # Extract session ID and call mission resume
    # Note: session_id extracted inline in command below
    "$CCONDUCTOR_ROOT/src/cconductor-mission.sh" resume --session "$session_path" ${refinement:+--refine "$refinement"}
}

# Simple interactive mode (fallback)
interactive_mode_simple() {
    echo "🔍 CConductor - AI Research, Orchestrated"
    echo ""
    echo "What would you like to research?"
    read -r research_question
    
    if [ -z "$research_question" ]; then
        echo "No research question provided. Exiting."
        return 0
    fi
    
    echo ""
    echo "Select mission type:"
    echo "  1) general-research (default - flexible for any topic)"
    echo "  2) academic-research (scholarly sources, scientific papers)"
    echo "  3) market-research (market sizing, trends, TAM/SAM/SOM)"
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
    
    # Build and execute mission command
    local mission_cmd=("$CCONDUCTOR_ROOT/src/cconductor-mission.sh" "run" "--mission" "$mission_name" "$research_question")
    "${mission_cmd[@]}"
}

# Advanced interactive mode with dialog
interactive_mode_advanced() {
    if ! command -v dialog &> /dev/null; then
        interactive_mode_simple
        return
    fi
    
    while true; do
        choice=$(dialog --clear --title "CConductor - AI Research System" \
            --menu "What would you like to do?" 16 60 6 \
            1 "Start New Research" \
            2 "View Sessions" \
            3 "Resume Session" \
            4 "Check Status" \
            5 "Configure" \
            6 "Exit" \
            2>&1 >/dev/tty)
        
        clear
        case $choice in
            1) research_wizard ;;
            2) sessions_browser ;;
            3) resume_wizard ;;
            4) 
                # shellcheck disable=SC2317
                pids=$(pgrep -f "cconductor-mission.sh" || true)
                if [ -z "$pids" ]; then
                    dialog --msgbox "No active research sessions" 7 40
                else
                    dialog --msgbox "Active sessions found:\nPIDs: $pids" 10 50
                fi
                ;;
            5)
                clear
                main configure
                read -r -p "Press Enter to continue..."
                ;;
            6|"") break ;;
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
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/path-resolver.sh" 2>/dev/null || true
    local session_dir
    session_dir=$(resolve_path "session_dir" 2>/dev/null || echo "$CCONDUCTOR_ROOT/research-sessions")
    
    if [ ! -d "$session_dir" ]; then
        dialog --msgbox "No sessions found. Start your first research!" 7 50
        return
    fi
    
    # Build session list sorted by modification time (newest first)
    local sessions=()
    local session_paths=()
    local idx=1
    
    # Sort by modification time, newest first
    # shellcheck disable=SC2045
    for session in $(ls -dt "$session_dir"/mission_* 2>/dev/null); do
        [ -d "$session" ] || continue
        local created="N/A"
        local question="N/A"
        local status="unknown"
        
        if [ -f "$session/session.json" ]; then
            created=$(jq -r '.created_at // "N/A"' "$session/session.json" 2>/dev/null)
            question=$(jq -r '.objective // "N/A"' "$session/session.json" 2>/dev/null)
        fi
        
        if [ -f "$session/output/mission-report.md" ]; then
            status="Complete"
            if [ -f "$session/session.json" ]; then
                local session_status
                session_status=$(jq -r '.status // ""' "$session/session.json" 2>/dev/null || echo "")
                if [ "$session_status" = "completed_with_advisory" ]; then
                    status="Complete (advisory)"
                fi
            fi
        else
            status="In progress"
        fi
        
        # Truncate question for display
        local display_text="$status | ${question:0:35}..."
        sessions+=("$idx" "$display_text")
        session_paths+=("$session")
        idx=$((idx + 1))
    done
    
    if [ ${#sessions[@]} -eq 0 ]; then
        dialog --msgbox "No sessions found." 7 50
        return
    fi
    
    local choice
    choice=$(dialog --title "Research Sessions (Newest First)" \
        --menu "Select a session:" 20 70 10 \
        "${sessions[@]}" \
        2>&1 >/dev/tty)
    
    clear
    [ -z "$choice" ] && return
    
    # Get selected session path
    local selected_idx=$((choice - 1))
    local session_path="${session_paths[$selected_idx]}"
    
    # Action menu for selected session
    local action
    action=$(dialog --title "Session Actions" \
        --menu "What would you like to do?" 12 60 4 \
        1 "View Details" \
        2 "Resume Research" \
        3 "View Journal" \
        4 "Back" \
        2>&1 >/dev/tty)
    
    clear
    case $action in
        1) 
            show_session_details "$session_path"
            read -r -p "Press Enter to continue..."
            ;;
        2) 
            resume_session_interactive "$session_path"
            read -r -p "Press Enter to continue..."
            ;;
        3) 
            # shellcheck disable=SC1091
            if source "$CCONDUCTOR_ROOT/src/utils/dashboard.sh" 2>/dev/null; then
                dashboard_view "$session_path"
            else
                echo "Error: Dashboard utility not found" >&2
            fi
            read -r -p "Press Enter to continue..."
            ;;
    esac
}

# Resume wizard (uses sessions browser)
resume_wizard() {
    sessions_browser
}

# Main interactive mode entry point
interactive_mode() {
    # Check for CI environment or non-TTY
    if [ -n "${CI:-}" ] || [ ! -t 0 ]; then
        echo "Error: Interactive mode requires a TTY" >&2
        echo "In CI or non-interactive environments, provide explicit arguments" >&2
        echo "Run: ./cconductor --help" >&2
        return 1
    fi
    
    interactive_mode_advanced
}
