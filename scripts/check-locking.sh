#!/usr/bin/env bash
# Check for manual locking patterns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== Manual Locking Usage Report ==="
echo ""

echo "Files using lock_acquire/lock_release (excluding shared-state.sh):"
grep -rl "lock_acquire\|lock_release" src/ 2>/dev/null | \
    grep -v "shared-state.sh" | \
    while read -r file; do
        count=$(grep -c "lock_acquire\|lock_release" "$file")
        echo "  $file: $count occurrences"
        
        # Show actual lines for review
        echo "    Lines:"
        grep -n "lock_acquire\|lock_release" "$file" | head -5 | sed 's/^/      /'
    done

echo ""
total=$(grep -r "lock_acquire\|lock_release" src/ 2>/dev/null | grep -vc "shared-state.sh" || echo "0")
echo "Total manual locking calls: $total"

echo ""
echo "Status:"
if [ "$total" -eq 0 ]; then
    echo "  ✅ All code uses atomic operations - no manual locking found!"
else
    echo "  ⚠️  Manual locking still in use - consider migrating to atomic_json_update"
fi

echo ""
echo "Recommendation: Migrate all JSON operations to atomic_json_update for consistency"

