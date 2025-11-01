#!/usr/bin/env bash
# Validate artifact contracts and schema references

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4.0 or higher is required to run this test." >&2
        exit 1
    fi
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source helpers
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/artifact-manager.sh"

EXPECTED_SCHEMA="$PROJECT_ROOT/config/schemas/artifacts/system/manifest-expected.schema.json"
echo "Checking artifact contracts under config/artifact-contracts/"

manifest_count=0
while IFS= read -r manifest_file; do
    manifest_count=$((manifest_count + 1))
    agent_name=$(basename "$(dirname "$manifest_file")")

    echo "  • $agent_name"

    # Validate JSON structure via schema
    if ! json_validate_with_schema "$EXPECTED_SCHEMA" "$manifest_file"; then
        echo "    ✗ Schema validation failed for $manifest_file"
        exit 1
    fi

    # Ensure each schema_id resolves to a schema file
    mapfile -t schema_ids < <(jq -r '.artifacts[] | .schema_id' "$manifest_file")
    for schema_id in "${schema_ids[@]}"; do
        if [[ -z "$schema_id" || "$schema_id" == "null" ]]; then
            continue
        fi
        local_schema_path="$(artifact_schema_path "$schema_id" 2>/dev/null || true)"
        if [[ -z "$local_schema_path" || ! -f "$local_schema_path" ]]; then
            echo "    ✗ Missing schema for $schema_id referenced by $manifest_file"
            exit 1
        fi
    done

    # Ensure relative paths/patterns stay relative (no leading slash)
    mapfile -t paths < <(jq -r '.artifacts[] | (.relative_path // empty), (.path_pattern // empty)' "$manifest_file")
    for rel in "${paths[@]}"; do
        [[ -z "$rel" ]] && continue
        if [[ "$rel" == /* ]]; then
            echo "    ✗ $agent_name manifest contains absolute path: $rel"
            exit 1
        fi
    done

done < <(find "$PROJECT_ROOT/config/artifact-contracts" -name 'manifest.expected.json' | sort)

if [[ $manifest_count -eq 0 ]]; then
    echo "No manifests found; aborting"
    exit 1
fi

printf "\nValidating fixture manifest generation\n"
FIXTURE_SRC="$PROJECT_ROOT/tests/data/artifact-contracts/basic-session"
TEMP_DIR="$(mktemp -d -t contract-fixture-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT
cp -R "$FIXTURE_SRC" "$TEMP_DIR/session"
SESSION_DIR="$TEMP_DIR/session"

# Run manifest generation for key agents
manifest_output_web="$(artifact_finalize_manifest "$SESSION_DIR" "web-researcher" "phase2" 0)"
manifest_output_syn="$(artifact_finalize_manifest "$SESSION_DIR" "synthesis-agent" "phase2" 0)"

# Validate manifest summary numbers
required_web=$(echo "$manifest_output_web" | jq -r '.summary.required_total // 0')
missing_web=$(echo "$manifest_output_web" | jq -r '.summary.missing_slots | length')
if [[ "$required_web" -ne 2 || "$missing_web" -ne 0 ]]; then
    echo "✗ Unexpected web-researcher manifest summary"
    echo "$manifest_output_web"
    exit 1
fi

required_syn=$(echo "$manifest_output_syn" | jq -r '.summary.required_total // 0')
missing_syn=$(echo "$manifest_output_syn" | jq -r '.summary.missing_slots | length')
if [[ "$required_syn" -lt 5 || "$missing_syn" -ne 0 ]]; then
    echo "✗ Unexpected synthesis-agent manifest summary"
    echo "$manifest_output_syn"
    exit 1
fi

echo "✓ All artifact contracts validated"
