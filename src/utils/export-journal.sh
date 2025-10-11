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
        if [ "$objective" != "Unknown" ]; then
            echo "**Research Objective:** $objective"
        else
            echo "**Research Question:** $question"
        fi
        echo ""
        echo "**Session:** $(basename "$session_dir")"
        echo ""
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
            # Format: "October 8, 2025 at 7:35 AM"
            # Strip microseconds if present (2025-10-08T07:35:57.159051Z -> 2025-10-08T07:35:57Z)
            local clean_timestamp
            # shellcheck disable=SC2001
            clean_timestamp=$(echo "$timestamp" | sed 's/\.[0-9]*Z$/Z/')
            formatted_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$clean_timestamp" "+%B %d, %Y at %l:%M %p" 2>/dev/null | sed 's/  / /g' || echo "$timestamp")
            
            case "$event_type" in
                mission_started)
                    local mission_objective
                    mission_objective=$(echo "$line" | jq -r '.data.objective // "research query"')
                    echo "## 🚀 Mission Started"
                    echo ""
                    echo "**Time:** $formatted_time"
                    echo ""
                    echo "**Objective:** $mission_objective"
                    echo ""
                    echo "Research mission initialized. The orchestrator will coordinate specialized agents to gather, analyze, and synthesize information."
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                
                session_created)
                    echo "## 🎯 Session Started"
                    echo ""
                    echo "**Time:** $formatted_time"
                    echo ""
                    echo "Research session initialized. Preparing to analyze the query and generate research tasks."
                    echo ""
                    echo "---"
                    echo ""
                    ;;
                    
                agent_invocation)
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local tools
                    tools=$(echo "$line" | jq -r '.data.tools // "N/A"')
                    
                    # Check if iteration changed (for mission-orchestrator)
                    if [ "$agent" = "mission-orchestrator" ] && [ "$has_orchestration_log" = true ]; then
                        # Extract iteration from orchestration log near this timestamp
                        # Match by time proximity (within a minute)
                        local iteration_number
                        local timestamp_minute
                        timestamp_minute="${clean_timestamp%:??Z}"  # 2025-10-11T12:03
                        iteration_number=$(grep "$timestamp_minute" "$orchestration_log" 2>/dev/null | head -1 | jq -r '.decision.iteration // 0' 2>/dev/null || echo "0")
                        
                        if [ "$iteration_number" != "0" ] && [ "$iteration_number" != "$current_iteration" ]; then
                            current_iteration=$iteration_number
                            echo "---"
                            echo ""
                            echo "## 🔄 Iteration $current_iteration"
                            echo ""
                        fi
                    fi
                    
                    echo "### ⚡ Agent Invoked: $agent"
                    echo ""
                    echo "**Time:** $formatted_time  "
                    echo "**Tools:** $tools"
                    echo ""
                    
                    # For mission-orchestrator, show orchestration decision
                    if [ "$agent" = "mission-orchestrator" ] && [ "$has_orchestration_log" = true ]; then
                        # Find matching decision in orchestration log
                        # Match by time proximity (within a minute)
                        local decision_entry
                        local timestamp_minute
                        timestamp_minute="${clean_timestamp%:??Z}"  # 2025-10-11T12:03
                        decision_entry=$(grep "$timestamp_minute" "$orchestration_log" 2>/dev/null | head -1)
                        
                        if [ -n "$decision_entry" ]; then
                            local decision_type
                            decision_type=$(echo "$decision_entry" | jq -r '.decision.type // "decision"' 2>/dev/null)
                            local rationale
                            rationale=$(echo "$decision_entry" | jq -r '.decision.rationale // ""' 2>/dev/null)
                            local expected_impact
                            expected_impact=$(echo "$decision_entry" | jq -r '.decision.expected_impact // ""' 2>/dev/null)
                            
                            if [ -n "$rationale" ]; then
                                echo "> [!NOTE]"
                                echo "> **🧠 Orchestration Decision: $decision_type**"
                                echo ">"
                                echo "> *Rationale:* $rationale"
                                
                                # Show alternatives considered
                                local alternatives
                                alternatives=$(echo "$decision_entry" | jq -r '.decision.alternatives_considered // [] | .[]' 2>/dev/null)
                                if [ -n "$alternatives" ]; then
                                    echo ">"
                                    echo "> *Alternatives Considered:*"
                                    while IFS= read -r alt; do
                                        echo "> - $alt"
                                    done <<< "$alternatives"
                                fi
                                
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
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local duration
                    duration=$(echo "$line" | jq -r '.data.duration_ms // 0')
                    local cost
                    cost=$(echo "$line" | jq -r '.data.cost_usd // 0')
                    
                    # Convert duration to seconds
                    local duration_sec=$((duration / 1000))
                    
                    echo "**Completed:** $formatted_time (${duration_sec}s, \$$(printf "%.3f" "$cost"))"
                    echo ""
                    
                    # Extract metadata summary
                    local metadata_keys
                    metadata_keys=$(echo "$line" | jq -r '.data | keys | .[] | select(. != "agent" and . != "duration_ms" and . != "cost_usd" and . != "reasoning")' 2>/dev/null)
                    
                    if [ -n "$metadata_keys" ]; then
                        echo "**Summary:**"
                        echo ""
                        while IFS= read -r key; do
                            local value
                            value=$(echo "$line" | jq -r ".data.${key}" 2>/dev/null)
                            # Format key name (convert snake_case to Title Case)
                            local formatted_key
                            formatted_key=$(echo "$key" | sed 's/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2));}1')
                            echo "- **$formatted_key:** $value"
                        done <<< "$metadata_keys"
                        echo ""
                    fi
                    
                    # Special handling for mission-orchestrator reasoning
                    if [ "$agent" = "mission-orchestrator" ]; then
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
                    fi
                    
                    # Find and include detailed findings
                    case "$agent" in
                        academic-researcher|web-researcher)
                            # Look for most recent findings file for this agent
                            # Since multiple tasks may complete around the same time, get the most recent one
                            local findings_file
                            findings_file=$(find "$session_dir/raw" -name "findings-*.json" -type f 2>/dev/null | tail -1)
                            
                            if [ -n "$findings_file" ] && [ -f "$findings_file" ]; then
                                # Check if this file has any content
                                local has_content
                                has_content=$(jq -e '(.entities_discovered // [] | length) > 0 or (.claims // [] | length) > 0' "$findings_file" 2>/dev/null && echo "yes" || echo "no")
                                
                                if [ "$has_content" = "yes" ]; then
                                    echo "#### 📊 Detailed Findings"
                                    echo ""
                                    
                                    # Extract entities
                                    local entities_count
                                    entities_count=$(jq '[.entities_discovered // []] | length' "$findings_file" 2>/dev/null || echo "0")
                                    if [ "$entities_count" -gt 0 ]; then
                                        echo "**Entities Discovered ($entities_count):**"
                                        echo ""
                                        jq -r '(.entities_discovered // []) | .[] | "- **\(.name)** (\(.type)): \(.description)\n  _Confidence: \((.confidence // 0) * 100 | floor)%_"' "$findings_file" 2>/dev/null
                                        echo ""
                                    fi
                                    
                                    # Extract claims  
                                    local claims_count
                                    claims_count=$(jq '[.claims // []] | length' "$findings_file" 2>/dev/null || echo "0")
                                    if [ "$claims_count" -gt 0 ]; then
                                        echo "**Claims Validated ($claims_count):**"
                                        echo ""
                                        jq -r '(.claims // []) | .[] | "- \(.statement)\n  - Confidence: \((.confidence // 0) * 100 | floor)%, Evidence Quality: \(.evidence_quality // "unknown")\n  - Sources: \(.sources | length)"' "$findings_file" 2>/dev/null
                                        echo ""
                                    fi
                                    
                                    # Show top sources with details
                                    local top_sources
                                    top_sources=$(jq -r '(.claims // []) | .[0].sources // []' "$findings_file" 2>/dev/null)
                                if [ -n "$top_sources" ] && [ "$top_sources" != "[]" ]; then
                                    echo "**Key Sources (sample):**"
                                    echo ""
                                    jq -r '
                                        def format_credibility:
                                            gsub("_"; " ") | split(" ") | map(.[0:1] as $first | .[1:] as $rest | ($first | ascii_upcase) + $rest) | join(" ");
                                        ([.claims // [] | .[].sources // [] | .[]] | unique_by(.url) | .[0:5] | .[] | 
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
                                        jq -r '(.gaps_identified // []) | .[] | "- \(.)"' "$findings_file" 2>/dev/null
                                        echo ""
                                    fi
                                fi
                            fi
                            ;;
                            
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
                    # Add H3 header if we just completed an iteration
                    if [ "$NEED_TASK_SECTION_HEADER" = "true" ]; then
                        echo "### New Research Tasks"
                        echo ""
                        NEED_TASK_SECTION_HEADER=false
                    fi
                    
                    local task_id
                    task_id=$(echo "$line" | jq -r '.data.task_id // "unknown"')
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local query
                    query=$(echo "$line" | jq -r '.data.query // "N/A"')
                    
                    echo "#### 📋 Task Started: $task_id"
                    echo ""
                    echo "**Time:** $formatted_time  "
                    echo "**Agent:** $agent  "
                    echo "**Query:** $query"
                    echo ""
                    ;;
                    
                task_completed)
                    local task_id
                    task_id=$(echo "$line" | jq -r '.data.task_id // "unknown"')
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local duration
                    duration=$(echo "$line" | jq -r '.data.duration // 0')
                    
                    echo "**✅ Task Completed:** $formatted_time (${duration}s)"
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
                    local iteration
                    iteration=$(echo "$line" | jq -r '.data.iteration // "?"')
                    local total_entities
                    total_entities=$(echo "$line" | jq -r '.data.stats.total_entities // 0')
                    local total_claims
                    total_claims=$(echo "$line" | jq -r '.data.stats.total_claims // 0')
                    
                    echo "## ✅ Iteration $iteration Complete"
                    echo ""
                    echo "**Time:** $formatted_time"
                    echo ""
                    echo "**Knowledge Graph Status:**"
                    echo "- Entities: $total_entities"
                    echo "- Claims: $total_claims"
                    echo ""
                    echo "---"
                    echo ""
                    
                    # Set flag to add H3 header before next task_started
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
                    local completion_status
                    completion_status=$(echo "$line" | jq -r '.data.status // "success"')
                    
                    # Get final KG stats if available
                    local kg_file="$session_dir/knowledge-graph.json"
                    local claims=0
                    local entities=0
                    local citations=0
                    if [ -f "$kg_file" ]; then
                        claims=$(jq -r '.stats.total_claims // 0' "$kg_file" 2>/dev/null || echo "0")
                        entities=$(jq -r '.stats.total_entities // 0' "$kg_file" 2>/dev/null || echo "0")
                        citations=$(jq -r '.stats.total_citations // 0' "$kg_file" 2>/dev/null || echo "0")
                    fi
                    
                    echo "## 🎉 Mission Complete"
                    echo ""
                    echo "**Time:** $formatted_time"
                    echo "**Status:** $completion_status"
                    echo ""
                    echo "Research mission completed successfully! Final knowledge graph contains:"
                    echo "- **Entities:** $entities"
                    echo "- **Claims:** $claims"
                    echo "- **Citations:** $citations"
                    echo ""
                    echo "📄 **[View Final Report]($report_file)**"
                    echo ""
                    echo "📖 **[View Research Journal](research-journal.md)** (This document)"
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
                                local domain
                                domain=$(echo "$input_summary" | sed -E 's|^https?://([^/]+).*|\1|')
                                echo "  📄 **Fetching**: $domain"
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
                                echo "  💾 **Saving**: $input_summary"
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
        
        echo ""
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

