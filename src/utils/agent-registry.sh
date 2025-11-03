#!/usr/bin/env bash
# Agent Registry - Discovery and validation of agents
# Supports project agents and user-defined agents with override capability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source core helpers first
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/validation.sh"

# Load dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/path-resolver.sh" 2>/dev/null || true

# Registry cache (populated by agent_registry_init)
declare -A AGENT_REGISTRY_CACHE
declare -A AGENT_SOURCE_MAP  # tracks if agent is from project or user
declare -A AGENT_ARTIFACT_FIRST
declare -A AGENT_REQUIRED_ARTIFACTS
declare -A AGENT_OPTIONAL_ARTIFACTS
declare -A AGENT_PRIMARY_ARTIFACT_SLOT
declare -A AGENT_LEGACY_RESULT_PARSING

AGENT_TOOLS_DATA="{}"

_agent_registry_set_artifact_metadata() {
  local agent_name="$1"

  if [[ -z "$agent_name" ]]; then
    return
  fi

  local artifact_first
  artifact_first=$(printf '%s\n' "$AGENT_TOOLS_DATA" | jq -r --arg agent "$agent_name" 'if has($agent) then (.[$agent].artifact_first // false) else false end' 2>/dev/null || echo "false")

  local required_list
  required_list=$(printf '%s\n' "$AGENT_TOOLS_DATA" | jq -c --arg agent "$agent_name" 'if has($agent) then (.[$agent].required_artifacts // []) else [] end' 2>/dev/null || echo "[]")

  local optional_list
  optional_list=$(printf '%s\n' "$AGENT_TOOLS_DATA" | jq -c --arg agent "$agent_name" 'if has($agent) then (.[$agent].optional_artifacts // []) else [] end' 2>/dev/null || echo "[]")

  local primary_slot
  primary_slot=$(printf '%s\n' "$AGENT_TOOLS_DATA" | jq -r --arg agent "$agent_name" 'if has($agent) then (.[$agent].primary_artifact_slot // "") else "" end' 2>/dev/null || echo "")
  [[ "$primary_slot" == "null" ]] && primary_slot=""

  local legacy_result
  legacy_result=$(printf '%s\n' "$AGENT_TOOLS_DATA" | jq -r --arg agent "$agent_name" 'if has($agent) then (.[$agent].legacy_result_parsing // false) else false end' 2>/dev/null || echo "false")

  AGENT_ARTIFACT_FIRST["$agent_name"]="$artifact_first"
  AGENT_REQUIRED_ARTIFACTS["$agent_name"]="$required_list"
  AGENT_OPTIONAL_ARTIFACTS["$agent_name"]="$optional_list"
  AGENT_PRIMARY_ARTIFACT_SLOT["$agent_name"]="$primary_slot"
  AGENT_LEGACY_RESULT_PARSING["$agent_name"]="$legacy_result"
}

