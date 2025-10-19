#!/usr/bin/env bash
# Web Fetch Cache Utilities
# Provides reusable functions for storing and retrieving cached WebFetch results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/config-loader.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/platform-paths.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh"

WEB_CACHE_SUBDIR="web-fetch"
WEB_CACHE_INDEX="index.json"

web_cache_load_config() {
    load_config "web-fetch-cache"
}

web_cache_enabled() {
    local config
    config=$(web_cache_load_config)
    if [[ "$(echo "$config" | jq -r '.enabled // true')" == "true" ]]; then
        return 0
    fi
    return 1
}

web_cache_root_dir() {
    local cache_dir
    cache_dir=$(ensure_path_exists "cache_dir")
    local root="$cache_dir/$WEB_CACHE_SUBDIR"
    mkdir -p "$root/objects" "$root/tmp" "$root/session" "$root/logs"
    echo "$root"
}

web_cache_index_path() {
    local root
    root=$(web_cache_root_dir)
    local index_path="$root/$WEB_CACHE_INDEX"
    if [ ! -f "$index_path" ]; then
        printf '{}' > "$index_path"
    fi
    echo "$index_path"
}

web_cache_hash_string() {
    python3 - "$1" <<'PY'
import hashlib, sys
data = sys.argv[1].encode("utf-8")
print(hashlib.sha256(data).hexdigest())
PY
}

web_cache_hash_file() {
    python3 - "$1" <<'PY'
import hashlib, sys, pathlib
path = pathlib.Path(sys.argv[1])
hasher = hashlib.sha256()
with path.open("rb") as fh:
    for chunk in iter(lambda: fh.read(1024 * 1024), b""):
        hasher.update(chunk)
print(hasher.hexdigest())
PY
}

web_cache_object_path() {
    local content_hash="$1"
    local root
    root=$(web_cache_root_dir)
    local prefix="${content_hash:0:2}"
    local dir="$root/objects/$prefix"
    mkdir -p "$dir"
    echo "$dir/$content_hash"
}

web_cache_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

web_cache_epoch() {
    date -u +%s
}

web_cache_extension_for_type() {
    local content_type="$1"
    case "$content_type" in
        text/html* ) echo ".html" ;;
        text/plain* ) echo ".txt" ;;
        application/json* ) echo ".json" ;;
        application/pdf ) echo ".pdf" ;;
        text/xml*|application/xml* ) echo ".xml" ;;
        application/octet-stream ) echo ".bin" ;;
        * ) echo ".dat" ;;
    esac
}

web_cache_prune_if_needed() {
    local index_path
    index_path=$(web_cache_index_path)
    local config
    config=$(web_cache_load_config)
    local max_entries
    max_entries=$(echo "$config" | jq -r '.max_entries // 500')

    local tmp_file
    tmp_file=$(mktemp)
    if ! lock_acquire "$index_path"; then
        rm -f "$tmp_file"
        return 1
    fi

    cp "$index_path" "$tmp_file"

    local entry_count
    entry_count=$(jq 'length' "$tmp_file")

    if [ "$entry_count" -le "$max_entries" ]; then
        rm -f "$tmp_file"
        lock_release "$index_path"
        return 0
    fi

    local remove_count=$(( entry_count - max_entries ))
    if [ "$remove_count" -lt 0 ]; then
        remove_count=0
    fi

    if [ "$remove_count" -gt 0 ]; then
        local pruned
        pruned=$(jq \
            --argjson remove "$remove_count" '
            to_entries
            | sort_by(.value.updated_at)
            | .[$remove:]
            | from_entries
        ' "$tmp_file")
        printf '%s' "$pruned" > "$index_path"
    fi

    rm -f "$tmp_file"
    lock_release "$index_path"
    return 0
}

web_cache_store() {
    local url="$1"
    local body_path="$2"
    local metadata_json="${3:-null}"

    if ! web_cache_enabled; then
        return 0
    fi

    if [ ! -f "$body_path" ]; then
        return 0
    fi

    local index_path
    index_path=$(web_cache_index_path)

    local url_hash content_hash stored_at size_bytes
    url_hash=$(web_cache_hash_string "$url")
    content_hash=$(web_cache_hash_file "$body_path")
    stored_at=$(web_cache_epoch)
    size_bytes=$(wc -c < "$body_path" | tr -d ' ')

    local content_type status_code etag last_modified
    content_type=$(echo "$metadata_json" | jq -r '.content_type // empty')
    status_code=$(echo "$metadata_json" | jq -r '.status_code // empty')
    etag=$(echo "$metadata_json" | jq -r '.headers.etag // empty')
    last_modified=$(echo "$metadata_json" | jq -r '.headers.last_modified // empty')

    local object_path
    object_path=$(web_cache_object_path "$content_hash")
    if [ ! -f "$object_path" ]; then
        cp "$body_path" "$object_path"
    fi

    local entry_json
    entry_json=$(jq -n \
        --arg url "$url" \
        --arg url_hash "$url_hash" \
        --arg content_hash "$content_hash" \
        --arg stored_at "$stored_at" \
        --arg size "$size_bytes" \
        --arg content_type "$content_type" \
        --arg status_code "$status_code" \
        --arg etag "$etag" \
        --arg last_modified "$last_modified" \
        '{
            url: $url,
            url_hash: $url_hash,
            content_hash: $content_hash,
            stored_at: ($stored_at | tonumber),
            updated_at: ($stored_at | tonumber),
            size_bytes: ($size | tonumber),
            content_type: (if $content_type == "" then null else $content_type end),
            status_code: (if $status_code == "" then null else ($status_code | tonumber) end),
            headers: {
                etag: (if $etag == "" then null else $etag end),
                last_modified: (if $last_modified == "" then null else $last_modified end)
            }
        }'
    )

    if lock_acquire "$index_path"; then
        local tmp_index
        tmp_index=$(mktemp)
        jq --arg key "$url_hash" --argjson entry "$entry_json" '.[$key] = $entry' "$index_path" > "$tmp_index"
        mv "$tmp_index" "$index_path"
        lock_release "$index_path"
        web_cache_prune_if_needed
    fi
}

