#!/usr/bin/env bash
# Adaptive Research Orchestrator
# Main control loop for adaptive research system

set -euo pipefail

# Save script directory before sourcing other files (which redefine SCRIPT_DIR)
CCONDUCTOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$CCONDUCTOR_SCRIPT_DIR")"

# Load debug utility first
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/debug.sh"
setup_error_trap

debug "Starting cconductor-adaptive.sh"
debug "CCONDUCTOR_SCRIPT_DIR=$CCONDUCTOR_SCRIPT_DIR"
debug "PROJECT_ROOT=$PROJECT_ROOT"

# Use CCONDUCTOR_SCRIPT_DIR for sourcing to avoid conflicts
# (sourced files may redefine SCRIPT_DIR for their own use)
debug "Sourcing knowledge-graph.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/knowledge-graph.sh"
debug "knowledge-graph.sh sourced successfully"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/task-queue.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/shared-state.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/gap-analyzer.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/contradiction-detector.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/lead-evaluator.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/confidence-scorer.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/config-loader.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/session-manager.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/event-logger.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/dashboard-metrics.sh"
# shellcheck disable=SC1091
source "$CCONDUCTOR_SCRIPT_DIR/utils/setup-hooks.sh"

# Load configuration using overlay pattern
# This automatically merges user config over defaults
debug "Loading adaptive-config"
if ! ADAPTIVE_CONFIG=$(load_config "adaptive-config"); then
    echo "❌ Error: Failed to load adaptive configuration" >&2
    echo "" >&2
    echo "To create a custom configuration:" >&2
    echo "  $CCONDUCTOR_SCRIPT_DIR/utils/config-loader.sh init adaptive-config" >&2
    echo "  vim ~/.config/cconductor/adaptive-config.json" >&2
    echo "" >&2
    exit 1
fi

# Load cconductor configuration (for agent settings)
if ! CCONDUCTOR_CONFIG=$(load_config "cconductor-config"); then
    echo "❌ Error: Failed to load cconductor configuration" >&2
    exit 1
fi

# Validate required fields exist and have correct types
# Using literal jq paths (not variables) because jq doesn't interpret dots in variables as path separators
# Note: Don't use 'jq -e' because it exits 1 for false/null values (by design)
validate_field_exists() {
    local field_desc="$1"
    local jq_expr="$2"
    
    local value
    value=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr" 2>/dev/null)
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "❌ Error: Required config field missing or null: $field_desc" >&2
        return 1
    fi
    return 0
}

validate_field_type() {
    local field_desc="$1"
    local jq_expr="$2"
    local expected_type="$3"
    
    local actual_type
    actual_type=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr | type" 2>/dev/null)
    if [ "$actual_type" != "$expected_type" ]; then
        local value
        value=$(echo "$ADAPTIVE_CONFIG" | jq -r "$jq_expr" 2>/dev/null)
        echo "❌ Error: Config field $field_desc has wrong type" >&2
        echo "   Expected: $expected_type, got: $actual_type (value: $value)" >&2
        return 1
    fi
    return 0
}

# Validate each required field with literal jq expressions
validate_field_exists "termination.max_iterations" ".termination.max_iterations" || exit 1
validate_field_type "termination.max_iterations" ".termination.max_iterations" "number" || exit 1

validate_field_exists "termination.confidence_threshold" ".termination.confidence_threshold" || exit 1
validate_field_type "termination.confidence_threshold" ".termination.confidence_threshold" "number" || exit 1

validate_field_exists "termination.max_tasks" ".termination.max_tasks" || exit 1
validate_field_type "termination.max_tasks" ".termination.max_tasks" "number" || exit 1

validate_field_exists "termination.interactive_mode" ".termination.interactive_mode" || exit 1
validate_field_type "termination.interactive_mode" ".termination.interactive_mode" "boolean" || exit 1

validate_field_exists "task_generation.exploration_mode" ".task_generation.exploration_mode" || exit 1
validate_field_type "task_generation.exploration_mode" ".task_generation.exploration_mode" "string" || exit 1

validate_field_exists "task_generation.min_gap_priority" ".task_generation.min_gap_priority" || exit 1
validate_field_type "task_generation.min_gap_priority" ".task_generation.min_gap_priority" "number" || exit 1

validate_field_exists "task_generation.min_lead_priority" ".task_generation.min_lead_priority" || exit 1
validate_field_type "task_generation.min_lead_priority" ".task_generation.min_lead_priority" "number" || exit 1

# Extract config values
MAX_ITERATIONS=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.max_iterations')
CONFIDENCE_THRESHOLD=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.confidence_threshold')
INTERACTIVE_MODE=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.interactive_mode')
EXPLORATION_MODE=$(echo "$ADAPTIVE_CONFIG" | jq -r '.task_generation.exploration_mode')

# Validate value ranges
if [ "$MAX_ITERATIONS" -lt 1 ] || [ "$MAX_ITERATIONS" -gt 100 ]; then
    echo "❌ Error: max_iterations must be between 1 and 100 (got: $MAX_ITERATIONS)" >&2
    exit 1
fi

# awk: exit 0 (success) if valid, exit 1 (failure) if invalid
# Check if threshold is OUT of range (< 0 or > 1)
if awk -v thresh="$CONFIDENCE_THRESHOLD" 'BEGIN { if (thresh < 0 || thresh > 1) exit 1; exit 0 }'; then
    : # Valid - do nothing
else
    echo "❌ Error: confidence_threshold must be between 0 and 1 (got: $CONFIDENCE_THRESHOLD)" >&2
    exit 1
fi

if [[ ! "$EXPLORATION_MODE" =~ ^(conservative|balanced|aggressive)$ ]]; then
    echo "❌ Error: exploration_mode must be one of: conservative, balanced, aggressive (got: $EXPLORATION_MODE)" >&2
    exit 1
fi

# Print banner
print_banner() {
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║             CCONDUCTOR - ADAPTIVE RESEARCH ENGINE              ║"
    echo "║  Intelligent, self-improving research with dynamic goals  ║"
    echo "║                  Powered by Claude Code                   ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""
}

