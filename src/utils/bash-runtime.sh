#!/usr/bin/env bash
# Utility helpers for selecting and enforcing the bash runtime used by CConductor.

# Resolve the preferred Bash runtime. Respects CCONDUCTOR_BASH_RUNTIME if already set,
# otherwise looks for modern Homebrew/GNU builds before falling back to whatever `bash`
# is on PATH.
resolve_cconductor_bash_runtime() {
    if [[ -n "${CCONDUCTOR_BASH_RUNTIME:-}" ]]; then
        printf '%s' "$CCONDUCTOR_BASH_RUNTIME"
        return 0
    fi

    local candidate
    for candidate in "/opt/homebrew/bin/bash" "/usr/local/bin/bash"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            CCONDUCTOR_BASH_RUNTIME="$(command -v "$candidate")"
            export CCONDUCTOR_BASH_RUNTIME
            printf '%s' "$CCONDUCTOR_BASH_RUNTIME"
            return 0
        fi
    done

    CCONDUCTOR_BASH_RUNTIME="$(command -v bash)"
    export CCONDUCTOR_BASH_RUNTIME
    printf '%s' "$CCONDUCTOR_BASH_RUNTIME"
    return 0
}

# Ensure the current shell is running with Bash >=4.0. If the active shell is older,
# re-exec using the resolved runtime. Exits with an error if a modern bash cannot be found.
ensure_modern_bash() {
    local runtime
    runtime="$(resolve_cconductor_bash_runtime)"

    if [[ -z "$runtime" ]]; then
        echo "Error: Unable to resolve a bash runtime." >&2
        exit 1
    fi

    local current_major="${BASH_VERSINFO[0]:-0}"
    if (( current_major >= 4 )); then
        # Already running under a modern bash; nothing to do.
        return 0
    fi

    local runtime_major
    # shellcheck disable=SC2016 # evaluated within the child bash process
    runtime_major="$("$runtime" -c 'printf "%s" "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
    if (( runtime_major < 4 )); then
        echo "Error: Bash 4.0 or higher is required (detected $runtime_major at $runtime)." >&2
        exit 1
    fi

    exec "$runtime" "$0" "$@"
}
