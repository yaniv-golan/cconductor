#!/usr/bin/env bash
# Argument Event Writer
# Ingests structured argument events emitted by agents and appends them to the
# Argument Event Graph log under each mission session.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/file-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/verbose.sh" 2>/dev/null; then
    verbose() { :; }
    export -f verbose
fi

# Optional shared-state utilities (locks + atomic updates)
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/../shared-state.sh" 2>/dev/null; then
    log_warn "argument-writer: shared-state not found; locking disabled"
fi

if ! declare -F with_lock >/dev/null 2>&1; then
    with_lock() {
        local _lock="$1"
        shift
        "$@"
    }
fi

ARGUMENT_WRITER_DEFAULT_STEP="UNKNOWN"

argument_writer_enabled() {
    [[ "${CCONDUCTOR_ENABLE_AEG:-0}" == "1" ]]
}

argument_writer_lock_path() {
    local session_dir="$1"
    echo "${session_dir}/argument/.aeg.lock"
}

argument_writer_init_session() {
    local session_dir="$1"
    ensure_dir "${session_dir}/argument"
    local log_path="${session_dir}/argument/aeg.log.jsonl"
    local index_path="${session_dir}/argument/aeg.index.json"
    if [[ ! -f "$log_path" ]]; then
        : > "$log_path"
    fi
    if [[ ! -f "$index_path" ]]; then
        printf '%s\n' '{"last_seq":0,"events":{}}' > "$index_path"
    fi
}

