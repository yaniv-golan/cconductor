#!/usr/bin/env bash
# Hook: PostToolUse - Logs and displays tool completion
# Called by Claude Code after each tool completes
# Receives JSON data via stdin

set -euo pipefail

# Find project root robustly (hooks may run in various contexts)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$HOOK_DIR/../../../.." && pwd)"

# Source core helpers with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks if core-helpers unavailable
    # shellcheck disable=SC2329
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    # shellcheck disable=SC2329
    get_epoch() { date +%s; }
}

# Source shared-state for atomic operations (with fallback)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/shared-state.sh" 2>/dev/null || true

# Source verbose utility
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/verbose.sh" 2>/dev/null || {
    # Fallback: stub functions if verbose.sh not available
    # shellcheck disable=SC2329
    is_verbose_enabled() { [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; }
    # shellcheck disable=SC2329
    verbose_completion() { :; }
}

# Optional cache utilities
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-cache.sh" 2>/dev/null || true
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/web-search-cache.sh" 2>/dev/null || true

# Read hook data from stdin
hook_data=$(cat)

# Extract tool information
tool_name=$(echo "$hook_data" | jq -r '.tool_name // "unknown"')
exit_code=$(echo "$hook_data" | jq -r '.exit_code // 0')
duration_ms=$(echo "$hook_data" | jq -r '.duration_ms // 0')

# Determine success/failure
if [ "$exit_code" = "0" ]; then
    status="✓"
    status_text="success"
else
    status="✗"
    status_text="failed"
fi

# Format duration
if [ "$duration_ms" -gt 1000 ]; then
    duration_sec=$(awk -v ms="$duration_ms" 'BEGIN { printf "%.1f", ms / 1000 }')
    duration_display="${duration_sec}s"
else
    duration_display="${duration_ms}ms"
fi

# Get session directory from environment or derive it
session_dir="${CCONDUCTOR_SESSION_DIR:-}"
if [ -z "$session_dir" ]; then
    if [ -f "logs/events.jsonl" ]; then
        session_dir=$(pwd)
    else
        session_dir=""
    fi
fi

# Create event for logging
timestamp=$(get_timestamp)
event_data=$(jq -n \
    --arg tool "$tool_name" \
    --arg status "$status_text" \
    --arg duration "$duration_ms" \
    --arg exit_code "$exit_code" \
    '{tool: $tool, status: $status, duration_ms: ($duration | tonumber), exit_code: ($exit_code | tonumber)}')

# Log to logs/events.jsonl if session directory is available
if [ -n "$session_dir" ] && [ -d "$session_dir" ]; then
    # Use atomic mkdir for locking (portable, works on all platforms)
    lock_file="$session_dir/logs/.events.lock"
    start_time=$(get_epoch)
    timeout=5
    
    while true; do
        if mkdir "$lock_file" 2>/dev/null; then
            # Lock acquired - write event
            echo "$hook_data" | jq -c \
                --arg ts "$timestamp" \
                --arg type "tool_use_complete" \
                --argjson data "$event_data" \
                '{timestamp: $ts, type: $type, data: $data}' \
                >> "$session_dir/logs/events.jsonl" 2>/dev/null
            
            # Release lock
            rmdir "$lock_file" 2>/dev/null || true
            break
        fi
        
        # Check timeout - but don't fail hook if lock times out
        elapsed=$(($(get_epoch) - start_time))
        if [ "$elapsed" -ge "$timeout" ]; then
            break
        fi
        
        sleep 0.05
    done
fi

# Print to stdout for real-time visibility
# In verbose mode, skip completion messages (handled by event tailer if needed)
if [[ "${CCONDUCTOR_VERBOSE:-0}" == "1" ]]; then
    # Skip all completion messages in verbose mode - they're too noisy
    # Only show failures if we want to add that back later
    :
else
    # Normal/debug mode: technical format
    echo "    $status $tool_name ($duration_display)" >&2
fi

