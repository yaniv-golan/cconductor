#!/usr/bin/env bash
# Detect direct `bash` invocations that bypass the configured runtime.
# Ensures child processes inherit the Homebrew bash (>=4).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIRS=(
  "$PROJECT_ROOT/src"
)

violations=()

while IFS= read -r match; do
  [[ -z "$match" ]] && continue

  IFS=":" read -r file lineno line <<< "$match"

  line_no_newline="${line%%$'\n'}"
  trimmed_leading="${line_no_newline#"${line_no_newline%%[![:space:]]*}"}"

  if [[ "$trimmed_leading" == \#* ]]; then
    continue
  fi
  if [[ "$trimmed_leading" == '#!'* ]]; then
    continue
  fi
  if [[ "$line_no_newline" == *'command -v bash'* ]]; then
    continue
  fi
  if [[ "$line_no_newline" == *'brew install bash'* ]]; then
    continue
  fi
  if [[ "$line_no_newline" == *'| bash'* ]]; then
    continue
  fi

  state_single=0
  state_double=0
  prev=""
  i=0
  length=${#line}
  while (( i < length )); do
    ch="${line:i:1}"

    if [[ "$ch" == "'" && "$state_double" -eq 0 && "$prev" != "\\" ]]; then
      ((state_single ^= 1))
    elif [[ "$ch" == '"' && "$state_single" -eq 0 && "$prev" != "\\" ]]; then
      ((state_double ^= 1))
    elif [[ "$ch" == "b" && "$state_single" -eq 0 && "$state_double" -eq 0 ]]; then
      if [[ "${line:i:4}" == "bash" ]]; then
        before_char=""
        after_char=""
        (( i > 0 )) && before_char="${line:i-1:1}"
        (( i + 4 < length )) && after_char="${line:i+4:1}"

        if [[ ! "$before_char" =~ [A-Za-z0-9_] ]] && [[ ! "$after_char" =~ [A-Za-z0-9_] ]]; then
          # Skip if explicitly invoking configured runtime variables
          token_rest="${line:i}"
          if [[ "$token_rest" != bash\ \$\{CCONDUCTOR_BASH_RUNTIME* ]] && \
             [[ "$token_rest" != bash\ \$\{BASH_RUNTIME* ]] && \
             [[ "$token_rest" != bash\ \$CCONDUCTOR_BASH_RUNTIME* ]] && \
             [[ "$token_rest" != bash\ \$BASH_RUNTIME* ]]; then
            violations+=("$file:$lineno:$line_no_newline")
          fi
        fi
        ((i+=3))
      fi
    fi
    prev="$ch"
    ((i++))
  done
done < <(rg --no-heading --color=never --line-number --glob '*.sh' '\bbash\s+' "${TARGET_DIRS[@]}" || true)

if (( ${#violations[@]} > 0 )); then
  {
    echo "bash runtime lint: found direct 'bash' invocations;"
    echo "use \"\${CCONDUCTOR_BASH_RUNTIME:-\$(command -v bash)}\" instead."
    printf '%s\n' "${violations[@]}"
  } >&2
  exit 1
fi

exit 0
