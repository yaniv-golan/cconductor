#!/usr/bin/env bash
# Session Commands - Handlers for sessions subcommand
# Provides list, latest, viewer, resume functionality

set -euo pipefail

# Guard against direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This script should be sourced, not executed" >&2
    exit 1
fi

# Source core helpers (when available)
if [[ -n "${CCONDUCTOR_ROOT:-}" ]] && [[ -f "$CCONDUCTOR_ROOT/src/utils/core-helpers.sh" ]]; then
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/core-helpers.sh"
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/error-messages.sh"
fi

# Shared session helpers
# shellcheck disable=SC1091
source "$CCONDUCTOR_ROOT/src/utils/session-utils.sh"

# Handle sessions list subcommand
sessions_list_handler() {
    local count=0
    local entries
    entries=$(session_utils_collect_sessions)

    if [ -z "$entries" ]; then
        echo "No research sessions found"
        echo "Start your first research: ./cconductor \"your question\""
        exit 0
    fi

    echo "Research Sessions:"
    echo "══════════════════════════════════════════════════"
    echo ""

    while IFS=$'\t' read -r path mission_id created status objective; do
        [ -n "$path" ] || continue
        count=$((count + 1))
        local display_question
        display_question=$(echo "$objective" | sed 's/  */ /g' | sed 's/^ *//; s/ *$//')
        if [ ${#display_question} -gt 80 ]; then
            display_question="${display_question:0:80}..."
        fi
        echo "[$count] $mission_id"
        echo "    Created: $created"
        echo "    Status: $status"
        echo "    Objective: $display_question"
        echo "    Path: $path"
        echo ""
    done <<< "$entries"

    if [ $count -eq 0 ]; then
        echo "No research sessions found"
        echo ""
        echo "Start your first research:"
        echo "  ./cconductor \"your question\""
    else
        echo "Total: $count session(s)"
        echo ""
        echo "View latest: ./cconductor sessions latest"
    fi
}

# Handle sessions latest subcommand  
sessions_latest_handler() {
    # Get session directory from path resolver (with fallback)
    local session_dir="$CCONDUCTOR_ROOT/research-sessions"
    if [ -f "$CCONDUCTOR_ROOT/src/utils/path-resolver.sh" ]; then
        # shellcheck disable=SC1091
        source "$CCONDUCTOR_ROOT/src/utils/path-resolver.sh" 2>/dev/null
        local resolved
        # Use return code instead of string check
        if resolved=$(resolve_path "session_dir" 2>/dev/null) && [ -n "$resolved" ]; then
            session_dir="$resolved"
        fi
    fi
    
    if [ -f "$session_dir/.latest" ]; then
        LATEST_SESSION=$(cat "$session_dir/.latest")
        LATEST_PATH="$session_dir/$LATEST_SESSION"
        
        if [ -d "$LATEST_PATH" ]; then
            echo "Latest session: $LATEST_SESSION"
            echo "Location: $LATEST_PATH"
            echo ""
            
            # Show session metadata if available
            if [ -f "$LATEST_PATH/meta/session.json" ]; then
                local question
                question=$(session_utils_safe_meta_value "$LATEST_PATH" '.research_question // "N/A"' "N/A" "latest.question")
                local status
                status=$(session_utils_safe_meta_value "$LATEST_PATH" '.status // "unknown"' "unknown" "latest.status")
                local created
                created=$(session_utils_safe_meta_value "$LATEST_PATH" '.created_at // "N/A"' "N/A" "latest.created")
                
                echo "Question: $question"
                echo "Status: $status"
                echo "Created: $created"
                echo ""
            fi
            
            # Show knowledge graph summary if available
            if [ -f "$LATEST_PATH/knowledge/knowledge-graph.json" ]; then
                local entities
                local claims
                local confidence
                local gaps
                entities=$(jq -r '.stats.total_entities // 0' "$LATEST_PATH/knowledge/knowledge-graph.json" 2>/dev/null)
                claims=$(jq -r '.stats.total_claims // 0' "$LATEST_PATH/knowledge/knowledge-graph.json" 2>/dev/null)
                confidence=$(jq -r '.confidence_scores.overall // 0' "$LATEST_PATH/knowledge/knowledge-graph.json" 2>/dev/null)
                gaps=$(jq -r '.stats.unresolved_gaps // 0' "$LATEST_PATH/knowledge/knowledge-graph.json" 2>/dev/null)
                
                echo "Progress:"
                echo "  • Entities: $entities"
                echo "  • Claims: $claims"
                echo "  • Confidence: $confidence"
                echo "  • Unresolved gaps: $gaps"
                echo ""
            fi
            
            # Show report if exists
            if [ -f "$LATEST_PATH/report/mission-report.md" ]; then
                echo "✓ Report available: $LATEST_PATH/report/mission-report.md"
                echo ""
                echo "View with:"
                echo "  cat $LATEST_PATH/report/mission-report.md"
                echo "  open $LATEST_PATH/report/mission-report.md"
                echo ""
                echo "Resume with:"
                echo "  ./cconductor resume $LATEST_SESSION"
            else
                echo "⏳ Research in progress or not yet complete"
                echo ""
                echo "Resume with:"
                echo "  ./cconductor resume $LATEST_SESSION"
            fi
        else
            if command -v error_missing_file &>/dev/null; then
                error_missing_file "$LATEST_SESSION" "Latest session directory not found"
            else
                echo "Error: Latest session directory not found: $LATEST_SESSION"
            fi
            exit 1
        fi
    else
        echo "No research sessions yet. Start one with:"
        echo "  ./cconductor \"your research question\""
    fi
}

# Handle sessions viewer subcommand
sessions_viewer_handler() {
    # Get session directory (optional parameter)
    local session_arg="$1"
    local session_dir=""
    
    if [ -z "$session_arg" ]; then
        # No argument - use latest session
        local latest_file="$CCONDUCTOR_ROOT/research-sessions/.latest"
        if [ ! -f "$latest_file" ]; then
            if command -v log_error &>/dev/null; then
                log_error "No active session found"
            else
                echo "Error: No active session found" >&2
            fi
            echo "Run a research query first: ./cconductor \"your question\"" >&2
            exit 1
        fi
        local session_id
        session_id=$(cat "$latest_file")
        session_dir="$CCONDUCTOR_ROOT/research-sessions/$session_id"
    elif [[ "$session_arg" == /* ]]; then
        # Absolute path provided
        session_dir="$session_arg"
    else
        # Session ID provided (supports mission_* and legacy session_* prefixes)
        local session_id="$session_arg"
        local resolved_id=""
        if [[ "$session_id" == mission_* ]]; then
            resolved_id="$session_id"
        elif [[ "$session_id" == session_* ]]; then
            resolved_id="$session_id"
            local mission_candidate="mission_${session_id#session_}"
            if [ ! -d "$CCONDUCTOR_ROOT/research-sessions/$resolved_id" ] && [ -d "$CCONDUCTOR_ROOT/research-sessions/$mission_candidate" ]; then
                resolved_id="$mission_candidate"
            fi
        else
            resolved_id="mission_$session_id"
            if [ ! -d "$CCONDUCTOR_ROOT/research-sessions/$resolved_id" ] && [ -d "$CCONDUCTOR_ROOT/research-sessions/session_$session_id" ]; then
                resolved_id="session_$session_id"
            fi
        fi
        session_dir="$CCONDUCTOR_ROOT/research-sessions/$resolved_id"
    fi
    
    # Validate session directory exists
    if [ ! -d "$session_dir" ]; then
        if command -v error_missing_file &>/dev/null; then
            error_missing_file "$session_dir" "Session directory not found"
        else
            echo "Error: Session directory not found: $session_dir" >&2
        fi
        exit 1
    fi
    
    # Launch dashboard using unified utility
    echo "Starting Research Journal Viewer..."
    # shellcheck disable=SC1091
    if source "$CCONDUCTOR_ROOT/src/utils/dashboard.sh" 2>/dev/null; then
        if dashboard_view "$session_dir"; then
            echo ""
            echo "To stop the server later:"
            if [ -f "$session_dir/.dashboard-server.pid" ]; then
                local server_pid
                server_pid=$(cat "$session_dir/.dashboard-server.pid")
                echo "  kill $server_pid"
            fi
            echo "  or: pkill -f 'http-server'"
        else
            log_system_error "$session_dir" "sessions_viewer" "Failed to launch dashboard viewer"
            echo "Error: Failed to launch dashboard viewer" >&2
            exit 1
        fi
    else
        log_system_error "$session_dir" "sessions_viewer" "Dashboard viewer utility not found"
        echo "Error: Dashboard viewer utility not found" >&2
        exit 1
    fi
}

# Handle sessions resume subcommand
sessions_resume_handler() {
    local session_id="$1"
    
    if [ -z "$session_id" ]; then
        if command -v log_error &>/dev/null; then
            log_error "Session ID required"
        else
            echo "Error: Session ID required" >&2
        fi
        echo "Usage: cconductor sessions resume <session_id> [--extend-iterations N] [--extend-time M] [--refine \"guidance\" | --refine-file path]" >&2
        exit 1
    fi
    
    # Get extension iterations if provided
    local extend_iterations=""
    if has_flag "extend-iterations"; then
        extend_iterations=$(get_flag "extend-iterations")
        # Validate it's a positive integer
        if ! [[ "$extend_iterations" =~ ^[0-9]+$ ]] || [[ "$extend_iterations" -eq 0 ]]; then
            echo "Error: --extend-iterations must be a positive integer" >&2
            exit 1
        fi
    fi
    
    # Get extension time if provided
    local extend_time=""
    if has_flag "extend-time"; then
        extend_time=$(get_flag "extend-time")
        # Validate it's a positive integer (minutes)
        if ! [[ "$extend_time" =~ ^[0-9]+$ ]] || [[ "$extend_time" -eq 0 ]]; then
            echo "Error: --extend-time must be a positive integer (minutes)" >&2
            exit 1
        fi
    fi
    
    # Get refinement if provided
    local refinement=""
    if has_flag "refine"; then
        refinement=$(get_flag "refine")
    elif has_flag "refine-file"; then
        local refine_file
        refine_file=$(get_flag "refine-file")
        if [ ! -f "$refine_file" ]; then
            if command -v error_missing_file &>/dev/null; then
                error_missing_file "$refine_file" "Refinement file not found"
            else
                echo "Error: Refinement file not found: $refine_file" >&2
            fi
            exit 1
        fi
        refinement=$(cat "$refine_file")
    fi
    
    # Interactive refinement prompt if no flags provided
    if [ -z "$refinement" ] && [ -t 0 ]; then
        echo "Resume session: $session_id"
        echo ""
        echo "Would you like to add refinement guidance? [y/N]"
        read -r add_refinement
        
        if [[ "$add_refinement" =~ ^[Yy] ]]; then
            echo ""
            echo "Enter refinement guidance (Ctrl+D when done):"
            refinement=$(cat)
        fi
    fi
    
    # Build session path
    local session_path
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/path-resolver.sh"
    local sessions_dir
    sessions_dir=$(resolve_path "session_dir" 2>/dev/null || echo "$CCONDUCTOR_ROOT/research-sessions")
    
    if [[ "$session_id" == /* ]]; then
        session_path="$session_id"
    elif [[ "$session_id" == mission_* ]]; then
        session_path="$sessions_dir/$session_id"
    else
        session_path="$sessions_dir/mission_$session_id"
    fi
    
    if [ ! -d "$session_path" ]; then
        log_system_error "$session_path" "sessions_resume" "Session not found: $session_id"
        echo "Error: Session not found: $session_id" >&2
        exit 1
    fi
    
    # Call mission resume
    local resume_args=("--session" "$session_path")
    
    if [ -n "$extend_iterations" ]; then
        resume_args+=("--extend-iterations" "$extend_iterations")
    fi
    
    if [ -n "$extend_time" ]; then
        resume_args+=("--extend-time" "$extend_time")
    fi
    
    if [ -n "$refinement" ]; then
        resume_args+=("--refine" "$refinement")
    fi
    
    "$CCONDUCTOR_ROOT/src/cconductor-mission.sh" resume "${resume_args[@]}"
}

# Main sessions router
handle_sessions_command() {
    local subcommand="${1:-list}"
    shift || true
    
    case "$subcommand" in
        list)
            sessions_list_handler "$@"
            ;;
        latest)
            sessions_latest_handler "$@"
            ;;
        viewer)
            sessions_viewer_handler "${1:-}"
            ;;
        resume)
            sessions_resume_handler "${1:-}" "$@"
            ;;
        *)
            echo "Unknown sessions subcommand: $subcommand" >&2
            echo "" >&2
            echo "Available subcommands:" >&2
            echo "  list                       List all research sessions" >&2
            echo "  latest                     Show latest session" >&2
            echo "  viewer [session_id]        View research journal" >&2
            echo "  resume <session_id>        Resume a session" >&2
            echo "    --extend-iterations N    Add N additional iterations" >&2
            echo "    --extend-time M          Add M additional minutes" >&2
            echo "    --refine \"guidance\"       Add refinement when resuming" >&2
            echo "    --refine-file path       Load refinement from file" >&2
            exit 1
            ;;
    esac
}
