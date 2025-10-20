#!/usr/bin/env bash
# show-search.sh - Inspect cached WebSearch results by query or hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    PROJECT_ROOT="$CLAUDE_PROJECT_DIR"
else
    search_path="$SCRIPT_DIR"
    while [[ "$search_path" != "/" ]]; do
        if [[ -f "$search_path/VERSION" ]]; then
            PROJECT_ROOT="$search_path"
            break
        fi
        search_path="$(dirname "$search_path")"
    done
    if [[ -z "${PROJECT_ROOT:-}" ]]; then
        PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
    fi
fi

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-search-cache.sh" 2>/dev/null || {
    echo '{"status":"error","message":"web-search cache utilities unavailable"}'
    exit 1
}

query_arg=""
hash_arg=""
limit=5
format="json"

usage() {
    cat <<'USAGE'
Usage: show-search.sh (--query "search terms" | --hash <sha256>) [--limit N] [--format json|text]

Options:
  --query   Search query to look up (will be normalized for cache lookup)
  --hash    Query hash (advanced usage)
  --limit   Limit number of results shown (default: 5, 0 = all)
  --format  Output format: json (default) or text
USAGE
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --query)
            shift
            [[ $# -gt 0 ]] || usage
            query_arg="$1"
            ;;
        --hash)
            shift
            [[ $# -gt 0 ]] || usage
            hash_arg="$1"
            ;;
        --limit)
            shift
            [[ $# -gt 0 ]] || usage
            limit="$1"
            ;;
        --format)
            shift
            [[ $# -gt 0 ]] || usage
            format="$1"
            ;;
        *)
            usage
            ;;
    esac
    shift
done

if [[ -z "$query_arg" && -z "$hash_arg" ]]; then
    usage
fi

if [[ -n "$query_arg" && -n "$hash_arg" ]]; then
    usage
fi

if [[ ! "$limit" =~ ^-?[0-9]+$ ]]; then
    echo '{"status":"error","message":"limit must be an integer"}'
    exit 1
fi

normalize_query() {
    local raw="$1"
    web_search_cache_normalize_query "$raw"
}

lookup_entry_by_hash() {
    local query_hash="$1"
    local index_path
    index_path=$(web_search_cache_index_path)
    jq --arg key "$query_hash" '.[$key]' "$index_path"
}

extract_payload_file() {
    local entry_json="$1"
    local results_hash
    results_hash=$(echo "$entry_json" | jq -r '.results_hash // empty')
    if [[ -z "$results_hash" ]]; then
        echo ""
        return 0
    fi
    web_search_cache_object_path "$results_hash"
}

query_status="miss"
entry="null"
object_path=""
normalized_query=""

if [[ -n "$hash_arg" ]]; then
    entry=$(lookup_entry_by_hash "$hash_arg")
    if [[ "$entry" != "null" ]]; then
        query_status="hit"
        normalized_query=$(echo "$entry" | jq -r '.normalized_query // ""')
        object_path=$(extract_payload_file "$entry")
    fi
else
    lookup_json=$(web_search_cache_lookup "$query_arg")
    query_status=$(echo "$lookup_json" | jq -r '.status // "miss"')
    if [[ "$query_status" == "force_refresh" ]]; then
        echo '{"status":"force_refresh","message":"Query explicitly requested fresh results"}'
        exit 0
    fi
    if [[ "$query_status" != "miss" && "$query_status" != "disabled" ]]; then
        entry=$(echo "$lookup_json" | jq -c '.metadata')
        normalized_query=$(echo "$lookup_json" | jq -r '.normalized_query // ""')
        object_path=$(echo "$lookup_json" | jq -r '.object_path // empty')
    elif [[ "$query_status" == "miss" ]]; then
        # Fallback: allow direct lookup by normalized hash to display stale entries even if disabled by TTL
        normalized_query=$(normalize_query "$query_arg")
        if [[ -n "$normalized_query" ]]; then
            hash_arg=$(web_search_cache_hash_string "$normalized_query")
            entry=$(lookup_entry_by_hash "$hash_arg")
            if [[ "$entry" != "null" ]]; then
                query_status="stale"
                object_path=$(extract_payload_file "$entry")
            fi
        fi
    fi
fi

if [[ "$query_status" == "disabled" ]]; then
    echo '{"status":"disabled","message":"WebSearch cache disabled in configuration"}'
    exit 0
fi

if [[ "$entry" == "null" || -z "$object_path" || ! -f "$object_path" ]]; then
    echo '{"status":"miss"}'
    exit 0
fi

payload=$(cat "$object_path")

stored_iso=$(echo "$entry" | jq -r '.stored_at_iso // empty')
if [[ -z "$stored_iso" || "$stored_iso" == "null" ]]; then
    stored_iso=$(web_search_cache_timestamp)
fi

result_count=$(echo "$entry" | jq -r '.result_count // 0')
if [[ -z "$result_count" || "$result_count" == "null" ]]; then
    result_count=0
fi

display_query=$(echo "$entry" | jq -r '.query // empty')
if [[ -z "$display_query" && -n "$query_arg" ]]; then
    display_query="$query_arg"
fi

limit_value="$limit"
if [[ "$limit_value" -lt 0 ]]; then
    limit_value=0
fi

if [[ "$format" == "text" ]]; then
    # Produce human-readable output
    echo "Query: $display_query"
    echo "Status: $query_status"
    echo "Stored: $stored_iso"
    echo "Cache File: $object_path"
    echo "Results: $result_count total"
    echo ""
    echo "$payload" | jq -r --argjson limit "$limit_value" '
        .results // [] | (if $limit > 0 then .[:$limit] else . end)
        | to_entries[]
        | "\(.key + 1). \(.value.title // "Untitled")\n   URL: \(.value.url // "unknown")\n   Snippet: \(.value.snippet // "")\n"
    '
    exit 0
fi

jq -n \
    --arg status "$query_status" \
    --arg query "$display_query" \
    --arg normalized "$normalized_query" \
    --arg stored "$stored_iso" \
    --arg path "$object_path" \
    --arg count "$result_count" \
    --argjson payload "$payload" \
    --argjson limit "$limit_value" \
    '{
        status: $status,
        query: $query,
        normalized_query: (if $normalized == "" then null else $normalized end),
        stored_at: $stored,
        cache_path: $path,
        result_count: ($count | tonumber),
        results: (
            ($payload.results // [])
            | (if $limit > 0 then .[:$limit] else . end)
        ),
        context: ($payload.context // {}),
        metadata: ($payload.metadata // null)
    }'
