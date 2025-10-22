#!/usr/bin/env bash
# hash-file.sh - Compute the SHA-256 hash for a file's content
# Cross-platform compatible: Linux (sha256sum), macOS (shasum), fallback (openssl)

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: hash-file.sh <file_path>" >&2
    exit 1
fi

file_path="$1"

if [[ ! -f "$file_path" ]]; then
    echo "hash-file.sh: file not found: $file_path" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    hash=$(sha256sum "$file_path" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    hash=$(shasum -a 256 "$file_path" | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
    hash=$(openssl dgst -sha256 "$file_path" | awk '{print $2}')
else
    echo "hash-file.sh: no SHA-256 tool available (sha256sum|shasum|openssl)" >&2
    exit 1
fi

printf '%s\n' "$hash"

