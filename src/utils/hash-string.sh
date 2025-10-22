#!/usr/bin/env bash
# hash-string.sh - Compute the SHA-256 hash for a string using common CLI tools.
# Cross-platform compatible: Linux (sha256sum), macOS (shasum), fallback (openssl)

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: hash-string.sh <string>" >&2
    exit 1
fi

string="$1"

if command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$string" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$string" | shasum -a 256 | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
    hash=$(printf '%s' "$string" | openssl dgst -sha256 | awk '{print $2}')
else
    echo "hash-string.sh: no SHA-256 tool available (sha256sum|shasum|openssl)" >&2
    exit 1
fi

printf '%s\n' "$hash"

