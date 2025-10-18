#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export CCONDUCTOR_CONFIG_DIR="$PROJECT_ROOT/.config/cconductor"

bash_bin="/bin/bash"
if command -v /opt/homebrew/bin/bash >/dev/null 2>&1; then
    bash_bin="/opt/homebrew/bin/bash"
elif command -v /usr/local/bin/bash >/dev/null 2>&1; then
    bash_bin="/usr/local/bin/bash"
fi

exec "$bash_bin" "$PROJECT_ROOT/cconductor" "$@"
