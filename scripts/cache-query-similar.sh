#!/usr/bin/env bash
# cache-query-similar.sh - List cached WebSearch queries similar to a given prompt.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: cache-query-similar.sh [--limit N] <query terms...>

Examples:
  cache-query-similar.sh "TAM SAM SOM best practices"
  cache-query-similar.sh --limit 3 "venture capital market sizing"
USAGE
    exit 1
}

limit=5
query_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --limit)
            shift
            [[ $# -gt 0 ]] || usage
            limit="$1"
            ;;
        --help|-h)
            usage
            ;;
        *)
            query_args+=("$1")
            ;;
    esac
    shift
done

if [[ ${#query_args[@]} -eq 0 ]]; then
    usage
fi

query="${query_args[*]}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh"

cache_dir=$(ensure_path_exists "cache_dir")
index_file="$cache_dir/web-search/index.json"

if [[ ! -f "$index_file" ]]; then
    echo "No cached WebSearch index found at: $index_file" >&2
    exit 1
fi

python3 - "$query" "$index_file" "$limit" "$cache_dir" <<'PY'
import json
import sys
import difflib
from pathlib import Path
import re

query = sys.argv[1]
index_path = Path(sys.argv[2])
limit = int(sys.argv[3])
cache_root = Path(sys.argv[4])

with index_path.open() as fh:
    index = json.load(fh)

if not index:
    print("Cache index is empty.")
    sys.exit(0)

STOPWORDS = {
    "the", "and", "of", "for", "in", "to", "with", "a", "an",
    "on", "by", "from", "about", "into", "over", "under"
}

WORD_RE = re.compile(r"[a-z0-9]+")

def normalize(text: str) -> str:
    return " ".join(text.lower().split())

def compute_canonical_tokens(text: str):
    tokens = []
    for word in WORD_RE.findall(text.lower()):
        if word in STOPWORDS:
            continue
        if len(word) > 4 and word.endswith("s"):
            word = word[:-1]
        tokens.append(word)
    return sorted(set(tokens))

def canonical_string(text: str) -> str:
    tokens = compute_canonical_tokens(text)
    return " ".join(tokens)

query_norm = normalize(query)
query_tokens = set(query_norm.split())
query_canonical_tokens = set(compute_canonical_tokens(query))

candidates = []
for entry in index.values():
    cached_query = entry.get("query") or entry.get("display_query") or ""
    if not cached_query:
        continue
    cached_norm = normalize(entry.get("normalized_query") or cached_query)
    seq_score = difflib.SequenceMatcher(None, query_norm, cached_norm).ratio()
    cached_tokens = set(cached_norm.split())
    canonical = entry.get("canonical_query") or canonical_string(cached_query)
    canonical_set = set(canonical.split()) if canonical else set(compute_canonical_tokens(cached_query))
    overlap_raw = len(query_tokens & cached_tokens) / max(len(query_tokens), 1)
    canon_den = len(query_canonical_tokens) if query_canonical_tokens else 1
    overlap_canonical = len(query_canonical_tokens & canonical_set) / canon_den
    score = 0.4 * seq_score + 0.3 * overlap_raw + 0.3 * overlap_canonical
    candidates.append((score, cached_query, entry))

if not candidates:
    print("No comparable cached queries found.")
    sys.exit(0)

candidates.sort(key=lambda item: item[0], reverse=True)
top_matches = candidates[:limit]

print(f"Query: {query}")
print(f"Top {len(top_matches)} cached matches:")

for rank, (score, cached_query, entry) in enumerate(top_matches, start=1):
    stored_iso = entry.get("stored_at_iso") or "unknown"
    result_count = entry.get("result_count")
    object_rel = entry.get("object_rel_path")
    snippet = ""
    canonical = entry.get("canonical_query") or canonical_string(cached_query)
    if object_rel:
        object_path = cache_root / "web-search" / object_rel
        if object_path.is_file():
            try:
                with object_path.open() as fh:
                    data = json.load(fh)
                results = data.get("results") or []
                if results:
                    snippet = (
                        results[0].get("snippet")
                        or results[0].get("summary")
                        or results[0].get("title")
                        or ""
                    )
            except Exception:
                snippet = ""
    if snippet:
        snippet = " ".join(snippet.strip().split())
        if len(snippet) > 200:
            snippet = snippet[:197] + "..."

    print(f" {rank}. score={score:.2f} stored={stored_iso} results={result_count}")
    print(f"    query: {cached_query}")
    if canonical:
        print(f"    canonical: {canonical}")
    if snippet:
        print(f"    snippet: {snippet}")
PY
