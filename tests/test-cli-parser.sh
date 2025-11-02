#!/usr/bin/env bash
# Test CLI Argument Parser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source the CLI parser
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/cli-parser.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper
test_case() {
    local description="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "Test $TESTS_RUN: $description"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local description="${3:-}"
    
    if [[ "$expected" == "$actual" ]]; then
        echo "  ✓ PASS"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ FAIL: Expected '$expected', got '$actual' $description"
        return 1
    fi
}

assert_true() {
    local description="$1"
    
    echo "  ✓ PASS: $description"
    return 0
}

assert_false() {
    local description="$1"
    
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  ✗ FAIL: $description"
    return 1
}

# Prompt parser test helpers
PROMPT_PARSER_HELPERS_READY=0
PROMPT_PARSER_INVOKE_READY=0

ensure_prompt_parser_handler() {
    if [[ "$PROMPT_PARSER_HELPERS_READY" -eq 0 ]]; then
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/src/utils/prompt-parser-handler.sh"
        PROMPT_PARSER_HELPERS_READY=1
    fi
}

ensure_prompt_parser_invoke_helpers() {
    ensure_prompt_parser_handler
    if [[ "$PROMPT_PARSER_INVOKE_READY" -eq 0 ]]; then
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/src/utils/invoke-agent.sh"
        PROMPT_PARSER_INVOKE_READY=1
    fi
}

create_prompt_parser_session() {
    local raw_prompt="$1"
    local session_dir
    session_dir=$(mktemp -d "${TMPDIR:-/tmp}/prompt-parser-session.XXXXXX")
    mkdir -p \
        "$session_dir/meta" \
        "$session_dir/knowledge" \
        "$session_dir/artifacts/prompt-parser" \
        "$session_dir/work/prompt-parser" \
        "$session_dir/logs"

    cat > "$session_dir/meta/session.json" <<JSON
{
  "objective": "$raw_prompt",
  "output_specification": null,
  "prompt_parsed": false
}
JSON

    cat > "$session_dir/knowledge/knowledge-graph.json" <<JSON
{
  "research_objective": "$raw_prompt"
}
JSON

    echo "$session_dir"
}

write_prompt_parser_artifacts() {
    local session_dir="$1"
    local objective="$2"
    local output_spec="$3"
    local research_prompt="$4"

    jq -n \
        --arg obj "$objective" \
        --arg rq "$research_prompt" \
        --arg spec "${output_spec:-}" \
        '{
            objective: $obj,
            output_specification: (if $spec == "" then null else $spec end),
            research_question: $rq
        }' > "$session_dir/artifacts/prompt-parser/output.json"

    local spec_display="${output_spec:-None}"
    cat > "$session_dir/artifacts/prompt-parser/output.md" <<EOF
## Objective
$objective

## Output Specification
$spec_display

