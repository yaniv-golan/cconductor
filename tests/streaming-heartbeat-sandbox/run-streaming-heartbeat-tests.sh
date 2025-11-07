#!/usr/bin/env bash
# Streaming heartbeat integration tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BASH_RUNTIME="${BASH_RUNTIME:-/opt/homebrew/bin/bash}"

if [[ ! -x "$BASH_RUNTIME" ]]; then
    echo "Expected Bash 4+ at \$BASH_RUNTIME ($BASH_RUNTIME) but it was not found." >&2
    exit 1
fi

CONTRACT_PATH="$PROJECT_ROOT/config/artifact-contracts/stream-test-agent/manifest.expected.json"
if [[ ! -f "$CONTRACT_PATH" ]]; then
    echo "Skipping streaming heartbeat sandbox tests (missing $CONTRACT_PATH)"
    exit 0
fi

original_path="$PATH"
export PATH="$SCRIPT_DIR/bin:$PATH"

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

session_template="$tmpdir/session_template"
mkdir -p "$session_template/.claude/agents" \
    "$session_template/.claude/agents/stream-test-agent" \
    "$session_template/work/stream-test-agent" \
    "$session_template/logs" \
    "$session_template/cache" \
    "$session_template/knowledge"

echo "$PROJECT_ROOT" > "$session_template/.cconductor-root"
touch "$session_template/logs/events.jsonl"

cat > "$session_template/.claude/agents/stream-test-agent.json" <<'JSON'
{
  "name": "stream-test-agent",
  "model": "claude-test",
  "systemPrompt": "You are a mock streaming agent used for verifying heartbeat propagation.",
  "description": "Mock agent for streaming heartbeat sandbox tests."
}
JSON

cat > "$session_template/.claude/agents/stream-test-agent/metadata.json" <<'JSON'
{
  "display_name": "Streaming Test Agent"
}
JSON

input_file="$tmpdir/input.md"
cat > "$input_file" <<'EOF'
Provide a concise confirmation. Use JSON formatting if explicitly instructed.
EOF

prepare_session_dir() {
    local dest="$1"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -R "$session_template/." "$dest"
}

run_stream_case() {
    local scenario="$1"
    local matcher="$2"
    local scenario_dir="$tmpdir/session_${scenario}"
    prepare_session_dir "$scenario_dir"
    local output_file="$scenario_dir/work/stream-test-agent/output.json"

    rm -f "$output_file" "${output_file}.stderr" "${output_file}.stream.jsonl"
    STREAMING_SCENARIO="$scenario" \
    CCONDUCTOR_ENABLE_STREAMING=1 \
    CCONDUCTOR_SKIP_EVENT_TAILER=1 \
    PATH="$SCRIPT_DIR/bin:$original_path" \
    "$BASH_RUNTIME" "$PROJECT_ROOT/src/utils/invoke-agent.sh" invoke-v2 \
        stream-test-agent \
        "$input_file" \
        "$output_file" \
        30 \
        "$scenario_dir" \
        >/dev/null

    jq -e '.type == "result"' "$output_file" >/dev/null
    jq -e "$matcher" "$output_file" >/dev/null

    if [[ ! -f "${output_file}.stream.jsonl" ]]; then
        echo "Stream log missing for scenario $scenario" >&2
        exit 1
    fi

    if ! rg -q '"stream_event"' "${output_file}.stream.jsonl"; then
        echo "Expected stream_event entries for scenario $scenario" >&2
        exit 1
    fi

    if [[ -f "$scenario_dir/.agent-heartbeat" ]]; then
        echo "Heartbeat file not cleaned up after scenario $scenario" >&2
        exit 1
    fi
}

run_legacy_case() {
    local legacy_session="$tmpdir/session_legacy"
    prepare_session_dir "$legacy_session"
    local output_file="$legacy_session/work/stream-test-agent/output.json"
    rm -f "$output_file" "${output_file}.stderr" "${output_file}.stream.jsonl"
    STREAMING_SCENARIO="text" \
    CCONDUCTOR_ENABLE_STREAMING=0 \
    CCONDUCTOR_SKIP_EVENT_TAILER=1 \
    PATH="$SCRIPT_DIR/bin:$original_path" \
    "$BASH_RUNTIME" "$PROJECT_ROOT/src/utils/invoke-agent.sh" invoke-v2 \
        stream-test-agent \
        "$input_file" \
        "$output_file" \
        30 \
        "$legacy_session" \
        >/dev/null

    jq -e '.result == "Legacy mode response"' "$output_file" >/dev/null
}

run_stream_case "json_result" '.result | contains("\"status\"")' &
pid_json=$!
run_stream_case "text" '.result == "Hello world"' &
pid_text=$!
run_legacy_case &
pid_legacy=$!

wait "$pid_json"
wait "$pid_text"
wait "$pid_legacy"

echo "✅ Streaming heartbeat sandbox tests passed."
