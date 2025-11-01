#!/usr/bin/env bash
# Artifact Manager - Manage artifacts produced by agents
# Tracks artifacts with metadata and provides handoff support

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source core helpers first
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# Check for jq dependency using helper
require_command "jq" "brew install jq" "apt install jq" || exit 1

# Source shared-state for atomic operations
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"

# Resolve contract path for agent
artifact_contract_path() {
  local agent_name="$1"
  local contract_path="$PROJECT_ROOT/config/artifact-contracts/$agent_name/manifest.expected.json"
  if [[ ! -f "$contract_path" ]]; then
    log_error "Artifact contract not found for agent $agent_name at $contract_path"
    return 1
  fi
  echo "$contract_path"
}

# Resolve schema path from schema_id (e.g., artifact://markdown/mission-report@v1)
artifact_schema_path() {
  local schema_id="$1"
  local trimmed="${schema_id#artifact://}"
  local base="${trimmed%@*}"
  local schema_path="$PROJECT_ROOT/config/schemas/artifacts/${base}.schema.json"

  if [[ ! -f "$schema_path" ]]; then
    log_error "Schema path not found for $schema_id ($schema_path)"
    return 1
  fi

  echo "$schema_path"
}

# Prepare directories for agent artifacts based on contract definition
artifact_prepare_directories() {
  local session_dir="$1"
  local agent_name="$2"

  if [[ -z "$session_dir" || -z "$agent_name" ]]; then
    log_error "artifact_prepare_directories requires session_dir and agent_name"
    return 1
  fi

  local contract_path
  if ! contract_path=$(artifact_contract_path "$agent_name"); then
    return 1
  fi

  local -a artifact_paths=()
  mapfile -t artifact_paths < <(jq -r '.artifacts[] | .relative_path // empty' "$contract_path")
  if [[ "${#artifact_paths[@]}" -eq 0 ]]; then
    return 0
  fi

  local rel_path parent_dir
  for rel_path in "${artifact_paths[@]}"; do
    [[ -z "$rel_path" ]] && continue
    parent_dir=$(dirname "$rel_path")
    if [[ -z "$parent_dir" || "$parent_dir" == "." ]]; then
      continue
    fi
    mkdir -p "$session_dir/$parent_dir"
  done
}

# Atomic write helper
artifact_write_json_atomic() {
  local target_path="$1"
  local payload="$2"

  local tmp_path="${target_path}.tmp"
  printf '%s\n' "$payload" > "$tmp_path"

  # Attempt fsync if available for durability
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "$tmp_path"
from pathlib import Path
import os, sys
path = Path(sys.argv[1])
with path.open("r+") as handle:
    handle.flush()
    os.fsync(handle.fileno())
PY
  fi

  mv "$tmp_path" "$target_path"
}