# Cache successful WebFetch results
if [ "$tool_name" = "WebFetch" ] && [ "$exit_code" = "0" ]; then
    # Persist bodies for evidence pipeline
    if [ -n "$session_dir" ]; then
        cache_root="$session_dir/cache/webfetch"
        mkdir -p "$cache_root"

        url=$(echo "$hook_data" | jq -r '.tool_input.url // empty')
        fetch_timestamp=$(echo "$hook_data" | jq -r '.timestamp // empty')
        content_type=$(echo "$hook_data" | jq -r '.tool_output.content_type // empty')
        status_code=$(echo "$hook_data" | jq -r '.tool_output.status_code // empty')

        if [[ -n "$url" ]]; then
            url_hash=$("$PROJECT_ROOT/src/utils/hash-string.sh" "$url")
            body_path="$cache_root/${url_hash}.txt"
            metadata_path="$cache_root/${url_hash}.json"

            body_file=$(echo "$hook_data" | jq -r '.tool_output.body_file // empty')
            if [[ -n "$body_file" && -f "$body_file" ]]; then
                cp "$body_file" "$body_path"
            else
                body_content=$(echo "$hook_data" | jq -r '.tool_output.body // empty')
                if [[ -n "$body_content" ]]; then
                    printf '%s' "$body_content" > "$body_path"
                else
                    rm -f "$body_path"
                fi
            fi

            jq -n \
                --arg url "$url" \
                --arg fetched_at "${fetch_timestamp:-$(get_timestamp)}" \
                --arg content_type "${content_type:-}" \
                --arg status_code "${status_code:-}" \
                --arg body_path "$(basename "$body_path")" \
                '{
                    url: $url,
                    fetched_at: $fetched_at,
                    content_type: (if $content_type == "" then null else $content_type end),
                    status_code: (if $status_code == "" then null else ($status_code | tonumber) end),
                    body_file: $body_path
                }' > "$metadata_path"

            manifest="$cache_root/index.json"
            tmp_manifest="${manifest}.tmp"
            if [ -f "$manifest" ]; then
                jq --arg hash "$url_hash" --arg url "$url" --arg body "$(basename "$body_path")" \
                   --arg meta "$(basename "$metadata_path")" \
                   --arg fetched "${fetch_timestamp:-$(get_timestamp)}" '
                    .entries = (
                        [.entries[]? | select(.hash != $hash)] +
                        [{
                            hash: $hash,
                            url: $url,
                            body_file: $body,
                            metadata_file: $meta,
                            fetched_at: $fetched
                        }]
                    )
                ' "$manifest" > "$tmp_manifest"
            else
                mkdir -p "$cache_root"
                jq -n \
                    --arg hash "$url_hash" \
                    --arg url "$url" \
                    --arg body "$(basename "$body_path")" \
                    --arg meta "$(basename "$metadata_path")" \
                    --arg fetched "${fetch_timestamp:-$(get_timestamp)}" \
                    '{
                        hash_algo: "sha256",
                        entries: [{
                            hash: $hash,
                            url: $url,
                            body_file: $body,
                            metadata_file: $meta,
                            fetched_at: $fetched
                        }]
                    }' > "$tmp_manifest"
            fi
            mv "$tmp_manifest" "$manifest"
        fi
    fi

    if command -v web_cache_store >/dev/null 2>&1 && web_cache_enabled; then
        if command -v web_cache_root_dir >/dev/null 2>&1; then
            debug_log="$(web_cache_root_dir)/logs/post-hook-debug.jsonl"
            mkdir -p "$(dirname "$debug_log")"
            printf '%s\n' "$hook_data" >> "$debug_log" 2>/dev/null || true
        fi
        url=$(echo "$hook_data" | jq -r '.tool_input.url // empty')
        if [[ -n "$url" ]]; then
            body_file=$(echo "$hook_data" | jq -r '.tool_output.body_file // empty')
            metadata=$(echo "$hook_data" | jq -c '
                {
                    status_code: (.tool_output.status_code // null),
                    content_type: (.tool_output.content_type // null),
                    headers: {
                        etag: (.tool_output.headers.etag // .tool_output.headers.ETag // null),
                        last_modified: (
                            .tool_output.headers["last-modified"]
                            // .tool_output.headers["Last-Modified"]
                            // null
                        )
                    }
                }' 2>/dev/null || echo '{}')

            if [[ -n "$body_file" && -f "$body_file" ]]; then
                web_cache_store "$url" "$body_file" "$metadata"
            else
                body_content=$(echo "$hook_data" | jq -r '.tool_output.body // empty')
                if [[ -n "$body_content" ]]; then
                    temp_body="$(mktemp)"
                    printf '%s' "$body_content" > "$temp_body"
                    web_cache_store "$url" "$temp_body" "$metadata"
                    rm -f "$temp_body"
                fi
            fi
        fi
    fi
fi

# Validate JSON written by Write tool and restore backup on failure
if [ "$tool_name" = "Write" ] && [ "$exit_code" = "0" ]; then
    file_path=$(echo "$hook_data" | jq -r '.tool_input.file_path // empty')
    if [[ -n "$file_path" && "$file_path" == *.json ]]; then
        if ! jq empty "$file_path" >/dev/null 2>&1; then
            restored="false"
            backup=""
            if [[ -n "$session_dir" ]]; then
                hash=$("$PROJECT_ROOT/src/utils/hash-string.sh" "$file_path")
                backup="$session_dir/.claude/write-backups/$hash.bak"
            fi
            if [[ -n "$backup" && -f "$backup" ]]; then
                cp "$backup" "$file_path" 2>/dev/null || true
                restored="true"
            else
                rm -f "$file_path" 2>/dev/null || true
            fi
            if [[ -n "$session_dir" ]]; then
                jq -nc \
                    --arg ts "$(get_timestamp)" \
                    --arg fp "$file_path" \
                    --arg restored "$restored" \
                    '{
                        timestamp: $ts,
                        type: "json_validation_error",
                        data: {
                            tool: "Write",
                            file_path: $fp,
                            restored: ($restored == "true")
                        }
                    }' >> "$session_dir/logs/events.jsonl" 2>/dev/null || true
            fi
            echo "⚠️ Invalid JSON detected in $file_path; previous content restored." >&2
        else
            if [[ -n "$session_dir" ]]; then
                hash=$("$PROJECT_ROOT/src/utils/hash-string.sh" "$file_path")
                rm -f "$session_dir/.claude/write-backups/$hash.bak" 2>/dev/null || true
            fi
        fi
    fi
fi

# Cache successful WebSearch results
if [ "$tool_name" = "WebSearch" ] && [ "$exit_code" = "0" ]; then
    if command -v web_search_cache_store >/dev/null 2>&1 && web_search_cache_enabled; then
        query=$(echo "$hook_data" | jq -r '.tool_input.query // empty')
        payload=$(echo "$hook_data" | jq -c '
            {
                query: .tool_input.query,
                results: (.tool_output.results // []),
                context: {
                    provider: (.tool_output.provider // .tool_output.engine // null),
                    search_type: (.tool_output.search_type // null),
                    region: (.tool_output.region // null),
                    total_count: (.tool_output.total_count // null),
                    executed_at: (.tool_output.issued_at // .tool_output.timestamp // null)
                },
                metadata: (.tool_output.metadata // null)
            }
        ' 2>/dev/null || echo "null")

        if [[ -n "$query" && "$payload" != "null" ]]; then
            metadata=$(echo "$payload" | jq -c '{provider: .context.provider, search_type: .context.search_type, region: .context.region, total_count: .context.total_count, executed_at: .context.executed_at}')
            web_search_cache_store "$query" "$payload" "$metadata"

            config=$(web_search_cache_load_config)
            if [[ "$(echo "$config" | jq -r '.log_debug_samples // false')" == "true" ]] && command -v web_search_cache_root_dir >/dev/null 2>&1; then
                search_debug="$(web_search_cache_root_dir)/logs/web-search-post-hook.jsonl"
                mkdir -p "$(dirname "$search_debug")"
                printf '%s\n' "$hook_data" >> "$search_debug" 2>/dev/null || true
            fi
        fi
    fi
fi

# Heartbeat tracking for agent timeout detection
# This runs after every tool use to signal agent is still active
if [[ -n "${CCONDUCTOR_AGENT_NAME:-}" && -n "$session_dir" ]]; then
    HEARTBEAT_FILE="$session_dir/.agent-heartbeat"
    TIMESTAMP=$(date +%s)
    echo "${CCONDUCTOR_AGENT_NAME}:${TIMESTAMP}" > "${HEARTBEAT_FILE}.tmp" 2>/dev/null || true
    mv "${HEARTBEAT_FILE}.tmp" "$HEARTBEAT_FILE" 2>/dev/null || true
fi

# Exit 0 to continue
exit 0