# Initialize session
initialize_session() {
    local research_question="$1"

    # Create session directory with unique timestamp to prevent collisions
    local timestamp
    # Check if we can get subsecond precision (GNU date with %N)
    if date +%s%N &>/dev/null 2>&1 && [[ "$(date +%s%N)" =~ ^[0-9]+$ ]]; then
        # GNU date (Linux) - use nanoseconds
        timestamp=$(date +%s%N)
    else
        # macOS or other - use seconds + PID + random
        timestamp="$(date +%s)_$$_${RANDOM}"
    fi
    local session_dir="$PROJECT_ROOT/research-sessions/session_${timestamp}"
    mkdir -p "$session_dir"
    mkdir -p "$session_dir/raw"
    mkdir -p "$session_dir/intermediate"
    mkdir -p "$session_dir/knowledge"
    
    # Copy Claude runtime context to session
    if [ -d "$PROJECT_ROOT/src/claude-runtime" ]; then
        cp -r "$PROJECT_ROOT/src/claude-runtime" "$session_dir/.claude"
        
        # Build agent JSON files from source (metadata.json + system-prompt.md)
        # Pass session_dir for knowledge injection (session > custom > core priority)
        echo "→ Building agents from source..." >&2
        bash "$PROJECT_ROOT/src/utils/build-agents.sh" "$session_dir/.claude/agents" "$session_dir" >&2 || {
            echo "Error: Failed to build agents" >&2
            exit 1
        }
        
        # Rename settings.json to settings.local.json for Claude Code
        if [ -f "$session_dir/.claude/settings.json" ]; then
            mv "$session_dir/.claude/settings.json" "$session_dir/.claude/settings.local.json"
        fi
        
        # Copy MCP configuration to session root (local scope)
        # Claude Code looks for .mcp.json in the working directory
        if [ -f "$PROJECT_ROOT/src/claude-runtime/mcp.json" ]; then
            cp "$PROJECT_ROOT/src/claude-runtime/mcp.json" "$session_dir/.mcp.json"
        fi
        
        # Make hooks executable
        chmod +x "$session_dir/.claude/hooks/"*.sh 2>/dev/null || true
    else
        echo "Error: Claude runtime template not found at $PROJECT_ROOT/src/claude-runtime" >&2
        exit 1
    fi
    
    # Phase 2.5: Set up tool observability hooks  
    # Project-level hooks work in print mode (contrary to initial testing)
    # Each session gets its own .claude/settings.json with hooks configured
    setup_tool_hooks "$session_dir" || echo "Warning: Failed to setup tool hooks" >&2

    # Source version checker
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_SCRIPT_DIR/utils/version-check.sh"

    # Get system version
    local system_version
    system_version=$(get_engine_version)

    # Capture config snapshot
    local exploration_mode
    exploration_mode=$(echo "$ADAPTIVE_CONFIG" | jq -r '.task_generation.exploration_mode // "balanced"')
    local security_profile
    security_profile=$(get_config_value "security-config" ".security_profile" "\"strict\"" | tr -d '"')

    # Create session metadata with version tracking
    jq -n \
        --arg version "$system_version" \
        --arg session "session_${timestamp}" \
        --arg question "$research_question" \
        --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg mode "$exploration_mode" \
        --arg profile "$security_profile" \
        '{
            session_id: $session,
            engine_version: $version,
            created_at: $date,
            last_opened: $date,
            research_question: $question,
            schemas: {
                knowledge_graph: "1.0",
                task_queue: "1.0",
                citations: "1.0"
            },
            status: "active",
            config_snapshot: {
                exploration_mode: $mode,
                security_profile: $profile
            }
        }' > "$session_dir/session.json"

    # Phase 2: Initialize event logging
    init_events "$session_dir"
    # Properly construct JSON for event data (handles multi-line questions)
    local event_data
    event_data=$(jq -n --arg q "$research_question" '{question: $q}')
    log_event "$session_dir" "session_created" "$event_data"
    
    # Phase 2: Generate dashboard
    bash "$CCONDUCTOR_SCRIPT_DIR/utils/dashboard-generator.sh" "$session_dir" >/dev/null 2>&1 || true

    echo "$session_dir"
}

