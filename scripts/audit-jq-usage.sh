#!/usr/bin/env bash
# Audit jq usage patterns across the codebase
# Categorizes jq patterns by risk level to guide migration

set -Eeuo pipefail
export LC_ALL=C.UTF-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Require ripgrep and jq
if ! command -v rg &>/dev/null; then
    echo "audit-jq-usage: ripgrep (rg) is required but not installed" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "audit-jq-usage: jq is required but not installed" >&2
    exit 1
fi

# Output file
OUTPUT_FILE="${1:-audit-results.json}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Auditing jq usage patterns..." >&2

# Category A: --argjson with shell variable interpolation (HIGH RISK)
echo "  Scanning Category A: --argjson without validation..." >&2
cd "$PROJECT_ROOT" && rg --json '--argjson\s+\w+\s+["\$]' src/ 2>/dev/null | \
jq -s '
    map(select(.type == "match")) |
    map(try {
        file: .data.path.text,
        line: .data.line_number,
        snippet: (.data.lines.text | gsub("^\\s+"; "") | .[0:100]),
        confidence: "high"
    } catch empty) |
    unique_by(.file + ":" + (.line | tostring))
' > "$TEMP_DIR/category_a.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/category_a.json"

category_a_count=$(jq -r 'length' "$TEMP_DIR/category_a.json")

# Category B: Silent error suppression (jq ... 2>/dev/null || fallback)
echo "  Scanning Category B: Silent error suppression..." >&2
cd "$PROJECT_ROOT" && rg --json 'jq.*2>/dev/null.*\|\|' src/ 2>/dev/null | \
jq -s '
    map(select(.type == "match")) |
    map(try {
        file: .data.path.text,
        line: .data.line_number,
        snippet: (.data.lines.text | gsub("^\\s+"; "") | .[0:100]),
        severity: (
            if (.data.path.text | test("mission-orchestration|quality-gate|knowledge-graph|invoke-agent"))
            then "critical"
            elif (.data.path.text | test("cache|dashboard"))
            then "medium"
            else "low"
            end
        )
    } catch empty) |
    unique_by(.file + ":" + (.line | tostring))
' > "$TEMP_DIR/category_b.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/category_b.json"

category_b_count=$(jq -r 'length' "$TEMP_DIR/category_b.json")
category_b_critical=$(jq -r '[.[] | select(.severity == "critical")] | length' "$TEMP_DIR/category_b.json")

# Category C: jq on temp files without guards
echo "  Scanning Category C: Temp file operations..." >&2
cd "$PROJECT_ROOT" && rg --json 'jq\s+-s.*<|jq.*temp.*\.json|jq.*\$temp|jq.*mktemp' src/ 2>/dev/null | \
jq -s '
    map(select(.type == "match")) |
    map(try {
        file: .data.path.text,
        line: .data.line_number,
        snippet: (.data.lines.text | gsub("^\\s+"; "") | .[0:100]),
        pattern: (
            if (.data.lines.text | test("jq_slurp_array|json_slurp_array"))
            then "safe"
            else "unsafe"
        )
    } catch empty) |
    unique_by(.file + ":" + (.line | tostring)) |
    map(select(.pattern == "unsafe"))
' > "$TEMP_DIR/category_c.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/category_c.json"

category_c_count=$(jq -r 'length' "$TEMP_DIR/category_c.json")

# Category D: atomic_json_update with --argjson (no pre-validation)
echo "  Scanning Category D: atomic_json_update without validation..." >&2
cd "$PROJECT_ROOT" && rg --json 'atomic_json_update.*--argjson' src/ 2>/dev/null | \
jq -s '
    map(select(.type == "match")) |
    map(try {
        file: .data.path.text,
        line: .data.line_number,
        snippet: (.data.lines.text | gsub("^\\s+"; "") | .[0:100])
    } catch empty) |
    unique_by(.file + ":" + (.line | tostring))
' > "$TEMP_DIR/category_d.json" 2>/dev/null || echo '[]' > "$TEMP_DIR/category_d.json"

category_d_count=$(jq -r 'length' "$TEMP_DIR/category_d.json")

# Calculate totals
total_callsites=$((category_a_count + category_b_count + category_c_count + category_d_count))
total_files=$(cat "$TEMP_DIR"/category_*.json | jq -s 'add | map(.file) | unique | length')

# Generate summary using slurpfile
jq -n \
    --arg scan_date "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg total_files "$total_files" \
    --arg total_callsites "$total_callsites" \
    --arg a_count "$category_a_count" \
    --slurpfile a_results "$TEMP_DIR/category_a.json" \
    --arg b_count "$category_b_count" \
    --arg b_critical "$category_b_critical" \
    --slurpfile b_results "$TEMP_DIR/category_b.json" \
    --arg c_count "$category_c_count" \
    --slurpfile c_results "$TEMP_DIR/category_c.json" \
    --arg d_count "$category_d_count" \
    --slurpfile d_results "$TEMP_DIR/category_d.json" \
    '{
        scan_date: $scan_date,
        total_files: ($total_files | tonumber),
        total_callsites: ($total_callsites | tonumber),
        by_category: {
            A: {
                description: "--argjson without validation",
                count: ($a_count | tonumber),
                risk: "high",
                callsites: $a_results[0]
            },
            B: {
                description: "Silent error suppression (jq ... 2>/dev/null or fallback)",
                count: ($b_count | tonumber),
                critical: ($b_critical | tonumber),
                risk: "critical_for_hot_paths",
                callsites: $b_results[0]
            },
            C: {
                description: "Temp file operations without guards",
                count: ($c_count | tonumber),
                risk: "medium",
                callsites: $c_results[0]
            },
            D: {
                description: "atomic_json_update with --argjson (no pre-validation)",
                count: ($d_count | tonumber),
                risk: "medium",
                callsites: $d_results[0]
            }
        },
        triage_guidance: {
            priority_1: "Category B critical (hot paths: orchestration, quality-gate, KG, invoke-agent)",
            priority_2: "Category A (--argjson without validation)",
            priority_3: "Category C (temp files in critical paths)",
            priority_4: "Category D (document best practices)",
            false_positives: "Add # lint-allow: <tag> reason=\"...\" to suppress legitimate patterns"
        }
    }' > "$OUTPUT_FILE"

echo "" >&2
echo "========================================" >&2
echo "Audit Complete" >&2
echo "========================================" >&2
echo "Total files:     $total_files" >&2
echo "Total callsites: $total_callsites" >&2
echo "" >&2
echo "By Category:" >&2
echo "  A (--argjson):        $category_a_count" >&2
echo "  B (silent errors):    $category_b_count ($category_b_critical critical)" >&2
echo "  C (temp files):       $category_c_count" >&2
echo "  D (atomic no-check):  $category_d_count" >&2
echo "" >&2
echo "Results written to: $OUTPUT_FILE" >&2
echo "" >&2
echo "Priority: Fix Category B critical first (hot paths), then A, then C." >&2
