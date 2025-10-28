#!/usr/bin/env bash
# Knowledge Loader - Convention-based discovery with priority override
# WordPress-style extensibility: core + user + session override

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source config loader for configuration access
# shellcheck disable=SC1091
source "$SCRIPT_DIR/config-loader.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# Load knowledge configuration (overlay pattern)
get_knowledge_config() {
    load_config "knowledge-config"
}

# Find knowledge file with priority order
# Priority: Session Override > User Custom > Core
# Usage: find_knowledge_file "business-methodology" [session_dir]
# Returns: Absolute path to knowledge file, or empty if not found
find_knowledge_file() {
    local knowledge_name="$1"
    local session_dir="${2:-}"

    local config
    config=$(get_knowledge_config)
    local core_path
    core_path="$PROJECT_ROOT/$(echo "$config" | jq -r '.knowledge_paths.core')"
    local user_path
    user_path="$PROJECT_ROOT/$(echo "$config" | jq -r '.knowledge_paths.user')"

    # Add .md extension if not present
    if [[ ! "$knowledge_name" =~ \.md$ ]]; then
        knowledge_name="${knowledge_name}.md"
    fi

    # Priority 1: Session override (if session_dir provided)
    if [ -n "$session_dir" ]; then
        local session_path="$session_dir/knowledge"
        if [ -f "$session_path/$knowledge_name" ]; then
            echo "$session_path/$knowledge_name"
            return 0
        fi
    fi

    # Priority 2: User custom
    if [ -f "$user_path/$knowledge_name" ]; then
        echo "$user_path/$knowledge_name"
        return 0
    fi

    # Priority 3: Core default
    if [ -f "$core_path/$knowledge_name" ]; then
        echo "$core_path/$knowledge_name"
        return 0
    fi

    # Not found - return empty (graceful degradation)
    echo ""
    return 1
}

