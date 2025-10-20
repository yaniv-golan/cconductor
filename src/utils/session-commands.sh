#!/usr/bin/env bash
# Session Commands - Handlers for sessions subcommand
# Provides list, latest, viewer, resume functionality

set -euo pipefail

# Guard against direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This script should be sourced, not executed" >&2
    exit 1
fi

# Handle sessions list subcommand
sessions_list_handler() {
    # List research sessions from session directory
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_ROOT/src/utils/path-resolver.sh"
    local session_dir
    session_dir=$(resolve_path "session_dir" 2>/dev/null || echo "$CCONDUCTOR_ROOT/research-sessions")
    
    if [ ! -d "$session_dir" ]; then
        echo "No research sessions found"
        echo "Start your first research: ./cconductor \"your question\""
        exit 0
    fi
    
    echo "Research Sessions:"
    echo "══════════════════════════════════════════════════"
    echo ""
    
    # Find all session directories
    local count=0
    for session in "$session_dir"/session_* "$session_dir"/mission_session_*; do
        [ -d "$session" ] || continue
        count=$((count + 1))
        
        local session_name
        session_name=$(basename "$session")
        local created="N/A"
        local question="N/A"
        local status="unknown"
        
        # Try to read session metadata
        if [ -f "$session/session.json" ]; then
            created=$(jq -r '.created_at // .started_at // "N/A"' "$session/session.json" 2>/dev/null)
            question=$(jq -r '.research_question // .objective // "N/A"' "$session/session.json" 2>/dev/null)
            status=$(jq -r '.status // "unknown"' "$session/session.json" 2>/dev/null)
        fi
        
        echo "[$count] $session_name"
        echo "    Created: $created"
        echo "    Status: $status"
        echo "    Question: ${question:0:80}$([ ${#question} -gt 80 ] && echo '...')"
        echo ""
    done
    
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
            if [ -f "$LATEST_PATH/session.json" ]; then
                local question
                question=$(jq -r '.research_question // "N/A"' "$LATEST_PATH/session.json" 2>/dev/null || echo "N/A")
                local status
                status=$(jq -r '.status // "unknown"' "$LATEST_PATH/session.json" 2>/dev/null || echo "unknown")
                local created
                created=$(jq -r '.created_at // "N/A"' "$LATEST_PATH/session.json" 2>/dev/null || echo "N/A")
                
                echo "Question: $question"
                echo "Status: $status"
                echo "Created: $created"
                echo ""
            fi
            
            # Show knowledge graph summary if available
            if [ -f "$LATEST_PATH/knowledge-graph.json" ]; then
                local entities
                local claims
                local confidence
                local gaps
                entities=$(jq -r '.stats.total_entities // 0' "$LATEST_PATH/knowledge-graph.json" 2>/dev/null)
                claims=$(jq -r '.stats.total_claims // 0' "$LATEST_PATH/knowledge-graph.json" 2>/dev/null)
                confidence=$(jq -r '.confidence_scores.overall // 0' "$LATEST_PATH/knowledge-graph.json" 2>/dev/null)
                gaps=$(jq -r '.stats.unresolved_gaps // 0' "$LATEST_PATH/knowledge-graph.json" 2>/dev/null)
                
                echo "Progress:"
                echo "  • Entities: $entities"
                echo "  • Claims: $claims"
                echo "  • Confidence: $confidence"
                echo "  • Unresolved gaps: $gaps"
                echo ""
            fi
            
            # Show report if exists
            if [ -f "$LATEST_PATH/final/mission-report.md" ]; then
                echo "✓ Report available: $LATEST_PATH/final/mission-report.md"
                echo ""
                echo "View with:"
                echo "  cat $LATEST_PATH/final/mission-report.md"
                echo "  open $LATEST_PATH/final/mission-report.md"
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
            echo "Error: Latest session directory not found: $LATEST_SESSION"
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
            echo "Error: No active session found" >&2
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
        # Session ID provided (with or without 'session_' prefix)
        local session_id="$session_arg"
        if [[ ! "$session_id" == session_* ]]; then
            session_id="session_${session_id}"
        fi
        session_dir="$CCONDUCTOR_ROOT/research-sessions/$session_id"
    fi
    
    # Validate session directory exists
    if [ ! -d "$session_dir" ]; then
        echo "Error: Session directory not found: $session_dir" >&2
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
            echo "Error: Failed to launch dashboard viewer" >&2
            exit 1
        fi
    else
        echo "Error: Dashboard viewer utility not found" >&2
        exit 1
    fi
}

# Handle sessions resume subcommand
sessions_resume_handler() {
    local session_id="$1"
    
    if [ -z "$session_id" ]; then
        echo "Error: Session ID required" >&2
        echo "Usage: cconductor sessions resume <session_id> [--refine \"guidance\" | --refine-file path]" >&2
        exit 1
    fi
    
    # Get refinement if provided
    local refinement=""
    if has_flag "refine"; then
        refinement=$(get_flag "refine")
    elif has_flag "refine-file"; then
        local refine_file
        refine_file=$(get_flag "refine-file")
        if [ ! -f "$refine_file" ]; then
            echo "Error: Refinement file not found: $refine_file" >&2
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
        echo "Error: Session not found: $session_id" >&2
        exit 1
    fi
    
    # Call mission resume
    if [ -n "$refinement" ]; then
        "$CCONDUCTOR_ROOT/src/cconductor-mission.sh" resume --session "$session_path" --refine "$refinement"
    else
        "$CCONDUCTOR_ROOT/src/cconductor-mission.sh" resume --session "$session_path"
    fi
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
            echo "    --refine \"guidance\"       Add refinement when resuming" >&2
            echo "    --refine-file path       Load refinement from file" >&2
            exit 1
            ;;
    esac
}
