#!/usr/bin/env bash
#
# export-journal.sh - Export research journal as markdown
#
# Generates a sequential, detailed markdown timeline of the research session
# from events.jsonl
#

# Helper function to format credibility (peer_reviewed -> Peer Reviewed, academic -> Academic)
format_credibility() {
    local cred="$1"
    # Replace underscores with spaces and capitalize each word
    echo "$cred" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1'
}

# Helper function to make paths relative to session directory
make_path_relative() {
    local path="$1"
    local session_dir="$2"
    
    # Normalize session_dir to absolute path
    local abs_session_dir
    abs_session_dir=$(cd "$session_dir" 2>/dev/null && pwd)
    
    # If path starts with absolute session_dir, make it relative
    if [[ "$path" == "$abs_session_dir"/* ]]; then
        echo "${path#"$abs_session_dir"/}"
    else
        # Otherwise return as-is
        echo "$path"
    fi
}

# Helper function to calculate elapsed time from session start
calculate_elapsed_time() {
    local session_start="$1"
    local event_time="$2"
    
    # Convert timestamps to epoch
    local start_epoch event_epoch
    start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$session_start" "+%s" 2>/dev/null || echo "0")
    event_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$event_time" "+%s" 2>/dev/null || echo "0")
    
    if [ "$start_epoch" = "0" ] || [ "$event_epoch" = "0" ]; then
        echo ""
        return
    fi
    
    local elapsed_seconds=$((event_epoch - start_epoch))
    local elapsed_minutes=$((elapsed_seconds / 60))
    
    if [ "$elapsed_minutes" -lt 60 ]; then
        echo "$elapsed_minutes min"
    else
        local hours=$((elapsed_minutes / 60))
        local mins=$((elapsed_minutes % 60))
        echo "${hours}h ${mins}m"
    fi
}

# Helper function to extract entity/claim/source counts from findings files
get_findings_stats() {
    local session_dir="$1"
    local stat_type="$2"  # entities, claims, or sources
    
    if [ ! -d "$session_dir/raw" ]; then
        echo "0"
        return
    fi
    
    case "$stat_type" in
        entities)
            find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '[.entities_discovered // [] | .[]] | length' 2>/dev/null | \
                awk '{sum+=$1} END {print sum+0}'
            ;;
        claims)
            find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '[.claims // [] | .[]] | length' 2>/dev/null | \
                awk '{sum+=$1} END {print sum+0}'
            ;;
        sources)
            find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '.claims[]?.sources[]?.url // empty' 2>/dev/null | \
                sort -u | wc -l | tr -d ' '
            ;;
    esac
}

# Helper function to extract first sentence from text
extract_first_sentence() {
    local text="$1"
    
    # Extract first sentence (up to first period followed by space or end)
    local first_sent
    first_sent=$(echo "$text" | sed 's/\([^.]*\.\) .*/\1/' | head -c 200)
    
    # If result is empty or only contains markdown/whitespace, use first 100 chars
    if [ -z "$first_sent" ] || ! echo "$first_sent" | grep -q '[a-zA-Z]'; then
        first_sent=$(echo "$text" | head -c 100)
        if [ ${#text} -gt 100 ]; then
            first_sent="${first_sent}..."
        fi
    fi
    
    echo "$first_sent"
}

format_single_line() {
    local text="$1"
    echo "$text" | tr '\n' ' ' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

render_evidence_footnotes() {
    local evidence_file="$1"

    echo ""
    echo "## Evidence Highlights"
    echo ""

    local claim_json
    local idx=0
    local used_markers=""
    local claim_lines=()
    local footnote_lines=()

    while IFS= read -r claim_json; do
        ((idx+=1))
        local marker
        marker=$(echo "$claim_json" | jq -r '.marker // .id // ""')
        if [[ -z "$marker" || "$marker" == "null" ]]; then
            marker="$idx"
        fi
        marker=$(echo "$marker" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
        if [[ -z "$marker" ]]; then
            marker="$idx"
        fi
        while [[ "$used_markers" == *"|$marker|"* ]]; do
            marker="${marker}_${idx}"
        done
        used_markers+="|$marker|"

        local claim_text why_supported
        claim_text=$(echo "$claim_json" | jq -r '.claim_text // .statement // ""')
        why_supported=$(echo "$claim_json" | jq -r '.why_supported // ""')

        claim_lines+=("- ${claim_text}[^${marker}]")

        local source_ids=()
        while IFS= read -r source_id; do
            [[ -n "$source_id" ]] && source_ids+=("$source_id")
        done < <(echo "$claim_json" | jq -r '.sources[]? // empty')
        if [[ ${#source_ids[@]} -eq 0 ]]; then
            continue
        fi

        local summary="Evidence"
        local first_label=""
        local footnote_block=()

        for source_id in "${source_ids[@]}"; do
            [[ -z "$source_id" ]] && continue
            local source_json
            source_json=$(jq -c --arg sid "$source_id" '.sources[]? | select(.id == $sid)' "$evidence_file")
            [[ -z "$source_json" ]] && continue

            local title url link quote
            title=$(echo "$source_json" | jq -r '.title // ""')
            url=$(echo "$source_json" | jq -r '.url // ""')
            link=$(echo "$source_json" | jq -r '.deep_link // .url // ""')
            quote=$(format_single_line "$(echo "$source_json" | jq -r '.quote // ""')")

            if [[ -z "$first_label" ]]; then
                first_label=${title:-$url}
                summary="Evidence from ${first_label:-Source}"
            fi

            if [[ -n "$quote" ]]; then
                footnote_block+=("> ${quote}")
                footnote_block+=("")
            fi

            local label=${title:-$url}
            if [[ -n "$link" ]]; then
                footnote_block+=("Source: [${label}](${link})")
            elif [[ -n "$url" ]]; then
                footnote_block+=("Source: ${url}")
            else
                footnote_block+=("Source: ${label:-Evidence}")
            fi
            footnote_block+=("")
        done

        if [[ ${#footnote_block[@]} -eq 0 ]]; then
            continue
        fi

        footnote_lines+=("[^${marker}]: <details><summary>${summary}</summary>")
        footnote_lines+=("")
        for line in "${footnote_block[@]}"; do
            footnote_lines+=("$line")
        done
        if [[ -n "$why_supported" && "$why_supported" != "null" ]]; then
            footnote_lines+=("**Why this supports the claim:** $(format_single_line "$why_supported")")
            footnote_lines+=("")
        fi
        footnote_lines+=("</details>")
        footnote_lines+=("")
    done < <(jq -c '.claims[]' "$evidence_file")

    if [[ ${#claim_lines[@]} -eq 0 ]]; then
        return
    fi

    for line in "${claim_lines[@]}"; do
        echo "$line"
    done
    echo ""
    for line in "${footnote_lines[@]}"; do
        printf '%s\n' "$line"
    done
}

render_evidence_fallback() {
    local evidence_file="$1"

    echo ""
    echo "## Evidence"
    echo ""

    local claim_json
    while IFS= read -r claim_json; do
        local claim_text why_supported
        claim_text=$(echo "$claim_json" | jq -r '.claim_text // .statement // ""')
        why_supported=$(echo "$claim_json" | jq -r '.why_supported // ""')
        echo "- ${claim_text}"
        if [[ -n "$why_supported" && "$why_supported" != "null" ]]; then
            echo "  - Why: $(format_single_line "$why_supported")"
        fi

        local source_ids=()
        while IFS= read -r source_id; do
            [[ -n "$source_id" ]] && source_ids+=("$source_id")
        done < <(echo "$claim_json" | jq -r '.sources[]? // empty')
        if [[ ${#source_ids[@]} -gt 0 ]]; then
            echo "  - Sources:"
            for source_id in "${source_ids[@]}"; do
                [[ -z "$source_id" ]] && continue
                local source_json
                source_json=$(jq -c --arg sid "$source_id" '.sources[]? | select(.id == $sid)' "$evidence_file")
                [[ -z "$source_json" ]] && continue

                local title url link quote
                title=$(echo "$source_json" | jq -r '.title // ""')
                url=$(echo "$source_json" | jq -r '.url // ""')
                link=$(echo "$source_json" | jq -r '.deep_link // .url // ""')
                quote=$(format_single_line "$(echo "$source_json" | jq -r '.quote // ""')")
                local label=${title:-$url}
                local descriptor="${quote}"
                if [[ -n "$descriptor" ]]; then
                    descriptor=" — ${descriptor}"
                fi
                if [[ -n "$link" ]]; then
                    echo "    - [${label}](${link})${descriptor}"
                elif [[ -n "$url" ]]; then
                    echo "    - ${url}${descriptor}"
                else
                    echo "    - ${label:-Source}${descriptor}"
                fi
            done
        fi
        echo ""
    done < <(jq -c '.claims[]' "$evidence_file")
}

render_evidence_section() {
    local session_dir="$1"
    local evidence_file="$session_dir/evidence/evidence.json"

    if [[ "${CCONDUCTOR_EVIDENCE_MODE:-render}" == "disabled" ]]; then
        return
    fi
    if [ ! -f "$evidence_file" ]; then
        return
    fi

    local claim_count
    claim_count=$(jq '.claims | length' "$evidence_file" 2>/dev/null || echo 0)
    if [[ "$claim_count" -eq 0 ]]; then
        return
    fi

    local render_mode="${CCONDUCTOR_EVIDENCE_RENDER:-footnotes}"
    case "$render_mode" in
        fallback)
            render_evidence_fallback "$evidence_file"
            ;;
        *)
            render_evidence_footnotes "$evidence_file"
            ;;
    esac
}

export_journal() {
    local session_dir="$1"
    local output_file="${2:-$session_dir/final/research-journal.md}"

    mkdir -p "$(dirname "$output_file")"
    
    local events_file="$session_dir/events.jsonl"
    if [ ! -f "$events_file" ]; then
        echo "Error: events.jsonl not found in $session_dir" >&2
        return 1
    fi
    
    # Initialize temp files for tool logging
    local tool_log_file="/tmp/tool-log-$$.txt"
    local tool_counts_file="/tmp/tool-counts-$$.json"
    echo '{"searches":0,"fetches":0,"saves":0,"plans":0,"greps":0}' > "$tool_counts_file"
    : > "$tool_log_file"
    
    # Cleanup temp files on exit (use ${var:-} to handle unbound variable if trap runs after function exits)
    trap 'rm -f "${tool_log_file:-}" "${tool_counts_file:-}"' EXIT
    
    # Flag to track when we need a task section header after iteration
    local NEED_TASK_SECTION_HEADER=false
    
    # Get session metadata
    local session_file="$session_dir/session.json"
    local question="Unknown"
    local objective="Unknown"
    local session_created=""
    if [ -f "$session_file" ]; then
        question=$(jq -r '.question // "Unknown"' "$session_file" 2>/dev/null || echo "Unknown")
        objective=$(jq -r '.objective // .question // "Unknown"' "$session_dir/session.json" 2>/dev/null || echo "Unknown")
        session_created=$(jq -r '.created_at // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
    fi
    
    # Load orchestration log for decision lookups
    local orchestration_log="$session_dir/orchestration-log.jsonl"
    local has_orchestration_log=false
    if [ -f "$orchestration_log" ]; then
        has_orchestration_log=true
    fi
    
    # Track current iteration for section markers
    local current_iteration=0
    
    # Track current agent for tool logging
    local current_agent=""
    
    # Start markdown document
    {
        echo "# Research Journal"
        echo ""
        
        # Display objective/question
        if [ "$objective" != "Unknown" ]; then
            echo "**Research Objective:** $objective"
        else
            echo "**Research Question:** $question"
        fi
        echo ""
        
        # Display output format if specified
        local output_spec
        output_spec=$(jq -r '.output_specification // ""' "$session_file" 2>/dev/null)
        if [ -n "$output_spec" ] && [ "$output_spec" != "null" ]; then
            echo "**User's Format Requirements:**"
            echo ""
            echo "$output_spec"
            echo ""
            echo "---"
            echo ""
        fi
        
        # Display research date
        local session_created
        session_created=$(jq -r '.created_at // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
        if [ "$session_created" != "unknown" ]; then
            local formatted_date
            # Convert UTC to local time: parse UTC to epoch, then format in local timezone
            local epoch
            epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$session_created" "+%s" 2>/dev/null || echo "0")
            if [ "$epoch" != "0" ]; then
                formatted_date=$(date -r "$epoch" "+%B %d, %Y" 2>/dev/null || echo "$session_created")
            else
                formatted_date="$session_created"
            fi
            echo "**Research Date:** $formatted_date"
            echo ""
        fi
        
        # Display runtime information
        local cconductor_ver claude_ver mission_name
        cconductor_ver=$(jq -r '.runtime.cconductor_version // .version // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
        claude_ver=$(jq -r '.runtime.claude_code_version // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
        mission_name=$(jq -r '.mission_name // "unknown"' "$session_file" 2>/dev/null || echo "unknown")
        
        if [ "$cconductor_ver" != "unknown" ] || [ "$claude_ver" != "unknown" ] || [ "$mission_name" != "unknown" ]; then
            echo "**Research Environment:**"
            [ "$mission_name" != "unknown" ] && echo "- Mission profile: $mission_name"
            [ "$cconductor_ver" != "unknown" ] && echo "- [CConductor](https://github.com/yaniv-golan/cconductor) version $cconductor_ver"
            [ "$claude_ver" != "unknown" ] && echo "- Claude Code CLI $claude_ver"
            echo ""
        fi
        
        echo "**Session:** $(basename "$session_dir")"
        echo ""
        
        # Calculate executive summary statistics
        local total_duration_min=0
        local total_iterations=0
        local total_entities=0
        local total_claims=0
        local total_sources=0
        local avg_confidence=0
        
        # Get duration
        local end_time
        end_time=$(jq -r '.completed_at // ""' "$session_file" 2>/dev/null)
        if [ -n "$session_created" ] && [ "$session_created" != "unknown" ] && [ -n "$end_time" ] && [ "$end_time" != "" ]; then
            local start_epoch end_epoch
            start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$session_created" "+%s" 2>/dev/null || echo "0")
            end_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end_time" "+%s" 2>/dev/null || echo "0")
            if [ "$start_epoch" != "0" ] && [ "$end_epoch" != "0" ]; then
                total_duration_min=$(( (end_epoch - start_epoch) / 60 ))
            fi
        fi
        
        # Get iteration count from dashboard metrics
        local dashboard_metrics="$session_dir/dashboard-metrics.json"
        if [ -f "$dashboard_metrics" ]; then
            total_iterations=$(jq -r '.iteration // 0' "$dashboard_metrics" 2>/dev/null || echo "0")
        fi
        
        # Get findings statistics
        total_entities=$(get_findings_stats "$session_dir" "entities")
        total_claims=$(get_findings_stats "$session_dir" "claims")
        total_sources=$(get_findings_stats "$session_dir" "sources")
        
        # Calculate average confidence
        if [ -d "$session_dir/raw" ] && [ "$total_claims" -gt 0 ]; then
            avg_confidence=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '[.claims[]?.confidence // 0] | add / length * 100 | floor' 2>/dev/null | \
                head -1)
            avg_confidence=${avg_confidence:-0}
        fi
        
        # Display executive summary if we have meaningful data
        if [ "$total_duration_min" -gt 0 ] || [ "$total_claims" -gt 0 ]; then
            echo "---"
            echo ""
            echo "## Executive Summary"
            echo ""
            
            if [ "$total_duration_min" -gt 0 ]; then
                echo "**Duration:** $total_duration_min minutes"
                if [ "$total_iterations" -gt 0 ]; then
                    echo " across $total_iterations research cycles"
                fi
                echo ""
            fi
            
            if [ "$total_claims" -gt 0 ]; then
                echo "**Knowledge Accumulated:**"
                echo "- $total_entities entities documented"
                echo "- $total_claims claims validated"
                echo "- $total_sources sources consulted"
                if [ "$avg_confidence" -gt 0 ]; then
                    echo "- ${avg_confidence}% average confidence"
                fi
                echo ""
            fi
            
            echo "**Process Overview:**"
            echo "- [Investigation Commenced](#investigation-commenced)"
            echo "- [Strategic Planning](#strategic-planning)"
            echo "- [Research Activities](#web-research)"
            echo "- [Research Summary](#research-summary)"
            echo ""
        fi
        
        # Display input materials if provided
        local input_manifest="$session_dir/input-files.json"
        if [ -f "$input_manifest" ]; then
            local input_dir_path
            input_dir_path=$(jq -r '.input_dir // ""' "$input_manifest" 2>/dev/null)
            
            if [ -n "$input_dir_path" ] && [ "$input_dir_path" != "" ]; then
                local pdf_count md_count txt_count
                pdf_count=$(jq '.pdfs | length' "$input_manifest" 2>/dev/null || echo "0")
                md_count=$(jq '.markdown | length' "$input_manifest" 2>/dev/null || echo "0")
                txt_count=$(jq '.text | length' "$input_manifest" 2>/dev/null || echo "0")
                local total_count=$((pdf_count + md_count + txt_count))
                
                if [ "$total_count" -gt 0 ]; then
                    echo "**Initial Materials:** Research began with $total_count provided document(s) for analysis:"
                    echo ""
                    
                    # List files naturally
                    if [ "$pdf_count" -gt 0 ]; then
                        jq -r '.pdfs[] | "- \(.original_name) (PDF document)"' "$input_manifest" 2>/dev/null
                    fi
                    if [ "$md_count" -gt 0 ]; then
                        jq -r '.markdown[] | "- \(.original_name) (markdown notes)"' "$input_manifest" 2>/dev/null
                    fi
                    if [ "$txt_count" -gt 0 ]; then
                        jq -r '.text[] | "- \(.original_name) (text document)"' "$input_manifest" 2>/dev/null
                    fi
                    echo ""
                fi
            fi
        fi
        
        render_evidence_section "$session_dir"

        echo "---"
        echo ""
        
        # Process events sequentially (oldest first - natural timeline order)
        while IFS= read -r line; do
            # Parse event
            local event_type
            event_type=$(echo "$line" | jq -r '.type // "unknown"')
            local timestamp
            timestamp=$(echo "$line" | jq -r '.timestamp // "unknown"')
            local formatted_time
            # Format: "October 8, 2025 at 7:35 AM" in local timezone
            # Strip microseconds if present (2025-10-08T07:35:57.159051Z -> 2025-10-08T07:35:57Z)
            local clean_timestamp
            # shellcheck disable=SC2001
            clean_timestamp=$(echo "$timestamp" | sed 's/\.[0-9]*Z$/Z/')
            # Convert UTC to local: parse UTC to epoch (using -u flag), then format in local timezone
            local epoch
            epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_timestamp" "+%s" 2>/dev/null || echo "0")
            if [ "$epoch" != "0" ]; then
                formatted_time=$(date -r "$epoch" "+%B %d, %Y at %l:%M %p" 2>/dev/null | sed 's/  / /g' || echo "$timestamp")
            else
                formatted_time="$timestamp"
            fi
            
            case "$event_type" in
                mission_started)
                    echo "## Investigation Commenced"
                    echo ""
                    echo "*$formatted_time*"
                    echo ""
                    echo "Beginning mission-based research investigation. The research will proceed through iterative cycles, with specialized analysis agents coordinated to gather, validate, and synthesize information."
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                
                session_created)
                    echo "## Session Established"
                    echo ""
                    echo "*$formatted_time*"
                    echo ""
                    echo "Session established. Initial analysis of the research question will guide task generation and source selection."
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                    
                agent_invocation)
                    local agent tools model
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    tools=$(echo "$line" | jq -r '.data.tools // "N/A"')
                    model=$(echo "$line" | jq -r '.data.model // "unknown"')
                    
                    # Update current agent for tool tracking
                    if [ "$current_agent" != "$agent" ]; then
                        # Reset tool log for new agent
                        : > "$tool_log_file"
                        echo '{"searches":0,"fetches":0,"saves":0,"plans":0,"greps":0}' > "$tool_counts_file"
                        current_agent="$agent"
                    fi
                    
                    # Calculate elapsed time
                    local elapsed=""
                    if [ "$session_created" != "unknown" ]; then
                        elapsed=$(calculate_elapsed_time "$session_created" "$clean_timestamp")
                    fi
                    
                    # Check iteration context for mission-orchestrator
                    if [ "$agent" = "mission-orchestrator" ] && [ "$has_orchestration_log" = true ]; then
                        local iteration_number timestamp_minute
                        timestamp_minute="${clean_timestamp%:??Z}"
                        iteration_number=$(grep "$timestamp_minute" "$orchestration_log" 2>/dev/null | head -1 | jq -r '.decision.iteration // 0' 2>/dev/null || echo "0")
                        
                        if [ "$iteration_number" != "0" ] && [ "$iteration_number" != "$current_iteration" ]; then
                            current_iteration=$iteration_number
                            echo "---"
                            echo ""
                            echo "## Research Cycle $current_iteration"
                            echo ""
                        fi
                    fi
                    
                    # Narrative based on agent type (natural language, not technical)
                    local timestamp_line="*$formatted_time*"
                    if [ -n "$elapsed" ]; then
                        timestamp_line="$timestamp_line • *Elapsed: $elapsed*"
                    fi
                    
                    case "$agent" in
                        mission-orchestrator)
                            echo "### Strategic Planning"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            ;;
                        academic-researcher)
                            echo "### Academic Literature Review"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Consulting peer-reviewed academic sources to establish theoretical foundation."
                            echo ""
                            ;;
                        web-researcher)
                            echo "### Web Research"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Gathering information from web sources to complement academic findings."
                            echo ""
                            ;;
                        research-planner)
                            echo "### Research Planning"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Analyzing the research question to develop a structured investigation plan."
                            echo ""
                            ;;
                        synthesis-agent)
                            echo "### Synthesis and Integration"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Integrating findings from multiple sources to develop coherent understanding."
                            echo ""
                            ;;
                        pdf-analyzer)
                            echo "### Document Analysis"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Analyzing provided PDF documents for relevant information and insights."
                            echo ""
                            ;;
                        fact-checker)
                            echo "### Fact Verification"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Cross-referencing claims against multiple sources to ensure accuracy."
                            echo ""
                            ;;
                        market-analyzer|market-sizing-expert)
                            echo "### Market Analysis"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            echo "Evaluating market data and trends to inform business insights."
                            echo ""
                            ;;
                        prompt-parser)
                            echo "### Understanding the Research Request"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            
                            # Extract prompt parser findings if available
                            local parser_output="$session_dir/agent-output-prompt-parser.json"
                            if [ -f "$parser_output" ]; then
                                local research_question output_spec
                                # shellcheck disable=SC2016
                                research_question=$(jq -r '.result' "$parser_output" 2>/dev/null | sed 's/^```json//;s/```$//' | jq -r '.research_question // .objective // empty' 2>/dev/null)
                                # shellcheck disable=SC2016
                                output_spec=$(jq -r '.result' "$parser_output" 2>/dev/null | sed 's/^```json//;s/```$//' | jq -r '.output_specification // empty' 2>/dev/null)
                                
                                if [ -n "$research_question" ]; then
                                    echo "**Research question as understood:** $research_question"
                                    echo ""
                                fi
                                
                                if [ -n "$output_spec" ] && [ "$output_spec" != "null" ]; then
                                    echo "**Output format requested:** $output_spec"
                                    echo ""
                                fi
                            fi
                            ;;
                        *)
                            # Generic case for custom agents
                            local agent_display="${agent//-/ }"
                            echo "### ${agent_display^} Analysis"
                            echo ""
                            echo "$timestamp_line"
                            echo ""
                            ;;
                    esac
                    
                    # Check for orchestration decisions for any agent (not just mission-orchestrator)
                    if [ "$has_orchestration_log" = true ]; then
                        # Look for agent_invocation decisions in orchestration log that match this agent
                        # Match on hour:minute only since seconds may differ slightly between logs
                        local decision_entry timestamp_hhmm
                        timestamp_hhmm="${clean_timestamp%:??Z}"  # Extract YYYY-MM-DDTHH:MM
                        
                        # Try to find the decision entry that led to this agent invocation
                        # Match on hour:minute window and agent name
                        decision_entry=$(jq -c "select(.type == \"agent_invocation\" and (.timestamp | startswith(\"$timestamp_hhmm\")) and .decision.decision.agent == \"$agent\")" "$orchestration_log" 2>/dev/null | head -1)
                        
                        if [ -n "$decision_entry" ]; then
                            local rationale alternatives_count
                            rationale=$(echo "$decision_entry" | jq -r '.decision.decision.rationale // ""' 2>/dev/null)
                            alternatives_count=$(echo "$decision_entry" | jq '.decision.decision.alternatives_considered // [] | length' 2>/dev/null)
                            
                            if [ -n "$rationale" ] && [ "$alternatives_count" -gt 0 ]; then
                                # Extract first sentence as summary
                                local rationale_summary
                                rationale_summary=$(extract_first_sentence "$rationale")
                                
                                echo "**🎯 Strategy:** $rationale_summary"
                                echo ""
                                echo "#### Reasoning and Alternatives"
                                echo ""
                                echo "**Why this approach:** $rationale"
                                echo ""
                                
                                # Show alternatives considered
                                local alternatives
                                alternatives=$(echo "$decision_entry" | jq -r '.decision.decision.alternatives_considered // [] | .[]' 2>/dev/null)
                                if [ -n "$alternatives" ]; then
                                    echo "**Alternatives considered:**"
                                    while IFS= read -r alt; do
                                        echo "- $alt"
                                    done <<< "$alternatives"
                                fi
                                
                                echo ""
                            fi
                        fi
                    fi
                    
                    ;;
                    
                agent_result)
                    local agent duration model
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    duration=$(echo "$line" | jq -r '.data.duration_ms // 0')
                    model=$(echo "$line" | jq -r '.data.model // "unknown"')
                    local duration_sec=$((duration / 1000))
                    
                    # Output tool activity summary split by planning phases
                    # Structure: PLAN → ACTIONS for that plan → PLAN → ACTIONS
                    if [ -f "$tool_log_file" ] && [ -s "$tool_log_file" ]; then
                        local current_plan=""
                        local current_phase_file="/tmp/phase-$$.txt"
                        : > "$current_phase_file"  # Initialize empty
                        
                        while IFS= read -r log_line; do
                            if echo "$log_line" | grep -q "📋 Planning:"; then
                                # Found planning marker
                                # First, output previous plan and its actions if we have them
                                if [ -n "$current_plan" ] && [ -s "$current_phase_file" ]; then
                                    # Output the plan
                                    echo "📋 **Plan:** $current_plan"
                                    echo ""
                                    
                                    # Count and output actions for this plan
                                    local phase_searches phase_fetches phase_saves phase_greps
                                    phase_searches=$(grep -c "🔍 Web Search:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                    phase_fetches=$(grep -c "📄 Fetching:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                    phase_saves=$(grep -c "💾 Saving:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                    phase_greps=$(grep -c "🔎 Searching for:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                    
                                    local phase_parts=()
                                    [ "$phase_searches" -gt 0 ] && phase_parts+=("$phase_searches searches")
                                    [ "$phase_fetches" -gt 0 ] && phase_parts+=("$phase_fetches pages fetched")
                                    [ "$phase_saves" -gt 0 ] && phase_parts+=("$phase_saves documents saved")
                                    [ "$phase_greps" -gt 0 ] && phase_parts+=("$phase_greps queries")
                                    
                                    if [ ${#phase_parts[@]} -gt 0 ]; then
                                        local phase_summary
                                        phase_summary=$(IFS=" • "; echo "${phase_parts[*]}")
                                        
                                        echo "**🔗 Actions:** $phase_summary"
                                        echo ""
                                        echo "> [!note]- View detailed activity log"
                                        echo ">"
                                        while IFS= read -r log_line; do
                                            echo "> $log_line"
                                        done < "$current_phase_file"
                                        echo ""
                                    fi
                                    
                                    echo "---"
                                    echo ""
                                    
                                    : > "$current_phase_file"  # Reset for next phase
                                fi
                                
                                # Save the new plan (will be output before its actions)
                                current_plan="${log_line#*📋 Planning: }"
                            else
                                # Regular activity - accumulate for current plan
                                echo "$log_line" >> "$current_phase_file"
                            fi
                        done < "$tool_log_file"
                        
                        # Output final plan and its actions if we have them
                        if [ -n "$current_plan" ]; then
                            echo "📋 **Plan:** $current_plan"
                            echo ""
                            
                            if [ -s "$current_phase_file" ]; then
                                local phase_searches phase_fetches phase_saves phase_greps
                                phase_searches=$(grep -c "🔍 Web Search:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                phase_fetches=$(grep -c "📄 Fetching:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                phase_saves=$(grep -c "💾 Saving:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                phase_greps=$(grep -c "🔎 Searching for:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                                
                                local phase_parts=()
                                [ "$phase_searches" -gt 0 ] && phase_parts+=("$phase_searches searches")
                                [ "$phase_fetches" -gt 0 ] && phase_parts+=("$phase_fetches pages fetched")
                                [ "$phase_saves" -gt 0 ] && phase_parts+=("$phase_saves documents saved")
                                [ "$phase_greps" -gt 0 ] && phase_parts+=("$phase_greps queries")
                                
                                if [ ${#phase_parts[@]} -gt 0 ]; then
                                    local phase_summary
                                    phase_summary=$(IFS=" • "; echo "${phase_parts[*]}")
                                    
                                    echo "**🔗 Actions:** $phase_summary"
                                    echo ""
                                    echo "> [!note]- View detailed activity log"
                                    echo ">"
                                    while IFS= read -r log_line; do
                                        echo "> $log_line"
                                    done < "$current_phase_file"
                                    echo ""
                                fi
                            fi
                        elif [ -s "$current_phase_file" ]; then
                            # No planning, just activities (shouldn't happen but handle it)
                            local phase_searches phase_fetches phase_saves phase_greps
                            phase_searches=$(grep -c "🔍 Web Search:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                            phase_fetches=$(grep -c "📄 Fetching:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                            phase_saves=$(grep -c "💾 Saving:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                            phase_greps=$(grep -c "🔎 Searching for:" "$current_phase_file" 2>/dev/null | tr -d '\n' || echo "0")
                            
                            local phase_parts=()
                            [ "$phase_searches" -gt 0 ] && phase_parts+=("$phase_searches searches")
                            [ "$phase_fetches" -gt 0 ] && phase_parts+=("$phase_fetches pages fetched")
                            [ "$phase_saves" -gt 0 ] && phase_parts+=("$phase_saves documents saved")
                            [ "$phase_greps" -gt 0 ] && phase_parts+=("$phase_greps queries")
                            
                            if [ ${#phase_parts[@]} -gt 0 ]; then
                                local phase_summary
                                phase_summary=$(IFS=" • "; echo "${phase_parts[*]}")
                                
                                echo "**🔗 Actions:** $phase_summary"
                                echo ""
                                echo "> [!note]- View detailed activity log"
                                echo ">"
                                while IFS= read -r log_line; do
                                    echo "> $log_line"
                                done < "$current_phase_file"
                                echo ""
                            fi
                        fi
                        
                        # Cleanup
                        rm -f "$current_phase_file"
                    fi
                    
                    echo "**📊 Results:**"
                    echo ""
                    echo "- Duration: ${duration_sec}s"
                    
                    # Extract metadata summary
                    local metadata_keys
                    metadata_keys=$(echo "$line" | jq -r '.data | keys | .[] | select(. != "agent" and . != "duration_ms" and . != "cost_usd" and . != "reasoning" and . != "model")' 2>/dev/null)
                    
                    if [ -n "$metadata_keys" ]; then
                        while IFS= read -r key; do
                            local value
                            value=$(echo "$line" | jq -r ".data.${key}" 2>/dev/null)
                            # Format key name (convert snake_case to Title Case with context-appropriate labels)
                            local formatted_key
                            case "$key" in
                                claims_found)
                                    formatted_key="Claims investigated"
                                    ;;
                                papers_found)
                                    formatted_key="Papers consulted"
                                    ;;
                                searches_performed)
                                    formatted_key="Searches performed"
                                    ;;
                                sources_found)
                                    formatted_key="Sources Found"
                                    ;;
                                *)
                                    formatted_key=$(echo "$key" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')
                                    ;;
                            esac
                            echo "- $formatted_key: $value"
                        done <<< "$metadata_keys"
                    fi
                    echo ""
                    
                    # Show technical details in collapsed section after results
                    if [ "$model" != "unknown" ]; then
                        local tools
                        tools=$(echo "$line" | jq -r '.data.tools // "N/A"' 2>/dev/null || echo "N/A")
                        echo "> [!note]- ⚙️ Configuration"
                        echo ">"
                        echo "> - Model: \`$model\`"
                        [ "$tools" != "N/A" ] && echo "> - Tools: \`$tools\`"
                        echo ""
                    fi
                    
                    # Display reasoning from any agent that provides it
                    local reasoning
                    reasoning=$(echo "$line" | jq -c '.data.reasoning // empty' 2>/dev/null)
                    
                    if [ -n "$reasoning" ] && [ "$reasoning" != "null" ]; then
                        # Extract components for summary
                        local synthesis_approach gap_prioritization
                        synthesis_approach=$(echo "$reasoning" | jq -r '.synthesis_approach // empty' 2>/dev/null)
                        gap_prioritization=$(echo "$reasoning" | jq -r '.gap_prioritization // empty' 2>/dev/null)
                        
                        # Create one-line summary from first available field
                        local reasoning_summary=""
                        if [ -n "$synthesis_approach" ]; then
                            reasoning_summary=$(extract_first_sentence "$synthesis_approach")
                        elif [ -n "$gap_prioritization" ]; then
                            reasoning_summary=$(extract_first_sentence "$gap_prioritization")
                        else
                            reasoning_summary="Research reasoning available"
                        fi
                        
                        echo "**🧠 Research Reasoning:** $reasoning_summary"
                        echo ""
                        echo "#### Detailed Reasoning"
                        echo ""
                        
                        if [ -n "$synthesis_approach" ]; then
                            echo "**Current situation:** $synthesis_approach"
                            echo ""
                        fi
                        
                        if [ -n "$gap_prioritization" ]; then
                            echo "**Focus areas:** $gap_prioritization"
                            echo ""
                        fi
                        
                        local key_insights_count
                        key_insights_count=$(echo "$reasoning" | jq '.key_insights // [] | length' 2>/dev/null)
                        if [ "$key_insights_count" -gt 0 ]; then
                            echo "**Key insights:**"
                            echo "$reasoning" | jq -r '.key_insights // [] | .[] | "- \(.)"' 2>/dev/null
                            echo ""
                        fi
                        
                        local strategic_decisions_count
                        strategic_decisions_count=$(echo "$reasoning" | jq '.strategic_decisions // [] | length' 2>/dev/null)
                        if [ "$strategic_decisions_count" -gt 0 ]; then
                            echo "**Strategic decisions:**"
                            echo "$reasoning" | jq -r '.strategic_decisions // [] | .[] | "- \(.)"' 2>/dev/null
                            echo ""
                        fi
                    fi
                    
                    # Find and include detailed findings
                    case "$agent" in
                        mission-orchestrator)
                            # Look for coordinator output with gap analysis in intermediate directory
                            local coordinator_file
                            coordinator_file=$(find "$session_dir/intermediate" "$session_dir/raw" -name "*coordinator*output*.json" 2>/dev/null | tail -1)
                            
                            if [ -n "$coordinator_file" ] && [ -f "$coordinator_file" ]; then
                                # Extract the actual result JSON from the wrapper
                                local result_json
                                # shellcheck disable=SC2016
                                result_json=$(jq -r '.result // empty' "$coordinator_file" 2>/dev/null | sed 's/^```json\s*//;s/\s*```$//')
                                
                                # Extract and show reasoning first from the parsed result
                                if [ -n "$result_json" ] && echo "$result_json" | jq -e '.reasoning' >/dev/null 2>&1; then
                                    echo "> [!NOTE]"
                                    echo "> **🧠 Coordination Reasoning**"
                                    echo ">"
                                    
                                    local synthesis_approach
                                    synthesis_approach=$(echo "$result_json" | jq -r '.reasoning.synthesis_approach // empty' 2>/dev/null)
                                    if [ -n "$synthesis_approach" ]; then
                                        echo "> *Synthesis Approach:* $synthesis_approach"
                                        echo ">"
                                    fi
                                    
                                    local gap_prioritization
                                    gap_prioritization=$(echo "$result_json" | jq -r '.reasoning.gap_prioritization // empty' 2>/dev/null)
                                    if [ -n "$gap_prioritization" ]; then
                                        echo "> *Gap Prioritization:* $gap_prioritization"
                                        echo ">"
                                    fi
                                    
                                    local key_insights_count
                                    key_insights_count=$(echo "$result_json" | jq '.reasoning.key_insights // [] | length' 2>/dev/null)
                                    if [ "$key_insights_count" -gt 0 ]; then
                                        echo "> *Key Insights:*"
                                        echo "$result_json" | jq -r '.reasoning.key_insights // [] | .[] | "> - \(.)"' 2>/dev/null
                                        echo ">"
                                    fi
                                    
                                    local strategic_decisions_count
                                    strategic_decisions_count=$(echo "$result_json" | jq '.reasoning.strategic_decisions // [] | length' 2>/dev/null)
                                    if [ "$strategic_decisions_count" -gt 0 ]; then
                                        echo "> *Strategic Decisions:*"
                                        echo "$result_json" | jq -r '.reasoning.strategic_decisions // [] | .[] | "> - \(.)"' 2>/dev/null
                                        echo ""
                                    fi
                                fi
                                
                                echo "#### 🔍 Gap Analysis"
                                echo ""
                                
                                # Extract gaps from the parsed result
                                local gaps_count
                                gaps_count=$(echo "$result_json" | jq '[.knowledge_graph_updates.gaps_detected // [], .next_steps // []] | length' 2>/dev/null || echo "0")
                                if [ "$gaps_count" -gt 0 ]; then
                                    echo "**Research Gaps Identified:**"
                                    echo ""
                                    echo "$result_json" | jq -r '([.knowledge_graph_updates.gaps_detected // [], .next_steps // []] | .[] | "- **Priority \(.priority // "medium")**: \(.gap_description // .description // .query)\n  - Rationale: \(.rationale // "No rationale provided")")' 2>/dev/null
                                    echo ""
                                fi
                                
                                # Extract contradictions from the parsed result
                                local contradictions_count
                                contradictions_count=$(echo "$result_json" | jq '[.knowledge_graph_updates.contradictions_detected // []] | length' 2>/dev/null || echo "0")
                                if [ "$contradictions_count" -gt 0 ]; then
                                    echo "**Contradictions Detected:**"
                                    echo ""
                                    echo "$result_json" | jq -r '(.knowledge_graph_updates.contradictions_detected // []) | .[] | "- \(.description)\n  - Claims in conflict: \(.conflicting_claims | length)"' 2>/dev/null
                                    echo ""
                                fi
                            fi
                            ;;
                            
                        research-planner)
                            # Show the initial research plan
                            local planner_file
                            planner_file=$(find "$session_dir/raw" -name "*planner*output*.json" -o -name "planning-output.json" 2>/dev/null | tail -1)
                            
                            if [ -n "$planner_file" ] && [ -f "$planner_file" ]; then
                                echo "#### 📋 Research Plan"
                                echo ""
                                
                                # Extract the actual result JSON from the wrapper
                                local result_json
                                # shellcheck disable=SC2016
                                result_json=$(jq -r '.result // empty' "$planner_file" 2>/dev/null | sed 's/^```json\s*//;s/\s*```$//')
                                
                                # Extract and show reasoning from the parsed result
                                if [ -n "$result_json" ] && echo "$result_json" | jq -e '.reasoning' >/dev/null 2>&1; then
                                    echo "> [!NOTE]"
                                    echo "> **🧠 Planning Reasoning:**"
                                    echo ">"
                                    local strategy
                                    strategy=$(echo "$result_json" | jq -r '.reasoning.strategy // empty' 2>/dev/null)
                                    if [ -n "$strategy" ]; then
                                        echo "> *Strategy:* $strategy"
                                        echo ">"
                                    fi
                                    
                                    local key_decisions
                                    key_decisions=$(echo "$result_json" | jq -r '.reasoning.key_decisions // [] | length' 2>/dev/null)
                                    if [ "$key_decisions" -gt 0 ]; then
                                        echo "> *Key Decisions:*"
                                        echo "$result_json" | jq -r '.reasoning.key_decisions // [] | .[] | "> - \(.)"' 2>/dev/null
                                        echo ">"
                                    fi
                                    
                                    local rationale
                                    rationale=$(echo "$result_json" | jq -r '.reasoning.task_ordering_rationale // empty' 2>/dev/null)
                                    if [ -n "$rationale" ]; then
                                        echo "> *Task Ordering:* $rationale"
                                        echo ""
                                    fi
                                fi
                                
                                # Extract tasks from the parsed result
                                if [ -n "$result_json" ]; then
                                    local tasks
                                    tasks=$(echo "$result_json" | jq -c '.initial_tasks // .tasks // []' 2>/dev/null)
                                    if [ "$tasks" != "[]" ] && [ -n "$tasks" ]; then
                                        echo "**Tasks Generated:**"
                                        echo ""
                                        echo "$tasks" | jq -r '.[] | "- **Task \(.id // "?")** (\(.agent)): \(.query)\n  - Priority: \(.priority // "medium"), Type: \(.task_type // .research_type // "unknown")"' 2>/dev/null
                                        echo ""
                                    fi
                                fi
                            fi
                            ;;
                            
                        synthesis-agent)
                            # Show synthesis output
                            local synthesis_file
                            synthesis_file=$(find "$session_dir/raw" -name "*synthesis*output*.json" 2>/dev/null | tail -1)
                            
                            if [ -n "$synthesis_file" ] && [ -f "$synthesis_file" ]; then
                                echo "#### 📝 Synthesis Analysis"
                                echo ""
                                
                                # Extract key themes
                                local themes_count
                                themes_count=$(jq '[.synthesis.key_themes // []] | length' "$synthesis_file" 2>/dev/null || echo "0")
                                if [ "$themes_count" -gt 0 ]; then
                                    echo "**Key Themes:**"
                                    echo ""
                                    jq -r '(.synthesis.key_themes // []) | .[] | "- \(.)"' "$synthesis_file" 2>/dev/null
                                    echo ""
                                fi
                                
                                # Extract remaining gaps
                                local remaining_gaps
                                remaining_gaps=$(jq '[.synthesis.remaining_gaps // []] | length' "$synthesis_file" 2>/dev/null || echo "0")
                                if [ "$remaining_gaps" -gt 0 ]; then
                                    echo "**Remaining Knowledge Gaps:**"
                                    echo ""
                                    jq -r '(.synthesis.remaining_gaps // []) | .[] | "- \(.)"' "$synthesis_file" 2>/dev/null
                                    echo ""
                                fi
                            fi
                            ;;
                    esac
                    
                    echo "---"
                    echo ""
                    ;;
                    
                task_started)
                    if [ "$NEED_TASK_SECTION_HEADER" = "true" ]; then
                        echo "### Research Tasks"
                        echo ""
                        NEED_TASK_SECTION_HEADER=false
                    fi
                    
                    local task_id agent query
                    task_id=$(echo "$line" | jq -r '.data.task_id // "unknown"')
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    query=$(echo "$line" | jq -r '.data.query // "N/A"')
                    
                    echo "#### $query"
                    echo ""
                    echo "*Initiated $formatted_time*"
                    echo ""
                    ;;
                    
                task_completed)
                    local task_id duration
                    task_id=$(echo "$line" | jq -r '.data.task_id // "unknown"')
                    duration=$(echo "$line" | jq -r '.data.duration // 0')
                    
                    echo "*Completed after ${duration}s*"
                    echo ""
                    
                    # Look for findings file for this specific task
                    local findings_file="$session_dir/raw/findings-${task_id}.json"
                    
                    if [ -f "$findings_file" ]; then
                        # Check if this file has any content
                        if jq -e '(.entities_discovered // [] | length) > 0 or (.claims // [] | length) > 0' "$findings_file" >/dev/null 2>&1; then
                            echo "#### 📊 Research Findings for $task_id"
                            echo ""
                            
                            # Extract entities
                            local entities_count
                            entities_count=$(jq '(.entities_discovered // []) | length' "$findings_file" 2>/dev/null || echo "0")
                            if [ "$entities_count" -gt 0 ]; then
                                echo "**Entities Discovered ($entities_count):**"
                                echo ""
                                jq -r '(.entities_discovered // []) | .[] | "- **\(.name)** (\(.type)): \(.description)\n  _Confidence: \((.confidence // 0) * 100 | floor)%_"' "$findings_file" 2>/dev/null
                                echo ""
                            fi
                            
                            # Extract claims
                            local claims_count
                            claims_count=$(jq '(.claims // []) | length' "$findings_file" 2>/dev/null || echo "0")
                            if [ "$claims_count" -gt 0 ]; then
                                # Limit to first 10 for brevity
                                local display_count=$((claims_count > 10 ? 10 : claims_count))
                                echo "**Claims Validated ($claims_count total, showing first $display_count):**"
                                echo ""
                                jq -r '(.claims // []) | .[0:10] | .[] | "- \(.statement)\n  - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence: \(.evidence_quality // "unknown")\n  - Sources: \(.sources | length)"' "$findings_file" 2>/dev/null
                                echo ""
                            fi
                            
                            # Show top sources with details
                            if jq -e '(.claims // []) | length > 0 and (.[0].sources // [] | length) > 0' "$findings_file" >/dev/null 2>&1; then
                                echo "**Key Sources:**"
                                echo ""
                                jq -r '
                                    def format_credibility:
                                        gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                                    ([.claims // [] | .[].sources // [] | .[]] | unique_by(.url) | .[0:8] | .[] | 
                                    "- [\(.title)](\(.url))\n  - Credibility: \((.credibility // "unknown") | format_credibility)")
                                ' "$findings_file" 2>/dev/null
                                echo ""
                            fi
                            
                            # Show gaps if any
                            local gaps_count
                            gaps_count=$(jq '[.gaps_identified // []] | length' "$findings_file" 2>/dev/null || echo "0")
                            if [ "$gaps_count" -gt 0 ]; then
                                echo "**Gaps Identified:**"
                                echo ""
                                jq -r '(.gaps_identified // []) | .[] | if type == "object" then "- **Priority \(.priority // "?")**: \(.question // .gap_description // .description)\n  _Reason: \(.reason // .rationale // "Not specified")_" else "- \(.)" end' "$findings_file" 2>/dev/null
                                echo ""
                            fi
                            
                            echo "---"
                            echo ""
                        fi
                    fi
                    ;;
                    
                task_failed)
                    local task_id
                    task_id=$(echo "$line" | jq -r '.data.task_id // "unknown"')
                    local error
                    error=$(echo "$line" | jq -r '.data.error // "Unknown error"')
                    local recoverable
                    recoverable=$(echo "$line" | jq -r '.data.recoverable // "false"')
                    
                    echo "**❌ Task Failed:** $formatted_time"
                    echo ""
                    echo "**Error:** $error  "
                    echo "**Recoverable:** $recoverable"
                    echo ""
                    ;;
                    
                iteration_complete)
                    local iteration total_entities total_claims
                    iteration=$(echo "$line" | jq -r '.data.iteration // "?"')
                    total_entities=$(echo "$line" | jq -r '.data.stats.total_entities // 0')
                    total_claims=$(echo "$line" | jq -r '.data.stats.total_claims // 0')
                    
                    echo "## Research Cycle $iteration Complete"
                    echo ""
                    echo "*$formatted_time*"
                    echo ""
                    echo "Current knowledge base: $total_entities entities documented, $total_claims claims validated."
                    echo ""
                    echo "---"
                    echo ""
                    
                    NEED_TASK_SECTION_HEADER=true
                    ;;
                    
                research_complete)
                    local claims
                    claims=$(echo "$line" | jq -r '.data.claims_synthesized // 0')
                    local entities
                    entities=$(echo "$line" | jq -r '.data.entities_integrated // 0')
                    local sections
                    sections=$(echo "$line" | jq -r '.data.report_sections // 0')
                    local report_file
                    report_file=$(echo "$line" | jq -r '.data.report_file // "final/mission-report.md"')
                    
                    echo "## 🎉 Research Complete"
                    echo ""
                    echo "**Time:** $formatted_time"
                    echo ""
                    echo "Final research report generated with:"
                    echo "- **Report Sections:** $sections"
                    echo "- **Claims Synthesized:** $claims"
                    echo "- **Entities Integrated:** $entities"
                    echo ""
                    echo "📄 **[View Final Report]($report_file)**"
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                
                mission_completed)
                    local report_file
                    report_file=$(echo "$line" | jq -r '.data.report_file // "final/mission-report.md"')
                    
                    # Get final stats from knowledge graph
                    local kg_file="$session_dir/knowledge-graph.json"
                    local claims=0 entities=0 citations=0
                    if [ -f "$kg_file" ]; then
                        claims=$(jq -r '.stats.total_claims // 0' "$kg_file" 2>/dev/null || echo "0")
                        entities=$(jq -r '.stats.total_entities // 0' "$kg_file" 2>/dev/null || echo "0")
                        citations=$(jq -r '.stats.total_citations // 0' "$kg_file" 2>/dev/null || echo "0")
                    fi
                    
                    echo "## Research Investigation Complete"
                    echo ""
                    echo "*$formatted_time*"
                    echo ""
                    echo "Mission concluded successfully. Final knowledge base contains $entities documented entities, $claims validated claims, and $citations source citations."
                    echo ""
                    echo "**Final Report:** [$report_file]($report_file)"
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                    
                tool_use_start)
                    local tool
                    tool=$(echo "$line" | jq -r '.data.tool // "unknown"')
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local input_summary
                    input_summary=$(echo "$line" | jq -r '.data.input_summary // ""')
                    
                    # Accumulate tool activity to temp file (hide internal operations)
                    case "$tool" in
                        WebSearch)
                            if [ -n "$input_summary" ]; then
                                echo "  🔍 Web Search: \"$input_summary\"" >> "$tool_log_file"
                                # Increment counter
                                local count
                                count=$(jq -r '.searches // 0' "$tool_counts_file" 2>/dev/null || echo "0")
                                jq --arg count "$((count + 1))" '.searches = ($count | tonumber)' "$tool_counts_file" > "$tool_counts_file.tmp" && mv "$tool_counts_file.tmp" "$tool_counts_file"
                            fi
                            ;;
                        WebFetch)
                            if [ -n "$input_summary" ]; then
                                echo "  📄 Fetching: <$input_summary>" >> "$tool_log_file"
                                # Increment counter
                                local count
                                count=$(jq -r '.fetches // 0' "$tool_counts_file" 2>/dev/null || echo "0")
                                jq --arg count "$((count + 1))" '.fetches = ($count | tonumber)' "$tool_counts_file" > "$tool_counts_file.tmp" && mv "$tool_counts_file.tmp" "$tool_counts_file"
                            fi
                            ;;
                        TodoWrite)
                            if [ -n "$input_summary" ] && [[ "$input_summary" != "tasks" ]]; then
                                echo "  📋 Planning: $input_summary" >> "$tool_log_file"
                                # Increment counter
                                local count
                                count=$(jq -r '.plans // 0' "$tool_counts_file" 2>/dev/null || echo "0")
                                jq --arg count "$((count + 1))" '.plans = ($count | tonumber)' "$tool_counts_file" > "$tool_counts_file.tmp" && mv "$tool_counts_file.tmp" "$tool_counts_file"
                            fi
                            ;;
                        Write|Edit|MultiEdit)
                            # Only show research-facing file writes
                            if [[ "$input_summary" =~ findings-|mission-report|research-|synthesis- ]]; then
                                local relative_path
                                relative_path=$(make_path_relative "$input_summary" "$session_dir")
                                echo "  💾 Saving: $relative_path" >> "$tool_log_file"
                                # Increment counter
                                local count
                                count=$(jq -r '.saves // 0' "$tool_counts_file" 2>/dev/null || echo "0")
                                jq --arg count "$((count + 1))" '.saves = ($count | tonumber)' "$tool_counts_file" > "$tool_counts_file.tmp" && mv "$tool_counts_file.tmp" "$tool_counts_file"
                            fi
                            ;;
                        Grep)
                            if [ -n "$input_summary" ]; then
                                echo "  🔎 Searching for: $input_summary" >> "$tool_log_file"
                                # Increment counter
                                local count
                                count=$(jq -r '.greps // 0' "$tool_counts_file" 2>/dev/null || echo "0")
                                jq --arg count "$((count + 1))" '.greps = ($count | tonumber)' "$tool_counts_file" > "$tool_counts_file.tmp" && mv "$tool_counts_file.tmp" "$tool_counts_file"
                            fi
                            ;;
                        Glob)
                            if [ -n "$input_summary" ]; then
                                echo "  📁 Finding files: $input_summary" >> "$tool_log_file"
                            fi
                            ;;
                        Bash|TodoRead)
                            # Hide internal operations
                            ;;
                    esac
                    ;;
                    
                tool_use_complete)
                    # Tool completions are logged but results aren't captured in events
                    # Individual tool results are aggregated in task findings files
                    # So we skip rendering individual tool completions to avoid clutter
                    ;;
                    
                *)
                    # Other event types can be added here
                    ;;
            esac
        done < "$events_file"
        
        # Add research knowledge map section
        echo ""
        echo "---"
        echo ""
        echo "## Research Knowledge Map"
        echo ""
        
        # Find findings files and calculate statistics
        local total_entities=0 total_claims=0 total_sources=0 total_gaps=0
        
        if [ -d "$session_dir/raw" ]; then
            # Count totals
            total_entities=$(get_findings_stats "$session_dir" "entities")
            total_claims=$(get_findings_stats "$session_dir" "claims")
            total_sources=$(get_findings_stats "$session_dir" "sources")
            total_gaps=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '[.gaps_identified // [] | .[]] | length' 2>/dev/null | \
                awk '{sum+=$1} END {print sum+0}')
            
            total_entities=${total_entities:-0}
            total_claims=${total_claims:-0}
            total_sources=${total_sources:-0}
            total_gaps=${total_gaps:-0}
            
            echo "Throughout this investigation, the research agents accumulated **${total_entities} entities**, validated **${total_claims} claims**, and consulted **${total_sources} authoritative sources**."
            echo ""
            
            # Coverage assessment based on entity types and claims
            if [ "$total_entities" -gt 0 ] || [ "$total_claims" -gt 0 ]; then
                echo "**Coverage Assessment:**"
                echo ""
                
                # Detect coverage areas from entity types
                local has_concepts has_papers has_technology
                has_concepts=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.entities_discovered[]? | select(.type == "concept") | .name' 2>/dev/null | head -1)
                has_papers=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.entities_discovered[]? | select(.type == "paper") | .name' 2>/dev/null | head -1)
                has_technology=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.entities_discovered[]? | select(.type == "technology") | .name' 2>/dev/null | head -1)
                
                [ -n "$has_concepts" ] && echo "✓ Theoretical foundations documented"
                [ -n "$has_papers" ] && echo "✓ Academic literature reviewed"
                [ -n "$has_technology" ] && echo "✓ Technologies and implementations analyzed"
                [ "$total_claims" -gt 10 ] && echo "✓ Multiple perspectives incorporated"
                [ "$total_sources" -gt 5 ] && echo "✓ Cross-validated across authoritative sources"
                
                if [ "$total_gaps" -gt 0 ]; then
                    echo "⚠ $total_gaps knowledge gaps identified for future research"
                fi
                echo ""
            fi
            
            # Show top priority research gaps (top 10)
            if [ "$total_gaps" -gt 0 ]; then
                echo "**Top Priority Research Gaps:**"
                echo ""
                find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.gaps_identified // [] | .[]' 2>/dev/null | \
                    jq -sr 'sort_by(.priority // 0) | reverse | .[0:10] | .[] | 
                        "\(.priority // 0). **\(.question // .gap_description // .description)**\n   - \(.reason // .rationale // "No rationale provided")\n"' 2>/dev/null
                
                if [ "$total_gaps" -gt 10 ]; then
                    echo ""
                    echo "> [!note]- View all gaps identified ($total_gaps total)"
                    echo ">"
                    find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                        xargs -0 jq -r '.gaps_identified // [] | .[] | 
                            "> - **\(.question // .gap_description // .description)**\n>   - Priority: \(.priority // 0), Reason: \(.reason // .rationale // \"Not specified\")\n>"' 2>/dev/null
                fi
                echo ""
            fi
            
            # Show detailed findings (visible by default)
            if [ "$total_entities" -gt 0 ] || [ "$total_claims" -gt 0 ]; then
                echo ""
                
                # Entities
                if [ "$total_entities" -gt 0 ]; then
                    echo "### Entities Discovered"
                    echo ""
                    find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | xargs -0 jq -r '
                        .entities_discovered // [] | .[] | 
                        "- **\(.name)** (\(.type)): \(.description)\n  _Confidence: \((.confidence // 0) * 100 | floor)%_\n"
                    ' 2>/dev/null
                    echo ""
                fi
                
                # Claims (show first 20, rest collapsed if more)
                if [ "$total_claims" -gt 0 ]; then
                    echo "### Claims Validated"
                    echo ""
                    
                    if [ "$total_claims" -le 20 ]; then
                        # Show all claims if 20 or fewer
                        # shellcheck disable=SC2016
                        find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | xargs -0 jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            .claims // [] | .[] | 
                            "- \(.statement)\n  - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence Quality: \(.evidence_quality // "unknown")\n  - Sources:\n\((.sources // [] | .[0:3] | .[] | "    - [\(.title)](\(.url)) (\(.credibility // "unknown" | format_credibility)\(.date // "" | if . != "" then ", " + . else "" end))"))\n"
                        ' 2>/dev/null
                    else
                        # Show first 20, collapse the rest
                        # shellcheck disable=SC2016
                        find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | xargs -0 jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            .claims // [] | .[] | 
                            "- \(.statement)\n  - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence Quality: \(.evidence_quality // "unknown")\n  - Sources:\n\((.sources // [] | .[0:3] | .[] | "    - [\(.title)](\(.url)) (\(.credibility // "unknown" | format_credibility)\(.date // "" | if . != "" then ", " + . else "" end))"))\n"
                        ' 2>/dev/null | head -120
                        
                        echo ""
                        echo "> [!note]- View all claims ($total_claims total)"
                        echo ">"
                        # shellcheck disable=SC2016
                        find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | xargs -0 jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            .claims // [] | .[] | 
                            "> - \(.statement)\n>   - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence Quality: \(.evidence_quality // \"unknown\")\n>   - Sources:\n\((.sources // [] | .[0:3] | .[] | \">     - [\(.title)](\(.url)) (\(.credibility // \"unknown\" | format_credibility)\(.date // \"\" | if . != \"\" then \", \" + . else \"\" end))\"))\n>"
                        ' 2>/dev/null | tail -n +121
                    fi
                    echo ""
                fi
                
                # Key Sources (show first 30, rest collapsed if more)
                if [ "$total_sources" -gt 0 ]; then
                    echo "### Key Sources"
                    echo ""
                    local temp_sources="/tmp/sources-$$.json"
                    find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                        xargs -0 jq -s '[.[] | .claims // [] | .[].sources // [] | .[]] | unique_by(.title)' > "$temp_sources" 2>/dev/null
                    
                    if [ "$total_sources" -le 30 ]; then
                        # Show all sources if 30 or fewer
                        # shellcheck disable=SC2016
                        jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            def construct_url:
                                if .url and .url != null and .url != "" then .url
                                elif .pmid and .pmid != null and .pmid != "" then "https://pubmed.ncbi.nlm.nih.gov/\(.pmid)/"
                                elif .doi and .doi != null and .doi != "" then "https://doi.org/\(.doi)"
                                else null
                                end;
                            .[] | select(construct_url != null) | 
                            "- [\(.title)](\(construct_url))\n  - Credibility: \((.credibility // "unknown") | format_credibility)\n"
                        ' "$temp_sources" 2>/dev/null
                    else
                        # Show first 30, collapse the rest
                        # shellcheck disable=SC2016
                        jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            def construct_url:
                                if .url and .url != null and .url != "" then .url
                                elif .pmid and .pmid != null and .pmid != "" then "https://pubmed.ncbi.nlm.nih.gov/\(.pmid)/"
                                elif .doi and .doi != null and .doi != "" then "https://doi.org/\(.doi)"
                                else null
                                end;
                            .[] | select(construct_url != null) | 
                            "- [\(.title)](\(construct_url))\n  - Credibility: \((.credibility // "unknown") | format_credibility)\n"
                        ' "$temp_sources" 2>/dev/null | head -90
                        
                        echo ""
                        echo "> [!note]- View all sources ($total_sources total)"
                        echo ">"
                        # shellcheck disable=SC2016
                        jq -r '
                            def format_credibility:
                                gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                            def construct_url:
                                if .url and .url != null and .url != "" then .url
                                elif .pmid and .pmid != null and .pmid != "" then "https://pubmed.ncbi.nlm.nih.gov/\(.pmid)/"
                                elif .doi and .doi != null and .doi != "" then "https://doi.org/\(.doi)"
                                else null
                                end;
                            .[] | select(construct_url != null) | 
                            "> - [\(.title)](\(construct_url))\n>   - Credibility: \((.credibility // \"unknown\") | format_credibility)\n>"
                        ' "$temp_sources" 2>/dev/null | tail -n +91
                    fi
                    
                    rm -f "$temp_sources"
                    echo ""
                fi
            fi
        else
            echo "No findings data available for this session."
        fi
        
        echo ""
        
        # Add comprehensive research summary at the end
        echo "---"
        echo ""
        echo "## Research Summary"
        echo ""
        
        # Load metrics from various sources
        local dashboard_metrics="$session_dir/dashboard-metrics.json"
        local kg_file="$session_dir/knowledge-graph.json"
        
        # Calculate duration
        local start_time end_time duration_minutes
        start_time=$(jq -r '.created_at // ""' "$session_file" 2>/dev/null)
        end_time=$(jq -r '.completed_at // ""' "$session_file" 2>/dev/null)
        
        if [ -n "$start_time" ] && [ -n "$end_time" ] && [ "$end_time" != "" ]; then
            local start_epoch end_epoch duration_seconds
            start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" "+%s" 2>/dev/null || echo "0")
            end_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$end_time" "+%s" 2>/dev/null || echo "0")
            duration_seconds=$((end_epoch - start_epoch))
            duration_minutes=$((duration_seconds / 60))
        fi
        
        # Get iteration count and entity/claim counts
        local iterations entities claims sources
        if [ -f "$dashboard_metrics" ]; then
            iterations=$(jq -r '.iteration // 0' "$dashboard_metrics" 2>/dev/null)
            entities=$(jq -r '.knowledge.entities // 0' "$dashboard_metrics" 2>/dev/null)
            claims=$(jq -r '.knowledge.claims // 0' "$dashboard_metrics" 2>/dev/null)
        elif [ -f "$kg_file" ]; then
            entities=$(jq -r '.stats.total_entities // 0' "$kg_file" 2>/dev/null)
            claims=$(jq -r '.stats.total_claims // 0' "$kg_file" 2>/dev/null)
        fi
        
        # Count unique sources from findings files
        sources=0
        if [ -d "$session_dir/raw" ]; then
            sources=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '.claims[]?.sources[]?.url // empty' 2>/dev/null | sort -u | wc -l | tr -d ' ')
        fi
        
        # Build narrative summary
        if [ -n "$duration_minutes" ] && [ "$duration_minutes" -gt 0 ]; then
            echo "This investigation was completed in **$duration_minutes minutes**"
            if [ "$iterations" -gt 0 ]; then
                echo -n " across **$iterations research iterations**"
            fi
            if [ "$sources" -gt 0 ]; then
                echo -n ", consulting **$sources authoritative sources**"
            fi
            if [ "$claims" -gt 0 ]; then
                echo -n " to validate **$claims factual claims**"
            fi
            if [ "$entities" -gt 0 ]; then
                echo -n " about $entities key concepts"
            fi
            echo "."
        else
            # Fallback if timing not available
            if [ "$claims" -gt 0 ] && [ "$sources" -gt 0 ]; then
                echo "This investigation validated **$claims factual claims** from **$sources authoritative sources**"
                if [ "$entities" -gt 0 ]; then
                    echo " about $entities key concepts"
                fi
                echo "."
            fi
        fi
        
        echo ""
        
        # Quality assessment from findings
        if [ -d "$session_dir/raw" ]; then
            local avg_confidence
            avg_confidence=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                xargs -0 jq -r '[.claims[]?.confidence // 0] | add / length * 100 | floor' 2>/dev/null | head -1)
            
            if [ -n "$avg_confidence" ] && [ "$avg_confidence" -gt 0 ]; then
                echo "**Quality Assessment:**"
                echo "- Average confidence: ${avg_confidence}%"
                
                # Check evidence quality
                local high_quality_count
                high_quality_count=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '[.claims[]? | select(.evidence_quality == "high")] | length' 2>/dev/null | head -1)
                if [ -n "$high_quality_count" ] && [ "$high_quality_count" -gt 0 ]; then
                    echo "- Evidence quality: High"
                fi
                
                # List source types
                local has_official has_academic
                has_official=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.claims[]?.sources[]? | select(.credibility == "official") | .credibility' 2>/dev/null | head -1)
                has_academic=$(find "$session_dir/raw" -name "findings-*.json" -type f -print0 2>/dev/null | \
                    xargs -0 jq -r '.claims[]?.sources[]? | select(.credibility == "academic") | .credibility' 2>/dev/null | head -1)
                
                if [ -n "$has_official" ] || [ -n "$has_academic" ]; then
                    echo -n "- Sources: "
                    local source_desc=""
                    [ -n "$has_official" ] && source_desc="Official standards bodies"
                    [ -n "$has_academic" ] && [ -n "$source_desc" ] && source_desc="$source_desc, academic institutions" || source_desc="${source_desc}Academic institutions"
                    echo "$source_desc"
                fi
                
                echo ""
            fi
        fi
        
        # System health warnings (only if there were issues)
        if [ -f "$dashboard_metrics" ]; then
            local errors warnings
            errors=$(jq -r '.system_health.errors // 0' "$dashboard_metrics" 2>/dev/null)
            warnings=$(jq -r '.system_health.warnings // 0' "$dashboard_metrics" 2>/dev/null)
            
            if [ "$errors" -gt 0 ] || [ "$warnings" -gt 0 ]; then
                echo "> [!WARNING]"
                echo "> **Research Notes:** This investigation encountered $errors error(s) and $warnings warning(s)."
                
                # Show observations if available
                local observations
                observations=$(jq -r '.system_health.observations[]? // empty' "$dashboard_metrics" 2>/dev/null)
                if [ -n "$observations" ]; then
                    echo ">"
                    while IFS= read -r obs; do
                        echo "> - $obs"
                    done <<< "$observations"
                fi
                echo ""
            fi
        fi
        
        # Process observations based on measurable metrics
        if [ -f "$dashboard_metrics" ] || [ -d "$session_dir/raw" ]; then
            echo "**Process Observations:**"
            echo ""
            
            local observations_found=false
            
            # Efficiency observation: check if completed quickly
            if [ -n "$duration_minutes" ] && [ "$duration_minutes" -gt 0 ]; then
                if [ "$iterations" -gt 0 ]; then
                    local avg_iteration_time=$((duration_minutes / iterations))
                    if [ "$avg_iteration_time" -lt 10 ]; then
                        echo "- Research cycles completed efficiently (avg ${avg_iteration_time} min per cycle)"
                        observations_found=true
                    fi
                fi
            fi
            
            # Quality observation: high confidence
            if [ -n "$avg_confidence" ] && [ "$avg_confidence" -ge 85 ]; then
                echo "- High-confidence findings achieved (${avg_confidence}% average)"
                observations_found=true
            fi
            
            # Coverage observation: multiple sources
            if [ "$sources" -gt 20 ]; then
                echo "- Comprehensive source coverage ($sources sources consulted)"
                observations_found=true
            fi
            
            # Issue observation from dashboard metrics
            if [ -f "$dashboard_metrics" ]; then
                local errors warnings
                errors=$(jq -r '.system_health.errors // 0' "$dashboard_metrics" 2>/dev/null)
                warnings=$(jq -r '.system_health.warnings // 0' "$dashboard_metrics" 2>/dev/null)
                
                if [ "$errors" -gt 0 ]; then
                    echo "- Encountered $errors error(s) during research (see system logs)"
                    observations_found=true
                fi
            fi
            
            # Gap observation
            if [ "$total_gaps" -gt 15 ]; then
                echo "- Significant knowledge gaps identified ($total_gaps) suggesting complex topic"
                observations_found=true
            fi
            
            if [ "$observations_found" = false ]; then
                echo "- Research completed successfully"
            fi
            
            echo ""
        fi
        
        # Link to final report
        if [ -f "$session_dir/final/mission-report.md" ]; then
            echo "**Final Report:** [final/mission-report.md](final/mission-report.md)"
            echo ""
        fi
        
        echo "---"
        echo ""
        echo "*Generated by CConductor Research Journal Exporter*"
        
    } > "$output_file"
    
    # Display path relative to session directory
    local display_output="$output_file"
    if [[ "$output_file" == "$session_dir"* ]]; then
        display_output="${output_file#"$session_dir"}"
        display_output="${display_output#/}"
    elif command -v python3 >/dev/null 2>&1; then
        display_output=$(python3 - "$output_file" "$session_dir" <<'PY'
import os, sys
path = sys.argv[1]
session_dir = sys.argv[2]
try:
    print(os.path.relpath(path, session_dir))
except Exception:
    print(path)
PY
)
    fi
    echo "  ✓ Research journal exported to: $display_output" >&2
}

# Export function for sourcing
export -f export_journal

# Allow direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir> [output_file]" >&2
        echo "  session_dir: Path to research session directory" >&2
        echo "  output_file: Optional output path (default: <session_dir>/final/research-journal.md)" >&2
        exit 1
    fi
    
    export_journal "$@"
fi
