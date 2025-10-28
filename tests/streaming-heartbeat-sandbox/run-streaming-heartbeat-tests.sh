#!/usr/bin/env bash
# Streaming heartbeat integration tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

original_path="$PATH"
export PATH="$SCRIPT_DIR/bin:$PATH"

tmpdir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmpdir"
}
trap cleanup EXIT INT TERM

session_dir="$tmpdir/session"
mkdir -p "$session_dir/.claude/agents" \
    "$session_dir/.claude/agents/stream-test-agent" \
    "$session_dir/work/stream-test-agent" \
    "$session_dir/logs" \
    "$session_dir/cache" \
    "$session_dir/knowledge"

echo "$PROJECT_ROOT" > "$session_dir/.cconductor-root"
touch "$session_dir/logs/events.jsonl"

cat > "$session_dir/.claude/agents/stream-test-agent.json" <<'JSON'
{
  "name": "stream-test-agent",
  "model": "claude-test",
  "systemPrompt": "You are a mock streaming agent used for verifying heartbeat propagation.",
  "description": "Mock agent for streaming heartbeat sandbox tests."
}
JSON

cat > "$session_dir/.claude/agents/stream-test-agent/metadata.json" <<'JSON'
{
  "display_name": "Streaming Test Agent"
}
JSON

input_file="$tmpdir/input.md"
cat > "$input_file" <<'EOF'
Provide a concise confirmation. Use JSON formatting if explicitly instructed.
EOF

output_file="$session_dir/work/stream-test-agent/output.json"

run_stream_case() {
    local scenario="$1"
    local matcher="$2"

    rm -f "$output_file" "${output_file}.stderr" "${output_file}.stream.jsonl"

    STREAMING_SCENARIO="$scenario" \
    CCONDUCTOR_ENABLE_STREAMING=1 \
    CCONDUCTOR_SKIP_EVENT_TAILER=1 \
    PATH="$SCRIPT_DIR/bin:$original_path" \
    bash "$PROJECT_ROOT/src/utils/invoke-agent.sh" invoke-v2 \
        stream-test-agent \
        "$input_file" \
        "$output_file" \
        30 \
        "$session_dir" \
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

    if [[ -f "$session_dir/.agent-heartbeat" ]]; then
        echo "Heartbeat file not cleaned up after scenario $scenario" >&2
        exit 1
    fi
}

run_stream_case "json_result" '.result | contains("\"status\"")'
run_stream_case "text" '.result == "Hello world"'

# Validate legacy (non-streaming) path remains functional.
rm -f "$output_file" "${output_file}.stderr" "${output_file}.stream.jsonl"
STREAMING_SCENARIO="text" \
CCONDUCTOR_ENABLE_STREAMING=0 \
CCONDUCTOR_SKIP_EVENT_TAILER=1 \
PATH="$SCRIPT_DIR/bin:$original_path" \
bash "$PROJECT_ROOT/src/utils/invoke-agent.sh" invoke-v2 \
    stream-test-agent \
    "$input_file" \
    "$output_file" \
    30 \
    "$session_dir" \
    >/dev/null

jq -e '.result == "Legacy mode response"' "$output_file" >/dev/null

echo "✅ Streaming heartbeat sandbox tests passed."
