#!/usr/bin/env bash
#
# export-journal.sh - Export research journal as markdown
#
# Generates a sequential, detailed markdown timeline of the research session
# from events.jsonl
#

export_journal() {
    local session_dir="$1"
    local output_file="${2:-$session_dir/research-journal.md}"
    
    local events_file="$session_dir/events.jsonl"
    if [ ! -f "$events_file" ]; then
        echo "Error: events.jsonl not found in $session_dir" >&2
        return 1
    fi
    
    # Get session metadata
    local session_file="$session_dir/session.json"
    local question="Unknown"
    if [ -f "$session_file" ]; then
        question=$(jq -r '.question // "Unknown"' "$session_file" 2>/dev/null || echo "Unknown")
    fi
    
    # Start markdown document
    {
        echo "# Research Journal"
        echo ""
        echo "**Research Question:** $question"
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
            formatted_time=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" "+%H:%M:%S" 2>/dev/null || echo "$timestamp")
            
            case "$event_type" in
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
                    
                    echo "### ⚡ Agent Invoked: $agent"
                    echo ""
                    echo "**Time:** $formatted_time  "
                    echo "**Tools:** $tools"
                    echo ""
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
                    metadata_keys=$(echo "$line" | jq -r '.data | keys | .[] | select(. != "agent" and . != "duration_ms" and . != "cost_usd")' 2>/dev/null)
                    
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
                                        jq -r '([.claims // [] | .[].sources // [] | .[]] | unique_by(.url) | .[0:5] | .[] | "- [\(.title)](\(.url))\n  - Credibility: \(.credibility // "unknown")")' "$findings_file" 2>/dev/null
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
                            
                        research-coordinator)
                            # Look for coordinator output with gap analysis
                            local coordinator_file
                            coordinator_file=$(find "$session_dir/raw" -name "*coordinator*output*.json" 2>/dev/null | tail -1)
                            
                            if [ -n "$coordinator_file" ] && [ -f "$coordinator_file" ]; then
                                echo "#### 🔍 Gap Analysis"
                                echo ""
                                
                                # Extract gaps
                                local gaps_count
                                gaps_count=$(jq '[.knowledge_graph_updates.gaps_detected // [], .next_steps // []] | length' "$coordinator_file" 2>/dev/null || echo "0")
                                if [ "$gaps_count" -gt 0 ]; then
                                    echo "**Research Gaps Identified:**"
                                    echo ""
                                    jq -r '([.knowledge_graph_updates.gaps_detected // [], .next_steps // []] | .[] | "- **Priority \(.priority // "medium")**: \(.gap_description // .description // .query)\n  - Rationale: \(.rationale // "No rationale provided")")' "$coordinator_file" 2>/dev/null
                                    echo ""
                                fi
                                
                                # Extract contradictions
                                local contradictions_count
                                contradictions_count=$(jq '[.knowledge_graph_updates.contradictions_detected // []] | length' "$coordinator_file" 2>/dev/null || echo "0")
                                if [ "$contradictions_count" -gt 0 ]; then
                                    echo "**Contradictions Detected:**"
                                    echo ""
                                    jq -r '(.knowledge_graph_updates.contradictions_detected // []) | .[] | "- \(.description)\n  - Claims in conflict: \(.conflicting_claims | length)"' "$coordinator_file" 2>/dev/null
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
                                
                                # Extract tasks
                                local tasks
                                tasks=$(jq -c '.initial_tasks // .tasks // []' "$planner_file" 2>/dev/null)
                                if [ "$tasks" != "[]" ] && [ -n "$tasks" ]; then
                                    echo "**Tasks Generated:**"
                                    echo ""
                                    echo "$tasks" | jq -r '.[] | "- **Task \(.id // "?")** (\(.agent)): \(.query)\n  - Priority: \(.priority // "medium"), Type: \(.research_type // "unknown")"'
                                    echo ""
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
                                jq -r '([.claims // [] | .[].sources // [] | .[]] | unique_by(.url) | .[0:8] | .[] | "- [\(.title)](\(.url))\n  - Credibility: \(.credibility // "unknown")")' "$findings_file" 2>/dev/null
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
                    
                tool_use_start)
                    local tool
                    tool=$(echo "$line" | jq -r '.data.tool // "unknown"')
                    local agent
                    agent=$(echo "$line" | jq -r '.data.agent // "unknown"')
                    local input_summary
                    input_summary=$(echo "$line" | jq -r '.data.input_summary // ""')
                    
                    # Only show interesting tool starts (searches, etc)
                    if [[ "$tool" == "WebSearch" ]] && [ -n "$input_summary" ]; then
                        echo "  🔍 **Web Search**: \"$input_summary\""
                        echo ""
                    fi
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

