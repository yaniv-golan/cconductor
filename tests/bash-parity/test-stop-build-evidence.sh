#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/stop"
EXPECTED_DIR="$SCRIPT_DIR/expected/stop"
BASH_HOOK="$ROOT_DIR/src/utils/hooks/stop-build-evidence.sh"
BASH_RUNTIME="${BASH_RUNTIME:-/opt/homebrew/bin/bash}"

if [[ ! -x "$BASH_RUNTIME" ]]; then
    echo "Expected Bash 4+ at \$BASH_RUNTIME ($BASH_RUNTIME) but it was not found." >&2
    exit 1
fi

run_case() {
    local case_name="$1"
    local fixture_dir="$FIXTURES_DIR/$case_name"

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    cp -R "$fixture_dir/." "$tmp_dir/"

    local expected_file="$EXPECTED_DIR/${case_name}.json"
    if [[ ! -f "$expected_file" ]]; then
        echo "Missing expected output: $expected_file" >&2
        exit 1
    fi

    local payload_bash
    if [[ "$case_name" == "transcript" ]]; then
        payload_bash=$(jq -n --arg path "$tmp_dir/transcript.jsonl" '{transcript_path: $path}')
    else
        payload_bash='{}'
    fi

    (
        cd "$tmp_dir"
        CCONDUCTOR_EVIDENCE_MODE=render \
        CCONDUCTOR_SESSION_DIR="$tmp_dir" \
        "$BASH_RUNTIME" "$BASH_HOOK" <<<"$payload_bash" >/dev/null
    )

    local normalized_actual
    normalized_actual=$(mktemp)
    jq 'del(.generated_at) | del(.metadata.transcript_path)' "$tmp_dir/evidence/evidence.json" | jq -S '.' > "$normalized_actual"

    if ! diff -u "$expected_file" "$normalized_actual"; then
        echo "Parity check failed for case: $case_name" >&2
        exit 1
    fi

    rm -f "$normalized_actual"
    trap - RETURN
}

run_case "findings"
run_case "transcript"

echo "stop-build-evidence parity: ok"
