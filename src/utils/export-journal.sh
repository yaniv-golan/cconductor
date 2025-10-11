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

export_journal() {
    local session_dir="$1"
    local output_file="${2:-$session_dir/research-journal.md}"
    
    local events_file="$session_dir/events.jsonl"
    if [ ! -f "$events_file" ]; then
        echo "Error: events.jsonl not found in $session_dir" >&2
        return 1
    fi
    
    # Flag to track when we need a task section header after iteration
    local NEED_TASK_SECTION_HEADER=false
    
    # Get session metadata
    local session_file="$session_dir/session.json"
    local question="Unknown"
    local objective="Unknown"
    if [ -f "$session_file" ]; then
        question=$(jq -r '.question // "Unknown"' "$session_file" 2>/dev/null || echo "Unknown")
        objective=$(jq -r '.objective // .question // "Unknown"' "$session_dir/session.json" 2>/dev/null || echo "Unknown")
    fi
    
    # Load orchestration log for decision lookups
    local orchestration_log="$session_dir/orchestration-log.jsonl"
    local has_orchestration_log=false
    if [ -f "$orchestration_log" ]; then
        has_orchestration_log=true
    fi
    
    # Track current iteration for section markers
    local current_iteration=0
    
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
                    case "$agent" in
                        mission-orchestrator)
                            echo "### Strategic Planning"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            ;;
                        academic-researcher)
                            echo "### Academic Literature Review"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Consulting peer-reviewed academic sources to establish theoretical foundation."
                            echo ""
                            ;;
                        web-researcher)
                            echo "### Web Research"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Gathering information from web sources to complement academic findings."
                            echo ""
                            ;;
                        research-planner)
                            echo "### Research Planning"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Analyzing the research question to develop a structured investigation plan."
                            echo ""
                            ;;
                        synthesis-agent)
                            echo "### Synthesis and Integration"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Integrating findings from multiple sources to develop coherent understanding."
                            echo ""
                            ;;
                        pdf-analyzer)
                            echo "### Document Analysis"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Analyzing provided PDF documents for relevant information and insights."
                            echo ""
                            ;;
                        fact-checker)
                            echo "### Fact Verification"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Cross-referencing claims against multiple sources to ensure accuracy."
                            echo ""
                            ;;
                        market-analyzer|market-sizing-expert)
                            echo "### Market Analysis"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            echo "Evaluating market data and trends to inform business insights."
                            echo ""
                            ;;
                        *)
                            # Generic case for custom agents
                            local agent_display="${agent//-/ }"
                            echo "### ${agent_display^} Analysis"
                            echo ""
                            echo "*$formatted_time*"
                            echo ""
                            ;;
                    esac
                    
                    # Show technical details in collapsed section if model is known
                    if [ "$model" != "unknown" ]; then
                        echo "<details><summary>Technical details</summary>"
                        echo ""
                        echo "- Model: \`$model\`"
                        echo "- Tools: \`$tools\`"
                        echo ""
                        echo "</details>"
                        echo ""
                    fi
                    
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
                                echo "<details><summary>Research strategy</summary>"
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
                                echo "</details>"
                                echo ""
                            fi
                        fi
                    fi
                    
                    # Show orchestration reasoning for mission-orchestrator (keep existing logic for backward compatibility)
                    if [ "$agent" = "mission-orchestrator" ] && [ "$has_orchestration_log" = true ]; then
                        local decision_entry timestamp_minute
                        timestamp_minute="${clean_timestamp%:??Z}"
                        decision_entry=$(grep "$timestamp_minute" "$orchestration_log" 2>/dev/null | head -1)
                        
                        if [ -n "$decision_entry" ]; then
                            local decision_type rationale expected_impact
                            decision_type=$(echo "$decision_entry" | jq -r '.decision.type // "decision"' 2>/dev/null)
                            rationale=$(echo "$decision_entry" | jq -r '.decision.rationale // ""' 2>/dev/null)
                            expected_impact=$(echo "$decision_entry" | jq -r '.decision.expected_impact // ""' 2>/dev/null)
                            
                            if [ -n "$rationale" ]; then
                                echo "> [!NOTE]"
                                echo "> **Orchestration Decision: $decision_type**"
                                echo ">"
                                echo "> *Rationale:* $rationale"
                                
                                # Show expected impact
                                if [ -n "$expected_impact" ]; then
                                    echo ">"
                                    echo "> *Expected Impact:* $expected_impact"
                                fi
                                
                                echo ""
                            fi
                        fi
                    fi
                    ;;
                    
                agent_result)
                    local agent duration
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    duration=$(echo "$line" | jq -r '.data.duration_ms // 0')
                    local duration_sec=$((duration / 1000))
                    
                    echo "*Analysis completed in ${duration_sec}s*"
                    echo ""
                    
                    # Extract metadata summary
                    local metadata_keys
                    metadata_keys=$(echo "$line" | jq -r '.data | keys | .[] | select(. != "agent" and . != "duration_ms" and . != "cost_usd" and . != "reasoning" and . != "model")' 2>/dev/null)
                    
                    if [ -n "$metadata_keys" ]; then
                        echo "**Research Activity:**"
                        echo ""
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
                                *)
                                    formatted_key=$(echo "$key" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')
                                    ;;
                            esac
                            echo "- **$formatted_key:** $value"
                        done <<< "$metadata_keys"
                        echo ""
                    fi
                    
                    # Display reasoning from any agent that provides it
                    local reasoning
                    reasoning=$(echo "$line" | jq -c '.data.reasoning // empty' 2>/dev/null)
                    
                    if [ -n "$reasoning" ] && [ "$reasoning" != "null" ]; then
                        echo "> [!NOTE]"
                        echo "> **🧠 Research Reasoning**"
                        echo ">"
                        
                        local synthesis_approach
                        synthesis_approach=$(echo "$reasoning" | jq -r '.synthesis_approach // empty' 2>/dev/null)
                        if [ -n "$synthesis_approach" ]; then
                            echo "> *Approach:* $synthesis_approach"
                            echo ">"
                        fi
                        
                        local gap_prioritization
                        gap_prioritization=$(echo "$reasoning" | jq -r '.gap_prioritization // empty' 2>/dev/null)
                        if [ -n "$gap_prioritization" ]; then
                            echo "> *Priority:* $gap_prioritization"
                            echo ">"
                        fi
                        
                        local key_insights_count
                        key_insights_count=$(echo "$reasoning" | jq '.key_insights // [] | length' 2>/dev/null)
                        if [ "$key_insights_count" -gt 0 ]; then
                            echo "> *Key Insights:*"
                            echo "$reasoning" | jq -r '.key_insights // [] | .[] | "> - \(.)"' 2>/dev/null
                            echo ">"
                        fi
                        
                        local strategic_decisions_count
                        strategic_decisions_count=$(echo "$reasoning" | jq '.strategic_decisions // [] | length' 2>/dev/null)
                        if [ "$strategic_decisions_count" -gt 0 ]; then
                            echo "> *Strategic Decisions:*"
                            echo "$reasoning" | jq -r '.strategic_decisions // [] | .[] | "> - \(.)"' 2>/dev/null
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
                    report_file=$(echo "$line" | jq -r '.data.report_file // "research-report.md"')
                    
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
                    report_file=$(echo "$line" | jq -r '.data.report_file // "mission-report.md"')
                    
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
                    
                    # Show user-facing tool activity (hide internal operations)
                    case "$tool" in
                        WebSearch)
                            if [ -n "$input_summary" ]; then
                                echo "  🔍 **Web Search**: \"$input_summary\""
                                echo ""
                            fi
                            ;;
                        WebFetch)
                            if [ -n "$input_summary" ]; then
                                echo "  📄 **Fetching**: <$input_summary>"
                                echo ""
                            fi
                            ;;
                        TodoWrite)
                            if [ -n "$input_summary" ] && [[ "$input_summary" != "tasks" ]]; then
                                echo "  📋 **Planning**: $input_summary"
                                echo ""
                            fi
                            ;;
                        Write|Edit|MultiEdit)
                            # Only show research-facing file writes
                            if [[ "$input_summary" =~ findings-|mission-report|research-|synthesis- ]]; then
                                local relative_path
                                relative_path=$(make_path_relative "$input_summary" "$session_dir")
                                echo "  💾 **Saving**: $relative_path"
                                echo ""
                            fi
                            ;;
                        Grep)
                            if [ -n "$input_summary" ]; then
                                echo "  🔎 **Searching for**: $input_summary"
                                echo ""
                            fi
                            ;;
                        Glob)
                            if [ -n "$input_summary" ]; then
                                echo "  📁 **Finding files**: $input_summary"
                                echo ""
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
        
        # Add comprehensive research findings section
        echo ""
        echo "---"
        echo ""
        echo "## Comprehensive Research Findings"
        echo ""
        
        local findings_files
        findings_files=$(find "$session_dir/raw" -name "findings-*.json" -type f 2>/dev/null)
        
        if [ -n "$findings_files" ]; then
            # Count totals
            local total_entities total_claims total_sources total_gaps
            total_entities=$(echo "$findings_files" | xargs jq -r '[.entities_discovered // [] | .[]] | length' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            total_claims=$(echo "$findings_files" | xargs jq -r '[.claims // [] | .[]] | length' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            total_sources=$(echo "$findings_files" | xargs jq -r '.claims[]?.sources[]?.url // empty' 2>/dev/null | sort -u | wc -l | tr -d ' ')
            total_gaps=$(echo "$findings_files" | xargs jq -r '[.gaps_identified // [] | .[]] | length' 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
            
            # Ensure variables are numeric (default to 0 if empty)
            total_entities=${total_entities:-0}
            total_claims=${total_claims:-0}
            total_sources=${total_sources:-0}
            total_gaps=${total_gaps:-0}
            
            echo "Throughout this investigation, the research agents discovered **${total_entities} entities**, validated **${total_claims} claims**, consulted **${total_sources} authoritative sources**, and identified **${total_gaps} knowledge gaps** requiring further investigation."
            echo ""
            
            echo "<details><summary>View detailed findings</summary>"
            echo ""
            
            # Entities
            if [ "$total_entities" -gt 0 ]; then
                echo "### Entities Discovered"
                echo ""
                echo "$findings_files" | xargs jq -r '
                    .entities_discovered // [] | .[] | 
                    "- **\(.name)** (\(.type)): \(.description)\n  _Confidence: \((.confidence // 0) * 100 | floor)%_\n"
                ' 2>/dev/null
                echo ""
            fi
            
            # Claims
            if [ "$total_claims" -gt 0 ]; then
                echo "### Claims Validated"
                echo ""
                echo "$findings_files" | xargs jq -r '
                    .claims // [] | .[] | 
                    "- \(.statement)\n  - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence Quality: \(.evidence_quality // "unknown")\n  - Sources: \((.sources // [] | length))\n"
                ' 2>/dev/null
                echo ""
            fi
            
            # Key Sources
            if [ "$total_sources" -gt 0 ]; then
                echo "### Key Sources"
                echo ""
                # shellcheck disable=SC2016
                echo "$findings_files" | xargs jq -r '
                    def format_credibility:
                        gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                    [.claims // [] | .[].sources // [] | .[]] | unique_by(.url) | .[] | 
                    "- [\(.title)](\(.url))\n  - Credibility: \((.credibility // "unknown") | format_credibility)\n"
                ' 2>/dev/null | head -50
                echo ""
            fi
            
            # Gaps
            if [ "$total_gaps" -gt 0 ]; then
                echo "### Research Gaps Identified"
                echo ""
                echo "$findings_files" | xargs jq -r '
                    .gaps_identified // [] | .[] | 
                    "- **\(.question)**\n  - Priority: \(.priority // 0), Reason: \(.reason // "Not specified")\n"
                ' 2>/dev/null
                echo ""
            fi
            
            echo "</details>"
        else
            echo "No detailed findings data available for this session."
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
        local findings_files
        findings_files=$(find "$session_dir/raw" -name "findings-*.json" -type f 2>/dev/null)
        if [ -n "$findings_files" ]; then
            sources=$(echo "$findings_files" | xargs jq -r '.claims[]?.sources[]?.url // empty' 2>/dev/null | sort -u | wc -l | tr -d ' ')
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
        if [ -n "$findings_files" ]; then
            local avg_confidence
            avg_confidence=$(echo "$findings_files" | xargs jq -r '[.claims[]?.confidence // 0] | add / length * 100 | floor' 2>/dev/null | head -1)
            
            if [ -n "$avg_confidence" ] && [ "$avg_confidence" -gt 0 ]; then
                echo "**Quality Assessment:**"
                echo "- Average confidence: ${avg_confidence}%"
                
                # Check evidence quality
                local high_quality_count
                high_quality_count=$(echo "$findings_files" | xargs jq -r '[.claims[]? | select(.evidence_quality == "high")] | length' 2>/dev/null | head -1)
                if [ -n "$high_quality_count" ] && [ "$high_quality_count" -gt 0 ]; then
                    echo "- Evidence quality: High"
                fi
                
                # List source types
                local has_official has_academic
                has_official=$(echo "$findings_files" | xargs jq -r '.claims[]?.sources[]? | select(.credibility == "official") | .credibility' 2>/dev/null | head -1)
                has_academic=$(echo "$findings_files" | xargs jq -r '.claims[]?.sources[]? | select(.credibility == "academic") | .credibility' 2>/dev/null | head -1)
                
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
        
        # Link to final report
        if [ -f "$session_dir/mission-report.md" ]; then
            echo "**Final Report:** [mission-report.md](mission-report.md)"
            echo ""
        fi
        
        echo "---"
        echo ""
        echo "*Generated by CConductor Research Journal Exporter*"
        
    } > "$output_file"
    
    echo "✓ Research journal exported to: $output_file" >&2
}

# Export function for sourcing
export -f export_journal

# Allow direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <session_dir> [output_file]" >&2
        echo "  session_dir: Path to research session directory" >&2
        echo "  output_file: Optional output path (default: <session_dir>/research-journal.md)" >&2
        exit 1
    fi
    
    export_journal "$@"
fi

