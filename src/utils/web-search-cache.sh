#!/usr/bin/env bash
# Web Search Cache Utilities
# Stores Claude WebSearch results to avoid redundant paid searches.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/config-loader.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/platform-paths.sh"
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/path-resolver.sh"

WEB_SEARCH_CACHE_SUBDIR="web-search"
WEB_SEARCH_CACHE_INDEX="index.json"

web_search_cache_load_config() {
    local base_config advanced_config
    base_config=$(load_config "web-search-cache")
    advanced_config=$(load_config "cconductor-config")

    echo "$base_config" | jq \
        --argjson advanced "$(echo "$advanced_config" | jq '.advanced // {}')" \
        '
        .enabled = (
            if $advanced.cache_search_results != null
            then $advanced.cache_search_results
            else .enabled
            end
        )
        | .ttl_hours = (
            if ($advanced.cache_ttl_hours // null) != null
            then ($advanced.cache_ttl_hours | tonumber)
            else .ttl_hours
            end
        )
        '
}

web_search_cache_enabled() {
    if [[ "${CCONDUCTOR_DISABLE_WEB_SEARCH_CACHE:-0}" == "1" ]]; then
        return 1
    fi
    local config
    config=$(web_search_cache_load_config)
    if [[ "$(echo "$config" | jq -r '.enabled // true')" == "true" ]]; then
        return 0
    fi
    return 1
}

web_search_cache_root_dir() {
    local cache_dir
    cache_dir=$(ensure_path_exists "cache_dir")
    local root="$cache_dir/$WEB_SEARCH_CACHE_SUBDIR"
    mkdir -p "$root/objects" "$root/tmp" "$root/session" "$root/logs"
    echo "$root"
}

web_search_cache_index_path() {
    local root
    root=$(web_search_cache_root_dir)
    local index_path="$root/$WEB_SEARCH_CACHE_INDEX"
    if [ ! -f "$index_path" ]; then
        printf '{}' > "$index_path"
    fi
    echo "$index_path"
}

web_search_cache_hash_string() {
    "$SCRIPT_DIR/hash-string.sh" "$1"
}

web_search_cache_hash_json() {
    local json_payload="$1"
    local canonical
    canonical=$(echo "$json_payload" | jq -S -c '.')
    "$SCRIPT_DIR/hash-string.sh" "$canonical"
}

web_search_cache_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

web_search_cache_epoch() {
    date -u +%s
}

web_search_cache_object_path() {
    local content_hash="$1"
    local root
    root=$(web_search_cache_root_dir)
    local prefix="${content_hash:0:2}"
    local dir="$root/objects/$prefix"
    mkdir -p "$dir"
    echo "$dir/${content_hash}.json"
}

web_search_cache_prepare_query() {
    local query="$1"
    local config
    config=$(web_search_cache_load_config)
    
    # Normalize whitespace: replace \r\n with spaces, collapse multiple spaces
    local normalized
    normalized=$(echo "$query" | tr '\n\r' '  ' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local normalized_lower
    normalized_lower=$(echo "$normalized" | tr '[:upper:]' '[:lower:]')
    local normalized_display="$normalized"
    
    # Check for fresh query markers
    local force="false"
    local markers
    markers=$(echo "$config" | jq -r '.fresh_query_markers[]? // empty')
    if [[ -n "$markers" ]]; then
        while IFS= read -r marker; do
            [[ -z "$marker" ]] && continue
            local marker_lower
            marker_lower=$(echo "$marker" | tr '[:upper:]' '[:lower:]')
            # Check if marker appears at end of query
            if [[ "$normalized_lower" =~ [[:space:]]*"$marker_lower"[[:space:]]*$ ]]; then
                force="true"
                # Remove marker from end of both versions
                normalized_lower=$(echo "$normalized_lower" | sed -E "s/[[:space:]]*$(echo "$marker_lower" | sed 's/[]\/$*.^[]/\\&/g')[[:space:]]*$//")
                normalized_display=$(echo "$normalized_display" | sed -E "s/[[:space:]]*$(echo "$marker" | sed 's/[]\/$*.^[]/\\&/g')[[:space:]]*$//i")
            fi
        done <<< "$markers"
    fi
    
    # Remove trailing punctuation and whitespace
    normalized_lower=$(echo "$normalized_lower" | sed -E 's/[[:space:]\?&]+$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    normalized_display=$(echo "$normalized_display" | sed -E 's/[[:space:]\?&]+$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Final whitespace collapse
    normalized_lower=$(echo "$normalized_lower" | tr -s ' ')
    normalized_display=$(echo "$normalized_display" | tr -s ' ')
    
    # Output JSON result
    jq -n \
        --arg norm "$normalized_lower" \
        --arg disp "$normalized_display" \
        --argjson force "$force" \
        '{normalized: $norm, display: $disp, force: $force}'
}

web_search_cache_canonicalize_query() {
    local input="$1"
    local canonical
    canonical=$(printf '%s' "$input" \
        | LC_ALL=C tr '[:upper:]' '[:lower:]' \
        | LC_ALL=C tr -c '[:alnum:] ' ' ' \
        | tr ' ' '\n' \
        | awk '
            {
                w=$0
                gsub(/^[^a-z0-9]+/, "", w)
                gsub(/[^a-z0-9]+$/, "", w)
                if (w == "") next
                if (w == "the" || w == "and" || w == "of" || w == "for" || w == "in" || w == "to" || w == "with" || w == "a" || w == "an" || w == "on" || w == "by" || w == "from" || w == "about" || w == "into" || w == "over" || w == "under") next
                if (length(w) > 4 && w ~ /s$/) {
                    w = substr(w, 1, length(w) - 1)
                }
                print w
            }
        ' \
        | LC_ALL=C sort -u \
        | tr '\n' ' ' \
        | sed 's/  */ /g; s/^ //; s/ $//')
    printf '%s\n' "$canonical"
}

web_search_cache_token_signature() {
    local canonical="$1"
    if [[ -z "$canonical" ]]; then
        printf ''
    else
        printf '%s\n' "${canonical// /|}"
    fi
}

web_search_cache_find_overlap_entry() {
    local canonical="$1"
    if [[ -z "$canonical" ]]; then
        return 0
    fi

    local index_path
    index_path=$(web_search_cache_index_path)
    
    # Convert canonical space-separated tokens to array for jq
    local canonical_tokens
    canonical_tokens=$(echo "$canonical" | tr ' ' '\n' | jq -R . | jq -s .)
    
    # Use jq to find best matching entry
    jq -r --argjson tokens "$canonical_tokens" '
        # Build set of canonical tokens
        ($tokens | unique) as $canonical_set |
        ($canonical_set | length) as $canonical_len |
        
        # Find best overlap
        [ 
            .[] | 
            select(.token_signature != null) |
            (.token_signature | split("|") | map(select(. != ""))) as $entry_tokens |
            ($entry_tokens | unique) as $entry_set |
            ($entry_set | length) as $entry_len |
            
            # Calculate overlap
            ([$canonical_set[], $entry_set[]] | group_by(.) | map(select(length > 1) | .[0]) | length) as $overlap |
            (if $canonical_len > $entry_len then $canonical_len else $entry_len end) as $denom |
            ($overlap / (if $denom > 0 then $denom else 1 end)) as $score |
            
            select($score > 0) |
            {entry: ., overlap: $score}
        ] |
        sort_by(-.overlap) |
        .[0] |
        select(.overlap >= 0.75)
    ' "$index_path" 2>/dev/null
}

web_search_cache_normalize_query() {
    local prepared
    prepared=$(web_search_cache_prepare_query "$1")
    echo "$prepared" | jq -r '.normalized // ""'
}

web_search_cache_display_query() {
    local prepared
    prepared=$(web_search_cache_prepare_query "$1")
    echo "$prepared" | jq -r '.display // ""'
}

web_search_cache_force_refresh_requested() {
    local prepared
    prepared=$(web_search_cache_prepare_query "$1")
    if [[ "$(echo "$prepared" | jq -r '.force')" == "true" ]]; then
        return 0
    fi
    return 1
}

web_search_cache_prune_if_needed() {
    local index_path config max_entries tmp_file entry_count remove_count
    index_path=$(web_search_cache_index_path)
    config=$(web_search_cache_load_config)
    max_entries=$(echo "$config" | jq -r '.max_entries // 400')

    tmp_file=$(mktemp)
    if ! lock_acquire "$index_path"; then
        rm -f "$tmp_file"
        return 1
    fi

    cp "$index_path" "$tmp_file"
    entry_count=$(jq 'length' "$tmp_file")

    if [ "$entry_count" -le "$max_entries" ]; then
        rm -f "$tmp_file"
        lock_release "$index_path"
        return 0
    fi

    remove_count=$(( entry_count - max_entries ))
    if [ "$remove_count" -gt 0 ]; then
        jq --argjson remove "$remove_count" '
            to_entries
            | sort_by(.value.updated_at)
            | .[$remove:]
            | from_entries
        ' "$tmp_file" > "$index_path"
    fi

    rm -f "$tmp_file"
    lock_release "$index_path"
    return 0
}

web_search_cache_store() {
    local raw_query="$1"
    local results_json="$2"
    local metadata_json="${3:-null}"

    if ! web_search_cache_enabled; then
        return 0
    fi

    if [[ -z "$raw_query" ]]; then
        return 0
    fi

    if [[ -z "$results_json" || "$results_json" == "null" ]]; then
        return 0
    fi

    local prepared normalized_query display_query query_hash stored_epoch stored_iso
    prepared=$(web_search_cache_prepare_query "$raw_query")
    normalized_query=$(echo "$prepared" | jq -r '.normalized // ""')
    display_query=$(echo "$prepared" | jq -r '.display // ""')

    if [[ -z "$normalized_query" ]]; then
        return 0
    fi

    local canonical_query token_signature
    canonical_query=$(web_search_cache_canonicalize_query "$raw_query")
    token_signature=$(web_search_cache_token_signature "$canonical_query")

    query_hash=$(web_search_cache_hash_string "$normalized_query")
    stored_epoch=$(web_search_cache_epoch)
    stored_iso=$(web_search_cache_timestamp)

    local results_hash
    results_hash=$(web_search_cache_hash_json "$results_json" 2>/dev/null || echo "")
    if [[ -z "$results_hash" ]]; then
        return 0
    fi

    local object_path
    object_path=$(web_search_cache_object_path "$results_hash")
    if [ ! -f "$object_path" ]; then
        printf '%s' "$results_json" > "$object_path"
    fi

    local result_count="0"
    if ! result_count=$(safe_jq_from_json "$results_json" 'if type=="array" then length else (if has("results") then (.results | length) else 0 end) end' "0" "${CCONDUCTOR_SESSION_DIR:-}" "web_search_cache.result_count" "true" "true"); then
        result_count="0"
    fi

    local metadata_arg
    metadata_arg="$metadata_json"
    if [[ -z "$metadata_arg" ]]; then
        metadata_arg="null"
    fi

    local index_entry
    index_entry=$(jq -n \
        --arg query "$display_query" \
        --arg normalized "$normalized_query" \
        --arg query_hash "$query_hash" \
        --arg results_hash "$results_hash" \
        --arg stored "$stored_epoch" \
        --arg stored_iso "$stored_iso" \
        --arg count "$result_count" \
        --arg rel_path "objects/${results_hash:0:2}/${results_hash}.json" \
        --arg canonical "$canonical_query" \
        --arg token_sig "$token_signature" \
        --argjson metadata "$metadata_arg" \
        '{
            query: $query,
            normalized_query: $normalized,
            query_hash: $query_hash,
            results_hash: $results_hash,
            stored_at: ($stored | tonumber),
            stored_at_iso: $stored_iso,
            updated_at: ($stored | tonumber),
            result_count: ($count | tonumber),
            object_rel_path: $rel_path,
            canonical_query: (if $canonical == "" then null else $canonical end),
            token_signature: (if $token_sig == "" then null else $token_sig end),
            metadata: (if $metadata == null then null else $metadata end)
        }'
    )

    local index_path
    index_path=$(web_search_cache_index_path)

    if lock_acquire "$index_path"; then
        local tmp_index
        tmp_index=$(mktemp)
        jq --arg key "$query_hash" --argjson entry "$index_entry" '.[$key] = $entry' "$index_path" > "$tmp_index"
        mv "$tmp_index" "$index_path"
        lock_release "$index_path"
        web_search_cache_prune_if_needed
    fi
}

web_search_cache_lookup() {
    local raw_query="$1"
    if ! web_search_cache_enabled; then
        jq -n '{status: "disabled"}'
        return 0
    fi

    if web_search_cache_force_refresh_requested "$raw_query"; then
        jq -n '{status: "force_refresh"}'
        return 0
    fi

    local normalized_query
    normalized_query=$(web_search_cache_normalize_query "$raw_query")
    if [[ -z "$normalized_query" ]]; then
        jq -n '{status: "miss"}'
        return 0
    fi

    local canonical_query
    canonical_query=$(web_search_cache_canonicalize_query "$raw_query")

    local index_path query_hash entry
    index_path=$(web_search_cache_index_path)
    query_hash=$(web_search_cache_hash_string "$normalized_query")
    entry=$(jq --arg key "$query_hash" '.[$key]' "$index_path")
    local overlap_match_ratio=""
    local cached_base_query=""

    if ! echo "$entry" | jq -e 'type=="object"' >/dev/null 2>&1; then
        if [[ -n "$canonical_query" ]]; then
            entry=$(jq --arg canonical "$canonical_query" '
                [ to_entries[] | select(.value.canonical_query == $canonical) | .value ][0]
            ' "$index_path")
        fi
        if ! echo "$entry" | jq -e 'type=="object"' >/dev/null 2>&1; then
            local overlap_json
            overlap_json=$(web_search_cache_find_overlap_entry "$canonical_query")
            if [[ -n "$overlap_json" ]]; then
                entry=$(echo "$overlap_json" | jq -c '.entry')
                overlap_match_ratio=$(echo "$overlap_json" | jq -r '.overlap // empty')
                cached_base_query=$(echo "$entry" | jq -r '.query // ""')
            fi
        fi
        if ! echo "$entry" | jq -e 'type=="object"' >/dev/null 2>&1; then
            jq -n '{status: "miss"}'
            return 0
        fi
        normalized_query=$(echo "$entry" | jq -r '.normalized_query // ""')
        query_hash=$(echo "$entry" | jq -r '.query_hash // ""')
    else
        cached_base_query=$(echo "$entry" | jq -r '.query // ""')
    fi

    if [[ -z "$cached_base_query" || "$cached_base_query" == "null" ]]; then
        cached_base_query=$(echo "$entry" | jq -r '.query // ""')
    fi

    local config ttl_hours ttl_seconds stored_at now age status results_hash object_path
    config=$(web_search_cache_load_config)
    ttl_hours=$(echo "$config" | jq -r '.ttl_hours // 12')
    ttl_seconds=$(( ttl_hours * 3600 ))
    stored_at=$(echo "$entry" | jq -r '.stored_at // 0')
    now=$(web_search_cache_epoch)
    age=$(( now - stored_at ))
    status="hit"

    if [ "$ttl_seconds" -gt 0 ] && [ "$age" -gt "$ttl_seconds" ]; then
        status="stale"
    fi

    results_hash=$(echo "$entry" | jq -r '.results_hash // empty')
    if [[ -z "$results_hash" ]]; then
        jq -n '{status: "miss"}'
        return 0
    fi

    object_path=$(web_search_cache_object_path "$results_hash")
    if [ ! -f "$object_path" ]; then
        if lock_acquire "$index_path"; then
            local tmp_index
            tmp_index=$(mktemp)
            jq --arg key "$query_hash" 'del(.[$key])' "$index_path" > "$tmp_index"
            mv "$tmp_index" "$index_path"
            lock_release "$index_path"
        fi
        jq -n '{status: "miss"}'
        return 0
    fi

    jq -n \
        --arg status "$status" \
        --arg path "$object_path" \
        --arg stored "$stored_at" \
        --arg age "$age" \
        --arg normalized "$normalized_query" \
        --arg display "$(echo "$entry" | jq -r '.query // ""')" \
        --arg match "$overlap_match_ratio" \
        --arg base "$cached_base_query" \
        --argjson entry "$entry" \
        '{
            status: $status,
            object_path: $path,
            stored_at: ($stored | tonumber),
            age_seconds: ($age | tonumber),
            normalized_query: $normalized,
            display_query: $display,
            match_ratio: (if $match == "" then null else ($match | tonumber) end),
            match_base_query: (if $base == "" then null else $base end),
            metadata: $entry
        }'
}

web_search_cache_materialize_for_session() {
    local session_dir="$1"
    local raw_query="$2"
    local lookup_json="$3"

    local object_path
    object_path=$(echo "$lookup_json" | jq -r '.object_path // empty')
    if [[ -z "$object_path" ]]; then
        return 1
    fi

    local manifest_dir="$session_dir/cache"
    mkdir -p "$manifest_dir/web-search"

    local results_hash
    results_hash=$(echo "$lookup_json" | jq -r '.metadata.results_hash // empty')
    if [[ -z "$results_hash" ]]; then
        results_hash=$(web_search_cache_hash_string "$(echo "$lookup_json" | jq -c '.metadata // {}')")
    fi

    local materialized_path="$manifest_dir/web-search/${results_hash}.json"
    if [ ! -f "$materialized_path" ]; then
        cp "$object_path" "$materialized_path"
    fi

    local snippet_preview=""
    if command -v jq >/dev/null 2>&1 && [[ -s "$materialized_path" ]]; then
        snippet_preview=$(jq -r '
            try (
                if (.results // [] | length) > 0 then
                    ( .results[0].snippet // .results[0].summary // .results[0].title // "" )
                else
                    ""
                end
            ) catch ""' "$materialized_path" 2>/dev/null || printf '')
        if [[ "$snippet_preview" == "null" ]]; then
            snippet_preview=""
        fi
    fi
    if [[ ${#snippet_preview} -gt 280 ]]; then
        snippet_preview="${snippet_preview:0:277}..."
    fi

    local manifest_file="$manifest_dir/web-search-manifest.json"
    if [ ! -f "$manifest_file" ]; then
        printf '[]' > "$manifest_file"
    fi

    local status stored_at stored_iso display_query result_count canonical_query token_signature
    status=$(echo "$lookup_json" | jq -r '.status // "hit"')
    stored_at=$(echo "$lookup_json" | jq -r '.stored_at // 0')
    stored_iso=$(echo "$lookup_json" | jq -r '.metadata.stored_at_iso // ""')
    display_query=$(web_search_cache_display_query "$raw_query")
    result_count=$(echo "$lookup_json" | jq -r '.metadata.result_count // 0')
    if [[ -z "$result_count" || "$result_count" == "null" ]]; then
        result_count=0
    fi
    canonical_query=$(echo "$lookup_json" | jq -r '.metadata.canonical_query // ""')
    token_signature=$(echo "$lookup_json" | jq -r '.metadata.token_signature // ""')

    local manifest_tmp
    manifest_tmp=$(mktemp)
    jq --arg query "$display_query" \
       --arg normalized "$(echo "$lookup_json" | jq -r '.normalized_query // empty')" \
       --arg path "$materialized_path" \
       --arg status "$status" \
       --arg stored "$stored_at" \
       --arg hash "$results_hash" \
       --arg count "$result_count" \
       --arg stored_iso "$stored_iso" \
       --arg canonical "$canonical_query" \
       --arg token_sig "$token_signature" \
       --arg preview "$snippet_preview" \
       '
       map(select(.results_hash != $hash)) + [{
            query: $query,
            normalized_query: $normalized,
            results_hash: $hash,
            path: $path,
            status: $status,
            stored_at: ($stored | tonumber),
            stored_at_iso: (if $stored_iso == "" then null else $stored_iso end),
            result_count: ($count | tonumber),
            canonical_query: (if $canonical == "" then null else $canonical end),
            token_signature: (if $token_sig == "" then null else $token_sig end),
            snippet_preview: (if $preview == "" then null else $preview end),
            materialized_at: (now | floor)
       }] | sort_by(-.stored_at)
       ' "$manifest_file" > "$manifest_tmp"
    mv "$manifest_tmp" "$manifest_file"

    echo "$materialized_path"
}

web_search_cache_format_summary() {
    local session_dir="$1"
    local manifest_file="$session_dir/cache/web-search-manifest.json"
    if [ ! -f "$manifest_file" ]; then
        printf '[]'
        return 0
    fi

    local config limit
    config=$(web_search_cache_load_config)
    limit=$(echo "$config" | jq -r '.materialize_per_session // 20')
    jq --argjson limit "$limit" '
        sort_by(-.stored_at)
        | .[:$limit]
    ' "$manifest_file"
}

export -f web_search_cache_load_config
export -f web_search_cache_enabled
export -f web_search_cache_root_dir
export -f web_search_cache_index_path
export -f web_search_cache_hash_string
export -f web_search_cache_prepare_query
export -f web_search_cache_canonicalize_query
export -f web_search_cache_token_signature
export -f web_search_cache_normalize_query
export -f web_search_cache_display_query
export -f web_search_cache_force_refresh_requested
export -f web_search_cache_store
export -f web_search_cache_lookup
export -f web_search_cache_materialize_for_session
export -f web_search_cache_format_summary