## Original Prompt
\`\`\`text
$research_prompt
\`\`\`
EOF
}

write_prompt_parser_result() {
    local session_dir="$1"
    local objective="$2"
    local output_spec="$3"
    local research_prompt="$4"

    jq -n \
        --arg obj "$objective" \
        --arg rq "$research_prompt" \
        --arg spec "${output_spec:-}" \
        '{
            result: (
                {
                    objective: $obj,
                    output_specification: (if $spec == "" then null else $spec end),
                    research_question: $rq
                } | @json
            )
        }' > "$session_dir/work/prompt-parser/output.json"
}

stub_prompt_parser_agent() {
    # shellcheck disable=SC2317,SC2329
    _invoke_delegated_agent() { return 0; }
}

restore_prompt_parser_agent() {
    unset -f _invoke_delegated_agent || true
}

# Test 1: Parse --flag value format
test_case "Parse --flag value format"
parse_cli_args --input-dir "/path/to/dir" "research question"
assert_equals "/path/to/dir" "$(get_flag "input-dir")" || exit 1
assert_equals "research question" "$(get_arg 0)" || exit 1

# Test 2: Parse --flag=value format
test_case "Parse --flag=value format"
parse_cli_args --mode=scientific "another question"
assert_equals "scientific" "$(get_flag "mode")" || exit 1
assert_equals "another question" "$(get_arg 0)" || exit 1

# Test 3: Parse boolean flags
test_case "Parse boolean flag (at end)"
parse_cli_args "query" --quiet
assert_equals "true" "$(get_flag "quiet")" || exit 1
assert_equals "query" "$(get_arg 0)" || exit 1

# Test 4: has_flag function
test_case "has_flag returns true for existing flag"
parse_cli_args --input-dir "/path"
if has_flag "input-dir"; then
    assert_true "has_flag detected existing flag"
else
    assert_false "has_flag failed to detect existing flag"
    exit 1
fi

# Test 5: has_flag returns false for non-existing flag
test_case "has_flag returns false for non-existing flag"
parse_cli_args --input-dir "/path"
if ! has_flag "nonexistent"; then
    assert_true "has_flag correctly returned false"
else
    assert_false "has_flag incorrectly detected non-existing flag"
    exit 1
fi

# Test 6: Multiple flags
test_case "Parse multiple flags"
parse_cli_args --input-dir "/path" --mode scientific --output html "query text"
assert_equals "/path" "$(get_flag "input-dir")" || exit 1
assert_equals "scientific" "$(get_flag "mode")" || exit 1
assert_equals "html" "$(get_flag "output")" || exit 1
assert_equals "query text" "$(get_arg 0)" || exit 1

# Test 7: Default values
test_case "get_flag returns default for missing flag"
parse_cli_args "just a query"
assert_equals "default_value" "$(get_flag "missing" "default_value")" || exit 1

# Test 8: Multiple positional arguments
test_case "Parse multiple positional arguments"
parse_cli_args "first" "second" "third"
assert_equals "first" "$(get_arg 0)" || exit 1
assert_equals "second" "$(get_arg 1)" || exit 1
assert_equals "third" "$(get_arg 2)" || exit 1
assert_equals "3" "$(get_arg_count)" || exit 1

# Test 9: Mixed flags and positional args
test_case "Parse mixed flags and positional arguments"
parse_cli_args "query" --flag1 value1 "arg2" --flag2 value2
assert_equals "query" "$(get_arg 0)" || exit 1
assert_equals "arg2" "$(get_arg 1)" || exit 1
assert_equals "value1" "$(get_flag "flag1")" || exit 1
assert_equals "value2" "$(get_flag "flag2")" || exit 1

# Prompt parser contract tests
test_case "Prompt parser JSON artifact updates session metadata"
ensure_prompt_parser_handler
session_dir_pp1=$(create_prompt_parser_session "Research market shifts for open-source databases")
write_prompt_parser_artifacts "$session_dir_pp1" "Analyze open-source database market trends" "Present three bullet findings" "Research market shifts for open-source databases with bullet summary"
write_prompt_parser_result "$session_dir_pp1" "Analyze open-source database market trends" "Present three bullet findings" "Research market shifts for open-source databases with bullet summary"
stub_prompt_parser_agent
parse_prompt "$session_dir_pp1"
restore_prompt_parser_agent
objective_pp1=$(jq -r '.objective' "$session_dir_pp1/meta/session.json")
output_spec_pp1=$(jq -r '.output_specification' "$session_dir_pp1/meta/session.json")
parsed_pp1=$(jq -r '.prompt_parsed' "$session_dir_pp1/meta/session.json")
kg_objective_pp1=$(jq -r '.research_objective' "$session_dir_pp1/knowledge/knowledge-graph.json")
assert_equals "Analyze open-source database market trends" "$objective_pp1" || exit 1
assert_equals "Present three bullet findings" "$output_spec_pp1" || exit 1
assert_equals "true" "$parsed_pp1" || exit 1
assert_equals "Analyze open-source database market trends" "$kg_objective_pp1" || exit 1
rm -rf "$session_dir_pp1"

test_case "Prompt parser stream fallback logs artifact adoption"
ensure_prompt_parser_invoke_helpers
session_dir_pp2=$(create_prompt_parser_session "Assess fallback events for prompt parser")
write_prompt_parser_artifacts "$session_dir_pp2" "Assess fallback logging behavior" "" "Assess fallback events for prompt parser"
touch "$session_dir_pp2/logs/events.jsonl"
if _prompt_parser_handle_stream_fallback "$session_dir_pp2" "prompt-parser"; then
    assert_true "Stream fallback handled via JSON artifact"
else
    assert_false "Stream fallback should be handled" && exit 1
fi
stream_reason_pp2=$(jq -r 'select(.type=="prompt_parser.artifact_fallbacks") | .data.reason' "$session_dir_pp2/logs/events.jsonl" | tail -n 1)
assert_equals "stream_synthesized" "$stream_reason_pp2" || exit 1
rm -rf "$session_dir_pp2"

test_case "Prompt parser falls back to legacy result when JSON artifact missing"
ensure_prompt_parser_handler
session_dir_pp3=$(create_prompt_parser_session "Legacy prompt needing fallback")
rm -f "$session_dir_pp3/artifacts/prompt-parser/output.json"
write_prompt_parser_result "$session_dir_pp3" "Legacy clean objective" "" "Legacy prompt needing fallback"
stub_prompt_parser_agent
parse_prompt "$session_dir_pp3"
restore_prompt_parser_agent
objective_pp3=$(jq -r '.objective' "$session_dir_pp3/meta/session.json")
assert_equals "Legacy clean objective" "$objective_pp3" || exit 1
fallback_reason_pp3=$(jq -r 'select(.type=="prompt_parser.artifact_fallbacks") | .data.reason' "$session_dir_pp3/logs/events.jsonl" | tail -n 1)
assert_equals "json_artifact_unavailable" "$fallback_reason_pp3" || exit 1
rm -rf "$session_dir_pp3"

test_case "Prompt parser resumes legacy session with corrupted JSON artifact"
ensure_prompt_parser_handler
session_dir_pp4=$(create_prompt_parser_session "Corrupted artifact resume path")
echo '{invalid_json' > "$session_dir_pp4/artifacts/prompt-parser/output.json"
write_prompt_parser_result "$session_dir_pp4" "Recovered objective from legacy result" "Use default output" "Corrupted artifact resume path"
stub_prompt_parser_agent
parse_prompt "$session_dir_pp4"
restore_prompt_parser_agent
objective_pp4=$(jq -r '.objective' "$session_dir_pp4/meta/session.json")
assert_equals "Recovered objective from legacy result" "$objective_pp4" || exit 1
fallback_reason_pp4=$(jq -r 'select(.type=="prompt_parser.artifact_fallbacks") | .data.reason' "$session_dir_pp4/logs/events.jsonl" | tail -n 1)
assert_equals "json_artifact_unavailable" "$fallback_reason_pp4" || exit 1
rm -rf "$session_dir_pp4"

# Summary
TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
echo ""
echo "================================"
echo "Test Results: $TESTS_PASSED/$TESTS_RUN test cases passed"
if [[ $TESTS_FAILED -gt 0 ]]; then
    echo "Failures: $TESTS_FAILED"
fi
echo "================================"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ $TESTS_FAILED test case(s) failed"
    exit 1
fi