# Initialize agent registry
# Scans project and user directories, builds cache
agent_registry_init() {
  local project_agent_dir="$PROJECT_ROOT/src/claude-runtime/agents"
  local user_agent_dir
  
  # Support CCONDUCTOR_USER_CONFIG_DIR for testing
  if [[ -n "${CCONDUCTOR_USER_CONFIG_DIR:-}" ]]; then
    user_agent_dir="$CCONDUCTOR_USER_CONFIG_DIR/agents"
  else
    user_agent_dir=$(path_resolve "user_agent_dir" 2>/dev/null || echo "$HOME/.config/cconductor/agents")
  fi
  
  # Clear cache
  AGENT_REGISTRY_CACHE=()
  AGENT_SOURCE_MAP=()
  AGENT_ARTIFACT_FIRST=()
  AGENT_REQUIRED_ARTIFACTS=()
  AGENT_OPTIONAL_ARTIFACTS=()
  AGENT_PRIMARY_ARTIFACT_SLOT=()
  AGENT_LEGACY_RESULT_PARSING=()

  local agent_tools_file="$PROJECT_ROOT/src/utils/agent-tools.json"
  if [[ -f "$agent_tools_file" ]]; then
    AGENT_TOOLS_DATA=$(cat "$agent_tools_file")
  else
    AGENT_TOOLS_DATA="{}"
  fi
  
  # Load capabilities, input_types, output_types taxonomy
  local capabilities_file="$PROJECT_ROOT/config/capabilities.json"
  local input_types_file="$PROJECT_ROOT/config/input_types.json"
  local output_types_file="$PROJECT_ROOT/config/output_types.json"
  
  if [[ ! -f "$capabilities_file" ]] || [[ ! -f "$input_types_file" ]] || [[ ! -f "$output_types_file" ]]; then
    log_error "Taxonomy files not found in config/"
    log_error "Missing: capabilities.json, input_types.json, or output_types.json"
    return 1
  fi
  
  # Scan project agents
  if [[ -d "$project_agent_dir" ]]; then
    for agent_path in "$project_agent_dir"/*; do
      [[ -d "$agent_path" ]] || continue
      local agent_name
      agent_name=$(basename "$agent_path")
      local metadata_file="$agent_path/metadata.json"
      
      if [[ -f "$metadata_file" ]]; then
        # Validate and cache
        if agent_registry_validate_metadata "$metadata_file" "$agent_name"; then
          AGENT_REGISTRY_CACHE["$agent_name"]="$metadata_file"
          AGENT_SOURCE_MAP["$agent_name"]="project"
          _agent_registry_set_artifact_metadata "$agent_name"
        fi
      fi
    done
  fi
  
  # Scan user agents (override project agents with same name)
  if [[ -d "$user_agent_dir" ]]; then
    for agent_path in "$user_agent_dir"/*; do
      [[ -d "$agent_path" ]] || continue
      local agent_name
      agent_name=$(basename "$agent_path")
      local metadata_file="$agent_path/metadata.json"
      
      if [[ -f "$metadata_file" ]]; then
        if agent_registry_validate_metadata "$metadata_file" "$agent_name"; then
          AGENT_REGISTRY_CACHE["$agent_name"]="$metadata_file"
          AGENT_SOURCE_MAP["$agent_name"]="user"
          _agent_registry_set_artifact_metadata "$agent_name"
        fi
      fi
    done
  fi
  
  # Only show in verbose mode
  if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
    echo "  ✓ Agent registry initialized: ${#AGENT_REGISTRY_CACHE[@]} agents" >&2
  fi
}

# Validate agent metadata against schema
agent_registry_validate_metadata() {
  local metadata_file="$1"
  local agent_name="$2"
  
  # Check valid JSON
  if ! jq empty "$metadata_file" 2>/dev/null; then
    echo "Warning: Invalid JSON in $metadata_file" >&2
    return 1
  fi
  
  # Check required fields
  local required_fields=("name" "description" "tools" "model")
  for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" "$metadata_file" >/dev/null 2>&1; then
      echo "Warning: Missing required field '$field' in $metadata_file" >&2
      return 1
    fi
  done
  
  # Validate name matches directory
  local metadata_name
  metadata_name=$(jq -r '.name' "$metadata_file")
  if [[ "$metadata_name" != "$agent_name" ]]; then
    echo "Warning: Agent name mismatch in $metadata_file: expected '$agent_name', got '$metadata_name'" >&2
    return 1
  fi
  
  # Validate capabilities against taxonomy (if present)
  if jq -e '.capabilities' "$metadata_file" >/dev/null 2>&1; then
    local capabilities_file="$PROJECT_ROOT/config/capabilities.json"
    if [[ -f "$capabilities_file" ]]; then
      local valid_caps
      valid_caps=$(jq -r '.capabilities[].id' "$capabilities_file")
      
      local agent_caps
      agent_caps=$(jq -r '.capabilities[]?' "$metadata_file")
      
      while IFS= read -r cap; do
        [[ -z "$cap" ]] && continue
        if ! echo "$valid_caps" | grep -q "^${cap}$"; then
          echo "Warning: Unknown capability '$cap' in $metadata_file" >&2
          echo "  Valid capabilities: $(echo "$valid_caps" | tr '\n' ', ' | sed 's/,$//')" >&2
        fi
      done <<< "$agent_caps"
    fi
  fi
  
  return 0
}

# Get agent metadata file path
agent_registry_get() {
  local agent_name="$1"
  
  if [[ -z "${AGENT_REGISTRY_CACHE[$agent_name]:-}" ]]; then
    log_error "Agent '$agent_name' not found in registry"
    log_info "Run 'cconductor list-agents' to see available agents"
    return 1
  fi
  
  echo "${AGENT_REGISTRY_CACHE[$agent_name]}"
}

agent_registry_is_artifact_first() {
  local agent_name="$1"
  echo "${AGENT_ARTIFACT_FIRST[$agent_name]:-false}"
}

agent_registry_required_artifacts() {
  local agent_name="$1"
  echo "${AGENT_REQUIRED_ARTIFACTS[$agent_name]:-[]}"
}

agent_registry_optional_artifacts() {
  local agent_name="$1"
  echo "${AGENT_OPTIONAL_ARTIFACTS[$agent_name]:-[]}"
}

agent_registry_primary_artifact_slot() {
  local agent_name="$1"
  echo "${AGENT_PRIMARY_ARTIFACT_SLOT[$agent_name]:-}"
}

agent_registry_legacy_result_parsing() {
  local agent_name="$1"
  echo "${AGENT_LEGACY_RESULT_PARSING[$agent_name]:-false}"
}

# List all agents
agent_registry_list() {
  local format="${1:-simple}"  # simple or detailed
  
  if [[ "$format" == "simple" ]]; then
    for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
      echo "$agent_name"
    done | sort
  elif [[ "$format" == "detailed" ]]; then
    echo "Available agents (${#AGENT_REGISTRY_CACHE[@]}):"
    echo ""
    
    # Group by source
    echo "Built-in agents:"
    for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
      if [[ "${AGENT_SOURCE_MAP[$agent_name]}" == "project" ]]; then
        local metadata_file="${AGENT_REGISTRY_CACHE[$agent_name]}"
        local description
        description=$(jq -r '.description' "$metadata_file")
        local tools
        tools=$(jq -r '.tools | join(", ")' "$metadata_file")
        echo "  $agent_name - $description [$tools]"
      fi
    done | sort
    
    echo ""
    echo "User agents:"
    for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
      if [[ "${AGENT_SOURCE_MAP[$agent_name]}" == "user" ]]; then
        local metadata_file="${AGENT_REGISTRY_CACHE[$agent_name]}"
        local description
        description=$(jq -r '.description' "$metadata_file")
        local tools
        tools=$(jq -r '.tools | join(", ")' "$metadata_file")
        echo "  $agent_name - $description [$tools]"
      fi
    done | sort
    
    # Check if no user agents were found (not modified in subshell)
    local user_agent_count=0
    for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
      if [[ "${AGENT_SOURCE_MAP[$agent_name]}" == "user" ]]; then
        user_agent_count=$((user_agent_count + 1))
      fi
    done
    if [ "$user_agent_count" -eq 0 ]; then
      echo "  (none)"
    fi
  fi
}

# Query agents by capability
agent_registry_query_capabilities() {
  local required_capability="$1"
  
  for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
    local metadata_file="${AGENT_REGISTRY_CACHE[$agent_name]}"
    
    # Check if agent has capability
    if jq -e --arg cap "$required_capability" \
       '.capabilities[]? | select(. == $cap)' \
       "$metadata_file" >/dev/null 2>&1; then
      echo "$agent_name"
    fi
  done
}

# Get agent metadata as JSON
agent_registry_get_metadata() {
  local agent_name="$1"
  
  local metadata_file
  metadata_file=$(agent_registry_get "$agent_name") || return 1
  
  cat "$metadata_file"
}

# Check if agent exists
agent_registry_exists() {
  local agent_name="$1"
  
  [[ -n "${AGENT_REGISTRY_CACHE[$agent_name]:-}" ]]
}

# Get agent source (project or user)
agent_registry_get_source() {
  local agent_name="$1"
  
  if [[ -z "${AGENT_SOURCE_MAP[$agent_name]:-}" ]]; then
    echo "unknown"
    return 1
  fi
  
  echo "${AGENT_SOURCE_MAP[$agent_name]}"
}

# Export registry as JSON
agent_registry_export_json() {
  local output_file="${1:-/dev/stdout}"
  
  local agents_json="[]"
  
  for agent_name in "${!AGENT_REGISTRY_CACHE[@]}"; do
    local metadata_file="${AGENT_REGISTRY_CACHE[$agent_name]}"
    local source="${AGENT_SOURCE_MAP[$agent_name]}"
    
    local agent_metadata
    agent_metadata=$(jq --arg source "$source" '. + {source: $source}' "$metadata_file")
    
    agents_json=$(echo "$agents_json" | jq --argjson agent "$agent_metadata" '. + [$agent]')
  done
  
  if [[ "$output_file" == "/dev/stdout" ]]; then
    printf '%s\n' "$agents_json"
  else
    echo "$agents_json" | jq '.' > "$output_file"
  fi
}
