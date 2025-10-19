#!/usr/bin/env bash
# hash-url.sh - Compute the SHA-256 hash for a URL using common CLI tools.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: hash-url.sh <url>" >&2
    exit 1
fi

url="$1"

if command -v sha256sum >/dev/null 2>&1; then
    hash=$(printf '%s' "$url" | sha256sum | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    hash=$(printf '%s' "$url" | shasum -a 256 | awk '{print $1}')
elif command -v openssl >/dev/null 2>&1; then
    hash=$(printf '%s' "$url" | openssl dgst -sha256 | awk '{print $2}')
else
    echo "hash-url.sh: no SHA-256 tool available (sha256sum|shasum|openssl)" >&2
    exit 1
fi

printf '%s\n' "$hash"
