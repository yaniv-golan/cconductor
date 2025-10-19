#!/usr/bin/env bash
# Digital Librarian - persist session findings into the shared research library.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

LIBRARY_DIR="$PROJECT_ROOT/library"
SOURCES_DIR="$LIBRARY_DIR/sources"
MANIFEST_FILE="$LIBRARY_DIR/manifest.json"

session_dir="${1:-}"

if [[ -z "$session_dir" || ! -d "$session_dir" ]]; then
    echo "Digital librarian: session directory missing" >&2
    exit 1
fi

kg_file="$session_dir/knowledge-graph.json"
if [[ ! -f "$kg_file" ]]; then
    # Nothing to archive
    exit 0
fi

mkdir -p "$SOURCES_DIR"
if [[ ! -f "$MANIFEST_FILE" ]]; then
    echo '{}' > "$MANIFEST_FILE"
fi

session_name="$(basename "$session_dir")"
timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Extract claim/source pairs from knowledge graph
mapfile -t SOURCES < <(jq -c '
    (.claims // [])[] as $claim
    | ($claim.sources // [])[]?
    | select((.url // "") != "")
    | {
        url: (.url // ""),
        title: (.title // ""),
        relevant_quote: (.relevant_quote // ""),
        claim_statement: ($claim.statement // ""),
        claim_id: ($claim.id // ($claim.statement // "" | @base64)),
        confidence: ($claim.confidence // null)
      }
' "$kg_file")

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    exit 0
fi

for raw in "${SOURCES[@]}"; do
    url="$(echo "$raw" | jq -r '.url')"
    [[ -z "$url" || "$url" == "null" ]] && continue

    entry_json=$(echo "$raw" | jq --arg session "$session_name" --arg now "$timestamp" '{
        url: .url,
        title: (.title // ""),
        quote: (.relevant_quote // ""),
        claim: (.claim_statement // ""),
        claim_id: (.claim_id // ""),
        confidence: .confidence,
        session: $session,
        collected_at: $now
    }')

    url_hash=$(printf '%s' "$url" | shasum -a 256 | awk '{print $1}')
    digest_path="$SOURCES_DIR/${url_hash}.json"

    if [[ -f "$digest_path" ]]; then
        tmp_digest="$(mktemp)"
        jq --argjson entry "$entry_json" '
            .last_updated = $entry.collected_at |
            .titles = ((.titles // []) + (if ($entry.title // "") == "" then [] else [$entry.title] end) | unique) |
            .entries += [{
                session: $entry.session,
                claim_id: $entry.claim_id,
                claim: $entry.claim,
                confidence: $entry.confidence,
                title: $entry.title,
                quote: $entry.quote,
                collected_at: $entry.collected_at
            }] |
            .entries |= unique_by({session: .session, claim_id: .claim_id, quote: .quote})
        ' "$digest_path" > "$tmp_digest"
        mv "$tmp_digest" "$digest_path"
    else
        echo "$entry_json" | jq '{
            url: .url,
            first_seen: .collected_at,
            last_updated: .collected_at,
            titles: (if (.title // "") == "" then [] else [ .title ] end),
            entries: [{
                session: .session,
                claim_id: .claim_id,
                claim: .claim,
                confidence: .confidence,
                title: .title,
                quote: .quote,
                collected_at: .collected_at
            }]
        }' > "$digest_path"
    fi

    entry_count=$(jq '.entries | length' "$digest_path")

    tmp_manifest="$(mktemp)"
    jq --arg hash "$url_hash" --arg url "$url" --arg session "$session_name" --arg now "$timestamp" --argjson count "$entry_count" '
        .[$hash] = (
            (.[$hash] // {url: $url, first_seen: $now, sessions: []})
            | .url = $url
            | .first_seen = (.first_seen // $now)
            | .last_updated = $now
            | .sessions = ((.sessions + [$session]) | unique)
            | .entry_count = $count
        )
    ' "$MANIFEST_FILE" > "$tmp_manifest"
    mv "$tmp_manifest" "$MANIFEST_FILE"
done

echo "  ✓ Research library updated (${#SOURCES[@]} source references processed)" >&2

