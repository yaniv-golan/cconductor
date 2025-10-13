#!/usr/bin/env bash
# Artifact Manager - Manage artifacts produced by agents
# Tracks artifacts with metadata and provides handoff support

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Initialize artifact manifest
artifact_init() {
  local session_dir="$1"
  
  mkdir -p "$session_dir/artifacts"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  echo '{"artifacts": []}' > "$manifest_file"
}

# Register artifact
artifact_register() {
  local session_dir="$1"
  local artifact_path="$2"
  local artifact_type="$3"
  local produced_by="$4"
  local tags="${5:-}"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    artifact_init "$session_dir"
  fi
  
  if [[ ! -f "$artifact_path" ]]; then
    echo "Error: Artifact file not found: $artifact_path" >&2
    return 1
  fi
  
  # Generate artifact ID
  local artifact_id
  artifact_id=$(echo -n "$artifact_path" | sha256sum | cut -c1-12)
  
  # Get file size and hash
  local file_size
  file_size=$(stat -f%z "$artifact_path" 2>/dev/null || stat -c%s "$artifact_path" 2>/dev/null)
  
  local file_hash
  file_hash=$(sha256sum "$artifact_path" | cut -d' ' -f1)
  
  local timestamp
  timestamp=$(get_timestamp)
  
  # Build tags array
  local tags_json="[]"
  if [[ -n "$tags" ]]; then
    tags_json=$(echo "$tags" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
  fi
  
  # Add to manifest
  jq \
    --arg id "$artifact_id" \
    --arg path "$artifact_path" \
    --arg type "$artifact_type" \
    --arg produced_by "$produced_by" \
    --arg timestamp "$timestamp" \
    --arg sha256 "$file_hash" \
    --argjson size "$file_size" \
    --argjson tags "$tags_json" \
    '.artifacts += [{
      id: $id,
      path: $path,
      type: $type,
      produced_by: $produced_by,
      produced_at: $timestamp,
      sha256: $sha256,
      size: $size,
      tags: $tags
    }]' "$manifest_file" > "$manifest_file.tmp"
  
  mv "$manifest_file.tmp" "$manifest_file"
  
  echo "$artifact_id"
}

# Get artifact path by ID
artifact_get_path() {
  local session_dir="$1"
  local artifact_id="$2"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "Error: Artifact manifest not found" >&2
    return 1
  fi
  
  jq -r \
    --arg id "$artifact_id" \
    '.artifacts[] | select(.id == $id) | .path' \
    "$manifest_file"
}

# List artifacts by agent
artifact_list_by_agent() {
  local session_dir="$1"
  local agent_name="$2"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "[]"
    return 0
  fi
  
  jq \
    --arg agent "$agent_name" \
    '[.artifacts[] | select(.produced_by == $agent)]' \
    "$manifest_file"
}

# Link artifact to handoff
artifact_link_handoff() {
  local session_dir="$1"
  local artifact_id="$2"
  local handoff_id="$3"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "Error: Artifact manifest not found" >&2
    return 1
  fi
  
  jq \
    --arg id "$artifact_id" \
    --arg handoff "$handoff_id" \
    '(.artifacts[] | select(.id == $id) | .handoffs) |= (. // []) + [$handoff]' \
    "$manifest_file" > "$manifest_file.tmp"
  
  mv "$manifest_file.tmp" "$manifest_file"
}

# Get artifact metadata
artifact_get_metadata() {
  local session_dir="$1"
  local artifact_id="$2"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "Error: Artifact manifest not found" >&2
    return 1
  fi
  
  jq \
    --arg id "$artifact_id" \
    '.artifacts[] | select(.id == $id)' \
    "$manifest_file"
}

# List all artifacts
artifact_list_all() {
  local session_dir="$1"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "[]"
    return 0
  fi
  
  jq '.artifacts' "$manifest_file"
}

# Get artifact count
artifact_count() {
  local session_dir="$1"
  
  local manifest_file="$session_dir/artifacts/manifest.json"
  
  if [[ ! -f "$manifest_file" ]]; then
    echo "0"
    return 0
  fi
  
  jq '.artifacts | length' "$manifest_file"
}

