#!/usr/bin/env bash
# Test extract_cost_from_output helper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../src/utils/invoke-agent.sh"

test_usage_field() {
    local tmpfile
    tmpfile=$(mktemp)
    echo '{"usage": {"total_cost_usd": 0.0042}}' > "$tmpfile"
    local result
    result=$(extract_cost_from_output "$tmpfile")
    rm "$tmpfile"
    if [[ "$result" == "0.0042" ]]; then
        echo "✓ usage.total_cost_usd"
        return 0
    else
        echo "✗ FAILED: expected 0.0042, got $result"
        return 1
    fi
}

test_top_level_field() {
    local tmpfile
    tmpfile=$(mktemp)
    echo '{"total_cost_usd": 0.0031}' > "$tmpfile"
    local result
    result=$(extract_cost_from_output "$tmpfile")
    rm "$tmpfile"
    if [[ "$result" == "0.0031" ]]; then
        echo "✓ total_cost_usd"
        return 0
    else
        echo "✗ FAILED: expected 0.0031, got $result"
        return 1
    fi
}

test_missing_field() {
    local tmpfile
    tmpfile=$(mktemp)
    echo '{"result": "success"}' > "$tmpfile"
    local result
    result=$(extract_cost_from_output "$tmpfile")
    rm "$tmpfile"
    if [[ "$result" == "0" ]]; then
        echo "✓ missing field returns 0"
        return 0
    else
        echo "✗ FAILED: expected 0, got $result"
        return 1
    fi
}

test_missing_file() {
    local result
    result=$(extract_cost_from_output "/nonexistent/file.json")
    if [[ "$result" == "0" ]]; then
        echo "✓ missing file returns 0"
        return 0
    else
        echo "✗ FAILED: expected 0, got $result"
        return 1
    fi
}

echo "Testing extract_cost_from_output..."
test_usage_field
test_top_level_field
test_missing_field
test_missing_file
echo "All tests completed."
