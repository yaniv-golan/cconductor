#!/usr/bin/env bash
# Cross-platform date/time helpers shared by CConductor scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

_DATE_HELPERS_IMPL=""

_date_helpers_detect_impl() {
    if [[ -n "$_DATE_HELPERS_IMPL" ]]; then
        return 0
    fi

    if date --version 2>/dev/null | grep -q "GNU"; then
        _DATE_HELPERS_IMPL="gnu"
    else
        _DATE_HELPERS_IMPL="bsd"
    fi
}

_date_helpers_strip_fractional_seconds() {
    local iso="$1"
    if [[ "$iso" =~ ^(.*T[0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+(.*)$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    else
        echo "$iso"
    fi
}

_date_helpers_normalize_timezone_colon() {
    local iso="$1"
    if [[ "$iso" =~ Z$ ]]; then
        echo "${iso%Z}+00:00"
        return 0
    fi

    if [[ "$iso" =~ [+-][0-9]{4}$ ]]; then
        local base="${iso:0:${#iso}-4}"
        local hours="${iso:${#iso}-4:2}"
        local minutes="${iso:${#iso}-2:2}"
        echo "${base}${hours}:${minutes}"
        return 0
    fi

    if [[ "$iso" =~ [+-][0-9]{2}$ ]]; then
        echo "${iso}:00"
        return 0
    fi

    echo "$iso"
}

_date_helpers_prepare_iso() {
    local raw="$1"
    local trimmed
    trimmed="${raw//$'\r'/}"
    trimmed="${trimmed//$'\n'/}"
    trimmed="${trimmed// /T}"

    if [[ "$trimmed" == "" ]]; then
        echo ""
        return 0
    fi

    local base
    base=$(_date_helpers_strip_fractional_seconds "$trimmed")
    base=$(_date_helpers_normalize_timezone_colon "$base")

    if [[ "$base" =~ [+-][0-9]{2}:[0-9]{2}$ ]]; then
        echo "$base"
    else
        echo "${base}+00:00"
    fi
}

_date_helpers_iso_for_bsd() {
    local with_colon="$1"
    if [[ "$with_colon" =~ (.*)([+-][0-9]{2}):([0-9]{2})$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
    else
        echo "$with_colon"
    fi
}

_date_helpers_format_epoch() {
    local epoch="$1"
    local format="$2"

    _date_helpers_detect_impl

    if [[ "$_DATE_HELPERS_IMPL" == "gnu" ]]; then
        date -d "@$epoch" "$format" 2>/dev/null || return 1
    else
        date -r "$epoch" "$format" 2>/dev/null || return 1
    fi
}

parse_iso_to_epoch() {
    local iso_time="$1"
    local prepared
    prepared=$(_date_helpers_prepare_iso "$iso_time")

    if [[ -z "$prepared" ]]; then
        echo "0"
        return 1
    fi

    _date_helpers_detect_impl

    if [[ "$_DATE_HELPERS_IMPL" == "gnu" ]]; then
        date -d "$prepared" +%s 2>/dev/null || echo "0"
    else
        local bsd_iso
        bsd_iso=$(_date_helpers_iso_for_bsd "$prepared")
        TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd_iso" "+%s" 2>/dev/null || echo "0"
    fi
}

format_epoch_custom() {
    local epoch="$1"
    local format="$2"

    if [[ -z "$epoch" ]]; then
        return 1
    fi

    local formatted
    if formatted=$(_date_helpers_format_epoch "$epoch" "$format"); then
        printf '%s\n' "$formatted"
        return 0
    fi

    return 1
}

format_epoch_date() {
    local epoch="$1"
    if ! format_epoch_custom "$epoch" "+%B %d, %Y"; then
        echo "$epoch"
    fi
}

format_epoch_datetime() {
    local epoch="$1"
    local formatted
    if formatted=$(format_epoch_custom "$epoch" "+%B %d, %Y at %l:%M %p"); then
        echo "$formatted" | sed -E 's/  +/ /g'
    else
        echo "$epoch"
    fi
}

calculate_iso_duration() {
    local start_iso="$1"
    local end_iso="$2"

    local start_epoch end_epoch
    start_epoch=$(parse_iso_to_epoch "$start_iso")
    end_epoch=$(parse_iso_to_epoch "$end_iso")

    if [[ "$start_epoch" == "0" || "$end_epoch" == "0" ]]; then
        echo "0"
        return 1
    fi

    echo $((end_epoch - start_epoch))
}

export -f parse_iso_to_epoch
export -f format_epoch_custom
export -f format_epoch_date
export -f format_epoch_datetime
export -f calculate_iso_duration