web_cache_lookup() {
    local url="$1"
    if ! web_cache_enabled; then
        jq -n '{status: "disabled"}'
        return 0
    fi

    local index_path
    index_path=$(web_cache_index_path)
    local url_hash
    url_hash=$(web_cache_hash_string "$url")

    local entry
    entry=$(jq --arg key "$url_hash" '.[$key]' "$index_path")

    if [[ "$entry" == "null" ]]; then
        jq -n '{status: "miss"}'
        return 0
    fi

    local config ttl_hours ttl_seconds
    config=$(web_cache_load_config)
    ttl_hours=$(echo "$config" | jq -r '.ttl_hours // 24')
    ttl_seconds=$(( ttl_hours * 3600 ))

    local stored_at
    stored_at=$(echo "$entry" | jq -r '.stored_at // 0')
    local now
    now=$(web_cache_epoch)
    local age=$(( now - stored_at ))

    local status="hit"
    if [ "$age" -gt "$ttl_seconds" ]; then
        status="stale"
    fi

    local content_hash
    content_hash=$(echo "$entry" | jq -r '.content_hash // empty')
    if [ -z "$content_hash" ]; then
        jq -n '{status: "miss"}'
        return 0
    fi

    local object_path
    object_path=$(web_cache_object_path "$content_hash")
    if [ ! -f "$object_path" ]; then
        # Remove missing entry
        if lock_acquire "$index_path"; then
            local tmp_index
            tmp_index=$(mktemp)
            jq --arg key "$url_hash" 'del(.[$key])' "$index_path" > "$tmp_index"
            mv "$tmp_index" "$index_path"
            lock_release "$index_path"
        fi
        jq -n '{status: "miss"}'
        return 0
    fi

    jq -n \
        --arg status "$status" \
        --arg path "$object_path" \
        --arg stored_at "$stored_at" \
        --arg age "$age" \
        --argjson entry "$entry" \
        '{
            status: $status,
            object_path: $path,
            stored_at: ($stored_at | tonumber),
            age_seconds: ($age | tonumber),
            metadata: $entry
        }'
}

web_cache_materialize_for_session() {
    local session_dir="$1"
    local url="$2"
    local lookup_json="$3"

    local object_path
    object_path=$(echo "$lookup_json" | jq -r '.object_path // empty')
    if [ -z "$object_path" ]; then
        return 1
    fi

    local entry
    entry=$(echo "$lookup_json" | jq -c '.metadata')

    local content_type
    content_type=$(echo "$entry" | jq -r '.content_type // empty')
    local extension
    extension=$(web_cache_extension_for_type "$content_type")

    local cache_dir="$session_dir/cache/web-fetch"
    mkdir -p "$cache_dir"

    local content_hash
    content_hash=$(echo "$entry" | jq -r '.content_hash')

    local materialized_path="$cache_dir/${content_hash}${extension}"
    if [ ! -f "$materialized_path" ]; then
        cp "$object_path" "$materialized_path"
    fi

    local manifest_file="$session_dir/cache/web-fetch-manifest.json"
    if [ ! -f "$manifest_file" ]; then
        printf '[]' > "$manifest_file"
    fi

    local manifest_tmp
    manifest_tmp=$(mktemp)
    jq --arg url "$url" \
       --arg path "$materialized_path" \
       --arg stored "$(echo "$lookup_json" | jq -r '.stored_at' )" \
       --arg status "$(echo "$lookup_json" | jq -r '.status')" \
       --arg content_type "$content_type" \
       --arg content_hash "$content_hash" \
       '
       map(select(.content_hash != $content_hash)) + [{
            url: $url,
            content_hash: $content_hash,
            path: $path,
            stored_at: ($stored | tonumber),
            status: $status,
            content_type: (if $content_type == "" then null else $content_type end),
            materialized_at: (now | floor)
       }]' "$manifest_file" > "$manifest_tmp"
    mv "$manifest_tmp" "$manifest_file"

    echo "$materialized_path"
}

web_cache_format_summary() {
    local session_dir="$1"
    local manifest_file="$session_dir/cache/web-fetch-manifest.json"
    if [ ! -f "$manifest_file" ]; then
        printf '[]'
        return 0
    fi

    local config
    config=$(web_cache_load_config)
    local limit
    limit=$(echo "$config" | jq -r '.materialize_per_session // 25')
    jq --argjson limit "$limit" 'sort_by(-.stored_at) | .[:$limit]' "$manifest_file"
}

export -f web_cache_load_config
export -f web_cache_enabled
export -f web_cache_root_dir
export -f web_cache_index_path
export -f web_cache_hash_string
export -f web_cache_hash_file
export -f web_cache_object_path
export -f web_cache_store
export -f web_cache_lookup
export -f web_cache_materialize_for_session
export -f web_cache_format_summary
