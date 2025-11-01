#!/usr/bin/env bash
# argument-events.sh - Helpers for generating IDs and envelopes for argument_event payloads

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"

argument_events_hex_to_base32() {
    local hex_value="$1"
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' "$hex_value"
import sys, base64
hex_value = sys.argv[1].strip()
try:
    digest = bytes.fromhex(hex_value)
except ValueError:
    print(hex_value)
    sys.exit(0)
encoded = base64.b32encode(digest).decode("ascii").rstrip("=").lower()
print(encoded)
PY
    else
        echo "$hex_value"
    fi
}

usage() {
    cat >&2 <<'EOF'
Usage: argument-events.sh <command> [options]

Commands:
  id --prefix <prefix> --seed "<text>" [--mission-step <step>] [--length <n>]
      Generate a deterministic identifier by hashing the seed (optionally scoped with mission step).
      Example: argument-events.sh id --prefix clm --mission-step S2.task.003 --seed "Claim text"

  envelope (--events-json '<json>' | --events-file <path>)
      Wrap one or more events in the standard stream_event envelope suitable for Claude streaming.

  help
      Show this help message.
EOF
    exit 1
}

require_min_args() {
    local got="$1"
    local needed="$2"
    if (( got < needed )); then
        usage
    fi
}

ensure_events_json() {
    local input="$1"
    if [[ -z "$input" ]]; then
        log_error "argument-events: events payload required (use --events-json or --events-file)"
        exit 1
    fi
    require_command jq
    local normalized
    normalized=$(printf '%s' "$input" | jq -c '
        if type == "array" then .
        elif type == "object" and has("events") then .events
        else [.] end
    ' 2>/dev/null) || {
        log_error "argument-events: failed to parse JSON events payload"
        exit 1
    }
    printf '%s' "$normalized"
}

command="${1:-help}"
shift || true

cmd_id() {
    require_min_args "$#" 2
    local prefix=""
    local seed=""
    local mission_step=""
    local length=12

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix)
                prefix="$2"
                shift 2
                ;;
            --seed)
                seed="$2"
                shift 2
                ;;
            --mission-step)
                mission_step="$2"
                shift 2
                ;;
            --length)
                length="$2"
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_error "argument-events: unknown option '$1' for id command"
                usage
                ;;
        esac
    done

    if [[ -z "$prefix" || -z "$seed" ]]; then
        log_error "argument-events: --prefix and --seed are required for id command"
        usage
    fi

    if ! [[ "$length" =~ ^[0-9]+$ ]]; then
        log_error "argument-events: --length must be numeric"
        exit 1
    fi

    local scope="$seed"
    if [[ -n "$mission_step" ]]; then
        scope="${mission_step}::${seed}"
    fi

    local hash
    hash=$("$SCRIPT_DIR/hash-string.sh" "$scope")
    local base32
    base32=$(argument_events_hex_to_base32 "$hash")
    local truncated="${base32:0:length}"

    printf '%s-%s\n' "$prefix" "$truncated"
}

cmd_envelope() {
    require_min_args "$#" 1
    local events_json=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --events-json)
                events_json="$2"
                shift 2
                ;;
            --events-file)
                if [[ ! -f "$2" ]]; then
                    log_error "argument-events: events file '$2' not found"
                    exit 1
                fi
                events_json=$(<"$2")
                shift 2
                ;;
            --help|-h)
                usage
                ;;
            *)
                log_error "argument-events: unknown option '$1' for envelope command"
                usage
                ;;
        esac
    done

    local normalized
    normalized=$(ensure_events_json "$events_json")
    require_command jq
    printf '%s\n' "$normalized" | jq -c '
        {
            type: "stream_event",
            event: {
                type: "custom_event",
                name: "argument_event",
                payload: {
                    events: .
                }
            }
        }
    '
}

case "$command" in
    id)
        cmd_id "$@"
        ;;

    envelope)
        cmd_envelope "$@"
        ;;

    help|--help|-h)
        usage
        ;;

    *)
        log_error "argument-events: unknown command '$command'"
        usage
        ;;
esac
