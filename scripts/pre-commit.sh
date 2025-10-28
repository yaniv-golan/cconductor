#!/usr/bin/env bash
# Unified pre-commit hook executed via .git/hooks/pre-commit

set -euo pipefail

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "pre-commit: Bash 4.0 or higher is required." >&2
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

cd "$PROJECT_ROOT"

log_info "pre-commit" "Running staged shell script checks"

if ! command -v shellcheck >/dev/null 2>&1; then
    log_error "pre-commit" "shellcheck is required but not installed"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    log_error "pre-commit" "jq is required but not installed"
    exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
    log_error "pre-commit" "ripgrep (rg) is required but not installed"
    exit 1
fi

readarray -d '' staged_shell_files < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.sh') || true

if ((${#staged_shell_files[@]} > 0)); then
    log_info "pre-commit" "Linting ${#staged_shell_files[@]} staged shell script(s) with ShellCheck"
    shellcheck "${staged_shell_files[@]}"
else
    log_info "pre-commit" "No staged shell scripts detected; skipping ShellCheck"
fi

log_info "pre-commit" "Running jq lint guardrails"
bash "$PROJECT_ROOT/scripts/lint-jq-patterns.sh"

log_info "pre-commit" "Checking bash runtime usage"
bash "$PROJECT_ROOT/scripts/lint-bash-runtime.sh"

log_info "pre-commit" "Running jq usage audit"
audit_output="${TMPDIR:-/tmp}/jq-audit-precommit.json"
bash "$PROJECT_ROOT/scripts/audit-jq-usage.sh" "$audit_output" >/dev/null
rm -f "$audit_output"

log_info "pre-commit" "All pre-commit checks passed"
