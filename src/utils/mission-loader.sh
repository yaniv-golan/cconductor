#!/usr/bin/env bash
# Mission Loader - Load and validate mission profiles
# Supports project missions and user-defined missions with override capability

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load dependencies
# shellcheck disable=SC1091
source "$SCRIPT_DIR/path-resolver.sh" 2>/dev/null || true

# Load mission profile by name
# User missions override project missions
mission_load() {
  local mission_name="$1"
  
  local user_mission_dir
  # Support CCONDUCTOR_USER_CONFIG_DIR for testing
  if [[ -n "${CCONDUCTOR_USER_CONFIG_DIR:-}" ]]; then
    user_mission_dir="$CCONDUCTOR_USER_CONFIG_DIR/missions"
  else
    user_mission_dir=$(path_resolve "user_mission_dir" 2>/dev/null || echo "$HOME/.config/cconductor/missions")
  fi
  local project_mission_dir="$PROJECT_ROOT/config/missions"
  
  local mission_file=""
  
  # Check user directory first (override)
  if [[ -f "$user_mission_dir/${mission_name}.json" ]]; then
    mission_file="$user_mission_dir/${mission_name}.json"
  elif [[ -f "$project_mission_dir/${mission_name}.json" ]]; then
    mission_file="$project_mission_dir/${mission_name}.json"
  else
    echo "Error: Mission '$mission_name' not found" >&2
    echo "  Searched: $user_mission_dir/" >&2
    echo "            $project_mission_dir/" >&2
    return 1
  fi
  
  # Validate mission profile
  if ! mission_validate "$mission_file"; then
    echo "Error: Mission validation failed for '$mission_name'" >&2
    return 1
  fi
  
  cat "$mission_file"
}

# Load mission from file path
mission_load_file() {
  local mission_file="$1"
  
  if [[ ! -f "$mission_file" ]]; then
    echo "Error: Mission file not found: $mission_file" >&2
    return 1
  fi
  
  if ! mission_validate "$mission_file"; then
    echo "Error: Mission validation failed" >&2
    return 1
  fi
  
  cat "$mission_file"
}

# Validate mission profile
mission_validate() {
  local mission_file="$1"
  
  # Check valid JSON
  if ! jq empty "$mission_file" 2>/dev/null; then
    echo "Error: Invalid JSON in $mission_file" >&2
    return 1
  fi
  
  # JSON schema validation if ajv-cli is available
  local schema_file="$PROJECT_ROOT/config/schemas/mission-profile.schema.json"
  if command -v ajv >/dev/null 2>&1 && [[ -f "$schema_file" ]]; then
    if ! ajv validate -s "$schema_file" -d "$mission_file" 2>/dev/null; then
      echo "Warning: Mission does not conform to schema" >&2
      # Don't fail - just warn
    fi
  fi
  
  # Check required fields
  local required_fields=(
    "name"
    "description"
    "objective"
    "success_criteria"
    "constraints"
  )
  
  for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" "$mission_file" >/dev/null 2>&1; then
      echo "Error: Missing required field '$field' in mission profile" >&2
      return 1
    fi
  done
  
  # Validate success_criteria structure
  if ! jq -e '.success_criteria.required_outputs' "$mission_file" >/dev/null 2>&1; then
    echo "Error: Missing success_criteria.required_outputs in mission profile" >&2
    return 1
  fi
  
  # Validate constraints structure
  local constraint_fields=("max_iterations")
  for field in "${constraint_fields[@]}"; do
    if ! jq -e ".constraints.$field" "$mission_file" >/dev/null 2>&1; then
      echo "Error: Missing constraints.$field in mission profile" >&2
      return 1
    fi
  done
  
  # Validate numeric constraints
  local max_iterations
  max_iterations=$(jq -r '.constraints.max_iterations' "$mission_file")
  if [[ ! "$max_iterations" =~ ^[0-9]+$ ]] || [[ "$max_iterations" -lt 1 ]]; then
    echo "Error: constraints.max_iterations must be a positive integer" >&2
    return 1
  fi
  
  return 0
}

