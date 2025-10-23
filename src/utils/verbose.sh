#!/usr/bin/env bash
# Verbose Mode Utility - User-friendly progress messages
# Usage: Set CCONDUCTOR_VERBOSE=1 to enable verbose output

set -euo pipefail 2>/dev/null || set -eu

# Check if verbose mode is enabled
is_verbose_enabled() {
    [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]
}

# Log verbose message (only if verbose enabled)
verbose() {
    if is_verbose_enabled; then
        echo "$*" >&2
    fi
}

# Show agent start with friendly description
# Usage: verbose_agent_start "web-researcher" "Search for market data"
verbose_agent_start() {
    if ! is_verbose_enabled; then
        return 0
    fi
    
    local agent_name="$1"
    local task="${2:-}"
    
    # Try to read display_name from agent metadata (if session available)
    local friendly_name=""
    if [[ -n "${CCONDUCTOR_SESSION_DIR:-}" ]]; then
        local metadata_file="$CCONDUCTOR_SESSION_DIR/.claude/agents/${agent_name}/metadata.json"
        if [[ -f "$metadata_file" ]]; then
            friendly_name=$(jq -r '.display_name // empty' "$metadata_file" 2>/dev/null)
        fi
    fi
    
    # Fallback: convert hyphens to spaces if no metadata
    if [[ -z "$friendly_name" ]]; then
        friendly_name="${agent_name//-/ }"
    fi
    
    echo "🤖 Starting $friendly_name" >&2
    
    # Only show task if it's meaningful (not system prompt preamble)
    if [[ -n "$task" ]] && \
       [[ ! "$task" =~ ^"I am providing" ]] && \
       [[ ${#task} -lt 150 ]]; then
        # Try to get action verb from agent metadata
        local action_verb=""
        if command -v agent_registry_get_metadata &>/dev/null; then
            local metadata_json
            if metadata_json=$(agent_registry_get_metadata "$agent_name" 2>/dev/null); then
                action_verb=$(echo "$metadata_json" | jq -r '.action_verb // empty' 2>/dev/null)
            fi
        fi
        
        # Fallback to generic "Looking for" if no action verb defined
        if [[ -z "$action_verb" ]]; then
            action_verb="Looking for"
        fi
        
        echo "   $action_verb: $task" >&2
    fi
}

# Show agent reasoning/decisions
# Usage: verbose_agent_reasoning "$reasoning_json"
verbose_agent_reasoning() {
    if ! is_verbose_enabled; then
        return 0
    fi
    
    local reasoning_json="$1"
    
    # Try to parse reasoning from JSON
    if [[ -z "$reasoning_json" ]] || [[ "$reasoning_json" == "null" ]]; then
        return 0
    fi
    
    echo "" >&2
    echo "🧠 Research reasoning:" >&2
    
    # Try different reasoning fields
    local synthesis_approach
    synthesis_approach=$(echo "$reasoning_json" | jq -r '.synthesis_approach // empty' 2>/dev/null || echo "")
    if [[ -n "$synthesis_approach" ]]; then
        echo "   - Approach: $synthesis_approach" >&2
    fi
    
    local gap_prioritization
    gap_prioritization=$(echo "$reasoning_json" | jq -r '.gap_prioritization // empty' 2>/dev/null || echo "")
    if [[ -n "$gap_prioritization" ]]; then
        echo "   - Priority: $gap_prioritization" >&2
    fi
    
    # Show key insights as bullet points
    local insights_count
    insights_count=$(echo "$reasoning_json" | jq '.key_insights // [] | length' 2>/dev/null || echo "0")
    if [[ "$insights_count" -gt 0 ]]; then
        echo "$reasoning_json" | jq -r '.key_insights[] // empty' 2>/dev/null | while IFS= read -r insight; do
            echo "   - $insight" >&2
        done
    fi
    
    # Show strategic decisions
    local decisions_count
    decisions_count=$(echo "$reasoning_json" | jq '.strategic_decisions // [] | length' 2>/dev/null || echo "0")
    if [[ "$decisions_count" -gt 0 ]]; then
        echo "$reasoning_json" | jq -r '.strategic_decisions[] // empty' 2>/dev/null | while IFS= read -r decision; do
            echo "   - $decision" >&2
        done
    fi
    
    echo "" >&2
}

# Show tool use in friendly format
# Usage: verbose_tool_use "WebSearch" "SaaS market size 2024"
verbose_tool_use() {
    if ! is_verbose_enabled; then
        return 0
    fi
    
    local tool_name="$1"
    local tool_input="$2"
    
    case "$tool_name" in
        WebSearch)
            echo "🔍 Searching the web for: $tool_input" >&2
            ;;
        WebFetch)
            # Extract domain from URL
            local domain
            domain=$(echo "$tool_input" | sed -E 's|^https?://([^/]+).*|\1|')
            echo "📄 Getting information from: $domain" >&2
            ;;
        Read)
            echo "📖 Opening: $tool_input" >&2
            ;;
        Write|Edit|MultiEdit)
            # Only show if it's a research file
            if is_research_file "$tool_input"; then
                echo "💾 Saving: $tool_input" >&2
            fi
            ;;
        Grep)
            echo "🔎 Looking for: $tool_input" >&2
            ;;
        Bash)
            # Hide bash commands in verbose mode (only show in debug)
            :
            ;;
        *)
            # Generic message for unknown tools
            echo "🔧 Using $tool_name" >&2
            ;;
    esac
}

