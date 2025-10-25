#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/render"
EXPECTED_DIR="$SCRIPT_DIR/expected/render"
BASH_RENDER="$ROOT_DIR/src/utils/render_mission_report.sh"
BASH_RUNTIME="${BASH_RUNTIME:-/opt/homebrew/bin/bash}"

if [[ ! -x "$BASH_RUNTIME" ]]; then
    echo "Expected Bash 4+ at \$BASH_RUNTIME ($BASH_RUNTIME) but it was not found." >&2
    exit 1
fi

run_case() {
    local case_name="$1"
    local render_mode="$2"

    local fixture_dir="$FIXTURES_DIR/$case_name"
    local expected_file="$EXPECTED_DIR/${case_name}.md"
    if [[ ! -f "$expected_file" ]]; then
        echo "Missing expected report: $expected_file" >&2
        exit 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap 'rm -rf "$tmp_dir"' RETURN

    cp -R "$fixture_dir/." "$tmp_dir/"

    (
        cd "$tmp_dir"
        CCONDUCTOR_EVIDENCE_MODE=render \
        CCONDUCTOR_EVIDENCE_RENDER="$render_mode" \
        "$BASH_RUNTIME" "$BASH_RENDER" "$tmp_dir" >/dev/null
    )

    if ! diff -u "$expected_file" "$tmp_dir/report/mission-report.md"; then
        echo "Render parity failed for case: $case_name" >&2
        exit 1
    fi

    rm -rf "$tmp_dir"
    trap - RETURN
}

run_case "footnotes" "footnotes"
run_case "fallback" "fallback"

echo "render_mission_report parity: ok"