# Get all knowledge files for an agent
# Usage: get_agent_knowledge "market-analyzer" [session_dir]
# Returns: JSON array of absolute paths
get_agent_knowledge() {
    local agent_name="$1"
    local session_dir="${2:-}"

    local config
    config=$(get_knowledge_config)
    if ! jq_validate_json "$config"; then
        log_warn "knowledge-loader: invalid knowledge-config JSON; using defaults"
        config='{}'
    fi

    local auto_discover="true"
    if auto_discover=$(safe_jq_from_json "$config" '.auto_discover // true' "true" "$session_dir" "knowledge_loader.auto_discover"); then
        auto_discover=${auto_discover:-true}
    else
        auto_discover="true"
    fi

    # Get mapped knowledge domains
    local mapped_knowledge=""
    local agent_key
    agent_key=$(printf '%s' "$agent_name" | jq -R @json)
    local mapped_filter="(.agent_knowledge_map // {})[$agent_key] // [] | .[]"
    if mapped_knowledge=$(safe_jq_from_json "$config" "$mapped_filter" "" "$session_dir" "knowledge_loader.mapped" ); then
        mapped_knowledge=${mapped_knowledge:-}
    else
        mapped_knowledge=""
    fi

    # Collect knowledge file paths
    local knowledge_files=()

    # Add explicitly mapped knowledge
    if [ -n "$mapped_knowledge" ]; then
        while IFS= read -r knowledge_name; do
            if [ -z "$knowledge_name" ]; then
                continue
            fi

            if [ "$knowledge_name" = "*" ]; then
                # Wildcard: discover all knowledge
                while IFS= read -r file; do
                    knowledge_files+=("$file")
                done < <(discover_all_knowledge "$session_dir")
            else
                # Specific knowledge file
                local found_file
                found_file=$(find_knowledge_file "$knowledge_name" "$session_dir" 2>/dev/null || echo "")
                if [ -n "$found_file" ]; then
                    knowledge_files+=("$found_file")
                fi
            fi
        done <<< "$mapped_knowledge"
    fi

    # Auto-discover if enabled and no explicit mapping
    if [ "$auto_discover" = "true" ] && [ ${#knowledge_files[@]} -eq 0 ]; then
        while IFS= read -r file; do
            knowledge_files+=("$file")
        done < <(discover_all_knowledge "$session_dir")
    fi

    # Output as JSON array
    if [ ${#knowledge_files[@]} -eq 0 ]; then
        echo "[]"
    else
        printf '%s\n' "${knowledge_files[@]}" | jq -R . | jq -s .
    fi
}

# Discover all available knowledge files (respects priority)
# Usage: discover_all_knowledge [session_dir]
# Returns: List of absolute paths (one per line)
discover_all_knowledge() {
    local session_dir="${1:-}"

    local config
    config=$(get_knowledge_config)
    if ! jq_validate_json "$config"; then
        log_warn "knowledge-loader: invalid knowledge-config JSON for discovery; using defaults"
        config='{}'
    fi

    local core_relative user_relative pattern excludes
    if ! core_relative=$(safe_jq_from_json "$config" '.knowledge_paths.core // "knowledge-base"' "knowledge-base" "$session_dir" "knowledge_loader.discovery.core" "true" "true"); then
        core_relative="knowledge-base"
    fi
    if ! user_relative=$(safe_jq_from_json "$config" '.knowledge_paths.user // "knowledge-base-custom"' "knowledge-base-custom" "$session_dir" "knowledge_loader.discovery.user" "true" "true"); then
        user_relative="knowledge-base-custom"
    fi
    if ! pattern=$(safe_jq_from_json "$config" '.discovery_rules.pattern // "*.md"' "*.md" "$session_dir" "knowledge_loader.discovery.pattern" "true" "true"); then
        pattern="*.md"
    fi
    if ! excludes=$(safe_jq_from_json "$config" '.discovery_rules.exclude[]?' "" "$session_dir" "knowledge_loader.discovery.excludes" "true" "true"); then
        excludes=""
    fi

    local core_path
    core_path="$PROJECT_ROOT/$core_relative"
    local user_path
    user_path="$PROJECT_ROOT/$user_relative"

    # Collect unique knowledge names (priority order)
    declare -A seen_knowledge
    local discovered_files=()

    # Priority 1: Session knowledge (if exists)
    if [ -n "$session_dir" ]; then
        local session_path="$session_dir/knowledge"
        if [ -d "$session_path" ]; then
            while IFS= read -r file; do
                local basename
                basename=$(basename "$file")
                if ! is_excluded "$basename" "$excludes"; then
                    seen_knowledge["$basename"]=1
                    discovered_files+=("$file")
                fi
            done < <(find "$session_path" -maxdepth 1 -name "$pattern" -type f 2>/dev/null || true)
        fi
    fi

    # Priority 2: User custom knowledge
    if [ -d "$user_path" ]; then
        while IFS= read -r file; do
            local basename
            basename=$(basename "$file")
            if ! is_excluded "$basename" "$excludes" && [ -z "${seen_knowledge[$basename]:-}" ]; then
                seen_knowledge["$basename"]=1
                discovered_files+=("$file")
            fi
        done < <(find "$user_path" -maxdepth 1 -name "$pattern" -type f 2>/dev/null || true)
    fi

    # Priority 3: Core knowledge
    if [ -d "$core_path" ]; then
        while IFS= read -r file; do
            local basename
            basename=$(basename "$file")
            if ! is_excluded "$basename" "$excludes" && [ -z "${seen_knowledge[$basename]:-}" ]; then
                seen_knowledge["$basename"]=1
                discovered_files+=("$file")
            fi
        done < <(find "$core_path" -maxdepth 1 -name "$pattern" -type f 2>/dev/null || true)
    fi

    printf '%s\n' "${discovered_files[@]}"
}

# Check if filename should be excluded
is_excluded() {
    local filename="$1"
    local excludes="$2"

    if [ -z "$excludes" ]; then
        return 1
    fi

    while IFS= read -r exclude_pattern; do
        if [ -z "$exclude_pattern" ]; then
            continue
        fi
        if [[ "$filename" == "$exclude_pattern" ]]; then
            return 0
        fi
    done <<< "$excludes"

    return 1
}

# Generate agent prompt with knowledge context
# Usage: inject_knowledge_context "market-analyzer" "base_prompt" [session_dir]
# Returns: Enhanced prompt with knowledge sections
inject_knowledge_context() {
    local agent_name="$1"
    local base_prompt="$2"
    local session_dir="${3:-}"

    local knowledge_files
    knowledge_files=$(get_agent_knowledge "$agent_name" "$session_dir")
    local knowledge_count
    knowledge_count=$(echo "$knowledge_files" | jq 'length')

    if [ "$knowledge_count" -eq 0 ]; then
        # No knowledge available - return base prompt
        echo "$base_prompt"
        return 0
    fi

    # Build knowledge context section with XML structure
    local knowledge_context="<domain_knowledge>\n\n# Domain Knowledge\n\nYou have access to the following domain-specific methodologies:\n\n"

    local idx=0
    while [ $idx -lt "$knowledge_count" ]; do
        local knowledge_file
        knowledge_file=$(echo "$knowledge_files" | jq -r ".[$idx]")
        local knowledge_name
        knowledge_name=$(basename "$knowledge_file" .md)

        if [ -f "$knowledge_file" ]; then
            local knowledge_content
            knowledge_content=$(cat "$knowledge_file")
            knowledge_context+="## ${knowledge_name}\n\n<knowledge_base name=\"${knowledge_name}\">\n${knowledge_content}\n</knowledge_base>\n\n"
        fi

        idx=$((idx + 1))
    done

    knowledge_context+="</domain_knowledge>"

    # Inject knowledge BEFORE the task-specific prompt
    echo -e "${knowledge_context}\n\n---\n\n${base_prompt}"
}

# List all available knowledge with sources
# Usage: list_all_knowledge [session_dir]
# Returns: Human-readable list with sources
list_all_knowledge() {
    local session_dir="${1:-}"

    local config
    config=$(get_knowledge_config)
    local core_path
    core_path="$PROJECT_ROOT/$(echo "$config" | jq -r '.knowledge_paths.core')"
    local user_path
    user_path="$PROJECT_ROOT/$(echo "$config" | jq -r '.knowledge_paths.user')"

    echo "Available Knowledge Files"
    echo "════════════════════════════════════════════════════════"
    echo ""

    # Session knowledge (if applicable)
    if [ -n "$session_dir" ]; then
        local session_path="$session_dir/knowledge"
        if [ -d "$session_path" ] && [ "$(ls -A "$session_path" 2>/dev/null)" ]; then
            echo "Session Override (Highest Priority):"
            find "$session_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r file; do
                echo "  • $(basename "$file") → $file"
            done
            echo ""
        fi
    fi

    # User custom knowledge
    if [ -d "$user_path" ] && [ "$(ls -A "$user_path" 2>/dev/null)" ]; then
        echo "User Custom:"
        find "$user_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r file; do
            echo "  • $(basename "$file") → $file"
        done
        echo ""
    fi

    # Core knowledge
    if [ -d "$core_path" ] && [ "$(ls -A "$core_path" 2>/dev/null)" ]; then
        echo "Core (Default):"
        find "$core_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r file; do
            echo "  • $(basename "$file") → $file"
        done
        echo ""
    fi

    echo "Priority order: Session > User > Core"
}

# Export functions for use in other scripts
export -f get_knowledge_config
export -f find_knowledge_file
export -f get_agent_knowledge
export -f discover_all_knowledge
export -f inject_knowledge_context
export -f list_all_knowledge

# CLI interface
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-help}" in
        find)
            # Usage: knowledge-loader.sh find "business-methodology" [session_dir]
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 find <knowledge-name> [session-dir]" >&2
                exit 1
            fi
            find_knowledge_file "$2" "${3:-}"
            ;;
        list)
            # Usage: knowledge-loader.sh list "market-analyzer" [session_dir]
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 list <agent-name> [session-dir]" >&2
                exit 1
            fi
            get_agent_knowledge "$2" "${3:-}"
            ;;
        discover)
            # Usage: knowledge-loader.sh discover [session_dir]
            discover_all_knowledge "${2:-}"
            ;;
        inject)
            # Usage: knowledge-loader.sh inject "agent-name" "base-prompt" [session_dir]
            if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
                echo "Usage: $0 inject <agent-name> <base-prompt> [session-dir]" >&2
                exit 1
            fi
            inject_knowledge_context "$2" "$3" "${4:-}"
            ;;
        all)
            # Usage: knowledge-loader.sh all [session_dir]
            list_all_knowledge "${2:-}"
            ;;
        help|--help|-h)
            cat <<EOF
