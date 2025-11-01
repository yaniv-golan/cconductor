#!/usr/bin/env bash
# Cross-platform date helper regression tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/date-helpers.sh"

fail() {
    echo "✗ FAIL: $1" >&2
    exit 1
}

pass() {
    echo "✓ PASS: $1"
}

echo "Running date helper regression tests"
echo "------------------------------------"

epoch_start=$(parse_iso_to_epoch "2025-01-01T00:00:00Z")
epoch_end=$(parse_iso_to_epoch "2025-01-01T00:01:00Z")
if [[ "$epoch_start" == "0" || "$epoch_end" == "0" ]]; then
    fail "ISO timestamps with trailing Z should parse"
fi
if [[ $((epoch_end - epoch_start)) -ne 60 ]]; then
    fail "One minute difference should equal 60 seconds (got $((epoch_end - epoch_start)))"
fi
pass "ISO timestamps with trailing Z parse correctly"

epoch_offset=$(parse_iso_to_epoch "2025-01-01T02:00:00+02:00")
if [[ "$epoch_offset" != "$epoch_start" ]]; then
    fail "Offset timestamp should normalize to the same epoch (got $epoch_offset expected $epoch_start)"
fi
pass "ISO timestamps with timezone offsets normalize correctly"

epoch_fraction=$(parse_iso_to_epoch "2025-01-01T00:00:00.512Z")
if [[ "$epoch_fraction" != "$epoch_start" ]]; then
    fail "Fractional seconds should be ignored (got $epoch_fraction expected $epoch_start)"
fi
pass "Fractional seconds are ignored during parsing"

duration_seconds=$(calculate_iso_duration "2025-01-01T00:00:00Z" "2025-01-01T01:30:00Z")
if [[ "$duration_seconds" != "5400" ]]; then
    fail "Duration calculation expected 5400 seconds (got $duration_seconds)"
fi
pass "ISO duration calculation works"

original_tz="${TZ:-}"
export TZ=UTC
formatted_datetime=$(format_epoch_datetime "$epoch_start")
if [[ "$formatted_datetime" != "January 01, 2025 at 12:00 AM" ]]; then
    fail "Expected formatted datetime in UTC, got '$formatted_datetime'"
fi
formatted_date=$(format_epoch_date "$epoch_start")
if [[ "$formatted_date" != "January 01, 2025" ]]; then
    fail "Expected formatted date in UTC, got '$formatted_date'"
fi
pass "Epoch formatting functions respect timezone"

if [[ -n "$original_tz" ]]; then
    export TZ="$original_tz"
else
    unset TZ
fi

echo ""
echo "All date helper tests passed."
