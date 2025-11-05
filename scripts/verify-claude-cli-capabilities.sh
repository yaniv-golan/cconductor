#!/usr/bin/env bash
# Verify Claude CLI tool configuration capabilities for WebFetch limits

set -euo pipefail

echo "=== Claude CLI Capability Check ==="
echo ""

if ! command -v claude >/dev/null 2>&1; then
    echo "ERROR: claude CLI not found on PATH."
    exit 1
fi

echo "1. CLI Version:"
claude --version || true
echo ""

echo "2. Inspecting help output (tool-related flags):"
claude --help 2>&1 | grep -i "tool" || echo "  No explicit tool flags listed."
echo ""

echo "3. Checking for advanced option flags:"
flags=(
    "--tools"
    "--allowedTools"
    "--disallowedTools"
    "--header"
    "--beta"
)
for flag in "${flags[@]}"; do
    if claude --help 2>&1 | grep -q -- "$flag"; then
        echo "  ✓ $flag supported"
    else
        echo "  ✗ $flag not advertised"
    fi
done
echo ""

tmp_tools_file=$(mktemp "/tmp/claude-tools-test.XXXXXX.json")
cat >"$tmp_tools_file" <<'JSON'
{
  "tools": [
    {
      "type": "web_fetch_20250910",
      "name": "web_fetch",
      "max_uses": 1,
      "allowed_domains": ["example.com"],
      "max_content_tokens": 1000
    }
  ]
}
JSON

echo "4. Attempting to pass tool config via --tools (expect failure if unsupported):"
set +e
claude --tools "$tmp_tools_file" "capability probe" >/tmp/claude-tools-test.out 2>&1
status=$?
set -e
echo "  Exit status: $status"
echo "  Output (first 10 lines):"
head -n 10 /tmp/claude-tools-test.out || true
rm -f "$tmp_tools_file" /tmp/claude-tools-test.out
echo ""

echo "5. Checking for beta header configuration support:"
if claude --help 2>&1 | grep -qi "beta"; then
    echo "  ✓ beta flag documented"
else
    echo "  No beta flag documented; may require environment variable (e.g., ANTHROPIC_BETA)."
fi
echo ""

echo "=== Next Steps ==="
echo "- Review output to determine how to inject max_uses / domain limits."
echo "- If --tools unsupported, plan to update agent metadata or invoke-agent runtime."
echo "- If beta header not available, test with ANTHROPIC_BETA environment variable."
