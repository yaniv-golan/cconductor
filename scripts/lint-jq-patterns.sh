#!/usr/bin/env bash
# jq safety lint - flags jq invocations that silence errors without validation

set -Eeuo pipefail
export LC_ALL=C.UTF-8

if ! command -v jq >/dev/null 2>&1; then
    echo "lint-jq-patterns: jq is required" >&2
    exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "lint-jq-patterns: ripgrep (rg) is required" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

pattern='jq[^"\n]*2>/dev/null[^"\n]*\|\|'

violations=()

has_allow_comment() {
    local file_path="$1"
    local line_number="$2"

    for offset in 0 1; do
        local check_line=$((line_number - offset))
        (( check_line <= 0 )) && continue
        local line_content
        line_content=$(sed -n "${check_line}p" "$file_path" 2>/dev/null || echo "")
        if [[ "$line_content" == *"lint-allow:"* ]]; then
            return 0
        fi
    done
    return 1
}

while IFS=$'\t' read -r file_path line_number line_text; do
    if [[ -z "$file_path" ]]; then
        continue
    fi
    trimmed="${line_text#"${line_text%%[!$' \t\r\n']*}"}"
    if [[ "$trimmed" == \#* ]]; then
        continue
    fi
    if has_allow_comment "$file_path" "$line_number"; then
        continue
    fi
    violations+=("$file_path:$line_number:$line_text")
done < <(rg --json "$pattern" --glob '*.sh' "$PROJECT_ROOT" 2>/dev/null | \
    jq -r 'select(.type == "match") | "\(.data.path.text)\t\(.data.line_number)\t\(.data.lines.text)"')

if [[ ${#violations[@]} -eq 0 ]]; then
    exit 0
fi

echo "jq lint: found ${#violations[@]} silent-failure patterns:" >&2
for violation in "${violations[@]}"; do
    IFS=':' read -r file_path line_number line_text <<<"$violation"
    display_text="${line_text#"${line_text%%[!$' \t\r\n']*}"}"
    printf '  %s:%s  %s\n' "$file_path" "$line_number" "$display_text" >&2
done

echo "" >&2
echo "Add '# lint-allow: reason=\"...\"' on the same or previous line after validating the input, or refactor to use safe helpers." >&2
exit 1
