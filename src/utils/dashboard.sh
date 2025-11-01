#!/usr/bin/env bash
# Dashboard - Unified dashboard operations
# Consolidates generation, viewing, metrics, and cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# Source shared-state for atomic operations
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-logger.sh" 2>/dev/null || true

dashboard_jq_payload() {
    local session_dir="$1"
    local payload="$2"
    local filter="$3"
    local fallback="${4:-}"
    local context="${5:-payload}"
    local raw="${6:-true}"
    safe_jq_from_json "$payload" "$filter" "$fallback" "$session_dir" "dashboard.${context}" "$raw"
}

dashboard_jq_file() {
    local session_dir="$1"
    local path="$2"
    local filter="$3"
    local fallback="${4:-}"
    local context="${5:-file}"
    local raw="${6:-true}"
    safe_jq_from_file "$path" "$filter" "$fallback" "$session_dir" "dashboard.${context}" "$raw"
}

dashboard_sanitize_number() {
    local raw="${1:-}"
    # strip all whitespace so blank or newline values collapse to empty
    local value="${raw//[[:space:]]/}"
    local fallback="${2:-0}"

    if [[ -z "$value" || "$value" == "null" ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    if [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

dashboard_ensure_json() {
    local value="${1:-}"
    local fallback="${2:-null}"

    if [[ -z "$value" ]]; then
        printf '%s' "$fallback"
        return 0
    fi

    if jq_validate_json "$value"; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

# ============================================================================
# SECTION 1: Metrics Generation (from dashboard-metrics.sh)
# ============================================================================

# Generate dashboard metrics
dashboard_generate_metrics() {
    local session_dir="$1"
    local metrics_file="$session_dir/viewer/dashboard-metrics.json"
    local events_file="$session_dir/logs/events.jsonl"
    
    # Read current state from files with locking to prevent partial reads
    local kg
    if [ -f "$session_dir/knowledge/knowledge-graph.json" ]; then
        kg=$(atomic_read "$session_dir/knowledge/knowledge-graph.json" 2>/dev/null || echo '{}')
    else
        kg='{}'
    fi
    
    local session
    if [ -f "$session_dir/meta/session.json" ]; then
        session=$(atomic_read "$session_dir/meta/session.json" 2>/dev/null || echo '{}')
    else
        session='{}'
    fi

    local events_payload='[]'
    local events_available=0
    if [ -f "$events_file" ] && [ -s "$events_file" ]; then
        events_payload=$(json_slurp_array "$events_file" '[]')
        events_available=1
    fi
    
    # Extract stats
    local iteration
    iteration=$(dashboard_jq_payload "$session_dir" "$kg" '.iteration // 0' "0" "kg.iteration")
    local confidence
    confidence=$(dashboard_jq_payload "$session_dir" "$kg" '.confidence_scores.overall // 0' "0" "kg.confidence")
    iteration=$(dashboard_sanitize_number "$iteration")
    confidence=$(dashboard_sanitize_number "$confidence")
    
    # NEW: Get agent invocation stats from events (v0.2.0 mission system)
    local total_invocations=0
    if [[ $events_available -eq 1 ]]; then
        total_invocations=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "agent_invocation")) | length' "0" "events.total_invocations" "false")
    fi
    total_invocations=$(dashboard_sanitize_number "$total_invocations")

    local completed_invocations=0
    if [[ $events_available -eq 1 ]]; then
        completed_invocations=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "agent_result")) | length' "0" "events.completed_invocations" "false")
    fi
    completed_invocations=$(dashboard_sanitize_number "$completed_invocations")

    local in_progress
    in_progress=$((total_invocations - completed_invocations))
    in_progress=$(dashboard_sanitize_number "$in_progress")

    local failed=0
    if [[ $events_available -eq 1 ]]; then
        failed=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "agent_result" and ((.data.status // "") == "failed"))) | length' "0" "events.failed_invocations" "false")
    fi
    failed=$(dashboard_sanitize_number "$failed")

    local preflight_heuristics=0
    local preflight_prompt=0
    local preflight_stakeholders=0
    if [[ $events_available -eq 1 ]]; then
        preflight_heuristics=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "agent_result" and .data.agent == "domain-heuristics")) | length' "0" "events.preflight_heuristics" "false")
        preflight_prompt=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "agent_result" and .data.agent == "prompt-parser")) | length' "0" "events.preflight_prompt" "false")
        preflight_stakeholders=$(dashboard_jq_payload "$session_dir" "$events_payload" 'map(select(.type == "stakeholder_classifier_completed")) | length' "0" "events.preflight_stakeholders" "false")
    fi
    preflight_heuristics=$(dashboard_sanitize_number "$preflight_heuristics")
    preflight_prompt=$(dashboard_sanitize_number "$preflight_prompt")
    preflight_stakeholders=$(dashboard_sanitize_number "$preflight_stakeholders")

    local preflight_json
    preflight_json=$(jq -n \
        --argjson heuristics "$preflight_heuristics" \
        --argjson prompt "$preflight_prompt" \
        --argjson stakeholders "$preflight_stakeholders" \
        '{domain_heuristics_runs: $heuristics, prompt_parser_runs: $prompt, stakeholder_classifications: $stakeholders}') || preflight_json='{}'

    local contract_metrics_json='{"evaluations":0,"passed":0,"failed":0,"avg_duration_ms":0,"total_missing_slots":0,"latest_missing_slots":[]}'
    if [[ $events_available -eq 1 ]]; then
        local contract_metrics_filter
        contract_metrics_filter=$(cat <<'JQ'
            (map(select(.type == "agent_result" and (.data.artifact_contract // null) != null))) as $events |
            if ($events | length) == 0 then
                {evaluations:0, passed:0, failed:0, avg_duration_ms:0, total_missing_slots:0, latest_missing_slots:[]}
            else
                {
                    evaluations: ($events | length),
                    passed: ($events | map(select(.data.artifact_contract.pass == true)) | length),
                    failed: ($events | map(select(.data.artifact_contract.pass == false)) | length),
                    avg_duration_ms: (($events | map((.data.artifact_contract.validation_duration_ms // 0)) | add) / ($events | length)),
                    total_missing_slots: ($events | map((.data.artifact_contract.missing_slots // []) | length) | add),
                    latest_missing_slots: ($events[-1].data.artifact_contract.missing_slots // [])
                }
            end
JQ
)
        contract_metrics_json=$(dashboard_jq_payload "$session_dir" "$events_payload" "$contract_metrics_filter" '{}' "events.contract_metrics" "false")
    fi
    contract_metrics_json=$(dashboard_ensure_json "$contract_metrics_json" '{"evaluations":0,"passed":0,"failed":0,"avg_duration_ms":0,"total_missing_slots":0,"latest_missing_slots":[]}')
    
    local entities
    entities=$(dashboard_jq_payload "$session_dir" "$kg" '.stats.total_entities // 0' "0" "kg.entities")
    local claims
    claims=$(dashboard_jq_payload "$session_dir" "$kg" '.stats.total_claims // 0' "0" "kg.claims")
    local citations
    citations=$(dashboard_jq_payload "$session_dir" "$kg" '.stats.total_citations // 0' "0" "kg.citations")
    local gaps
    gaps=$(dashboard_jq_payload "$session_dir" "$kg" '.stats.unresolved_gaps // 0' "0" "kg.unresolved_gaps")
    local contradictions
    contradictions=$(dashboard_jq_payload "$session_dir" "$kg" '.stats.unresolved_contradictions // 0' "0" "kg.unresolved_contradictions")
    entities=$(dashboard_sanitize_number "$entities")
    claims=$(dashboard_sanitize_number "$claims")
    citations=$(dashboard_sanitize_number "$citations")
    gaps=$(dashboard_sanitize_number "$gaps")
    contradictions=$(dashboard_sanitize_number "$contradictions")
    
    # Calculate costs from events
    local total_cost
    total_cost=$(calculate_total_cost "$session_dir")
    total_cost=$(dashboard_sanitize_number "$total_cost")
    
    # Calculate duration
    local created_at
    created_at=$(dashboard_jq_payload "$session_dir" "$session" '.created_at // ""' "" "session.created_at")
    local elapsed_seconds
    elapsed_seconds=$(calculate_elapsed_seconds "$created_at")
    elapsed_seconds=$(dashboard_sanitize_number "$elapsed_seconds")
    
    # Extract session info
    local session_status
    session_status=$(dashboard_jq_payload "$session_dir" "$session" '.status // "unknown"' "unknown" "session.status")
    local completed_at
    completed_at=$(dashboard_jq_payload "$session_dir" "$session" '.completed_at // ""' "" "session.completed_at")
    local research_question
    research_question=$(dashboard_jq_payload "$session_dir" "$session" '.research_question // ""' "" "session.research_question")

    local quality_gate
    quality_gate=$(dashboard_jq_payload "$session_dir" "$session" '.quality_gate // null' 'null' "session.quality_gate" "false")
    quality_gate=$(dashboard_ensure_json "$quality_gate" "null")
    
    # NEW: Get active agents from recent orchestration decisions (v0.2.0)
    local active_agents='[]'
    if [ -f "$session_dir/logs/orchestration.jsonl" ]; then
        local orchestration_tail
        orchestration_tail=$(tail -20 "$session_dir/logs/orchestration.jsonl" 2>/dev/null || echo '')
        if [[ -n "$orchestration_tail" ]]; then
            local orchestration_json
            local orchestration_tmp
            orchestration_tmp=$(mktemp)
            printf '%s\n' "$orchestration_tail" > "$orchestration_tmp"
            orchestration_json=$(json_slurp_array "$orchestration_tmp" '[]')
            rm -f "$orchestration_tmp"
            active_agents=$(dashboard_jq_payload "$session_dir" "$orchestration_json" '[.[] | select(type == "object" and (.type == "invoke" or .type == "reinvoke")) | .decision.agent] | unique' '[]' "orchestration.active_agents" "false")
        fi
    fi
    active_agents=$(dashboard_ensure_json "$active_agents" "[]")
    
    # Get system observations (last 20, most recent first)
    # Exclude resolved observations by checking for matching observation_resolved events
    local observations
    local observations='[]'
    if [[ $events_available -eq 1 ]]; then
        if [[ -n "$events_payload" ]]; then
            # shellcheck disable=SC2016
            observations=$(dashboard_jq_payload "$session_dir" "$events_payload" '
            # Get all observations
            (map(select(.type == "system_observation"))) as $all_obs |
            # Get all resolved observation components+text to filter out
            (map(select(.type == "observation_resolved") | 
                .data.original_observation | 
                {component: .component, observation: .observation})) as $resolved |
            # Filter: keep only observations NOT in resolved list
            $all_obs | map(
                . as $obs |
                select(
                    ($resolved | map(
                        (.component == $obs.data.component and .observation == $obs.data.observation)
                    ) | any) | not
                )
            ) | .[-20:] | reverse
        ' '[]' "events.observations" "false")
        fi
    fi
    observations=$(dashboard_ensure_json "$observations" "[]")
    
    # Get error/warning counts from system-errors.log
    local error_count=0
    local warning_count=0
    if [ -f "$session_dir/logs/system-errors.log" ]; then
        error_count=$(grep -c '"severity": "error"' "$session_dir/logs/system-errors.log" 2>/dev/null || true)
        warning_count=$(grep -c '"severity": "warning"' "$session_dir/logs/system-errors.log" 2>/dev/null || true)
        
        # Sanitize counts (ensure single numeric value)
        error_count=${error_count:-0}
        warning_count=${warning_count:-0}
    fi
    error_count=$(dashboard_sanitize_number "$error_count")
    warning_count=$(dashboard_sanitize_number "$warning_count")
    
    # Build metrics JSON
    # Use atomic write pattern: write to temp file, then atomic rename
    # This prevents corruption during concurrent access or interruptions
    local temp_metrics_file="${metrics_file}.tmp.$$"
    
    if ! jq -n \
        --arg updated "$(get_timestamp)" \
        --argjson iter "$iteration" \
        --argjson confidence "$confidence" \
        --argjson total "$total_invocations" \
        --argjson completed "$completed_invocations" \
        --argjson in_progress "$in_progress" \
        --argjson failed "$failed" \
        --argjson entities "$entities" \
        --argjson claims "$claims" \
        --argjson citations "$citations" \
        --argjson gaps "$gaps" \
        --argjson contradictions "$contradictions" \
        --argjson total_cost "$total_cost" \
        --argjson elapsed "$elapsed_seconds" \
        --argjson agents "$active_agents" \
        --argjson observations "$observations" \
        --argjson errors "$error_count" \
        --argjson warnings "$warning_count" \
        --argjson preflight "$preflight_json" \
        --argjson contract "$contract_metrics_json" \
        --arg session_status "$session_status" \
        --arg session_created "$created_at" \
        --arg session_completed "$completed_at" \
        --arg research_question "$research_question" \
        --argjson quality_gate "$quality_gate" \
        '{
            last_updated: $updated,
            iteration: $iter,
            confidence: $confidence,
            session: {
                status: $session_status,
                created_at: $session_created,
                completed_at: $session_completed,
                research_question: $research_question,
                quality_gate: $quality_gate
            },
            progress: {
                agent_invocations: $total,
                completed_invocations: $completed,
                in_progress: $in_progress,
                failed: $failed,
                iteration: $iter
            },
            preflight: $preflight,
            knowledge: {
                entities: $entities,
                claims: $claims,
                citations: $citations
            },
            issues: {
                gaps: $gaps,
                contradictions: $contradictions
            },
            costs: {
                total_usd: $total_cost,
                per_iteration: ($total_cost / ($iter + 0.001))
            },
            runtime: {
                elapsed_seconds: $elapsed,
                active_agents: $agents
            },
            artifact_contract: $contract,
            system_health: {
                errors: $errors,
                warnings: $warnings,
                observations: $observations
            }
        }' > "$temp_metrics_file" 2>&1; then
        # jq failed - log error if error logger is available
        if [ -n "${session_dir:-}" ]; then
            log_system_error "$session_dir" "dashboard_metrics" "Failed to generate dashboard metrics JSON" \
                "Check variables: iter=$iteration, confidence=$confidence, total=$total_invocations"
        fi
        log_error "Failed to generate dashboard metrics"
        # Create minimal valid JSON so dashboard doesn't break
        echo '{"error": "Failed to generate metrics", "last_updated": "'"$(get_timestamp)"'"}' > "$metrics_file"
        return 1
    fi
    
    # Atomic rename (POSIX guarantees atomicity)
    if ! mv "$temp_metrics_file" "$metrics_file" 2>&1; then
        if [ -n "${session_dir:-}" ]; then
            log_system_error "$session_dir" "dashboard_metrics" "Failed to move temp metrics file"
        fi
        log_error "Failed to write dashboard metrics"
        return 1
    fi
}

# Calculate total cost from events
calculate_total_cost() {
    local session_dir="$1"
    local events_file="$session_dir/logs/events.jsonl"
    
    if [ ! -f "$events_file" ] || [ ! -s "$events_file" ]; then
        echo "0"
        return
    fi
    
    # Sum cost_usd from all agent_result events
    # Events have structure: {type: "agent_result", data: {cost_usd: X}}
    local events_payload
    events_payload=$(json_slurp_array "$events_file" '[]')
    local cost
    if [[ -z "$events_payload" || "$events_payload" == "[]" ]]; then
        echo "0"
        return
    fi
    cost=$(safe_jq_from_json "$events_payload" 'map(select(.type == "agent_result") | .data.cost_usd // 0) | add // 0' "0" "$session_dir" "dashboard.total_cost" "false")
    [[ -z "$cost" || "$cost" == "null" ]] && cost="0"
    echo "$cost"
}

# Calculate elapsed seconds
calculate_elapsed_seconds() {
    local start_time="$1"
    
    if [ -z "$start_time" ]; then
        echo "0"
        return
    fi
    
    # Platform-agnostic approach to parse ISO 8601 UTC timestamp
    local start_epoch
    local now_epoch
    
    # Detect OS type
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS (BSD date) - use -j flag to not set system time
        start_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null || echo "0")
        now_epoch=$(date -ju +%s)
    else
        # Linux (GNU date) - use -d flag for date parsing
        start_epoch=$(date -u -d "$start_time" +%s 2>/dev/null || echo "0")
        now_epoch=$(get_epoch)
    fi
    
    # If parsing failed (start_epoch is 0), return 0
    if [ "$start_epoch" = "0" ]; then
        echo "0"
        return
    fi
    
    echo $((now_epoch - start_epoch))
}

# ============================================================================
# SECTION 2: HTML Generation (from dashboard-generator.sh)
# ============================================================================

# Generate dashboard HTML for session
dashboard_generate_html() {
    local session_dir="$1"
    
    local template="$PROJECT_ROOT/src/templates/dashboard-template.html"
    local js_template="$PROJECT_ROOT/src/templates/dashboard.js"
    
    if [ ! -f "$template" ]; then
        log_error "Dashboard template not found: $template"
        return 1
    fi
    
    if [ ! -f "$js_template" ]; then
        log_error "Dashboard JS not found: $js_template"
        return 1
    fi
    
    # Ensure viewer directory exists
    mkdir -p "$session_dir/viewer"
    
    # Copy JS to viewer directory
    cp "$js_template" "$session_dir/viewer/dashboard.js"
    
    local session_id
    session_id=$(basename "$session_dir")
    
    # Generate HTML with cache-busting timestamp for JS file
    # This forces browser to reload JS on each dashboard generation (critical for file:// protocol)
    local js_version
    js_version="v=$(get_epoch)"
    sed \
        -e "s|<body>|<body data-session-id=\"${session_id}\">|" \
        -e "s|<script src=\"./dashboard.js\"></script>|<script src=\"/${session_id}/viewer/dashboard.js?${js_version}\"></script>|" \
        "$template" > "$session_dir/viewer/index.html"
    
    # Only output file path in verbose mode (session-relative)
    if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
        echo "viewer/index.html"
    fi
}

# ============================================================================
# SECTION 3: Server Management (from dashboard-viewer.sh)
# ============================================================================

# Launch dashboard viewer with HTTP server
dashboard_serve() {
    local session_dir="$1"
    local auto_open="${2:-true}"
    
    if [ ! -d "$session_dir" ]; then
        log_system_error "$session_dir" "dashboard_serve" "Session directory not found"
        return 1
    fi
    
    # Check if dashboard exists, generate if needed
    local dashboard_file="$session_dir/viewer/index.html"
    if [ ! -f "$dashboard_file" ]; then
        dashboard_generate_html "$session_dir" >/dev/null 2>&1 || return 1
    fi
    
    # Find an available port (initial range 8890-8899, with fallbacks)
    local dashboard_port=""
    local search_ranges=("8890 8899" "8890 8929")
    local attempt=0
    for range in "${search_ranges[@]}"; do
        local start_port
        local end_port
        start_port=$(echo "$range" | awk '{print $1}')
        end_port=$(echo "$range" | awk '{print $2}')
        for p in $(seq "$start_port" "$end_port"); do
            if ! lsof -i ":$p" >/dev/null 2>&1; then
                dashboard_port=$p
                break
            fi
        done
        if [ -n "$dashboard_port" ]; then
            break
        fi
        if [ $attempt -eq 0 ]; then
            dashboard_cleanup_orphans "$(dirname "$session_dir")" >/dev/null 2>&1 || true
        fi
        attempt=$((attempt + 1))
    done

    if [ -z "$dashboard_port" ]; then
        # Final fallback: aggressively terminate lingering http-server processes
        pkill -f 'http-server' >/dev/null 2>&1 || true
        for p in $(seq 8890 8929); do
            if ! lsof -i ":$p" >/dev/null 2>&1; then
                dashboard_port=$p
                break
            fi
        done
    fi
    
    if [ -z "$dashboard_port" ]; then
        log_error "No available ports in range 8890-8929"
        echo "Try: pkill -f 'http-server'" >&2
        return 1
    fi
    
    # Start HTTP server in background
    local parent_dir
    parent_dir=$(dirname "$session_dir")
    
    cd "$parent_dir"
    npx --yes http-server "$parent_dir" -p "$dashboard_port" --silent >/dev/null 2>&1 &
    local server_pid=$!
    cd - >/dev/null
    
    # Store PID for cleanup
    echo "$server_pid" > "$session_dir/.dashboard-server.pid"
    
    # Wait for server to be ready (poll until it responds)
    local max_wait=10  # Maximum 10 seconds
    local elapsed=0
    while [ $elapsed -lt $max_wait ]; do
        local session_id
        session_id=$(basename "$session_dir")
        local health_url="http://localhost:$dashboard_port/$session_id/"
        if curl -s -o /dev/null -w "%{http_code}" "$health_url" 2>/dev/null | grep -q "200\|404"; then
            # Server is responding (200 or 404 both mean server is up)
            break
        fi
        sleep 0.5
        elapsed=$((elapsed + 1))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        echo "  ⚠ Warning: Server may still be starting..." >&2
    fi
    
    # Add session ID to URL to prevent caching
    local viewer_url="http://localhost:$dashboard_port/$session_id/viewer/index.html"
    
    echo "  ✓ Research Journal Viewer: $viewer_url"
    # Only show server details in verbose mode
    if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
        echo "     (HTTP server PID: $server_pid, port: $dashboard_port)"
    fi
    
    # Auto-open in browser if requested
    if [ "$auto_open" = "true" ]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open "$viewer_url" 2>/dev/null || true
        elif command -v xdg-open &> /dev/null; then
            xdg-open "$viewer_url" 2>/dev/null || true
        elif command -v explorer.exe &> /dev/null; then
            # WSL
            explorer.exe "$viewer_url" 2>/dev/null || true
        fi
    fi
    
    return 0
}

# Stop dashboard server for a session
dashboard_stop() {
    local session_dir="$1"
    
    local pid_file="$session_dir/.dashboard-server.pid"
    if [ ! -f "$pid_file" ]; then
        echo "No dashboard server running for this session" >&2
        return 1
    fi
    
    local server_pid
    server_pid=$(cat "$pid_file" 2>/dev/null || echo "")
    
    if [ -z "$server_pid" ]; then
        rm -f "$pid_file"
        return 1
    fi
    
    if kill -0 "$server_pid" 2>/dev/null; then
        kill "$server_pid" 2>/dev/null || true
        rm -f "$pid_file"
        echo "Dashboard server stopped (PID: $server_pid)"
    else
        rm -f "$pid_file"
        echo "Dashboard server was not running"
    fi
    
    return 0
}

# Get dashboard URL for a session
dashboard_get_url() {
    local session_dir="$1"
    
    local pid_file="$session_dir/.dashboard-server.pid"
    if [ ! -f "$pid_file" ]; then
        echo ""
        return 1
    fi
    
    local server_pid
    server_pid=$(cat "$pid_file" 2>/dev/null || echo "")
    
    if [ -z "$server_pid" ] || ! kill -0 "$server_pid" 2>/dev/null; then
        echo ""
        return 1
    fi
    
    # Find port from lsof
    local port
    port=$(lsof -Pan -p "$server_pid" -i 2>/dev/null | grep LISTEN | awk '{print $9}' | cut -d: -f2 | head -1)
    
    if [ -z "$port" ]; then
        echo ""
        return 1
    fi
    
    local session_id
    session_id=$(basename "$session_dir")
    echo "http://localhost:$port/$session_id/viewer/index.html"
    return 0
}

# ============================================================================
# SECTION 4: Cleanup (from cleanup-dashboard-servers.sh)
# ============================================================================

# Cleanup stale dashboard HTTP servers
dashboard_cleanup_orphans() {
    local sessions_dir="${1:-$PROJECT_ROOT/research-sessions}"
    local killed=0
    
    if [ ! -d "$sessions_dir" ]; then
        return 0
    fi
    
    # Find all .dashboard-server.pid files
    while IFS= read -r -d '' pid_file; do
        local session_dir
        session_dir=$(dirname "$pid_file")
        local session_id
        session_id=$(basename "$session_dir")
        
        if [ ! -f "$pid_file" ]; then
            continue
        fi
        
        local server_pid
        server_pid=$(cat "$pid_file" 2>/dev/null || echo "")
        
        if [ -z "$server_pid" ]; then
            rm -f "$pid_file"
            continue
        fi
        
        local is_stale=false
        local reason=""
        
        # Check if process is still running
        if ! kill -0 "$server_pid" 2>/dev/null; then
            is_stale=true
            reason="process not running"
        # Check if session is completed
        elif [ -f "$session_dir/meta/session.json" ]; then
            local status
            status=$(dashboard_jq_file "$session_dir" "$session_dir/meta/session.json" '.status // "active"' "active" "session.status_active")
            if [ "$status" = "completed" ]; then
                is_stale=true
                reason="session completed"
            fi
        fi
        
        if [ "$is_stale" = true ]; then
            echo "  → Stopping stale HTTP server for $session_id (PID: $server_pid, reason: $reason)"
            kill "$server_pid" 2>/dev/null || true
            rm -f "$pid_file"
            killed=$((killed + 1))
        fi
    done < <(find "$sessions_dir" -name ".dashboard-server.pid" -type f -print0 2>/dev/null)
    
    if [ "$killed" -gt 0 ]; then
        echo "  ✓ Stopped $killed stale HTTP server(s)"
    fi
    
    return 0
}

# ============================================================================
# SECTION 5: High-level operations
# ============================================================================

# View dashboard (full workflow: metrics + HTML + serve)
dashboard_view() {
    local session_dir="$1"
    dashboard_generate_metrics "$session_dir"
    dashboard_generate_html "$session_dir"
    dashboard_serve "$session_dir" true
}

# Update metrics (call after state changes)
dashboard_update_metrics() {
    local session_dir="$1"
    dashboard_generate_metrics "$session_dir" 2>/dev/null || true
}

# ============================================================================
# Export functions
# ============================================================================

export -f dashboard_generate_metrics
export -f dashboard_generate_html
export -f dashboard_serve
export -f dashboard_stop
export -f dashboard_get_url
export -f dashboard_cleanup_orphans
export -f dashboard_view
export -f dashboard_update_metrics

# Legacy compatibility (old function names)
export -f calculate_total_cost
export -f calculate_elapsed_seconds

# ============================================================================
# CLI interface
# ============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        generate)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 generate <session_dir>" >&2
                exit 1
            fi
            dashboard_generate_html "${2}"
            ;;
        serve)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 serve <session_dir>" >&2
                exit 1
            fi
            dashboard_serve "${2}" true
            ;;
        stop)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 stop <session_dir>" >&2
                exit 1
            fi
            dashboard_stop "${2}"
            ;;
        cleanup)
            echo "Cleaning up stale dashboard servers..."
            dashboard_cleanup_orphans "${2:-}"
            ;;
        view)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 view <session_dir>" >&2
                exit 1
            fi
            dashboard_view "${2}"
            ;;
        metrics)
            if [ $# -lt 2 ]; then
                echo "Usage: $0 metrics <session_dir>" >&2
                exit 1
            fi
            dashboard_generate_metrics "${2}"
            ;;
        help|--help)
            cat <<EOF
Dashboard - Unified dashboard operations

Usage: dashboard.sh <command> [args]

Commands:
  generate <session>  Generate dashboard HTML
  metrics <session>   Generate dashboard metrics
  serve <session>     Start dashboard server
  stop <session>      Stop dashboard server
  cleanup             Clean up orphaned servers
  view <session>      Full dashboard workflow (metrics + HTML + serve)
  help                Show this help

Examples:
  dashboard.sh view research-sessions/mission_session_123
  dashboard.sh cleanup
  dashboard.sh metrics research-sessions/latest
EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
