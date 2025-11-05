#!/usr/bin/env bash
set -euo pipefail

# Determine script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/json-helpers.sh"

# Optional helpers (fail gracefully if unavailable)
# shellcheck disable=SC1091
if ! source "$SCRIPT_DIR/json-parser.sh" 2>/dev/null; then
    :
fi

require_command "python3" "brew install python3" "apt install python3" >/dev/null

stakeholder_classifier_state_file() {
    local session_dir="$1"
    echo "$session_dir/meta/stakeholder-classifier-state.json"
}

stakeholder_classifier_collect_sources() {
    local session_dir="$1"
    local kg_file="$session_dir/knowledge/knowledge-graph.json"

    if [[ ! -f "$kg_file" ]]; then
        jq -n '{digest: "", count: 0, sources: []}'
        return 0
    fi

    local result
    result=$(python3 - "$kg_file" <<'PY'
import hashlib
import json
import sys
from urllib.parse import urlparse

kg_path = sys.argv[1]

def normalize_url(raw_url: str):
    raw_url = (raw_url or "").strip()
    if not raw_url:
        return None
    parsed = urlparse(raw_url)
    netloc = parsed.netloc
    path = parsed.path
    query = parsed.query

    if not netloc:
        if "://" in raw_url:
            return None
        stripped = raw_url
        if stripped.startswith("//"):
            stripped = stripped[2:]
        parts = stripped.split("/", 1)
        netloc = parts[0]
        if len(parts) > 1:
            path = "/" + parts[1]
        else:
            path = "/"
        query = ""

    netloc = (netloc or "").strip().lower()
    if not netloc:
        return None

    if not path:
        path = "/"
    if path != "/":
        path = path.rstrip("/")
        if not path:
            path = "/"

    normalized = netloc + path
    if query:
        normalized += "?" + query
    return normalized

try:
    with open(kg_path, "r", encoding="utf-8") as handle:
        kg = json.load(handle)
except (OSError, json.JSONDecodeError):
    print(json.dumps({"digest": "", "count": 0, "sources": []}))
    sys.exit(0)

sources = set()
for claim in kg.get("claims", []):
    for source in claim.get("sources") or []:
        url = ""
        if isinstance(source, dict):
            url = source.get("url") or ""
        elif isinstance(source, str):
            url = source
        normalized = normalize_url(url)
        if normalized:
            sources.add(normalized)

normalized_list = sorted(sources)
if normalized_list:
    joined = "\n".join(normalized_list).encode("utf-8")
    digest = hashlib.sha256(joined).hexdigest()
else:
    digest = ""

print(json.dumps({
    "digest": digest,
    "count": len(normalized_list),
    "sources": normalized_list
}))
PY
    ) || return 1

    printf '%s\n' "$result"
}

stakeholder_classifier_write_state() {
    local session_dir="$1"
    local sources_json="$2"
    local digest="$3"
    local total_classifications="$4"
    local pending_sources="$5"

    local kg_file="$session_dir/knowledge/knowledge-graph.json"
    local iteration
    iteration=$(safe_jq_from_file "$kg_file" '.iteration // 0' '0' "$session_dir" "stakeholder_state.iteration")
    local source_count
    source_count=$(printf '%s\n' "$sources_json" | jq 'length' 2>/dev/null || echo "0")

    local state_json
    state_json=$(jq -n \
        --arg schema "1.0" \
        --arg updated "$(get_timestamp)" \
        --argjson iteration "$iteration" \
        --arg digest "$digest" \
        --argjson count "$source_count" \
        --argjson total "$total_classifications" \
        --argjson pending "$pending_sources" \
        --argjson sources "$sources_json" \
        '{
            schema_version: $schema,
            updated_at: $updated,
            kg_iteration: $iteration,
            kg_source_digest: (if $digest == "" then null else $digest end),
            kg_source_count: $count,
            total_classifications: $total,
            pending_sources: $pending,
            sources: $sources
        }')

    local state_file
    state_file=$(stakeholder_classifier_state_file "$session_dir")
    mkdir -p "$(dirname "$state_file")"
    local tmp
    tmp=$(mktemp "${state_file}.tmp.XXXXXX")
    printf '%s\n' "$state_json" >"$tmp"
    mv "$tmp" "$state_file"
}

stakeholder_classifier_read_state() {
    local session_dir="$1"
    local state_file
    state_file=$(stakeholder_classifier_state_file "$session_dir")
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        jq -n '{}'
    fi
}

stakeholder_classifier_sources_diff() {
    local previous_sources="$1"
    local current_sources="$2"

    jq -n \
        --argjson previous "$previous_sources" \
        --argjson current "$current_sources" \
        '{
            added: (($current - $previous) | length),
            removed: (($previous - $current) | length)
        }'
}
