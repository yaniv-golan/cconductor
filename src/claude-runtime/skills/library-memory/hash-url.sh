#!/usr/bin/env bash
# hash-url.sh - Wrapper for hash-string.sh (backward compatibility)
# Computes SHA-256 hash for a URL using common CLI tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delegate to centralized hash-string helper (3 levels up: skills -> claude-runtime -> src)
exec "$SCRIPT_DIR/../../../utils/hash-string.sh" "$@"
