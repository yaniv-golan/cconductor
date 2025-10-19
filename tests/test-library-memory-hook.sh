#!/usr/bin/env bash
# Lightweight tests for the LibraryMemory PreToolUse guard

set -euo pipefail

if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        PATH="/opt/homebrew/bin:$PATH"
        export PATH
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        PATH="/usr/local/bin:$PATH"
        export PATH
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4.0 or higher is required to run this test." >&2
        exit 1
    fi
fi

if [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]] && command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
    PATH="/opt/homebrew/bin:$PATH"
    export PATH
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_SCRIPT="$REPO_ROOT/src/utils/hooks/pre-tool-use.sh"
HASH_SCRIPT="$REPO_ROOT/src/claude-runtime/skills/library-memory/hash-url.sh"

if [[ ! -x "$HOOK_SCRIPT" ]]; then
    echo "Hook script not executable: $HOOK_SCRIPT" >&2
    exit 1
fi

if [[ ! -x "$HASH_SCRIPT" ]]; then
    echo "Hash script not executable: $HASH_SCRIPT" >&2
    exit 1
fi

tmp_dirs=()
cleanup() {
    for path in "${tmp_dirs[@]}"; do
        if [[ -d "$path" ]]; then
            rm -rf "$path"
        elif [[ -e "$path" ]]; then
            rm -f "$path"
        fi
    done
}
trap cleanup EXIT

create_library() {
    local url="$1"
    local last_updated="$2"

    local lib_dir
    lib_dir="$(mktemp -d)"
    tmp_dirs+=("$lib_dir")
    mkdir -p "$lib_dir/sources"

    local hash
    hash=$("$HASH_SCRIPT" "$url")
    cat >"$lib_dir/sources/${hash}.json" <<JSON
{
  "url": "$url",
  "last_updated": "$last_updated",
  "entries": []
}
JSON

    echo "$lib_dir"
}

run_hook() {
    local url="$1"
    local library_root="$2"
    local session_dir
    session_dir="$(mktemp -d)"
    tmp_dirs+=("$session_dir")
    touch "$session_dir/events.jsonl"

    local payload
    payload=$(jq -n --arg url "$url" '{tool_name:"WebFetch", tool_input:{url:$url}}')

    local stderr_file
    stderr_file="$(mktemp)"
    tmp_dirs+=("$stderr_file")

    set +e
    echo "$payload" | \
        LIBRARY_MEMORY_ROOT="$library_root" \
        CCONDUCTOR_SESSION_DIR="$session_dir" \
        CCONDUCTOR_AGENT_NAME="web-researcher" \
        CLAUDE_PROJECT_DIR="$REPO_ROOT" \
        "$HOOK_SCRIPT" > /dev/null 2> "$stderr_file"
    local exit_code=$?
    set -e

    echo "$session_dir|$stderr_file|$exit_code"
}

echo "Test 1: cache hit blocks WebFetch"
fresh_url="https://example.com/library-memory-test"
fresh_library=$(create_library "$fresh_url" "2025-10-19T00:00:00Z")
result=$(run_hook "$fresh_url" "$fresh_library")
session_dir="${result%%|*}"
rest="${result#*|}"
stderr_file="${rest%%|*}"
exit_code="${result##*|}"

if [[ "$exit_code" -ne 2 ]]; then
    echo "Expected exit code 2 for cache hit, got $exit_code" >&2
    exit 1
fi

if ! grep -q "Digest" "$stderr_file"; then
    echo "Cache-hit message missing in stderr" >&2
    exit 1
fi

library_event=$(tail -n 2 "$session_dir/events.jsonl" | head -n 1)
blocked_event=$(tail -n 1 "$session_dir/events.jsonl")

if [[ "$(echo "$library_event" | jq -r '.type')" != "library_digest_hit" ]]; then
    echo "Expected library_digest_hit event, got: $library_event" >&2
    exit 1
fi

if [[ "$(echo "$blocked_event" | jq -r '.type')" != "tool_use_blocked" ]]; then
    echo "Expected tool_use_blocked event, got: $blocked_event" >&2
    exit 1
fi

echo "Test 2: stale digest allows WebFetch"
stale_url="https://example.com/library-memory-stale"
stale_library=$(create_library "$stale_url" "2024-01-01T00:00:00Z")
result=$(run_hook "$stale_url" "$stale_library")
exit_code="${result##*|}"
if [[ "$exit_code" -ne 0 ]]; then
    echo "Expected exit code 0 for stale digest, got $exit_code" >&2
    exit 1
fi

echo "Test 3: ?fresh=1 bypasses cache guard"
fresh_override_url="https://example.com/library-memory-test?fresh=1"
result=$(run_hook "$fresh_override_url" "$fresh_library")
exit_code="${result##*|}"
if [[ "$exit_code" -ne 0 ]]; then
    echo "Expected exit code 0 for ?fresh=1 URL, got $exit_code" >&2
    exit 1
fi

echo "✓ LibraryMemory hook tests passed"