# Build manifest.actual.json for an agent
artifact_finalize_manifest() {
  local session_dir="$1"
  local agent_name="$2"
  local validation_phase="${3:-phase2}"
  local bypass_flag="${4:-0}"

  local contract_path
  if ! contract_path=$(artifact_contract_path "$agent_name"); then
    return 1
  fi

  local contract_sha
  contract_sha=$("$SCRIPT_DIR/hash-file.sh" "$contract_path")

  local work_dir="$session_dir/work/$agent_name"
  mkdir -p "$work_dir"
  local manifest_path="$work_dir/manifest.actual.json"

  local validation_start_ms
  if command -v python3 >/dev/null 2>&1; then
      validation_start_ms=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
  else
      validation_start_ms=$(($(get_epoch) * 1000))
  fi

  local timestamp
  timestamp=$(get_timestamp)

  local artifacts=()
  local missing_slots=()
  local schema_failures=()
  local checksum_failures=()
  local required_total=0
  local required_present=0
  local optional_present=0

  mapfile -t expected_entries < <(jq -c '.artifacts[]' "$contract_path")

  shopt -s nullglob

  local entry_json
  for entry_json in "${expected_entries[@]}"; do
    local slot
    slot=$(jq -r '.slot' <<<"$entry_json")
    local relative_path
    relative_path=$(jq -r '.relative_path // empty' <<<"$entry_json")
    local path_pattern
    path_pattern=$(jq -r '.path_pattern // empty' <<<"$entry_json")
    local required
    required=$(jq -r '.required' <<<"$entry_json")
    local content_type
    content_type=$(jq -r '.content_type // empty' <<<"$entry_json")
    local schema_id
    schema_id=$(jq -r '.schema_id' <<<"$entry_json")
    local allow_multiple
    allow_multiple=$(jq -r '.allow_multiple // false' <<<"$entry_json")

    if [[ "$required" == "true" ]]; then
      required_total=$((required_total + 1))
    fi

    local match_paths=()
    if [[ -n "$relative_path" ]]; then
      local absolute_path="$session_dir/$relative_path"
      if [[ -f "$absolute_path" ]]; then
        match_paths+=("$absolute_path")
      fi
    elif [[ -n "$path_pattern" ]]; then
      local absolute_pattern="$session_dir/$path_pattern"
      while IFS= read -r candidate; do
        [[ -f "$candidate" ]] && match_paths+=("$candidate")
      done < <(compgen -G "$absolute_pattern" || true)
    fi

    local emitted_any=0
    local slot_index=0

    if [[ "${#match_paths[@]}" -gt 1 && "$allow_multiple" != "true" ]]; then
      log_warn "Multiple artifacts matched slot '$slot' but allow_multiple is false (agent: $agent_name)"
    fi

    local schema_path=""
    if [[ -n "$schema_id" ]]; then
      if schema_path=$(artifact_schema_path "$schema_id"); then
        true
      else
        schema_path=""
        log_warn "Schema lookup failed for slot '$slot' ($schema_id)"
      fi
    fi

    if [[ ${#match_paths[@]} -eq 0 ]]; then
      local relative_display="$relative_path"
      [[ -z "$relative_display" ]] && relative_display="$path_pattern"
      local missing_entry
      missing_entry=$(jq -n \
        --arg slot "$slot" \
        --arg relative "$relative_display" \
        --arg content "$content_type" \
        --arg schema "$schema_id" \
        --arg required "$required" \
        --arg phase "$validation_phase" \
        --arg timestamp "$timestamp" \
        --argjson required_bool "$( [[ "$required" == "true" ]] && echo true || echo false )" \
        '{
          slot: $slot,
          relative_path: $relative,
          content_type: ($content // ""),
          schema_id: $schema,
          required: ($required_bool),
          status: "missing",
          validated_at: $timestamp,
          validation: {
            schema: "skipped",
            checksum: "skipped"
          },
          messages: ["Artifact missing for slot"]
        }')
      artifacts+=("$missing_entry")
      if [[ "$required" == "true" ]]; then
        missing_slots+=("$slot")
      fi
      continue
    fi

    local path
    for path in "${match_paths[@]}"; do
      if [[ "$allow_multiple" != "true" && $slot_index -ge 1 ]]; then
        break
      fi

      emitted_any=1

      local rel_path="${path#"$session_dir"/}"
      [[ "$rel_path" == "$path" ]] && rel_path="$path"

      local size
      size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0)
      local sha256
      local checksum_status="passed"
      if [[ -f "$path" ]]; then
        sha256=$("$SCRIPT_DIR/hash-file.sh" "$path")
      else
        sha256=""
        checksum_status="skipped"
      fi

      local schema_status="skipped"
      local messages_json="[]"

      local is_json=0
      if [[ "$content_type" == *"json"* ]]; then
        is_json=1
      elif [[ "$rel_path" == *.json ]]; then
        is_json=1
      fi

      if [[ -n "$schema_path" && -f "$path" && $is_json -eq 1 ]]; then
        if json_validate_with_schema "$schema_path" "$path"; then
          schema_status="passed"
        else
          schema_status="failed"
          checksum_status="passed"
          messages_json=$(jq -n --arg msg "Schema validation failed" '[ $msg ]')
          schema_failures+=("$slot")
        fi
      elif [[ -n "$schema_path" && -f "$path" && $is_json -eq 0 ]]; then
        schema_status="skipped"
      fi

      if [[ "$content_type" == "text/markdown" && "$size" -le 0 ]]; then
        schema_status="failed"
        messages_json=$(jq -n --arg msg "Markdown artifact is empty" '[ $msg ]')
        schema_failures+=("$slot")
      fi

      if [[ -z "$sha256" ]]; then
        checksum_status="failed"
        messages_json=$(jq -n --arg msg "Checksum unavailable" '[ $msg ]')
        checksum_failures+=("$slot")
      fi

      local entry
      entry=$(jq -n \
        --arg slot "$slot" \
        --argjson slot_index "$slot_index" \
        --arg relative "$rel_path" \
        --arg content "$content_type" \
        --arg schema "$schema_id" \
        --arg required "$required" \
        --arg status "$( [[ "$schema_status" == "failed" || "$checksum_status" == "failed" ]] && echo "invalid" || echo "present" )" \
        --arg sha "$sha256" \
        --argjson size "$size" \
        --arg timestamp "$timestamp" \
        --arg schema_status "$schema_status" \
        --arg checksum_status "$checksum_status" \
        --argjson messages "$messages_json" \
        '{
          slot: $slot,
          slot_instance: $slot_index,
          relative_path: $relative,
          content_type: ($content // ""),
          schema_id: $schema,
          required: ($required == "true"),
          status: $status,
          sha256: ($sha // ""),
          size_bytes: $size,
          validated_at: $timestamp,
          validation: {
            schema: $schema_status,
            checksum: $checksum_status
          },
          messages: $messages
        }')
      artifacts+=("$entry")

      if [[ "$required" == "true" ]]; then
        if [[ "$schema_status" == "failed" || "$checksum_status" == "failed" ]]; then
          # invalid required artifact
          :
        else
          required_present=$((required_present + 1))
        fi
      else
        if [[ "$schema_status" != "failed" && "$checksum_status" != "failed" ]]; then
          optional_present=$((optional_present + 1))
        fi
      fi

      slot_index=$((slot_index + 1))
    done

    if [[ "$required" == "true" && $emitted_any -eq 0 ]]; then
      missing_slots+=("$slot")
    fi
  done

  shopt -u nullglob

  local artifacts_json="[]"
  if [[ ${#artifacts[@]} -gt 0 ]]; then
    artifacts_json=$(printf '%s\n' "${artifacts[@]}" | jq -s '.')
  fi

  local summary
  local missing_json="[]"
  local checksum_json="[]"
  local schema_json="[]"

  if [[ ${#missing_slots[@]} -gt 0 ]]; then
    missing_json=$(printf '%s\n' "${missing_slots[@]}" | jq -R . | jq -s '.')
  fi
  if [[ ${#checksum_failures[@]} -gt 0 ]]; then
    checksum_json=$(printf '%s\n' "${checksum_failures[@]}" | jq -R . | jq -s '.')
  fi
  if [[ ${#schema_failures[@]} -gt 0 ]]; then
    schema_json=$(printf '%s\n' "${schema_failures[@]}" | jq -R . | jq -s '.')
  fi

  local artifact_count
  artifact_count=$(echo "$artifacts_json" | jq 'length')

  summary=$(jq -n \
    --argjson required_total "$required_total" \
    --argjson required_present "$required_present" \
    --argjson optional_present "$optional_present" \
    --argjson missing "$missing_json" \
    --argjson checksum "$checksum_json" \
    --argjson schema "$schema_json" \
    --argjson total_artifacts "$artifact_count" \
    '{
      required_total: $required_total,
      required_present: $required_present,
      optional_present: $optional_present,
      total_artifacts: $total_artifacts,
      missing_slots: $missing,
      checksum_failures: $checksum,
      schema_failures: $schema
    }')

  local validation_end_ms
  if command -v python3 >/dev/null 2>&1; then
      validation_end_ms=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
  else
      validation_end_ms=$(($(get_epoch) * 1000))
  fi
  local validation_duration_ms=$((validation_end_ms - validation_start_ms))
  if [[ $validation_duration_ms -lt 0 ]]; then
      validation_duration_ms=0
  fi

  local manifest
  manifest=$(jq -n \
    --arg schema_version "1.0.0" \
    --arg agent "$agent_name" \
    --arg generated_at "$timestamp" \
    --arg contract_path_rel "${contract_path#"$PROJECT_ROOT"/}" \
    --arg contract_sha "$contract_sha" \
    --arg validation_phase "$validation_phase" \
    --argjson validation_duration_ms "$validation_duration_ms" \
    --argjson artifacts "$artifacts_json" \
    --argjson summary "$summary" \
    '{
      schema_version: $schema_version,
      agent: $agent,
      generated_at: $generated_at,
      contract_path: $contract_path_rel,
      contract_sha256: $contract_sha,
      validation_phase: $validation_phase,
      validation_duration_ms: $validation_duration_ms,
      artifacts: $artifacts,
      summary: $summary
    }')

  artifact_write_json_atomic "$manifest_path" "$manifest"

  local output_payload
  output_payload=$(jq -n \
    --arg manifest_path_rel "${manifest_path#"$session_dir"/}" \
    --arg validation_phase "$validation_phase" \
    --argjson validation_duration_ms "$validation_duration_ms" \
    --argjson summary "$summary" \
    '{
      manifest_path: $manifest_path_rel,
      validation_phase: $validation_phase,
      validation_duration_ms: $validation_duration_ms,
      summary: $summary
    }')
  echo "$output_payload"

  local should_fail=0
  if [[ "$validation_phase" == "phase1" ]]; then
    should_fail=0
  else
    if [[ ${#missing_slots[@]} -gt 0 || ${#schema_failures[@]} -gt 0 || ${#checksum_failures[@]} -gt 0 ]]; then
      should_fail=1
    fi
  fi

  if [[ "$bypass_flag" -eq 1 ]]; then
    should_fail=0
  fi

  return "$should_fail"
}

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
  
  # Validate or reinitialize manifest
  if [[ -f "$manifest_file" ]]; then
    if ! jq -e '.artifacts | type == "array"' "$manifest_file" >/dev/null 2>&1; then
      echo "Warning: Corrupted artifact manifest detected, reinitializing" >&2
      artifact_init "$session_dir"
    fi
  else
    artifact_init "$session_dir"
  fi
  
  if [[ ! -f "$artifact_path" ]]; then
    echo "Error: Artifact file not found: $artifact_path" >&2
    return 1
  fi
  
  # Generate content-based artifact ID (stable across file moves)
  local artifact_id
  artifact_id=$("$SCRIPT_DIR/hash-file.sh" "$artifact_path" | cut -c1-12)
  
  # Get file size and hash
  local file_size
  file_size=$(stat -f%z "$artifact_path" 2>/dev/null || stat -c%s "$artifact_path" 2>/dev/null)
  
  local file_hash
  file_hash=$("$SCRIPT_DIR/hash-file.sh" "$artifact_path")
  
  local timestamp
  timestamp=$(get_timestamp)
  
  # Build tags array
  local tags_json="[]"
  if [[ -n "$tags" ]]; then
    tags_json=$(echo "$tags" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')
  fi
  
  # Add to manifest with atomic update
  # shellcheck disable=SC2016
  atomic_json_update "$manifest_file" \
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
    }]'
  
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
  
  local result
  result=$(jq -r \
    --arg id "$artifact_id" \
    '.artifacts[] | select(.id == $id) | .path' \
    "$manifest_file")
  
  # Check if artifact was found
  if [[ -z "$result" || "$result" == "null" ]]; then
    echo "Error: Artifact not found: $artifact_id" >&2
    return 1
  fi
  
  echo "$result"
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
  
  # shellcheck disable=SC2016
  atomic_json_update "$manifest_file" \
    --arg id "$artifact_id" \
    --arg handoff "$handoff_id" \
    '(.artifacts[] | select(.id == $id) | .handoffs) |= (. // []) + [$handoff]'
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