# Check if a file is a research/user-facing file (not internal)
# Usage: if is_research_file "findings-web-001.json"; then ...
is_research_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")
    
    # Research/user-facing files
    case "$filename" in
        findings-*.json|findings-*.md)
            return 0
            ;;
        mission-report.md|research-journal.md|research-plan.md)
            return 0
            ;;
        synthesis-*.json|synthesis-*.md)
            return 0
            ;;
        # Exclude internal/system files
        events.jsonl|system-errors.log|orchestration-log.jsonl)
            return 1
            ;;
        agent-input-*|agent-output-*|agent-result-*)
            return 1
            ;;
        .*)
            return 1
            ;;
        *)
            # Default: allow if in session directory and looks like output
            if [[ "$filename" =~ \.(md|json)$ ]]; then
                return 0
            fi
            return 1
            ;;
    esac
}

# Show file operation in friendly format
# Usage: verbose_file_op "write" "findings-web-001.json"
verbose_file_op() {
    if ! is_verbose_enabled; then
        return 0
    fi
    
    local operation="$1"
    local filepath="$2"
    
    # Only show research files
    if ! is_research_file "$filepath"; then
        return 0
    fi
    
    local filename
    filename=$(basename "$filepath")
    
    case "$operation" in
        write|save|create)
            echo "💾 Saved: $filename" >&2
            ;;
        read|open)
            echo "📖 Opened: $filename" >&2
            ;;
        update|edit)
            echo "📝 Updated: $filename" >&2
            ;;
    esac
}

# Show friendly completion message
# Usage: verbose_completion "success" "1200" "WebSearch"
verbose_completion() {
    if ! is_verbose_enabled; then
        return 0
    fi
    
    local status="$1"
    local duration_ms="$2"
    local tool_name="${3:-}"
    
    # Skip Bash completions in verbose mode
    if [[ "$tool_name" == "Bash" ]]; then
        return 0
    fi
    
    # Format duration
    local duration_display
    if [[ "$duration_ms" -gt 1000 ]]; then
        local duration_sec
        duration_sec=$(echo "scale=1; $duration_ms / 1000" | bc 2>/dev/null || echo "?")
        duration_display="${duration_sec}s"
    else
        duration_display="${duration_ms}ms"
    fi
    
    if [[ "$status" == "success" ]]; then
        echo "✓ Done in $duration_display" >&2
    else
        echo "✗ Didn't work ($duration_display)" >&2
    fi
}

# Export functions for use in subshells
export -f is_verbose_enabled
export -f verbose
export -f verbose_agent_start
export -f verbose_agent_reasoning
export -f verbose_tool_use
export -f verbose_file_op
export -f verbose_completion
export -f is_research_file

# Usage examples (only shown when script is run directly)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cat <<'EOF'
Verbose Mode Utility for CConductor
====================================

Enable verbose mode:
  export CCONDUCTOR_VERBOSE=1
  ./cconductor "your query"

Or for a single run:
  CCONDUCTOR_VERBOSE=1 ./cconductor "your query"

Or with flag:
  ./cconductor "your query" --verbose

Functions available:
  verbose "message"                          - Log user-friendly message
  verbose_agent_start "agent" "task"         - Show agent starting
  verbose_agent_reasoning "$reasoning_json"  - Show reasoning/decisions
  verbose_tool_use "tool" "input"            - Show tool use
  verbose_file_op "operation" "file"         - Show file operations
  verbose_completion "status" "duration_ms"  - Show completion

Example usage in scripts:
  source "$SCRIPT_DIR/utils/verbose.sh"
  
  if is_verbose_enabled; then
      verbose_agent_start "web-researcher" "Find market data"
  fi

EOF
fi

