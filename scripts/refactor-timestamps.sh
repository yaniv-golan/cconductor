#!/usr/bin/env bash
# Refactor all timestamp occurrences to use get_timestamp()
# This script replaces 'date -u +"%Y-%m-%dT%H:%M:%SZ"' with get_timestamp()

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "=== Refactoring Timestamps to use get_timestamp() ==="
echo ""

# Files to process (excluding shared-state.sh where the function is defined)
files=(
    "src/knowledge-graph.sh"
    "src/utils/dashboard.sh"
    "src/utils/hooks/post-tool-use.sh"
    "src/utils/hooks/pre-tool-use.sh"
    "src/utils/mission-session-init.sh"
    "src/utils/orchestration-logger.sh"
    "src/utils/budget-tracker.sh"
    "src/utils/mission-orchestration.sh"
    "src/utils/artifact-manager.sh"
    "src/utils/session-manager.sh"
    "src/claude-runtime/hooks/research-logger.sh"
    "src/claude-runtime/hooks/citation-tracker.sh"
    "src/utils/pdf-cache.sh"
    "src/utils/citation-manager.sh"
)

total_replacements=0

for file in "${files[@]}"; do
    if [ ! -f "$file" ]; then
        echo "⚠️  Skipping $file (not found)"
        continue
    fi
    
    # Count occurrences before
    before=$(grep -c 'date -u +"%Y-%m-%dT%H:%M:%SZ"' "$file" 2>/dev/null || echo "0")
    
    if [ "$before" -eq 0 ]; then
        echo "✓ $file (no occurrences)"
        continue
    fi
    
    # Create backup
    cp "$file" "$file.backup"
    
    # Replace all occurrences with get_timestamp
    # Pattern 1: --arg date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"  →  --arg date "$(get_timestamp)"
    # shellcheck disable=SC2016
    sed -i.tmp 's/--arg date "\$(date -u +"\\"%Y-%m-%dT%H:%M:%SZ\\"")"/--arg date "$(get_timestamp)"/g' "$file"
    
    # Pattern 2: --arg started "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"  →  --arg started "$(get_timestamp)"
    # shellcheck disable=SC2016
    sed -i.tmp 's/--arg started "\$(date -u +"\\"%Y-%m-%dT%H:%M:%SZ\\"")"/--arg started "$(get_timestamp)"/g' "$file"
    
    # Pattern 3: --arg updated "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"  →  --arg updated "$(get_timestamp)"
    # shellcheck disable=SC2016
    sed -i.tmp 's/--arg updated "\$(date -u +"\\"%Y-%m-%dT%H:%M:%SZ\\"")"/--arg updated "$(get_timestamp)"/g' "$file"
    
    # Pattern 4: timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"  →  timestamp=$(get_timestamp)
    # shellcheck disable=SC2016
    sed -i.tmp 's/timestamp="\$(date -u +"\\"%Y-%m-%dT%H:%M:%SZ\\"")"$/timestamp=$(get_timestamp)/g' "$file"
    
    # Pattern 5: local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")  →  local timestamp=$(get_timestamp)
    # shellcheck disable=SC2016
    sed -i.tmp 's/local timestamp=\$(date -u +"\\"%Y-%m-%dT%H:%M:%SZ\\"")/local timestamp=$(get_timestamp)/g' "$file"
    
    # Clean up sed temp file
    rm -f "$file.tmp"
    
    # Count occurrences after
    after=$(grep -c 'date -u +"%Y-%m-%dT%H:%M:%SZ"' "$file" 2>/dev/null || echo "0")
    replaced=$((before - after))
    
    if [ "$replaced" -gt 0 ]; then
        echo "✅ $file: replaced $replaced occurrence(s)"
        total_replacements=$((total_replacements + replaced))
    else
        echo "⚠️  $file: no replacements made (check manually)"
        # Restore backup if nothing changed
        mv "$file.backup" "$file"
    fi
done

echo ""
echo "=== Summary ==="
echo "Total replacements: $total_replacements"
echo ""
echo "Backup files created with .backup extension"
echo "Run 'find src -name \"*.backup\" -delete' to remove backups after verification"