# Initial planning phase
initial_planning() {
    local session_dir="$1"
    local research_question="$2"

    # All progress messages to stderr to avoid polluting JSON output
    echo "=== Phase 0: Initial Planning ===" >&2
    echo "Research Question: $research_question" >&2
    echo "" >&2

    # Invoke research planner with explicit instructions for automated mode
    echo "⚡ Invoking research-planner agent..." >&2
    local planning_output="$session_dir/raw/planning-output.json"
    
    # Create input file for invoke-v2 with structured JSON input
    local planning_input="$session_dir/intermediate/planning-input.txt"
    jq -n \
        --arg question "$research_question" \
        --arg mode "automated" \
        '{
            research_question: $question,
            mode: $mode,
            instruction: "Return ONLY valid JSON with initial_tasks array. Each task must have: type (research), agent (web-researcher/code-analyzer/academic-researcher/market-analyzer), priority (1-10), query (specific search query). NO explanatory text, just the JSON object starting with {."
        }' | jq -r 'to_entries | map("\(.key): \(.value)") | join("\n")' > "$planning_input"
    
    # Use invoke-v2 with systemPrompt injection and clean JSON output
    if ! bash "$CCONDUCTOR_SCRIPT_DIR/utils/invoke-agent.sh" invoke-v2 \
        "research-planner" \
        "$planning_input" \
        "$planning_output" \
        600 \
        "$session_dir"; then
        echo "Error: Research planner failed" >&2
        return 1
    fi
    
    # No extract-json needed - v2 returns clean JSON directly

    if [ ! -f "$planning_output" ]; then
        echo "Error: Planning output not found" >&2
        return 1
    fi

    # Extract initial tasks (Phase 0: data is in .result as JSON string)
    local initial_tasks
    # First extract .result (which contains JSON as a string), then parse it
    local result_json
    result_json=$(cat "$planning_output" | jq -r '.result // empty')
    
    if [ -z "$result_json" ]; then
        echo "Error: No result field in planning output" >&2
        echo "Raw output:" >&2
        cat "$planning_output" | jq '.' >&2
        return 1
    fi
    
    # Strip markdown code fences if present (```json ... ```)
    # shellcheck disable=SC2016  # Single quotes intentional for sed pattern
    result_json=$(echo "$result_json" | sed '/^```json$/d; /^```$/d')
    
    # Parse the JSON string and extract initial_tasks
    # Also add missing 'type' field if not present (use task_type or default to 'research')
    initial_tasks=$(echo "$result_json" | jq '[(.initial_tasks // .tasks // [])[] | 
        if has("type") then . 
        else . + {type: (.task_type // "research")} 
        end]')
    
    # Validate that result is an array
    if ! echo "$initial_tasks" | jq -e 'type == "array"' >/dev/null 2>&1; then
        echo "Error: Planning output is not a valid array" >&2
        echo "Received: ${initial_tasks:0:200}..." >&2
        echo "Full result:" >&2
        echo "$result_json" | jq '.' >&2
        return 1
    fi
    
    echo "$initial_tasks"
}

# Execute pending tasks (parallel)
execute_pending_tasks() {
    local session_dir="$1"

    local pending
    pending=$(tq_get_pending "$session_dir")
    local pending_count
    pending_count=$(echo "$pending" | jq 'length')

    if [ "$pending_count" -eq 0 ]; then
        echo "No pending tasks"
        return 0
    fi

    echo "Executing $pending_count pending tasks..."

    # Get tasks by agent type
    local agents
    agents=$(echo "$pending" | jq -r '.[].agent' | sort -u)
    
    # Check if parallel execution is enabled
    local parallel_enabled
    parallel_enabled=$(echo "$CCONDUCTOR_CONFIG" | jq -r '.agents.parallel_execution // false')
    local max_parallel
    max_parallel=$(echo "$CCONDUCTOR_CONFIG" | jq -r '.agents.max_parallel_agents // 4')
    
    if [ "$parallel_enabled" = "true" ]; then
        echo "  → Parallel execution enabled (max $max_parallel concurrent agents)"
    fi

    # Arrays to track background jobs
    declare -a agent_pids=()
    declare -a agent_names=()
    local active_jobs=0

    # Execute each agent's tasks
    while IFS= read -r agent; do
        local agent_tasks
        agent_tasks=$(echo "$pending" | jq -c --arg agent "$agent" '[.[] | select(.agent == $agent)]')
        local task_count
        task_count=$(echo "$agent_tasks" | jq 'length')

        if [ "$task_count" -eq 0 ]; then
            continue
        fi

        echo "  → $agent: $task_count tasks"

        # Mark tasks as in progress
        echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
            tq_start_task "$session_dir" "$task_id"
        done

        # Create agent input
        local agent_input="$session_dir/raw/${agent}-input.json"
        echo "$agent_tasks" > "$agent_input"

        # Function to execute agent (can be run in background)
        execute_single_agent() {
            local agent_name="$1"
            local input_file="$2"
            local output_file="$3"
            local sess_dir="$4"  # Add session_dir parameter
            
            # Invoke agent using v2 (systemPrompt + tool restrictions + clean JSON)
            if bash "$CCONDUCTOR_SCRIPT_DIR/utils/invoke-agent.sh" invoke-v2 \
                "$agent_name" \
                "$input_file" \
                "$output_file" \
                900 \
                "$sess_dir"; then  # Pass session directory
                return 0
            else
                echo "Error: Agent $agent_name failed" >&2
                return 1
            fi
        }
        
        export -f execute_single_agent
        export CCONDUCTOR_SCRIPT_DIR

        # Invoke agent (parallel or sequential)
        local agent_output="$session_dir/raw/${agent}-output.json"
        
        if [ "$parallel_enabled" = "true" ]; then
            # Wait if we've hit the parallel limit
            while [ "$active_jobs" -ge "$max_parallel" ]; do
                # Check if any jobs have completed
                local new_active=0
                for i in "${!agent_pids[@]}"; do
                    if kill -0 "${agent_pids[$i]}" 2>/dev/null; then
                        new_active=$((new_active + 1))
                    fi
                done
                active_jobs=$new_active
                
                if [ "$active_jobs" -ge "$max_parallel" ]; then
                    sleep 1
                fi
            done
            
            # Execute in background
            execute_single_agent "$agent" "$agent_input" "$agent_output" "$session_dir" &
            local pid=$!
            agent_pids+=("$pid")
            agent_names+=("$agent")
            active_jobs=$((active_jobs + 1))
            echo "    Started $agent (PID $pid)"
        else
            # Execute sequentially
            if ! execute_single_agent "$agent" "$agent_input" "$agent_output" "$session_dir"; then
                echo "Warning: Agent $agent failed, marking tasks as failed..." >&2
                # Mark agent's tasks as failed
                echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
                    tq_fail_task "$session_dir" "$task_id" "Agent $agent failed to execute"
                done
            fi
        fi

    done <<< "$agents"
    
    # Wait for all background jobs to complete
    if [ "$parallel_enabled" = "true" ] && [ "${#agent_pids[@]}" -gt 0 ]; then
        echo ""
        echo "  → Waiting for ${#agent_pids[@]} agents to complete..."
        
        local failed_agents=()
        for i in "${!agent_pids[@]}"; do
            local pid="${agent_pids[$i]}"
            local agent_name="${agent_names[$i]}"
            
            if wait "$pid"; then
                echo "    ✓ $agent_name completed"
            else
                echo "    ✗ $agent_name failed" >&2
                failed_agents+=("$agent_name")
                
                # Mark agent's tasks as failed
                local agent_tasks
                agent_tasks=$(echo "$pending" | jq -c --arg agent "$agent_name" '[.[] | select(.agent == $agent)]')
                echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
                    tq_fail_task "$session_dir" "$task_id" "Agent $agent_name failed during parallel execution"
                done
            fi
        done
        
        if [ "${#failed_agents[@]}" -gt 0 ]; then
            echo "Error: ${#failed_agents[@]} agent(s) failed: ${failed_agents[*]}" >&2
            
            # Check if any are critical agents (required for research)
            local critical_failed=()
            for agent in "${failed_agents[@]}"; do
                if [[ "$agent" =~ ^(web-researcher|academic-researcher)$ ]]; then
                    critical_failed+=("$agent")
                fi
            done
            
            if [ "${#critical_failed[@]}" -gt 0 ]; then
                echo "Critical agents failed: ${critical_failed[*]}" >&2
                echo "Aborting iteration due to critical agent failure" >&2
                log_event "$session_dir" "system_observation" \
                    "{\"severity\": \"critical\", \"component\": \"agents\", \"observation\": \"Critical agents failed (${critical_failed[*]})\", \"iteration\": $iteration}"
                return 1
            fi
            
            echo "Warning: Non-critical agents failed, continuing with partial results" >&2
            
            # Log warning for multiple failures
            if [ "${#failed_agents[@]}" -ge 2 ]; then
                log_event "$session_dir" "system_observation" \
                    "{\"severity\": \"warning\", \"component\": \"agents\", \"observation\": \"Multiple agents failed (${#failed_agents[@]})\", \"agents\": [\"${failed_agents[*]}\"]}"
            fi
        fi
    fi
    
    # Mark tasks as completed (post-processing)
    while IFS= read -r agent; do
        local agent_tasks
        agent_tasks=$(echo "$pending" | jq -c --arg agent "$agent" '[.[] | select(.agent == $agent)]')
        
        echo "$agent_tasks" | jq -r '.[].id' | while read -r task_id; do
            local findings_file="$session_dir/raw/${agent}-${task_id}-findings.json"
            local agent_output="$session_dir/raw/${agent}-output.json"
            
            # Check if either findings file or agent output exists
            if [ ! -f "$findings_file" ] && [ ! -f "$agent_output" ]; then
                echo "Error: No output file for task $task_id, marking as FAILED" >&2
                tq_fail_task "$session_dir" "$task_id" "No output file generated by agent"
                continue  # Skip marking as complete
            fi
            
            # If we reach here, we have output - mark as complete
            if [ -f "$findings_file" ]; then
                tq_complete_task "$session_dir" "$task_id" "$findings_file"
            else
                tq_complete_task "$session_dir" "$task_id" "$agent_output"
            fi
        done
    done <<< "$agents"
}

# Build input files context for coordinator
build_input_files_context() {
    local session_dir="$1"
    local manifest="$session_dir/input-files.json"
    
    # Check if manifest exists
    if [ ! -f "$manifest" ]; then
        echo ""
        return 0
    fi
    
    local context="📁 USER-PROVIDED INPUT FILES (PRIORITY ANALYSIS):

The user has provided the following materials for analysis. 
IMPORTANT: Analyze these materials FIRST before expanding research to web/academic sources.

"
    
    # List PDFs
    local pdf_count
    pdf_count=$(jq '.pdfs | length' "$manifest" 2>/dev/null || echo "0")
    if [ "$pdf_count" -gt 0 ]; then
        context+="PDF Documents ($pdf_count):
"
        while IFS= read -r pdf; do
            local name
            name=$(echo "$pdf" | jq -r '.original_name')
            local path
            path=$(echo "$pdf" | jq -r '.cached_path')
            local size
            size=$(echo "$pdf" | jq -r '.file_size')
            context+="  • $name ($size bytes)
    Path: $path
    [Use Read tool to analyze this PDF]
"
        done < <(jq -c '.pdfs[]' "$manifest" 2>/dev/null || echo '[]')
        context+="
"
    fi
    
    # List markdown/text files
    local md_count
    md_count=$(jq '.markdown | length' "$manifest" 2>/dev/null || echo "0")
    local txt_count
    txt_count=$(jq '.text | length' "$manifest" 2>/dev/null || echo "0")
    local total_text=$((md_count + txt_count))
    
    if [ "$total_text" -gt 0 ]; then
        context+="Context Files ($total_text - already loaded in session knowledge):
"
        
        if [ "$md_count" -gt 0 ]; then
            while IFS= read -r md; do
                local name
                name=$(echo "$md" | jq -r '.original_name')
                local spath
                spath=$(echo "$md" | jq -r '.session_path')
                context+="  • $name (markdown) → $spath
"
            done < <(jq -c '.markdown[]' "$manifest" 2>/dev/null || echo '[]')
        fi
        
        if [ "$txt_count" -gt 0 ]; then
            while IFS= read -r txt; do
                local name
                name=$(echo "$txt" | jq -r '.original_name')
                local spath
                spath=$(echo "$txt" | jq -r '.session_path')
                context+="  • $name (text) → $spath
"
            done < <(jq -c '.text[]' "$manifest" 2>/dev/null || echo '[]')
        fi
        context+="
"
    fi
    
    context+="RESEARCH STRATEGY:
1. Analyze all user-provided materials FIRST
2. Extract key concepts, claims, and data points
3. Identify questions that need validation or expansion
4. THEN use web/academic sources to:
   - Validate claims in user materials
   - Fill knowledge gaps
   - Provide additional context
   - Find supporting/contradicting evidence

The user's materials should drive the research direction.
"
    
    echo "$context"
}

# Run coordinator analysis
run_coordinator() {
    local session_dir="$1"
    local iteration="$2"

    echo "" >&2
    echo "=== Iteration $iteration: Coordinator Analysis ===" >&2

    # Increment knowledge graph iteration
    kg_increment_iteration "$session_dir"

    # Prepare coordinator input
    local kg
    kg=$(kg_read "$session_dir")
    local queue
    queue=$(tq_read "$session_dir")
    local completed_tasks
    completed_tasks=$(tq_get_completed "$session_dir")

    # Get NEW findings from tasks completed THIS iteration only (prevent duplicates)
    local iteration_start_file="$session_dir/.iteration-$iteration-start"
    local cutoff_time=""
    if [ -f "$iteration_start_file" ]; then
        cutoff_time=$(cat "$iteration_start_file")
    fi
    
    # Filter completed tasks to only those completed after iteration started
    local new_completed_tasks
    if [ -n "$cutoff_time" ]; then
        new_completed_tasks=$(echo "$completed_tasks" | jq --arg cutoff "$cutoff_time" \
            '[.[] | select(.completed_at >= $cutoff)]')
    else
        # Fallback: if no cutoff time, use all completed tasks (iteration 1)
        new_completed_tasks="$completed_tasks"
    fi
    
    # Count findings for logging (currently unused but kept for future debugging)
    local findings_count
    # shellcheck disable=SC2034
    findings_count=$(echo "$new_completed_tasks" | jq 'length')
    
    # Extract and parse findings from new completions only
    # Deduplicate by findings_file (multiple tasks may share same output file)
    local new_findings='[]'
    local -a seen_files  # Declare as array explicitly
    while IFS= read -r task; do
        local findings_file
        findings_file=$(echo "$task" | jq -r '.findings_file // ""')
        
        # Skip if we've already processed this file
        # shellcheck disable=SC2076  # Literal match is intentional
        if [[ " ${seen_files[*]:-} " =~ " ${findings_file} " ]]; then
            continue
        fi
        seen_files+=("$findings_file")
        
        if [ -n "$findings_file" ] && [ -f "$findings_file" ]; then
            # Read raw agent output (contains .result as string with embedded JSON)
            local raw_finding
            raw_finding=$(cat "$findings_file")
            
            # Extract and parse the JSON from .result field
            local result_text
            result_text=$(echo "$raw_finding" | jq -r '.result // empty')
            
            if [ -n "$result_text" ]; then
                # Strip markdown fences and extract JSON object
                result_text=$(echo "$result_text" | sed -e 's/^```json$//' -e 's/^```$//')
                
                # Extract JSON using awk with proper brace balancing
                local parsed_json
                parsed_json=$(echo "$result_text" | awk '
                    BEGIN { depth=0; started=0 }
                    /{/ && !started { 
                        sub(/^[^{]*/, "")
                        started=1
                    }
                    started {
                        # Count braces on this line
                        open_count = gsub(/{/, "{")
                        close_count = gsub(/}/, "}")
                        
                        print
                        
                        depth += (open_count - close_count)
                        
                        # Exit when we close the root object
                        if (depth == 0) exit
                    }
                ')
                
                # Remove any trailing markdown fences
                parsed_json=$(echo "$parsed_json" | sed '/^```$/d')
                
                # Validate it's valid JSON
                if echo "$parsed_json" | jq '.' >/dev/null 2>&1; then
                    # Check if parsed_json is an array (agent returned multiple findings) or single object
                    if echo "$parsed_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
                        # It's an array of findings - concatenate all findings
                        new_findings=$(echo "$new_findings" | jq --argjson arr "$parsed_json" '. + $arr')
                    else
                        # It's a single finding object - wrap in array and add
                        new_findings=$(echo "$new_findings" | jq --argjson f "$parsed_json" '. += [$f]')
                    fi
                else
                    echo "⚠️  Warning: Could not parse JSON from findings file: $findings_file" >&2
                    echo "  ✗ Skipping invalid finding" >&2
                fi
            else
                echo "⚠️  Warning: No .result field in findings file: $findings_file" >&2
            fi
        fi
    done <<< "$(echo "$new_completed_tasks" | jq -c '.[]')"

    # Build input files context if present
    local input_context
    input_context=$(build_input_files_context "$session_dir")

    local coordinator_input="$session_dir/intermediate/coordinator-input-${iteration}.json"
    jq -n \
        --argjson kg "$kg" \
        --argjson queue "$queue" \
        --argjson findings "$new_findings" \
        --arg iteration "$iteration" \
        --argjson config "$ADAPTIVE_CONFIG" \
        --arg input_context "$input_context" \
        '{
            knowledge_graph: $kg,
            task_queue: $queue,
            new_findings: $findings,
            iteration: ($iteration | tonumber),
            config: $config,
            input_files_context: $input_context
        }' \
        > "$coordinator_input"

    # Invoke coordinator
    local coordinator_output="$session_dir/intermediate/coordinator-output-${iteration}.json"

    # Use session continuity for iterations 2+ (Phase 1)
    if [ "$iteration" = "1" ]; then
        echo "⚡ Starting coordinator session (iteration 1)..." >&2
        # Start session with initial context
        local session_id
        session_id=$(start_agent_session \
            "research-coordinator" \
            "$session_dir" \
            "$(cat "$coordinator_input")" \
            900)
        
        if [ -z "$session_id" ]; then
            echo "Error: Failed to start coordinator session" >&2
            return 1
        fi
        
        # Copy start output to coordinator output
        cp "$session_dir/.agent-sessions/research-coordinator.start-output.json" \
           "$coordinator_output"
    else
        echo "⚡ Continuing coordinator session (iteration $iteration)..." >&2
        # Continue existing session
        if ! continue_agent_session \
            "research-coordinator" \
            "$session_dir" \
            "$(cat "$coordinator_input")" \
            "$coordinator_output" \
            900; then
            echo "Error: Research coordinator failed" >&2
            return 1
        fi
    fi

    if [ ! -f "$coordinator_output" ]; then
        echo "Error: Coordinator output not found" >&2
        return 1
    fi

    cat "$coordinator_output"
}

# Update knowledge graph from coordinator output
update_knowledge_graph() {
    local session_dir="$1"
    local coordinator_cleaned_file="$2"

    echo "Updating knowledge graph..."

    # Track entities before update
    local entities_before
    entities_before=$(kg_read "$session_dir" | jq '.entities | length // 0')

    # Bulk update
    kg_bulk_update "$session_dir" "$coordinator_cleaned_file"

    # Validate update was successful
    local entities_after
    entities_after=$(kg_read "$session_dir" | jq '.entities | length // 0')

    local claims_after
    claims_after=$(kg_read "$session_dir" | jq '.claims | length // 0')

    # Check if coordinator processed findings but KG didn't update
    local coordinator_findings
    coordinator_findings=$(jq '.knowledge_graph_updates.entities_discovered | length // 0' "$coordinator_cleaned_file" 2>/dev/null || echo "0")

    if [ "$entities_before" -eq "$entities_after" ] && [ "$claims_after" -eq "0" ] && [ "$coordinator_findings" -gt 0 ]; then
        echo "🔴 CRITICAL: Coordinator processed $coordinator_findings findings but KG has 0 entities after update" >&2
        log_event "$session_dir" "system_observation" \
            "{\"severity\": \"critical\", \"component\": \"knowledge_graph\", \"observation\": \"Coordinator processed findings but KG update failed\", \"evidence\": {\"findings_count\": $coordinator_findings, \"entities_before\": $entities_before, \"entities_after\": $entities_after}}"
    fi

    echo "  → Knowledge graph: $entities_before → $entities_after entities (+$((entities_after - entities_before))), $claims_after claims"

    # Update confidence
    local confidence
    confidence=$(jq '.knowledge_graph_updates.confidence_scores // null' "$coordinator_cleaned_file")
    if [ "$confidence" != "null" ]; then
        kg_update_confidence "$session_dir" "$confidence"
    fi

    # Update coverage
    local coverage
    coverage=$(jq '.knowledge_graph_updates.coverage // null' "$coordinator_cleaned_file")
    if [ "$coverage" != "null" ]; then
        kg_update_coverage "$session_dir" "$coverage"
    fi
}

# Add new tasks from coordinator
add_coordinator_tasks() {
    local session_dir="$1"
    local coordinator_output_file="$2"

    local new_tasks
    new_tasks=$(cat "$coordinator_output_file" | jq '.new_tasks // []' 2>/dev/null)
    local task_count
    task_count=$(echo "$new_tasks" | jq 'length' 2>/dev/null || echo "0")

    # Ensure task_count is a valid integer
    if ! [[ "$task_count" =~ ^[0-9]+$ ]]; then
        task_count=0
    fi

    if [ "$task_count" -gt 0 ]; then
        echo "Adding $task_count new tasks to queue..."
        tq_add_tasks "$session_dir" "$new_tasks" >/dev/null
    else
        echo "No new tasks generated"
    fi
}

# Check termination
should_terminate() {
    local coordinator_output_file="$1"

    local should_stop
    should_stop=$(cat "$coordinator_output_file" | jq -r '.termination_recommendation // false')
    [ "$should_stop" = "true" ]
}

# Interactive prompt
interactive_prompt() {
    local session_dir="$1"
    local iteration="$2"
    local coordinator_cleaned_file="$3"

    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    local confidence
    confidence=$(echo "$kg_summary" | jq -r '.confidence')
    local entities
    entities=$(echo "$kg_summary" | jq -r '.entities')
    local claims
    claims=$(echo "$kg_summary" | jq -r '.claims')
    local gaps
    gaps=$(echo "$kg_summary" | jq -r '.unresolved_gaps')
    local contradictions
    contradictions=$(echo "$kg_summary" | jq -r '.unresolved_contradictions')
    local pending
    pending=$(tq_get_stats "$session_dir" | jq -r '.pending')

    local recommendations
    recommendations=$(jq -r '.recommendations | join("\n  - ")' "$coordinator_cleaned_file")

    # Use loop instead of recursion to prevent stack overflow
    while true; do
        cat <<EOF

╔════════════════════════════════════════════════════════════╗
║  Iteration $iteration Complete                                      ║
╚════════════════════════════════════════════════════════════╝

Summary:
  - Confidence: ${confidence}
  - Entities: $entities
  - Claims: $claims
  - Unresolved Gaps: $gaps
  - Contradictions: $contradictions
  - Pending Tasks: $pending

Recommendations:
  - $recommendations

Options:
  [c] Continue
  [s] Stop and synthesize now
  [d] Show detailed knowledge graph
  [r] Show recommendations
  [q] Quit

EOF

        read -r -p "Your choice: " choice

        case "$choice" in
            c|C|"")
                return 0  # Continue
                ;;
            s|S)
                return 1  # Stop
                ;;
            d|D)
                echo ""
                kg_read "$session_dir" | jq '.'
                echo ""
                # Loop continues to show menu again
                ;;
            r|R)
                echo ""
                jq -r '.recommendations | join("\n")' "$coordinator_cleaned_file"
                echo ""
                # Loop continues to show menu again
                ;;

            q|Q)
                exit 0
                ;;
            *)
                echo "Invalid option"
                # Loop continues to show menu again
                ;;
        esac
    done
}

