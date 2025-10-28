#!/usr/bin/env bash
# Hook Bootstrap Helpers - shared utilities for Claude CLI hooks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hook_read_first_line() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        head -n1 "$file_path" 2>/dev/null || true
    fi
}

hook_find_repo_root_from_path() {
    local start_path="$1"
    local search_path="$start_path"
    while [[ -n "$search_path" && "$search_path" != "/" ]]; do
        if [[ -f "$search_path/VERSION" ]]; then
            printf '%s\n' "$search_path"
            return 0
        fi
        search_path="$(dirname "$search_path")"
    done
    printf '%s\n' ""
}

# Resolve repository root and session directory for hook execution.
# Usage: hook_resolve_roots "$BASH_SOURCE" repo_var session_var
hook_resolve_roots() {
    local hook_path="$1"
    local repo_root="${CCONDUCTOR_ROOT:-}"
    local session_dir="${CLAUDE_PROJECT_DIR:-${CCONDUCTOR_SESSION_DIR:-}}"

    if [[ -n "$session_dir" && -z "$repo_root" ]]; then
        local session_root_file="$session_dir/.cconductor-root"
        repo_root="$(hook_read_first_line "$session_root_file")"
    fi

    if [[ -z "$repo_root" && -n "$session_dir" ]]; then
        repo_root="$(hook_find_repo_root_from_path "$session_dir")"
    fi

    if [[ -z "$repo_root" ]]; then
        repo_root="$(hook_find_repo_root_from_path "$(cd "$(dirname "$hook_path")" && pwd)")"
    fi

    if [[ -z "$repo_root" ]]; then
        repo_root="$(hook_find_repo_root_from_path "$SCRIPT_DIR")"
    fi

    if [[ -n "$repo_root" && ! -d "$repo_root" ]]; then
        repo_root=""
    fi

    HOOK_REPO_ROOT="$repo_root"
    HOOK_SESSION_DIR="$session_dir"
    export HOOK_REPO_ROOT HOOK_SESSION_DIR
}

export -f hook_resolve_roots
