#!/usr/bin/env bash
# Code Health Metrics

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== Code Health Report ==="
echo ""

# Function count
echo "Top 20 files by function count:"
grep -rh "^[a-z_][a-z_0-9]*() {" src/*.sh src/utils/*.sh 2>/dev/null | \
    sed 's/^.*\///' | cut -d: -f1 | sort | uniq -c | sort -rn | head -20

echo ""
total=$(grep -r "^[a-z_][a-z_0-9]*() {" src/ 2>/dev/null | wc -l | xargs)
files=$(find src -name "*.sh" 2>/dev/null | wc -l | xargs)
if [ "$files" -gt 0 ]; then
    avg=$((total / files))
else
    avg=0
fi

echo "Summary:"
echo "  Total functions: $total"
echo "  Total shell files: $files"  
echo "  Average: $avg functions/file"
echo ""

# Lines of code
echo "Lines of code by type:"
find src -name "*.sh" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print "  Shell scripts: " $1 " lines"}'
find src -name "*.json" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print "  JSON files: " $1 " lines"}'
find src -name "*.md" -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print "  Markdown: " $1 " lines"}'

echo ""
echo "Code quality indicators:"
echo "  TODO/FIXME comments: $(grep -r "TODO\|FIXME\|HACK\|XXX\|BUG" src/ -i 2>/dev/null | wc -l | xargs)"
echo "  Manual locking calls: $(grep -r "lock_acquire\|lock_release" src/ 2>/dev/null | grep -vc "shared-state.sh" || echo "0")"
echo "  Duplicate date calls: $(grep -r 'date -u +"%Y-%m-%dT%H:%M:%SZ"' src/ 2>/dev/null | wc -l | xargs)"

echo ""
echo "=== Report Complete ===" 