argument_writer_hash_base32() {
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

argument_writer_compute_event_id() {
    local event_json="$1"
    local canonical
    canonical=$(printf '%s' "$event_json" | jq -c 'del(.event_id)')
    local hex_digest
    if command -v sha256sum >/dev/null 2>&1; then
        hex_digest=$(printf '%s' "$canonical" | sha256sum | awk '{print $1}')
    else
        hex_digest=$(printf '%s' "$canonical" | shasum -a 256 | awk '{print $1}')
    fi
    local b32
    b32=$(argument_writer_hash_base32 "$hex_digest")
    printf 'evt-%s\n' "$b32"
}

argument_writer_normalise_event() {
    local raw_event="$1"
    local agent="$2"
    local mission_step="$3"
    local stream_offset="$4"

    local default_ts
    default_ts=$(get_timestamp)

    printf '%s\n' "$raw_event" | jq -c \
        --arg agent "$agent" \
        --arg step "${mission_step:-$ARGUMENT_WRITER_DEFAULT_STEP}" \
        --arg ts "$default_ts" \
        --argjson stream_offset_json "${stream_offset:-null}" '
        (if type == "object" then . else error("Event must be object") end) as $ev
        | $ev
        | .agent = ($ev.agent // ($agent | select(length > 0) // "unknown"))
        | .mission_step = ($ev.mission_step // ($step | select(length > 0) // "UNKNOWN"))
        | .timestamp = ($ev.timestamp // $ts)
        | .stream_offset = ($ev.stream_offset // $stream_offset_json)
        | .event_type as $et
        | if ($et == null) or (($et | tostring | length) == 0) then error("Missing event_type") else . end
        | if (.payload? // null) == null then error("Missing payload") else . end
    '
}

argument_writer_append_locked() {
    local session_dir="$1"
    local event_json="$2"

    local log_path="${session_dir}/argument/aeg.log.jsonl"
    local index_path="${session_dir}/argument/aeg.index.json"
    local event_id
    event_id=$(printf '%s' "$event_json" | jq -r '.event_id')
    local mission_step
    mission_step=$(printf '%s' "$event_json" | jq -r '.mission_step')
    local agent
    agent=$(printf '%s' "$event_json" | jq -r '.agent')
    local timestamp
    timestamp=$(printf '%s' "$event_json" | jq -r '.timestamp')
    local stream_offset
    stream_offset=$(printf '%s' "$event_json" | jq -r '.stream_offset // empty')

    if [[ -z "$event_id" ]]; then
        log_error "argument-writer: event_id missing after normalisation"
        return 1
    fi

    if [[ ! -f "$index_path" ]]; then
        printf '%s\n' '{"last_seq":0,"events":{}}' > "$index_path"
    fi

    if jq -e --arg id "$event_id" '.events[$id]' "$index_path" >/dev/null 2>&1; then
        verbose "argument-writer: deduped event $event_id"
        return 0
    fi

    printf '%s\n' "$event_json" >> "$log_path"

    local stream_offset_arg="null"
    if [[ -n "$stream_offset" && "$stream_offset" != "null" ]]; then
        stream_offset_arg="$stream_offset"
    fi

# shellcheck disable=SC2016
    atomic_json_update "$index_path" \
        --arg id "$event_id" \
        --arg agent "$agent" \
        --arg step "$mission_step" \
        --arg ts "$timestamp" \
        --argjson stream_offset "$stream_offset_arg" \
        '
        .last_seq = (.last_seq // 0) + 1
        | .events[$id] = {
            seq: .last_seq,
            agent: $agent,
            mission_step: $step,
            timestamp: $ts,
            stream_offset: $stream_offset
        }
        '
}

argument_writer_append_events() {
    local session_dir="$1"
    local events_json="$2"
    local agent="${3:-}"
    local mission_step="${4:-}"
    local stream_offset="${5:-null}"

    argument_writer_init_session "$session_dir"

    printf '%s\n' "$events_json" | jq -c '
        if (type == "object") and has("events") then .events
        elif type == "array" then .
        else [ . ]
        end
        | .[]
    ' | while IFS= read -r event; do
        [[ -z "$event" ]] && continue
        local enriched
        enriched=$(argument_writer_normalise_event "$event" "$agent" "$mission_step" "$stream_offset")
        if [[ "$(printf '%s' "$enriched" | jq -r '.event_id // empty')" == "" ]]; then
            local generated_id
            generated_id=$(argument_writer_compute_event_id "$enriched")
            enriched=$(printf '%s' "$enriched" | jq -c --arg id "$generated_id" '.event_id = $id')
        fi

        local lock_path
        lock_path=$(argument_writer_lock_path "$session_dir")
        with_lock "$lock_path" argument_writer_append_locked "$session_dir" "$enriched"
    done
}

argument_writer_usage() {
    cat <<'EOF'
Usage: argument-writer.sh append --session <session_dir> [--agent <agent>] [--mission-step <step>] [--file <json>]
Reads events from stdin if --file is omitted.
EOF
}

argument_writer_cli() {
    local command="${1:-}"
    shift || true

    case "$command" in
        append)
            local session=""
            local agent=""
            local mission_step=""
            local file=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --session)
                        session="$2"
                        shift 2
                        ;;
                    --agent)
                        agent="$2"
                        shift 2
                        ;;
                    --mission-step)
                        mission_step="$2"
                        shift 2
                        ;;
                    --file)
                        file="$2"
                        shift 2
                        ;;
                    --help|-h)
                        argument_writer_usage
                        return 0
                        ;;
                    *)
                        log_error "Unknown argument: $1"
                        argument_writer_usage
                        return 1
                        ;;
                esac
            done

            if [[ -z "$session" ]]; then
                log_error "--session is required"
                return 1
            fi

            if ! argument_writer_enabled; then
                verbose "argument-writer: disabled via CCONDUCTOR_ENABLE_AEG"
                return 0
            fi

            local input_json
            if [[ -n "$file" ]]; then
                input_json=$(cat "$file")
            else
                input_json=$(cat)
            fi

            argument_writer_append_events "$session" "$input_json" "$agent" "$mission_step"
            ;;
        *)
            argument_writer_usage
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    argument_writer_cli "$@"
fi

export -f argument_writer_enabled
export -f argument_writer_init_session
export -f argument_writer_append_events
