#!/bin/bash
# Generate SHA256 checksums for release artifacts

set -euo pipefail

VERSION="${1:-$(cat VERSION 2>/dev/null || echo "unknown")}"

if [ "$VERSION" = "unknown" ]; then
    echo "Error: VERSION file not found"
    echo "Usage: $0 [version]"
    exit 1
fi

echo "Generating checksums for v${VERSION}..."
echo ""

# Files to checksum
files=(
    "install.sh"
    "delve"
    "delve-v${VERSION}.tar.gz"
)

# Generate individual checksums
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        sha256sum "$file" > "${file}.sha256" 2>/dev/null || \
            shasum -a 256 "$file" > "${file}.sha256"
        echo "✓ ${file}.sha256"
    else
        echo "⚠ Skipping $file (not found)"
    fi
done

# Generate combined checksums file
{
    echo "# Delve v${VERSION} - SHA256 Checksums"
    echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "# Verify: sha256sum -c CHECKSUMS.txt"
    echo ""
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            sha256sum "$file" 2>/dev/null || shasum -a 256 "$file"
        fi
    done
} > CHECKSUMS.txt

echo "✓ CHECKSUMS.txt"
echo ""
echo "Complete! Generated checksums for v${VERSION}"

