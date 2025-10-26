#!/usr/bin/env bash
# CConductor Mission-Based Research
# Entry point for mission-based orchestration (v0.4.0)

set -euo pipefail

# Re-enable bash trace if debug mode is active
if [[ "${CCONDUCTOR_DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Save script directory before sourcing other files (they may redefine SCRIPT_DIR)
CCONDUCTOR_MISSION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$CCONDUCTOR_MISSION_SCRIPT_DIR")"
export PROJECT_ROOT

# Load utilities
# shellcheck disable=SC1091
source "$CCONDUCTOR_MISSION_SCRIPT_DIR/utils/mission-loader.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_MISSION_SCRIPT_DIR/utils/mission-orchestration.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_MISSION_SCRIPT_DIR/utils/mission-session-init.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_MISSION_SCRIPT_DIR/knowledge-graph.sh"

# Enable error traps for mission orchestration workflows
if [[ "$(type -t setup_error_trap 2>/dev/null)" != "function" ]]; then
    # shellcheck disable=SC1090,SC1091
    source "$CCONDUCTOR_MISSION_SCRIPT_DIR/utils/debug.sh"
fi
setup_error_trap

# Print usage
usage() {
    cat <<EOF
CConductor Mission-Based Research (v0.4.0)

USAGE:
  cconductor-mission run --mission <name> [OPTIONS]
  cconductor-mission missions list
  cconductor-mission missions describe <name>
  cconductor-mission agents list
  cconductor-mission agents describe <name>
  cconductor-mission dry-run --mission <name> [OPTIONS]

COMMANDS:
  run            Execute a mission
  missions       Mission management (list, describe)
  agents         Agent management (list, describe)
  dry-run        Validate mission and show what would happen (alias: preflight)

OPTIONS:
  --mission <name>              Mission profile name
  --mission-file <path>         Path to custom mission JSON file
  --input-dir <dir>             Directory with input files (PDFs, notes, etc.)
  --output <dir>                Output directory for reports
  --budget <usd>                Budget limit in USD (overrides mission default)
  --max-time <minutes>          Time limit in minutes (overrides mission default)
  --max-invocations <n>         Max agent invocations (overrides mission default)
  --strict                      Enforce all validations (fail if unmet)
  --yes                         Non-interactive mode (skip confirmations)
  --open                        Open dashboard/viewer after completion
  --no-dashboard                Don't launch dashboard
  --log-level <level>           Logging level (info|debug)

EXAMPLES:
  # Run market research mission
  cconductor-mission run --mission market-research --input-dir ~/data/

  # Run with budget override
  cconductor-mission run --mission market-research --input-dir ~/data/ --budget 5.0

  # Dry-run to validate
  cconductor-mission dry-run --mission market-research --input-dir ~/data/

  # List available missions
  cconductor-mission missions list

  # Describe a mission
  cconductor-mission missions describe market-research

  # List available agents
  cconductor-mission agents list

EOF
}

# Command: missions list
cmd_missions_list() {
    mission_list "detailed"
}

# Command: missions describe
cmd_missions_describe() {
    local mission_name="$1"
    
    if [[ -z "$mission_name" ]]; then
        echo "Error: Mission name required" >&2
        echo "Usage: cconductor-mission missions describe <name>" >&2
        exit 1
    fi
    
    mission_describe "$mission_name"
}

# Command: agents list
cmd_agents_list() {
    agent_registry_init
    agent_registry_list "detailed"
}

# Command: agents describe
cmd_agents_describe() {
    local agent_name="$1"
    
    if [[ -z "$agent_name" ]]; then
        echo "Error: Agent name required" >&2
        echo "Usage: cconductor-mission agents describe <name>" >&2
        exit 1
    fi
    
    agent_registry_init
    
    if ! agent_registry_exists "$agent_name"; then
        echo "Error: Agent '$agent_name' not found" >&2
        exit 1
    fi
    
    local metadata
    metadata=$(agent_registry_get_metadata "$agent_name")
    
    echo "Agent: $agent_name"
    echo ""
    echo "Description:"
    echo "  $(echo "$metadata" | jq -r '.description')"
    echo ""
    echo "Capabilities:"
    echo "$metadata" | jq -r '.capabilities[]? | "  - \(.)"'
    echo ""
    echo "Tools:"
    echo "$metadata" | jq -r '.tools | join(", ")' | sed 's/^/  /'
    echo ""
    echo "Model:"
    echo "  $(echo "$metadata" | jq -r '.model')"
    
    if echo "$metadata" | jq -e '.best_used_for' >/dev/null 2>&1; then
        echo ""
        echo "Best Used For:"
        echo "  $(echo "$metadata" | jq -r '.best_used_for')"
    fi
}

# Command: resume
cmd_resume() {
    local session_dir="$1"
    local refinement="${2:-}"
    local extend_iterations="${3:-}"
    local extend_time="${4:-}"
    
    # Load session metadata
    if [ ! -f "$session_dir/meta/session.json" ]; then
        echo "Error: Invalid session directory" >&2
        exit 1
    fi
    
    local objective
    objective=$(jq -r '.objective' "$session_dir/meta/session.json")
    echo "→ Resuming session..."
    echo "  Original objective: $objective"
    
    if [ -n "$extend_iterations" ]; then
        echo "  Extending by $extend_iterations additional iterations"
    fi
    
    if [ -n "$extend_time" ]; then
        echo "  Extending by $extend_time additional minutes"
    fi
    
    if [ -n "$refinement" ]; then
        echo "  With refinement: ${refinement:0:60}..."
        
        # Add refinement to session metadata with safe array init
        local temp_file
        temp_file=$(mktemp)
        jq --arg ref "$refinement" \
           --arg time "$(get_timestamp)" \
           '.refinements = (.refinements // []) | .refinements += [{refinement: $ref, added_at: $time}]' \
           "$session_dir/meta/session.json" > "$temp_file"
        mv "$temp_file" "$session_dir/meta/session.json"
    fi
    
    # Load mission profile from original session
    local mission_name
    mission_name=$(jq -r '.mission_name // "general-research"' "$session_dir/meta/session.json" 2>/dev/null || echo "general-research")
    
    # Store mission_name in session if not present
    if ! jq -e '.mission_name' "$session_dir/meta/session.json" >/dev/null 2>&1; then
        local temp_file
        temp_file=$(mktemp)
        jq --arg mn "$mission_name" '.mission_name = $mn' "$session_dir/meta/session.json" > "$temp_file"
        mv "$temp_file" "$session_dir/meta/session.json"
    fi
    
    local mission_profile
    if ! mission_profile=$(mission_load "$mission_name"); then
        exit 1
    fi
    
    # Continue orchestration with resume flag
    run_mission_orchestration_resume "$mission_profile" "$session_dir" "$refinement" "$extend_iterations" "$extend_time"
}

# Command: dry-run
cmd_dry_run() {
    local mission_name="$1"
    local input_dir="${2:-}"
    
    echo "🔍 Dry-Run: Mission Preflight Check"
    echo ""
    
    # Load mission
    echo "→ Loading mission profile..."
    local mission_profile
    if ! mission_profile=$(mission_load "$mission_name"); then
        exit 1
    fi
    echo "  ✓ Mission loaded: $mission_name"
    echo ""
    
    # Validate input directory if provided
    if [[ -n "$input_dir" ]]; then
        echo "→ Checking input directory..."
        if [[ ! -d "$input_dir" ]]; then
            echo "  ✗ Error: Input directory not found: $input_dir"
            exit 1
        fi
        
        local file_count
        file_count=$(find "$input_dir" -type f | wc -l | tr -d ' ')
        echo "  ✓ Input directory exists ($file_count files)"
        echo ""
    fi
    
    # Display mission details
    echo "═══ Mission Details ═══"
    echo ""
    mission_describe "$mission_name"
    echo ""
    
    # Check agent availability
    echo "═══ Agent Availability ═══"
    echo ""
    echo "→ Initializing agent registry..."
    agent_registry_init
    
    local preferred_agents
    preferred_agents=$(echo "$mission_profile" | jq -r '.preferred_agents[]?.agent // empty')
    
    if [[ -n "$preferred_agents" ]]; then
        echo "Checking preferred agents:"
        while IFS= read -r agent_name; do
            if agent_registry_exists "$agent_name"; then
                echo "  ✓ $agent_name (available)"
            else
                echo "  ⚠ $agent_name (not found - will use alternatives)"
            fi
        done <<< "$preferred_agents"
    else
        echo "  No preferred agents specified - orchestrator will select dynamically"
    fi
    
    echo ""
    echo "═══ Preflight Complete ═══"
    echo ""
    echo "✓ Mission is ready to run"
    echo ""
    echo "To execute:"
    echo "  cconductor-mission run --mission $mission_name" \
         "${input_dir:+--input-dir $input_dir}"
}

# Command: run
cmd_run() {
    local mission_name="$1"
    local input_dir="${2:-}"
    local research_question="${3:-}"
    local non_interactive="${4:-false}"
    local output_dir="${5:-}"
    
    # Load mission
    echo "→ Loading mission profile..."
    local mission_profile
    if ! mission_profile=$(mission_load "$mission_name"); then
        exit 1
    fi
    
    # Use research question if provided, otherwise use mission objective
    local mission_objective
    if [[ -n "$research_question" ]]; then
        mission_objective="$research_question"
    else
        mission_objective=$(echo "$mission_profile" | jq -r '.objective')
    fi
    
    # Initialize session
    echo "→ Initializing session..."
    local session_dir
    session_dir=$(initialize_session "$mission_objective" "$output_dir")
    echo "  ✓ Session: $(basename "$session_dir")"
    echo "    Path: $session_dir"
    echo ""
    
    # Initialize knowledge graph with clean objective
    echo "→ Initializing knowledge graph..."
    local clean_objective
    clean_objective=$(jq -r '.objective' "$session_dir/meta/session.json")
    kg_init "$session_dir" "$clean_objective" >/dev/null
    echo "  ✓ Knowledge graph ready"
    echo ""
    
    # Process input files if provided
    local UTILS_DIR="$CCONDUCTOR_MISSION_SCRIPT_DIR/utils"
    if [[ -n "$input_dir" ]]; then
        echo "→ Processing input files..."
        # shellcheck disable=SC1091
        source "$UTILS_DIR/input-files-manager.sh"
        
        if process_input_directory "$input_dir" "$session_dir"; then
            echo "  ✓ Input files processed"
            
            # Store input_dir reference in session metadata
            local temp_session="$session_dir/meta/session.json.tmp"
            jq --arg input_dir "$input_dir" \
               '.input_dir = $input_dir' \
               "$session_dir/meta/session.json" > "$temp_session" && \
               mv "$temp_session" "$session_dir/meta/session.json"
        else
            echo "  ⚠  Warning: Failed to process some input files"
        fi
        echo ""
    fi
    
    # Store mission name in session metadata for journal
    local temp_session="$session_dir/meta/session.json.tmp"
    jq --arg mission "$mission_name" \
       '.mission_name = $mission' \
       "$session_dir/meta/session.json" > "$temp_session" && \
       mv "$temp_session" "$session_dir/meta/session.json"
    
    # Run mission orchestration
    run_mission_orchestration "$mission_profile" "$session_dir"
}

# Main entry point
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        run)
            # Parse run options
            local mission_name=""
            local input_dir=""
            local non_interactive=false
            local research_question=""
            local output_dir=""
            
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --mission)
                        mission_name="$2"
                        shift 2
                        ;;
                    --input-dir)
                        input_dir="$2"
                        shift 2
                        ;;
                    --non-interactive|-y)
                        non_interactive=true
                        shift
                        ;;
                    --output)
                        if [[ -z "${2:-}" ]]; then
                            echo "Error: --output requires a directory" >&2
                            exit 1
                        fi
                        output_dir="$2"
                        shift 2
                        ;;
                    --*)
                        echo "Error: Unknown option: $1" >&2
                        exit 1
                        ;;
                    *)
                        # Positional argument (research question)
                        research_question="$1"
                        shift
                        ;;
                esac
            done
            
            if [[ -z "$mission_name" ]]; then
                echo "Error: --mission required" >&2
                exit 1
            fi
            
            cmd_run "$mission_name" "$input_dir" "$research_question" "$non_interactive" "$output_dir"
            ;;
            
        missions)
            local subcommand="${1:-list}"
            shift || true
            
            case "$subcommand" in
                list)
                    cmd_missions_list
                    ;;
                describe)
                    cmd_missions_describe "$@"
                    ;;
                *)
                    echo "Error: Unknown missions subcommand: $subcommand" >&2
                    exit 1
                    ;;
            esac
            ;;
            
        agents)
            local subcommand="${1:-list}"
            shift || true
            
            case "$subcommand" in
                list)
                    cmd_agents_list
                    ;;
                describe)
                    cmd_agents_describe "$@"
                    ;;
                *)
                    echo "Error: Unknown agents subcommand: $subcommand" >&2
                    exit 1
                    ;;
            esac
            ;;
            
        dry-run|preflight)
            # Parse dry-run options
            local mission_name=""
            local input_dir=""
            
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --mission)
                        mission_name="$2"
                        shift 2
                        ;;
                    --input-dir)
                        input_dir="$2"
                        shift 2
                        ;;
                    *)
                        echo "Error: Unknown option: $1" >&2
                        exit 1
                        ;;
                esac
            done
            
            if [[ -z "$mission_name" ]]; then
                echo "Error: --mission required" >&2
                exit 1
            fi
            
            cmd_dry_run "$mission_name" "$input_dir"
            ;;
        
        resume)
            # Parse resume options
            local session_path=""
            local refinement=""
            local extend_iterations=""
            local extend_time=""
            
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --session)
                        session_path="$2"
                        shift 2
                        ;;
                    --extend-iterations)
                        extend_iterations="$2"
                        # Validate it's a positive integer
                        if ! [[ "$extend_iterations" =~ ^[0-9]+$ ]] || [[ "$extend_iterations" -eq 0 ]]; then
                            echo "Error: --extend-iterations must be a positive integer" >&2
                            exit 1
                        fi
                        shift 2
                        ;;
                    --extend-time)
                        extend_time="$2"
                        # Validate it's a positive integer (minutes)
                        if ! [[ "$extend_time" =~ ^[0-9]+$ ]] || [[ "$extend_time" -eq 0 ]]; then
                            echo "Error: --extend-time must be a positive integer (minutes)" >&2
                            exit 1
                        fi
                        shift 2
                        ;;
                    --refine)
                        refinement="$2"
                        shift 2
                        ;;
                    --refine-file)
                        if [ ! -f "$2" ]; then
                            echo "Error: Refinement file not found: $2" >&2
                            exit 1
                        fi
                        refinement=$(cat "$2")
                        shift 2
                        ;;
                    *)
                        echo "Error: Unknown option: $1" >&2
                        exit 1
                        ;;
                esac
            done
            
            if [[ -z "$session_path" ]]; then
                echo "Error: --session required" >&2
                exit 1
            fi
            
            cmd_resume "$session_path" "$refinement" "$extend_iterations" "$extend_time"
            ;;
            
        help|--help|-h)
            usage
            ;;
            
        *)
            echo "Error: Unknown command: $command" >&2
            echo "" >&2
            usage
            exit 1
            ;;
    esac
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
