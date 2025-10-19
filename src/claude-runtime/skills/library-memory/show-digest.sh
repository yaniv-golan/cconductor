#!/usr/bin/env bash
# show-digest.sh - Return cached digest JSON for a given URL or hash.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LIBRARY_DIR="$PROJECT_ROOT/library"
limit=3
hash_arg=""
url_arg=""

usage() {
    echo "Usage: show-digest.sh [--limit N] (--url <url> | --hash <sha256>)" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit)
            shift
            [[ $# -gt 0 ]] || usage
            limit="$1"
            ;;
        --url)
            shift
            [[ $# -gt 0 ]] || usage
            url_arg="$1"
            ;;
        --hash)
            shift
            [[ $# -gt 0 ]] || usage
            hash_arg="$1"
            ;;
        *)
            usage
            ;;
    esac
    shift
done

if [[ -z "$url_arg" && -z "$hash_arg" ]]; then
    usage
fi

if [[ -n "$url_arg" && -n "$hash_arg" ]]; then
    usage
fi

if [[ -n "$url_arg" ]]; then
    hash_arg="$("$SCRIPT_DIR/hash-url.sh" "$url_arg")"
fi

digest_path="$LIBRARY_DIR/sources/${hash_arg}.json"

if [[ ! -f "$digest_path" ]]; then
    echo "{}"
    exit 0
fi

jq --arg hash "$hash_arg" --argjson limit "$limit" '{
    hash: $hash,
    url: .url,
    first_seen: (.first_seen // ""),
    last_updated: (.last_updated // ""),
    titles: (.titles // []),
    entry_count: ((.entries // []) | length),
    entries: (
        (.entries // [])
        | sort_by(.collected_at)
        | reverse
        | (if $limit > 0 then .[:$limit] else . end)
    )
}' "$digest_path"
