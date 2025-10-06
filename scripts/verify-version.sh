#!/usr/bin/env bash
# Verify VERSION file matches git tag

set -euo pipefail

TAG_VERSION="${1:-}"

if [ -z "$TAG_VERSION" ]; then
    echo "Usage: $0 <tag>"
    echo "Example: $0 v0.1.0"
    exit 1
fi

# Remove 'v' prefix
TAG_VERSION="${TAG_VERSION#v}"

# Read VERSION file
if [ ! -f "VERSION" ]; then
    echo "ERROR: VERSION file not found"
    exit 1
fi

FILE_VERSION=$(cat VERSION)

# Compare
if [ "$FILE_VERSION" != "$TAG_VERSION" ]; then
    echo "ERROR: Version mismatch!"
    echo "  VERSION file: $FILE_VERSION"
    echo "  Git tag:      v$TAG_VERSION"
    exit 1
fi

echo "✓ Version verified: $FILE_VERSION"