# Final synthesis
final_synthesis() {
    local session_dir="$1"

    echo ""
    echo "=== Final Synthesis ==="

    # Clean up coordinator session (Phase 1)
    if has_agent_session "research-coordinator" "$session_dir"; then
        echo "Cleaning up coordinator session..."
        end_agent_session "research-coordinator" "$session_dir" || true
    fi

    local kg
    kg=$(kg_read "$session_dir")
    local synthesis_input="$session_dir/intermediate/synthesis-input.json"
    local synthesis_output="$session_dir/research-report.json"
    
    # Check if KG is empty (no entities, claims, or relationships)
    local entities_count
    entities_count=$(echo "$kg" | jq '.stats.total_entities // 0')
    local claims_count
    claims_count=$(echo "$kg" | jq '.stats.total_claims // 0')
    
    # If KG is empty or nearly empty, include raw agent findings as fallback
    if [ "$entities_count" -lt 5 ] && [ "$claims_count" -lt 5 ]; then
        echo "⚠️  Knowledge graph appears empty, providing raw agent findings to synthesis agent..." >&2
        
        # Collect all raw agent findings
        local raw_findings='[]'
        for findings_file in "$session_dir"/raw/*-output.json; do
            if [ -f "$findings_file" ]; then
                local result_text
                result_text=$(jq -r '.result // empty' "$findings_file" 2>/dev/null)
                
                if [ -n "$result_text" ] && [ "$result_text" != "null" ]; then
                    # Strip markdown fences
                    result_text=$(echo "$result_text" | sed -e 's/^```json$//' -e 's/^```$//')
                    
                    # Extract JSON using awk with proper brace balancing
                    local parsed
                    parsed=$(echo "$result_text" | awk '
                        BEGIN { depth=0; started=0 }
                        /{/ && !started { 
                            sub(/^[^{]*/, "")
                            started=1
                        }
                        started {
                            open_count = gsub(/{/, "{")
                            close_count = gsub(/}/, "}")
                            print
                            depth += (open_count - close_count)
                            if (depth == 0) exit
                        }
                    ' | sed '/^```$/d')
                    
                    # Validate and add to array
                    if echo "$parsed" | jq '.' >/dev/null 2>&1; then
                        raw_findings=$(echo "$raw_findings" | jq --argjson f "$parsed" '. += [$f]' 2>/dev/null) || {
                            echo "  ⚠️  Warning: Could not parse finding from $(basename "$findings_file")" >&2
                        }
                    fi
                fi
            fi
        done
        
        # Combine KG and raw findings (validate before using)
        if echo "$raw_findings" | jq '.' >/dev/null 2>&1 && echo "$kg" | jq '.' >/dev/null 2>&1; then
            jq -n --argjson kg "$kg" --argjson findings "$raw_findings" \
                '{knowledge_graph: $kg, raw_agent_findings: $findings, note: "Knowledge graph is empty - using raw agent findings as fallback"}' \
                > "$synthesis_input" 2>/dev/null || {
                    echo "  ⚠️  Warning: Could not create synthesis input with fallback, using empty KG" >&2
                    echo "$kg" > "$synthesis_input"
                }
        else
            echo "  ⚠️  Warning: Invalid JSON in raw findings or KG, using empty KG only" >&2
            echo "$kg" > "$synthesis_input"
        fi
    else
        # Normal case: KG has data
        echo "$kg" > "$synthesis_input"
    fi

    echo "→ Generating final report..."
    
    # Invoke synthesis agent
    if bash "$CCONDUCTOR_SCRIPT_DIR/utils/invoke-agent.sh" invoke-v2 \
        "synthesis-agent" \
        "$synthesis_input" \
        "$synthesis_output" \
        600 \
        "$session_dir"; then
        
        echo "  ✓ Synthesis complete"
        
        # Extract report content and save as markdown
        if [ -f "$synthesis_output" ]; then
            jq -r '.result // empty' "$synthesis_output" > "$session_dir/research-report.md" 2>/dev/null
            echo ""
            echo "✓ Research complete! Output at: $session_dir/research-report.md"
        else
            echo "⚠️  Warning: Synthesis output not found" >&2
        fi
    else
        echo "✗ Synthesis failed" >&2
    fi
}

# Run a single research iteration
# Returns: 0 to continue, 1 to stop
run_single_iteration() {
    local session_dir="$1"
    local iteration="$2"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  ITERATION $iteration / $MAX_ITERATIONS"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # Update knowledge graph with current iteration number
    local kg_file="$session_dir/knowledge-graph.json"
    local tmp_kg="$session_dir/knowledge-graph.json.tmp"
    jq --arg iter "$iteration" '.iteration = ($iter | tonumber)' "$kg_file" > "$tmp_kg" && mv "$tmp_kg" "$kg_file"

    # Phase 2: Log iteration start
    log_iteration_start "$session_dir" "$iteration"
    
    # Track iteration start time (for filtering new findings later)
    local iteration_start_time
    iteration_start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "$iteration_start_time" > "$session_dir/.iteration-$iteration-start"
    
    # Phase 2: Update metrics immediately after iteration starts
    update_metrics "$session_dir"

    # Show pending tasks count
    local pending
    pending=$(jq '.stats.pending' "$session_dir/task-queue.json" 2>/dev/null || echo "0")
    echo "📋 Tasks: $pending pending"
    echo ""

    # Execute pending tasks
    echo "→ Executing tasks..."
    execute_pending_tasks "$session_dir"
    echo "  ✓ Tasks complete"
    echo ""
    
    # Phase 2: Update metrics after tasks complete
    update_metrics "$session_dir"

    # Run coordinator analysis
    echo "→ Running coordinator analysis..."
    local coordinator_output
    coordinator_output=$(run_coordinator "$session_dir" "$iteration")
    local coordinator_file="$session_dir/intermediate/coordinator-output-${iteration}.json"
    
    # Save coordinator output to file
    echo "$coordinator_output" > "$coordinator_file"
    
    echo "  ✓ Coordinator analysis complete"
    echo ""
    
    # Extract and clean coordinator result (strip markdown fences and text before JSON)
    local coordinator_cleaned="$session_dir/intermediate/coordinator-cleaned-${iteration}.json"
    local raw_result
    # First extract just the JSON line (skip debug headers)
    raw_result=$(grep '^{' "$coordinator_file" | jq -r '.result // empty' 2>/dev/null)
    
    # Check if we got anything
    if [ -z "$raw_result" ] || [ "$raw_result" = "null" ]; then
        echo "⚠️  Warning: No .result field in coordinator output" >&2
        # Try reading the file directly (might be already JSON)
        if jq '.' "$coordinator_file" >/dev/null 2>&1; then
            cp "$coordinator_file" "$coordinator_cleaned"
        else
            echo "  ✗ Coordinator output is not valid JSON" >&2
            echo "Coordinator file contents:" >&2
            head -30 "$coordinator_file" >&2
            return 1
        fi
    else
        # Strip markdown code fences
        raw_result=$(echo "$raw_result" | sed -e 's/^```json$//' -e 's/^```$//')
        
        # Extract JSON object using awk with proper brace balancing
        echo "$raw_result" | awk '
            BEGIN { depth=0; started=0 }
            /{/ && !started { 
                sub(/^[^{]*/, "")
                started=1
            }
            started {
                # Count braces on this line
                open_count = gsub(/{/, "{")
                close_count = gsub(/}/, "}")
                
                print
                
                depth += (open_count - close_count)
                
                # Exit when we close the root object
                if (depth == 0) exit
            }
        ' | sed '/^```$/d' > "$coordinator_cleaned"
        
        # Validate cleaned JSON
        if ! jq '.' "$coordinator_cleaned" >/dev/null 2>&1; then
            echo "⚠️  Warning: Initial JSON extraction failed" >&2
            echo "  ✗ Could not extract valid JSON object" >&2
            echo "Raw result (first 30 lines):" >&2
            echo "$raw_result" | head -30 >&2
            return 1
        fi
    fi
    
    # Phase 2: Update metrics after coordinator
    update_metrics "$session_dir"

    # Phase 2.1: Extract and log system observations
    local observations
    observations=$(jq '.system_observations // []' "$coordinator_cleaned" 2>/dev/null)
    if [ "$observations" != "[]" ] && [ "$observations" != "null" ]; then
        local obs_count
        obs_count=$(echo "$observations" | jq 'length')
        echo "→ Processing $obs_count system observation(s)..."
        
        # Log each observation
        echo "$observations" | jq -c '.[]' | while read -r obs; do
            local severity
            severity=$(echo "$obs" | jq -r '.severity // "info"')
            local component
            component=$(echo "$obs" | jq -r '.component // "unknown"')
            local observation_text
            observation_text=$(echo "$obs" | jq -r '.observation // "No description"')
            
            # Log to events.jsonl
            if command -v log_event &>/dev/null; then
                log_event "$session_dir" "system_observation" "$obs" || true
            fi
            
            # Display with appropriate symbol
            case "$severity" in
                critical)
                    echo "  🔴 CRITICAL [$component]: $observation_text" >&2
                    ;;
                warning)
                    echo "  ⚠️  WARNING [$component]: $observation_text" >&2
                    ;;
                info)
                    echo "  ℹ️  INFO [$component]: $observation_text" >&2
                    ;;
                *)
                    echo "  • [$component]: $observation_text" >&2
                    ;;
            esac
        done
    fi

    # Update knowledge graph with coordinator findings
    echo "→ Updating knowledge graph..."
    update_knowledge_graph "$session_dir" "$coordinator_cleaned"

    # Show knowledge graph statistics
    local kg_file="$session_dir/knowledge-graph.json"
    if [ -f "$kg_file" ]; then
        local claims
        claims=$(jq '.stats.total_claims' "$kg_file" 2>/dev/null || echo "0")
        local entities
        entities=$(jq '.stats.total_entities' "$kg_file" 2>/dev/null || echo "0")
        local citations
        citations=$(jq '.stats.total_citations' "$kg_file" 2>/dev/null || echo "0")
        local confidence
        confidence=$(jq '.confidence_scores.overall' "$kg_file" 2>/dev/null || echo "0")
        local gaps
        gaps=$(jq '.stats.unresolved_gaps' "$kg_file" 2>/dev/null || echo "0")

        echo "  ✓ Knowledge graph updated"
        echo ""
        echo "  Knowledge Graph:"
        echo "    • Claims: $claims"
        echo "    • Entities: $entities"
        echo "    • Citations: $citations"
        echo "    • Confidence: $confidence"
        echo "    • Unresolved gaps: $gaps"
        echo ""
    fi

    # Generate new tasks based on coordinator analysis
    echo "→ Generating new tasks..."
    add_coordinator_tasks "$session_dir" "$coordinator_cleaned"
    local new_pending
    new_pending=$(jq '.stats.pending' "$session_dir/task-queue.json" 2>/dev/null || echo "0")
    echo "  ✓ Generated tasks (now $new_pending pending)"
    echo ""

    # Check termination conditions
    if should_terminate "$coordinator_cleaned"; then
        local reason
        reason=$(jq -r '.termination_reason // "Research appears complete"' "$coordinator_cleaned")
        echo ""
        echo "✓ Research Complete: $reason"
        return 1  # Signal termination
    fi

    # Check if no pending tasks remain
    if ! tq_has_pending "$session_dir"; then
        echo ""
        echo "✓ No pending tasks remaining"
        echo "✓ Research appears complete"
        return 1  # Signal termination
    fi

    # Interactive prompt if enabled
    if [ "$INTERACTIVE_MODE" = "true" ]; then
        if ! interactive_prompt "$session_dir" "$iteration" "$coordinator_cleaned"; then
            echo "User requested stop"
            return 1  # Signal termination
        fi
    fi

    # Show progress estimate
    if [ "$iteration" -lt "$MAX_ITERATIONS" ]; then
        echo "Next: Iteration $((iteration + 1))/$MAX_ITERATIONS"
    fi

    # Phase 2: Log iteration complete and update metrics
    local kg_stats
    kg_stats=$(jq '.stats' "$session_dir/knowledge-graph.json" 2>/dev/null || echo '{}')
    log_iteration_complete "$session_dir" "$iteration" "$kg_stats"
    update_metrics "$session_dir"

    return 0  # Continue iterations
}

# Resume existing session
resume_session() {
    local session_id="$1"
    
    # Try to find session directory
    local session_dir=""
    
    # Check if it's a full path
    if [ -d "$session_id" ]; then
        session_dir="$session_id"
    # Check if it's just the session name
    elif [ -d "$PROJECT_ROOT/research-sessions/$session_id" ]; then
        session_dir="$PROJECT_ROOT/research-sessions/$session_id"
    else
        echo "❌ Error: Session not found: $session_id" >&2
        echo "" >&2
        echo "Available sessions:" >&2
        # shellcheck disable=SC2012
        ls -1t "$PROJECT_ROOT/research-sessions/" 2>/dev/null | head -10 >&2
        echo "" >&2
        echo "Usage: ./cconductor resume <session_id>" >&2
        return 1
    fi
    
    # Validate session structure
    if [ ! -f "$session_dir/session.json" ]; then
        echo "❌ Error: Invalid session (missing session.json): $session_dir" >&2
        return 1
    fi
    
    if [ ! -f "$session_dir/knowledge-graph.json" ]; then
        echo "❌ Error: Invalid session (missing knowledge-graph.json): $session_dir" >&2
        return 1
    fi
    
    if [ ! -f "$session_dir/task-queue.json" ]; then
        echo "❌ Error: Invalid session (missing task-queue.json): $session_dir" >&2
        return 1
    fi
    
    # Verify session compatibility
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_SCRIPT_DIR/utils/version-check.sh"
    if ! validate_session_compatibility "$session_dir" 2>/dev/null; then
        echo "" >&2
        echo "⚠️  Warning: Session may be incompatible with current engine version" >&2
        echo "   You can try to continue, but results may be unexpected." >&2
        echo "" >&2
        read -r -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Update last_opened timestamp
    local tmp_file="$session_dir/session.json.tmp"
    jq --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.last_opened = $date | .status = "resumed"' \
       "$session_dir/session.json" > "$tmp_file"
    mv "$tmp_file" "$session_dir/session.json"
    
    # Update .latest marker
    basename "$session_dir" > "$PROJECT_ROOT/research-sessions/.latest"
    
    echo "$session_dir"
}

# List available sessions
list_sessions() {
    local sessions_dir="$PROJECT_ROOT/research-sessions"
    
    if [ ! -d "$sessions_dir" ]; then
        echo "No sessions found (directory doesn't exist)" >&2
        return 1
    fi
    
    # Find all session directories with valid session.json
    local found_sessions=0
    
    echo "Available research sessions:"
    echo ""
    printf "%-25s %-50s %-20s\n" "SESSION ID" "QUESTION" "STATUS"
    printf "%-25s %-50s %-20s\n" "----------" "--------" "------"
    
    # Use find + sort to handle spaces in paths (common in macOS iCloud Drive)
    # Sort by modification time (newest first)
    while IFS= read -r session_path; do
        if [ -f "$session_path/session.json" ]; then
            local session_id
            session_id=$(basename "$session_path")
            local question
            question=$(jq -r '.research_question // "N/A"' "$session_path/session.json" 2>/dev/null)
            local status
            status=$(jq -r '.status // "unknown"' "$session_path/session.json" 2>/dev/null)
            
            # Truncate question if too long
            if [ ${#question} -gt 47 ]; then
                question="${question:0:44}..."
            fi
            
            printf "%-25s %-50s %-20s\n" "$session_id" "$question" "$status"
            found_sessions=$((found_sessions + 1))
            
            # Limit output
            if [ $found_sessions -ge 10 ]; then
                break
            fi
        fi
    done < <(find "$sessions_dir" -maxdepth 1 -type d -name "session_*" -print0 2>/dev/null | xargs -0 ls -1dt 2>/dev/null)
    
    if [ $found_sessions -eq 0 ]; then
        echo "No sessions found"
        return 1
    fi
    
    echo ""
    echo "To resume: ./cconductor resume <session_id>"
}

# Main adaptive research loop
main() {
    local research_question="$1"

    print_banner

    echo "════════════════════════════════════════════════════════════"
    echo "Starting Research"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "Question: $research_question"
    echo ""

    # Initialize session
    echo "→ Initializing research session..."
    local session_dir
    session_dir=$(initialize_session "$research_question")
    echo "  ✓ Session created: $(basename "$session_dir")"
    echo ""

    # Process input files if --input-dir was provided
    if [ -n "${CCONDUCTOR_INPUT_DIR:-}" ]; then
        echo "→ Processing input files..."
        # shellcheck disable=SC1091
        source "$CCONDUCTOR_SCRIPT_DIR/utils/input-files-manager.sh"
        
        if process_input_directory "$CCONDUCTOR_INPUT_DIR" "$session_dir"; then
            echo "  ✓ Input files processed"
            
            # Store input_dir reference in session metadata
            local temp_session="$session_dir/session.json.tmp"
            jq --arg input_dir "$CCONDUCTOR_INPUT_DIR" \
               '.input_dir = $input_dir' \
               "$session_dir/session.json" > "$temp_session" && \
               mv "$temp_session" "$session_dir/session.json"
        else
            echo "  ⚠  Warning: Failed to process some input files"
        fi
        echo ""
    fi

    # Verify session compatibility (for existing sessions, if resume added later)
    # For new sessions, this validates the metadata was created correctly
    # shellcheck disable=SC1091
    source "$CCONDUCTOR_SCRIPT_DIR/utils/version-check.sh"
    if ! validate_session_compatibility "$session_dir" 2>/dev/null; then
        echo "⚠️  Warning: Session version mismatch (this shouldn't happen for new sessions)"
        echo "   Continuing anyway..."
    fi

    # Initialize knowledge graph and task queue
    echo "→ Setting up knowledge graph and task queue..."
    kg_init "$session_dir" "$research_question" >/dev/null
    tq_init "$session_dir" >/dev/null
    echo "  ✓ Data structures initialized"
    echo ""

    # Initial planning
    echo "→ Creating initial research plan..."
    local initial_tasks
    initial_tasks=$(initial_planning "$session_dir" "$research_question")
    
    # Validate that we got tasks
    local task_count
    task_count=$(echo "$initial_tasks" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$task_count" -eq 0 ]; then
        echo "  ✗ Error: Planning failed to generate any tasks" >&2
        echo "  This could indicate an issue with the research-planner agent." >&2
        echo "" >&2
        echo "  Session saved at: $session_dir" >&2
        echo "  You can try to resume it later with: ./cconductor resume $(basename "$session_dir")" >&2
        exit 1
    fi
    
    tq_add_tasks "$session_dir" "$initial_tasks" >/dev/null
    echo "  ✓ Generated $task_count initial tasks"
    echo ""
    
    # Phase 2: Update metrics after planning
    update_metrics "$session_dir"
    
    # Check if user guidance is enabled - show plan and ask for confirmation
    local allow_guidance
    allow_guidance=$(echo "$ADAPTIVE_CONFIG" | jq -r '.termination.allow_user_guidance // false')
    
    # Override if CCONDUCTOR_NON_INTERACTIVE environment variable is set
    if [ "${CCONDUCTOR_NON_INTERACTIVE:-0}" = "1" ]; then
        allow_guidance="false"
    fi
    
    if [ "$allow_guidance" = "true" ]; then
        echo "════════════════════════════════════════════════════════════"
        echo "Research Plan Review"
        echo "════════════════════════════════════════════════════════════"
        echo ""
        echo "I've created an initial research plan with $task_count tasks:"
        echo ""
        
        # Show the tasks in a readable format (with index + priority)
        echo "$initial_tasks" | jq -r 'to_entries[] | "  [\(.key + 1), P\(.value.priority)] \(.value.agent): \(.value.query)"' | head -10
        
        if [ "$task_count" -gt 10 ]; then
            echo "  ... and $((task_count - 10)) more tasks"
        fi
        
        echo ""
        echo "Does this research approach look correct?"
        echo ""
        echo "Options:"
        echo "  [y] Yes, proceed with research"
        echo "  [n] No, let me refine the question"
        echo "  [s] Show all tasks in detail"
        echo ""
        
        while true; do
            read -r -p "Your choice [y/n/s]: " choice
            
            case "$choice" in
                y|Y|"")
                    echo ""
                    echo "✓ Proceeding with research..."
                    echo ""
                    break
                    ;;
                n|N)
                    echo ""
                    echo "Research cancelled. You can start a new session with a refined question."
                    echo ""
                    echo "Session saved at: $session_dir"
                    echo "You can resume later with: ./cconductor resume $(basename "$session_dir")"
                    exit 0
                    ;;
                s|S)
                    echo ""
                    echo "All planned tasks:"
                    echo ""
                    echo "$initial_tasks" | jq -r 'to_entries[] | "[Task \(.key + 1), Priority \(.value.priority)] \(.value.agent):\n  Query: \(.value.query)\n"'
                    echo ""
                    echo "Options:"
                    echo "  [y] Yes, proceed with research"
                    echo "  [n] No, let me refine the question"
                    echo ""
                    ;;
                *)
                    echo "Invalid choice. Please enter y, n, or s."
                    ;;
            esac
        done
    fi

    # Update .latest marker
    basename "$session_dir" > "$PROJECT_ROOT/research-sessions/.latest"

    echo "════════════════════════════════════════════════════════════"
    echo "Max Iterations: $MAX_ITERATIONS"
    echo "Interactive Mode: $INTERACTIVE_MODE"
    echo "════════════════════════════════════════════════════════════"

    # Main adaptive loop
    local iteration=0
    while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
        iteration=$((iteration + 1))

        # Run single iteration (returns 1 to stop, 0 to continue)
        if ! run_single_iteration "$session_dir" "$iteration"; then
            break
        fi
    done

    # Final synthesis
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Generating Final Report"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    final_synthesis "$session_dir"

    # Finalize research (copy report, update metadata)
    finalize_research "$session_dir" "$research_question"

    # Print summary
    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Research Complete                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Final Statistics:"
    echo "$kg_summary" | jq '.'
    echo ""
    echo "Session: $session_dir"
}

# Resume adaptive research loop
main_resume() {
    local session_id="$1"
    
    print_banner
    
    echo "════════════════════════════════════════════════════════════"
    echo "Resuming Research Session"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Load existing session
    echo "→ Loading session..."
    local session_dir
    if ! session_dir=$(resume_session "$session_id"); then
        exit 1
    fi
    echo "  ✓ Session loaded: $(basename "$session_dir")"
    echo ""
    
    # Load session metadata
    local research_question
    research_question=$(jq -r '.research_question' "$session_dir/session.json")
    local created_at
    created_at=$(jq -r '.created_at' "$session_dir/session.json")
    
    echo "Question: $research_question"
    echo "Originally created: $created_at"
    echo ""
    
    # Show current state
    local kg_summary
    kg_summary=$(kg_get_summary "$session_dir")
    local current_iteration
    current_iteration=$(echo "$kg_summary" | jq -r '.iteration')
    local confidence
    confidence=$(echo "$kg_summary" | jq -r '.confidence')
    local pending_tasks
    pending_tasks=$(jq '.stats.pending' "$session_dir/task-queue.json")
    local completed_tasks
    completed_tasks=$(jq '.stats.completed' "$session_dir/task-queue.json")
    
    echo "Current State:"
    echo "  • Iteration: $current_iteration"
    echo "  • Confidence: $confidence"
    echo "  • Tasks: $completed_tasks completed, $pending_tasks pending"
    echo "  • Entities: $(echo "$kg_summary" | jq -r '.entities')"
    echo "  • Claims: $(echo "$kg_summary" | jq -r '.claims')"
    echo "  • Unresolved gaps: $(echo "$kg_summary" | jq -r '.unresolved_gaps')"
    echo ""
    
    # Check if there are pending tasks
    if [ "$pending_tasks" -eq 0 ]; then
        echo "⚠️  No pending tasks found in session."
        echo ""
        read -r -p "Generate new tasks and continue? [Y/n] " -r
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo ""
            echo "→ Running coordinator to generate new tasks..."
            local next_iteration
            next_iteration=$((current_iteration + 1))
            run_coordinator "$session_dir" "$next_iteration" >/dev/null 2>&1 || true
            local coordinator_file="$session_dir/intermediate/coordinator-output-${next_iteration}.json"
            if [ -f "$coordinator_file" ]; then
                # Extract and clean coordinator result
                local coordinator_cleaned="$session_dir/intermediate/coordinator-cleaned-${next_iteration}.json"
                local raw_result
                # First extract just the JSON line (skip debug headers)
                raw_result=$(grep '^{' "$coordinator_file" | jq -r '.result // empty' 2>/dev/null)
                
                # Strip markdown fences and extract JSON with proper brace balancing
                raw_result=$(echo "$raw_result" | sed -e 's/^```json$//' -e 's/^```$//')
                echo "$raw_result" | awk '
                    BEGIN { depth=0; started=0 }
                    /{/ && !started { 
                        sub(/^[^{]*/, "")
                        started=1
                    }
                    started {
                        open_count = gsub(/{/, "{")
                        close_count = gsub(/}/, "}")
                        print
                        depth += (open_count - close_count)
                        if (depth == 0) exit
                    }
                ' | sed '/^```$/d' > "$coordinator_cleaned"
                
                if jq '.' "$coordinator_cleaned" >/dev/null 2>&1; then
                    add_coordinator_tasks "$session_dir" "$coordinator_cleaned"
                fi
            fi
            pending_tasks=$(jq '.stats.pending' "$session_dir/task-queue.json")
            echo "  ✓ Generated new tasks (now $pending_tasks pending)"
            echo ""
        else
            echo ""
            echo "No new tasks generated. Proceeding to final synthesis..."
            final_synthesis "$session_dir"
            finalize_research "$session_dir" "$research_question"
            return 0
        fi
    fi
    
    echo "════════════════════════════════════════════════════════════"
    echo "Max Iterations: $MAX_ITERATIONS"
    echo "Interactive Mode: $INTERACTIVE_MODE"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    
    # Continue iteration loop from last iteration
    local iteration=$current_iteration
    while [ "$iteration" -lt "$MAX_ITERATIONS" ]; do
        iteration=$((iteration + 1))
        
        # Run single iteration (returns 1 to stop, 0 to continue)
        if ! run_single_iteration "$session_dir" "$iteration"; then
            break
        fi
    done
    
    # Final synthesis
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "Generating Final Report"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    final_synthesis "$session_dir"
    
    # Finalize research (copy report, update metadata)
    finalize_research "$session_dir" "$research_question"
    
    # Print summary
    kg_summary=$(kg_get_summary "$session_dir")
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Research Resumed and Complete                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Final Statistics:"
    echo "$kg_summary" | jq '.'
    echo ""
    echo "Session: $session_dir"
}

# Finalize research session
finalize_research() {
    local session_dir="$1"
    local question="$2"

    local report="$session_dir/research-report.md"

    if [ ! -f "$report" ]; then
        echo "⚠️  Warning: No research report found"

        # Update metadata to reflect completion (even without report)
        if [ -f "$session_dir/session.json" ]; then
            local tmp_file="$session_dir/session.json.tmp"
            jq --arg status "completed_no_report" \
               --arg completed "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
               '.status = $status | .completed_at = $completed' \
               "$session_dir/session.json" > "$tmp_file"
            mv "$tmp_file" "$session_dir/session.json"
        fi

        return 1
    fi

    # Create reports directory
    mkdir -p "$PROJECT_ROOT/reports"

    # Generate filename
    local date
    date=$(date +%Y-%m-%d)
    local slug
    slug=$(echo "$question" | \
        tr '[:upper:]' '[:lower:]' | \
        tr -cs '[:alnum:]' '-' | \
        sed 's/^-*//' | sed 's/-*$//' | \
        cut -c1-40)

    local report_copy="$PROJECT_ROOT/reports/${slug}-${date}.md"

    # Copy report
    cp "$report" "$report_copy"

    # Update metadata to completed
    if [ -f "$session_dir/session.json" ]; then
        local tmp_file="$session_dir/session.json.tmp"
        jq --arg status "completed" \
           --arg completed "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           --arg report "$report_copy" \
           '.status = $status | .completed_at = $completed | .report_path = $report' \
           "$session_dir/session.json" > "$tmp_file"
        mv "$tmp_file" "$session_dir/session.json"
    fi

    # Print completion message
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "✅ Research Complete!"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "📄 Report saved to:"
    echo "   • $report"
    echo "   • $report_copy"
    echo ""
    echo "View with:"
    echo "   cat $report_copy"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "   open $report_copy"
    elif command -v xdg-open &> /dev/null; then
        echo "   xdg-open $report_copy"
    fi
    echo ""
    echo "Resume this session:"
    echo "   ./cconductor resume $(basename "$session_dir")"
    echo ""
}

# CLI
if [ $# -lt 1 ]; then
    echo "Usage:"
    echo "  $0 \"<research question>\"           # Start new research"
    echo "  $0 --resume <session_id>            # Resume existing session"
    echo "  $0 --list                           # List available sessions"
    echo ""
    echo "Examples:"
    echo "  $0 \"How does PostgreSQL implement MVCC?\""
    echo "  $0 --resume session_1234567890"
    echo "  $0 --list"
    exit 1
fi

# Parse command-line arguments
case "${1:-}" in
    --resume)
        if [ $# -lt 2 ]; then
            echo "Error: --resume requires a session ID" >&2
            echo "" >&2
            echo "Usage: $0 --resume <session_id>" >&2
            echo "" >&2
            list_sessions
            exit 1
        fi
        main_resume "$2"
        ;;
    --list)
        list_sessions
        ;;
    *)
        # Regular research question
        main "$1"
        ;;
esac
