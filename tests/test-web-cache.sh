#!/usr/bin/env bash
# Simple regression test for web fetch cache utilities

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PROJECT_ROOT

tmp_session="$(mktemp -d)"
trap 'rm -rf "$tmp_session"' EXIT

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-cache.sh"

if ! web_cache_enabled; then
    echo "Cache disabled in configuration; skipping test."
    exit 0
fi

cache_dir=$(web_cache_root_dir)
echo "Cache root: $cache_dir"

sample_file="$tmp_session/sample.txt"
printf 'cached content %s\n' "$(date -u +%s)" > "$sample_file"

url="https://example.com/test-cache"
metadata=$(jq -n '{content_type: "text/plain", status_code: 200}')

web_cache_store "$url" "$sample_file" "$metadata"

lookup=$(web_cache_lookup "$url")
status=$(echo "$lookup" | jq -r '.status')
if [[ "$status" != "hit" ]]; then
    echo "Expected cache hit but got status=$status"
    exit 1
fi

materialized=$(web_cache_materialize_for_session "$tmp_session" "$url" "$lookup")
if [[ ! -f "$materialized" ]]; then
    echo "Materialized cache file missing: $materialized"
    exit 1
fi

summary=$(web_cache_format_summary "$tmp_session")
if [[ "$summary" == "[]" ]]; then
    echo "Cache summary unexpectedly empty"
    exit 1
fi

echo "Web cache test passed."