Knowledge Loader - Convention-based knowledge discovery

Usage: $0 <command> [args]

Commands:
  find <knowledge-name> [session-dir]
      Find specific knowledge file with priority resolution
      Example: $0 find business-methodology

  list <agent-name> [session-dir]
      List all knowledge files for specific agent (JSON array)
      Example: $0 list market-analyzer

  discover [session-dir]
      Discover all available knowledge files
      Example: $0 discover

  inject <agent-name> <base-prompt> [session-dir]
      Inject knowledge context into agent prompt
      Example: $0 inject market-analyzer "Analyze market..."

  all [session-dir]
      List all available knowledge with sources (human-readable)
      Example: $0 all

  help
      Show this help

Priority Order:
  1. Session Override    → research-sessions/mission_X/knowledge/
  2. User Custom         → knowledge-base-custom/
  3. Core Default        → knowledge-base/

Configuration:
  Default config: config/knowledge-config.default.json (git-tracked, don't edit)
  Custom config:  ~/.config/cconductor/knowledge-config.json (user customizations)

  Create custom config:
    ./src/utils/config-loader.sh init knowledge-config
    vim ~/.config/cconductor/knowledge-config.json

Examples:
  # Find where business-methodology is loaded from
  $0 find business-methodology

  # See all knowledge for synthesis agent
  $0 list synthesis-agent | jq .

  # List all available knowledge
  $0 all

  # Add custom knowledge
  mkdir -p knowledge-base-custom
  echo "# My Domain" > knowledge-base-custom/my-domain.md
  $0 discover

EOF
            ;;
        *)
            echo "Unknown command: $1" >&2
            echo "Run '$0 help' for usage" >&2
            exit 1
            ;;
    esac
fi