# List available missions
mission_list() {
  local format="${1:-simple}"  # simple or detailed
  
  local user_mission_dir
  # Support CCONDUCTOR_USER_CONFIG_DIR for testing
  if [[ -n "${CCONDUCTOR_USER_CONFIG_DIR:-}" ]]; then
    user_mission_dir="$CCONDUCTOR_USER_CONFIG_DIR/missions"
  else
    user_mission_dir=$(path_resolve "user_mission_dir" 2>/dev/null || echo "$HOME/.config/cconductor/missions")
  fi
  local project_mission_dir="$PROJECT_ROOT/config/missions"
  
  declare -A missions
  
  # Scan project missions
  if [[ -d "$project_mission_dir" ]]; then
    for mission_file in "$project_mission_dir"/*.json; do
      [[ -f "$mission_file" ]] || continue
      local mission_name
      mission_name=$(basename "$mission_file" .json)
      missions["$mission_name"]="project"
    done
  fi
  
  # Scan user missions (override)
  if [[ -d "$user_mission_dir" ]]; then
    for mission_file in "$user_mission_dir"/*.json; do
      [[ -f "$mission_file" ]] || continue
      local mission_name
      mission_name=$(basename "$mission_file" .json)
      missions["$mission_name"]="user"
    done
  fi
  
  if [[ "$format" == "simple" ]]; then
    for mission_name in "${!missions[@]}"; do
      echo "$mission_name"
    done | sort
  elif [[ "$format" == "detailed" ]]; then
    echo "Available missions (${#missions[@]}):"
    echo ""
    
    echo "Built-in missions:"
    for mission_name in "${!missions[@]}"; do
      if [[ "${missions[$mission_name]}" == "project" ]]; then
        local mission_file="$project_mission_dir/${mission_name}.json"
        local description
        description=$(jq -r '.description' "$mission_file" 2>/dev/null || echo "")
        echo "  $mission_name - $description"
      fi
    done | sort
    
    echo ""
    echo "User missions:"
    for mission_name in "${!missions[@]}"; do
      if [[ "${missions[$mission_name]}" == "user" ]]; then
        local mission_file="$user_mission_dir/${mission_name}.json"
        local description
        description=$(jq -r '.description' "$mission_file" 2>/dev/null || echo "")
        echo "  $mission_name - $description"
      fi
    done | sort
    
    # Check if no user missions were found (not modified in subshell)
    local user_mission_count=0
    for mission_name in "${!missions[@]}"; do
      if [[ "${missions[$mission_name]}" == "user" ]]; then
        user_mission_count=$((user_mission_count + 1))
      fi
    done
    if [ "$user_mission_count" -eq 0 ]; then
      echo "  (none)"
    fi
  fi
}

# Describe a mission
mission_describe() {
  local mission_name="$1"
  
  local mission_profile
  mission_profile=$(mission_load "$mission_name") || return 1
  
  echo "Mission: $mission_name"
  echo ""
  echo "Description:"
  echo "  $(echo "$mission_profile" | jq -r '.description')"
  echo ""
  echo "Objective:"
  echo "  $(echo "$mission_profile" | jq -r '.objective')"
  echo ""
  echo "Success Criteria:"
  echo "  Required outputs:"
  echo "$mission_profile" | jq -r '.success_criteria.required_outputs[] | "    - \(.)"'
  
  if echo "$mission_profile" | jq -e '.success_criteria.required_validations' >/dev/null 2>&1; then
    echo "  Required validations:"
    echo "$mission_profile" | jq -r '.success_criteria.required_validations[] | "    - \(.)"'
  fi
  
  local confidence_threshold
  confidence_threshold=$(echo "$mission_profile" | jq -r '.success_criteria.confidence_threshold // "N/A"')
  echo "  Confidence threshold: $confidence_threshold"
  
  echo ""
  echo "Constraints:"
  echo "$mission_profile" | jq -r '.constraints | to_entries | .[] | "  \(.key): \(.value)"'
  
  if echo "$mission_profile" | jq -e '.preferred_agents' >/dev/null 2>&1; then
    echo ""
    echo "Preferred Agents:"
    echo "$mission_profile" | jq -r '.preferred_agents[] | "  - \(.agent): \(.for)"'
  fi
  
  if echo "$mission_profile" | jq -e '.orchestration_guidance' >/dev/null 2>&1; then
    echo ""
    echo "Orchestration Guidance:"
    echo "  $(echo "$mission_profile" | jq -r '.orchestration_guidance')"
  fi
}

# Expand template variables in mission (future use)
mission_expand_template() {
  local mission_json="$1"
  shift
  # Note: replacements array reserved for future variable replacement feature
  # shellcheck disable=SC2034
  local -a replacements=("$@")
  
  # For now, just return as-is
  # Future: support {{variable}} replacement
  echo "$mission_json"
}

# Check if mission exists
mission_exists() {
  local mission_name="$1"
  
  local user_mission_dir
  # Support CCONDUCTOR_USER_CONFIG_DIR for testing
  if [[ -n "${CCONDUCTOR_USER_CONFIG_DIR:-}" ]]; then
    user_mission_dir="$CCONDUCTOR_USER_CONFIG_DIR/missions"
  else
    user_mission_dir=$(path_resolve "user_mission_dir" 2>/dev/null || echo "$HOME/.config/cconductor/missions")
  fi
  local project_mission_dir="$PROJECT_ROOT/config/missions"
  
  [[ -f "$user_mission_dir/${mission_name}.json" ]] || \
  [[ -f "$project_mission_dir/${mission_name}.json" ]]
}

