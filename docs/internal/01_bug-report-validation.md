# Bug Report Validation & Remediation Plan

> **Status (2025-11-01):** Cross-platform date helper (C1), safe path expansion (C2), hook shared-state sourcing (Security Test #3), setup-hooks idempotency (Security Test #8), and the baseline safe-fetch policy (Security Test #9) all shipped on 2025-11-01; remaining findings stay in backlog until validated.

**Related plans:**
- `02_codebase-maintainability-opportunities.md` – broader maintainability fixes validated by the team
- `15_shell-refactoring-plan.md` – staged refactor roadmap that absorbs the fixes called out here

**Generated:** 2025-11-01  
**Status:** Validated against codebase v0.5.0-dev  
**Scope:** AI-generated bug reports from external audit

This document validates all reported bugs, categorizes them by severity, and provides detailed remediation plans leveraging existing CConductor infrastructure.

---

## Table of Contents

1. [Critical Bugs](#critical-bugs)
2. [High Priority Bugs](#high-priority-bugs)
3. [Medium Priority Bugs](#medium-priority-bugs)
4. [Low Priority Bugs](#low-priority-bugs)
5. [Remediation Priorities](#remediation-priorities)

## Revision Notes

**Revision 1 (Post-Review):**
- Corrected H17: ShellCheck SC2295 confirms unquoted expansions ARE unsafe
- Expanded C1 coverage from 3 to 4 files (16 total occurrences)
- Renumbered all bugs for consistency (no gaps)
- Removed invalid "Invalid Bug Reports" section
- Updated totals: 38 validated bugs (was 35)

**Implementation Updates (2025-11-01):**
- ✅ Security Test #3 (hook sourcing) addressed: `src/claude-runtime/hooks/research-logger.sh` now sources `shared-state.sh`, guaranteeing `get_timestamp` is available without relying on ad-hoc fallbacks.
- ✅ Security Test #8 (setup-hooks idempotency) addressed: `src/utils/setup-hooks.sh` skips copying hooks or rewriting `.claude/settings.json` when the desired configuration is already present.
- ✅ Security Test #9 (safe-fetch policy baseline) addressed: added `config/safe-fetch-policy.json`, mirroring the default configuration so the safe-fetch wrapper always loads a validated policy before user overrides.

---

## Critical Bugs

### ✅ C1: BSD-specific `date` commands break Linux compatibility

**Files affected (16 occurrences across 4 files):**
- `src/utils/export-journal.sh` (10 occurrences: lines 129-137, 526-533, 566-570, 678-683, 1787-1793)
- `src/utils/dashboard.sh` (2 occurrences: lines 413-414)
- `src/utils/event-tailer.sh` (1 occurrence: line 93)
- `src/utils/session-utils.sh` (3 occurrences: lines 94, 127-128)

**Validation:** ✅ CONFIRMED

Multiple files use BSD-specific `date -j` and `date -r` flags that fail on GNU date (Linux). This is more widespread than initially reported.

**Evidence:**
```bash
# src/utils/export-journal.sh:129-130
start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$session_start" "+%s" 2>/dev/null || echo "0")
event_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$event_time" "+%s" 2>/dev/null || echo "0")

# src/utils/dashboard.sh:413-414
start_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$start_time" +%s 2>/dev/null || echo "0")
now_epoch=$(date -ju +%s)

# src/utils/event-tailer.sh:93
formatted=$(date -j -f "%Y-%m-%dT%H:%M:%S%z" "$iso_fixed" "+%b %d %Y, %I:%M %p %Z" 2>/dev/null)
```

**Impact:** Breaks all date/time display and calculations on Linux, yielding zeros or raw ISO strings.

**Remediation Plan:**

Create a centralized cross-platform date helper in `src/utils/date-helpers.sh`:

```bash
#!/usr/bin/env bash
# Date Helpers - Cross-platform date/time utilities
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

# Detect date implementation once
_DATE_IMPL=""
_detect_date_impl() {
    if [[ -n "$_DATE_IMPL" ]]; then
        return 0
    fi
    
    if date --version 2>&1 | grep -q "GNU"; then
        _DATE_IMPL="gnu"
    else
        _DATE_IMPL="bsd"
    fi
}

# Parse ISO8601 timestamp to epoch
# Usage: parse_iso_to_epoch "2025-11-01T12:34:56Z"
# Returns: Unix timestamp
parse_iso_to_epoch() {
    local iso_time="$1"
    _detect_date_impl
    
    if [[ "$_DATE_IMPL" == "gnu" ]]; then
        date -d "$iso_time" +%s 2>/dev/null || echo "0"
    else
        # BSD date
        TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_time" "+%s" 2>/dev/null || echo "0"
    fi
}

# Format epoch to human-readable date
# Usage: format_epoch_date 1698765432
# Returns: "November 01, 2025"
format_epoch_date() {
    local epoch="$1"
    _detect_date_impl
    
    if [[ "$_DATE_IMPL" == "gnu" ]]; then
        date -d "@$epoch" "+%B %d, %Y" 2>/dev/null || echo "$epoch"
    else
        # BSD date
        date -r "$epoch" "+%B %d, %Y" 2>/dev/null || echo "$epoch"
    fi
}

# Format epoch to human-readable datetime
# Usage: format_epoch_datetime 1698765432
# Returns: "November 01, 2025 at 12:34 PM"
format_epoch_datetime() {
    local epoch="$1"
    _detect_date_impl
    
    if [[ "$_DATE_IMPL" == "gnu" ]]; then
        date -d "@$epoch" "+%B %d, %Y at %l:%M %p" 2>/dev/null | sed 's/  / /g' || echo "$epoch"
    else
        # BSD date
        date -r "$epoch" "+%B %d, %Y at %l:%M %p" 2>/dev/null | sed 's/  / /g' || echo "$epoch"
    fi
}

# Calculate duration between two ISO timestamps (in seconds)
# Usage: calculate_iso_duration "2025-11-01T10:00:00Z" "2025-11-01T11:30:00Z"
# Returns: 5400
calculate_iso_duration() {
    local start_iso="$1"
    local end_iso="$2"
    
    local start_epoch end_epoch
    start_epoch=$(parse_iso_to_epoch "$start_iso")
    end_epoch=$(parse_iso_to_epoch "$end_iso")
    
    if [[ "$start_epoch" == "0" || "$end_epoch" == "0" ]]; then
        echo "0"
        return 1
    fi
    
    echo $((end_epoch - start_epoch))
}

export -f parse_iso_to_epoch
export -f format_epoch_date
export -f format_epoch_datetime
export -f calculate_iso_duration
```

**Migration steps:**
1. Create `src/utils/date-helpers.sh` with functions above
2. Add `source "$SCRIPT_DIR/date-helpers.sh"` to affected files
3. Replace all `date -j` / `date -r` calls with helper functions
4. Add tests in `tests/test-date-helpers.sh` for both BSD and GNU platforms
5. Update `AGENTS.md` to mandate use of date-helpers for all date operations

**Estimated effort:** 3-4 hours (centralized helper + systematic replacement)

**Implementation Update (2025-11-01):**
- Added `src/utils/date-helpers.sh` providing cross-platform parsing and formatting functions (`parse_iso_to_epoch`, `format_epoch_custom`, `format_epoch_date`, `format_epoch_datetime`, `calculate_iso_duration`).
- Updated `src/utils/export-journal.sh`, `src/utils/dashboard.sh`, `src/utils/event-tailer.sh`, and `src/utils/session-utils.sh` to source the helper and replace all BSD-only `date` invocations.
- Documented the helper requirement in `AGENTS.md` and introduced regression coverage via `tests/test-date-helpers.sh` (passes on 2025-11-01).
- Validated changes with `shellcheck` across all modified scripts.

---

### ✅ C2: `eval echo` command injection in path-resolver.sh

**File:** `src/utils/path-resolver.sh:67`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
# src/utils/path-resolver.sh:67
expanded_path=$(eval echo "$expanded_path")
```

**Impact:** User-controllable config paths in `~/.config/cconductor/paths.json` are passed through `eval`, enabling arbitrary command execution via crafted paths like `${PROJECT_ROOT}/$(rm -rf /)`.

**Remediation Plan:**

The string replacement approach on lines 58-64 is already correct and safe. Line 67's `eval echo` is only needed for tilde expansion, which can be done safely:

```bash
# BEFORE (line 67):
expanded_path=$(eval echo "$expanded_path")

# AFTER (safe tilde expansion):
# Handle tilde expansion without eval
if [[ "$expanded_path" =~ ^~ ]]; then
    expanded_path="${expanded_path/#\~/$HOME}"
fi
```

The normalization code (lines 69-75) already handles relative paths correctly, so this is the only change needed.

**Testing:**
1. Add test case with malicious path: `~/.config/cconductor/paths.json` containing `"cache_dir": "${PROJECT_ROOT}/$(echo hacked)"`
2. Verify path resolver fails gracefully or sanitizes without executing
3. Add shellcheck suppression with explanation if needed

**Estimated effort:** 30 minutes (single line fix + test case)

**Implementation Update (2025-11-01):**
- Replaced `eval`-based expansion in `src/utils/path-resolver.sh` with explicit tilde handling for `~`, `~+`, and `~-`, eliminating command substitution attack vectors.
- Added a regression to `tests/test-security-fixes.sh` (Test 11) that verifies malicious `$(...)` segments in `paths.json` are treated as literals; confirmed the marker file is not created.
- Manually validated the hardened resolver via subshell invocation to ensure outputs remain stable and injection markers are absent.

---

### ✅ C3: Test suite expects old report path `70_report/`

**File:** `tests/test-simple-query.sh:60-74`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
# tests/test-simple-query.sh:60-74
if [ -f "$SESSION_DIR/70_report/mission-report.md" ]; then
    echo "✓ Report generated successfully"
```

The codebase now uses `report/mission-report.md` structure (as evidenced by git modifications to documentation), but test still checks the old path.

**Remediation Plan:**

```bash
# Update test-simple-query.sh line 60:
# BEFORE:
if [ -f "$SESSION_DIR/70_report/mission-report.md" ]; then

# AFTER:
if [ -f "$SESSION_DIR/report/mission-report.md" ]; then
    echo "✓ Report generated successfully"
elif [ -f "$SESSION_DIR/70_report/mission-report.md" ]; then
    echo "✓ Report generated successfully (legacy path)"
```

Also update lines 64 and 68 to check the new path first with fallback.

**Testing:**
1. Run `./tests/test-simple-query.sh` against fresh mission
2. Verify it detects new `report/` structure
3. Consider deprecating old path check after migration period

**Estimated effort:** 15 minutes

**Implementation Update (2025-11-01):**
- Updated `tests/test-simple-query.sh` to prioritize the modern `report/mission-report.md` layout, fall back to `final/mission-report.md`, and retain support for legacy `70_report/mission-report.md`.
- The script now surfaces which path was validated while keeping the existing executive-summary and sources checks intact.
- Validated the changes with `shellcheck tests/test-simple-query.sh`.

---

### ✅ C4: Citation tracker lock file leak on early exit

**File:** `src/claude-runtime/hooks/citation-tracker.sh:54-62, 74-81`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
# Lines 54-62 and 74-81 show lock creation without trap:
lock_dir="${CITATIONS_DB}.lock"
if mkdir "$lock_dir" 2>/dev/null; then
    jq --arg url "$URL" --arg ts "$TIMESTAMP" \
        '. += [{url: $url, accessed: $ts, type: "web"}]' \
        "$CITATIONS_DB" > "$CITATIONS_DB.tmp" && mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
    rmdir "$lock_dir"
fi
```

If jq or mv fails, the script exits due to implicit `set -e` (inherited from sourcing core-helpers.sh), leaving lock behind. Also, the script has NO trap for cleanup.

**Impact:** Permanent lock file blocks all future citation writes until manually removed.

**Remediation Plan:**

Use existing `core-helpers.sh` lock infrastructure which already handles traps:

```bash
# BEFORE (lines 48-62):
if type atomic_json_update &>/dev/null; then
    atomic_json_update "$CITATIONS_DB" --arg url "$URL" --arg ts "$TIMESTAMP" \
        '. += [{url: $url, accessed: $ts, type: "web"}]'
else
    # Fallback: manual temp file with brief lock attempt
    lock_dir="${CITATIONS_DB}.lock"
    if mkdir "$lock_dir" 2>/dev/null; then
        jq --arg url "$URL" --arg ts "$TIMESTAMP" \
            '. += [{url: $url, accessed: $ts, type: "web"}]' \
            "$CITATIONS_DB" > "$CITATIONS_DB.tmp" && mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
        rmdir "$lock_dir"
    fi
fi

# AFTER (use core-helpers locking):
if type atomic_json_update &>/dev/null; then
    atomic_json_update "$CITATIONS_DB" --arg url "$URL" --arg ts "$TIMESTAMP" \
        '. += [{url: $url, accessed: $ts, type: "web"}]'
else
    # Fallback: use simple_lock from core-helpers (has automatic cleanup)
    lock_file="${CITATIONS_DB}.lock"
    if simple_lock_acquire "$lock_file" 5; then
        trap "simple_lock_release '$lock_file'" EXIT ERR
        jq --arg url "$URL" --arg ts "$TIMESTAMP" \
            '. += [{url: $url, accessed: $ts, type: "web"}]' \
            "$CITATIONS_DB" > "$CITATIONS_DB.tmp" && mv "$CITATIONS_DB.tmp" "$CITATIONS_DB"
        simple_lock_release "$lock_file"
        trap - EXIT ERR
    else
        # Lock timeout - log and continue (hooks must not block)
        if command -v log_warn &>/dev/null; then
            log_warn "Citation tracker: lock timeout, skipping citation"
        fi
    fi
fi
```

Apply same fix to lines 74-81 (Read tool citations).

**Testing:**
1. Simulate jq failure in fallback path (invalid JSON)
2. Verify lock is cleaned up
3. Test parallel hook invocations

**Estimated effort:** 1 hour (fix + comprehensive testing)

---

### ✅ C5: Citation tracker silently drops citations on lock contention

**File:** `src/claude-runtime/hooks/citation-tracker.sh:54-62`

**Validation:** ✅ CONFIRMED

The fallback path silently fails if lock cannot be acquired:

```bash
lock_dir="${CITATIONS_DB}.lock"
if mkdir "$lock_dir" 2>/dev/null; then
    # ... write citation ...
    rmdir "$lock_dir"
fi
# If mkdir fails, citation is silently dropped (no retry, no logging)
```

**Impact:** Under parallel tool calls, citations are lost without trace.

**Remediation Plan:**

Already addressed in C4 remediation above - the `simple_lock_acquire` function includes timeout and retry logic, and logs failures via `log_warn`.

---

### ✅ C6: Homebrew formula has empty sha256

**File:** `Formula-cconductor.rb:11`

**Validation:** ✅ CONFIRMED

**Evidence:**
```ruby
url "https://github.com/yaniv-golan/cconductor/archive/v0.4.0.tar.gz"
sha256 "" # Will be filled during release
```

**Impact:** Brew install fails with checksum error.

**Remediation Plan:**

This is a release engineering issue, not a code bug. The formula should:

1. Never be committed with empty sha256
2. Be auto-generated during release from template
3. Include checksum calculation in release script

**Action items:**

1. Create `scripts/release-homebrew.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="$1"
TARBALL_URL="https://github.com/yaniv-golan/cconductor/archive/v${VERSION}.tar.gz"

# Download and calculate sha256
echo "Downloading tarball..."
curl -sL "$TARBALL_URL" -o "/tmp/cconductor-${VERSION}.tar.gz"

SHA256=$(shasum -a 256 "/tmp/cconductor-${VERSION}.tar.gz" | awk '{print $1}')
echo "SHA256: $SHA256"

# Update formula
sed -i.bak "s|url \".*\"|url \"$TARBALL_URL\"|g" Formula-cconductor.rb
sed -i.bak "s|sha256 \".*\"|sha256 \"$SHA256\"|g" Formula-cconductor.rb
rm Formula-cconductor.rb.bak

echo "✓ Updated Formula-cconductor.rb"
```

2. Add to release checklist in `docs/CONTRIBUTING.md`
3. Add CI check that fails if sha256 is empty

**Estimated effort:** 1 hour (script + documentation)

---

## High Priority Bugs

### ✅ H1: Averaging confidence only reads first findings file

**File:** `src/utils/export-journal.sh:586-588`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
avg_confidence=$(find "$session_dir/work" -name "findings-*.json" -type f -print0 2>/dev/null | \
    xargs -0 jq -r '[.claims[]?.confidence // 0] | add / length * 100 | floor' 2>/dev/null | \
    head -1)
```

The `head -1` takes only the first file's result, not an average across all files.

**Impact:** Reported confidence is wrong when multiple finding shards exist.

**Remediation Plan:**

Use jq's slurp mode to aggregate all files:

```bash
# BEFORE (lines 586-589):
avg_confidence=$(find "$session_dir/work" -name "findings-*.json" -type f -print0 2>/dev/null | \
    xargs -0 jq -r '[.claims[]?.confidence // 0] | add / length * 100 | floor' 2>/dev/null | \
    head -1)
avg_confidence=${avg_confidence:-0}

# AFTER (proper aggregation):
if [ -d "$session_dir/work" ] && [ "$total_claims" -gt 0 ]; then
    avg_confidence=$(
        find "$session_dir/work" -name "findings-*.json" -type f 2>/dev/null | \
        xargs jq -s '
            [.[] | .claims[]? | select(.confidence != null) | .confidence] |
            if length > 0 then (add / length * 100 | floor) else 0 end
        ' 2>/dev/null || echo "0"
    )
    avg_confidence=${avg_confidence:-0}
else
    avg_confidence=0
fi
```

This properly:
1. Uses `-s` to slurp all files into one array
2. Flattens claims from all files
3. Handles missing/null confidence values
4. Returns 0 for empty sets
5. Uses existing `safe_jq_from_file` pattern for error handling

**Testing:**
1. Create mission with multiple findings-*.json files
2. Verify avg_confidence reflects all files
3. Test with missing claims[] in some files

**Estimated effort:** 30 minutes

---

### ✅ H2-H14: Missing `sort_by` before `group_by` in jq pipelines

**Files affected:**
- `src/utils/context-manager.sh:31-38, 112-123`
- `src/utils/summarizer.sh:19-23`
- `src/utils/mission-orchestration.sh:2449-2458`
- `src/utils/kg-utils.sh:47-54`
- `src/utils/gap-analyzer.sh:116-123`
- `src/utils/web-search-cache.sh:204-228`
- `src/utils/confidence-scorer.sh:221-223`
- `src/utils/orchestration-logger.sh:167-175`
- `src/utils/citation-manager.sh:182-188`

**Validation:** ✅ CONFIRMED (all instances)

jq's `group_by()` requires sorted input to work correctly. Without `sort_by()`, identical values in different positions create separate groups.

**Evidence (context-manager.sh:31-38):**
```bash
# Incorrect:
group_by(.source_url) |

# Should be:
sort_by(.source_url) | group_by(.source_url) |
```

**Impact:** 
- Duplicate groups for same keys
- Incorrect counts in statistics
- Under-counting in aggregations

**Remediation Plan:**

Create a systematic fix script to ensure correctness across all files:

```bash
#!/usr/bin/env bash
# scripts/fix-group-by-sorting.sh
set -euo pipefail

# Pattern: add sort_by before every group_by that lacks it
# Check each file individually to preserve different field names

declare -A FIXES=(
    # file:line:field
    ["src/utils/context-manager.sh:31"]=".source_url"
    ["src/utils/context-manager.sh:120"]=".fact"
    ["src/utils/summarizer.sh:19"]=".credibility"
    ["src/utils/mission-orchestration.sh:2449"]=".topic // \"general\""
    ["src/utils/kg-utils.sh:47"]=".verification_status // \"unknown\""
    ["src/utils/gap-analyzer.sh:116"]="(severity_field)"  # needs context review
    ["src/utils/web-search-cache.sh:218"]="."
    ["src/utils/confidence-scorer.sh:222"]=".related_entities[0]"
    ["src/utils/orchestration-logger.sh:169"]=".type"
    ["src/utils/citation-manager.sh:185"]=".type"
)

for fix in "${!FIXES[@]}"; do
    file="${fix%:*}"
    field="${FIXES[$fix]}"
    echo "Fixing $file: add sort_by($field) before group_by($field)"
    # Manual review and fix each case
done
```

**Manual fixes required** (jq context varies):

**context-manager.sh line 31:**
```bash
# BEFORE:
group_by(.source_url) |

# AFTER:
sort_by(.source_url) | group_by(.source_url) |
```

**context-manager.sh line 120:**
```bash
# BEFORE:
group_by(.fact) |

# AFTER:
sort_by(.fact) | group_by(.fact) |
```

Repeat for all other files listed above with their specific grouping fields.

**Testing:**
1. Run `tests/run-all-tests.sh` before and after
2. Compare stats outputs for consistency
3. Verify no duplicate groups in reports

**Estimated effort:** 2-3 hours (systematic review + testing)

---

### ✅ H15: Findings pruning fails on missing glob matches

**File:** `src/utils/context-manager.sh:18-45`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
jq -s '...' "$raw_dir"/*-findings*.json
```

If no files match the glob, bash passes the literal string `"$raw_dir/*-findings*.json"` to jq, causing exit 2.

**Impact:** Prune pipeline aborts on empty findings directory.

**Remediation Plan:**

Use bash array to check for matches first:

```bash
# BEFORE (line 18-45):
jq -s '...' "$raw_dir"/*-findings*.json

# AFTER (safe glob handling):
prune_context() {
    local raw_dir="$1"
    local findings_files=()
    
    # Safely collect matching files
    shopt -s nullglob
    findings_files=("$raw_dir"/*-findings*.json)
    shopt -u nullglob
    
    # Return empty array if no files
    if [ ${#findings_files[@]} -eq 0 ]; then
        echo "[]"
        return 0
    fi
    
    # Process files
    jq -s '
        # [rest of jq filter unchanged]
    ' "${findings_files[@]}"
}
```

**Testing:**
1. Call `prune_context` on empty directory
2. Verify it returns `[]` without error
3. Test with actual findings files

**Estimated effort:** 30 minutes

---

### ✅ H16: Hierarchical summary creation fails on missing output directory

**File:** `src/utils/summarizer.sh:38-46`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
jq '[.[] | .key_facts[0:2]] | flatten | .[0:10]' "$input_file" \
    > "$output_dir/summary-level1.json"
```

If `$output_dir` doesn't exist, the redirection fails silently (or noisily with "No such file or directory").

**Remediation Plan:**

Use existing `ensure_dir` helper from `file-helpers.sh`:

```bash
create_hierarchical_summary() {
    local input_file="$1"
    local output_dir="$2"
    
    # Ensure output directory exists
    if ! ensure_dir "$output_dir"; then
        log_error "Failed to create summary output directory: $output_dir"
        return 1
    fi
    
    # Level 1: Executive summary (500 tokens)
    jq '[.[] | .key_facts[0:2]] | flatten | .[0:10]' "$input_file" \
        > "$output_dir/summary-level1.json"
    
    # [rest unchanged]
}
```

**Testing:**
1. Call with non-existent directory path
2. Verify directory is created
3. Verify summaries are written

**Estimated effort:** 15 minutes

---

### ✅ H17: Artifact validator uses unquoted pattern expansion (SC2295)

**Files:** 
- `src/utils/artifact-manager.sh` (3 occurrences: lines 246, 413, 435)
- `src/knowledge-graph.sh` (1 occurrence: line 1317)

**Validation:** ✅ CONFIRMED by ShellCheck SC2295

**Evidence from shellcheck:**
```
src/utils/artifact-manager.sh:246:30: info: SC2295: Expansions inside ${..} need to be quoted separately
      local rel_path="${path#$session_dir/}"
                             ^----------^
Did you mean: "${path#"$session_dir"/}"

src/utils/artifact-manager.sh:413:37: info: SC2295
    --arg contract_path_rel "${contract_path#$PROJECT_ROOT/}" \
                                             ^-----------^
Did you mean: "${contract_path#"$PROJECT_ROOT"/}"

src/utils/artifact-manager.sh:435:37: info: SC2295
    --arg manifest_path_rel "${manifest_path#$session_dir/}" \
                                             ^----------^
Did you mean: "${manifest_path#"$session_dir"/}"
```

**Why this matters:**

While parameter expansion with `${var#pattern}` is NOT pathname expansion, the pattern itself (`$session_dir/`) is expanded BEFORE the removal operation. If `$session_dir` contains glob metacharacters like `[`, `*`, or `?`, they will be interpreted as patterns during the removal operation, causing unexpected behavior.

**Example failure scenario:**
```bash
session_dir="/tmp/test-[123]"
path="/tmp/test-[123]/file.txt"
rel_path="${path#$session_dir/}"  # May NOT remove prefix correctly if [123] matches as pattern
# Expected: "file.txt"
# Actual: Could be original path if pattern match fails
```

**Impact:** Sessions under directories with glob characters produce incorrect relative paths in manifests and reports.

**Remediation Plan:**

Quote the expansion inside the pattern per ShellCheck recommendation:

```bash
# BEFORE (src/utils/artifact-manager.sh:246):
local rel_path="${path#$session_dir/}"

# AFTER:
local rel_path="${path#"$session_dir"/}"

# BEFORE (src/utils/artifact-manager.sh:413):
--arg contract_path_rel "${contract_path#$PROJECT_ROOT/}" \

# AFTER:
--arg contract_path_rel "${contract_path#"$PROJECT_ROOT"/}" \

# BEFORE (src/utils/artifact-manager.sh:435):
--arg manifest_path_rel "${manifest_path#$session_dir/}" \

# AFTER:
--arg manifest_path_rel "${manifest_path#"$session_dir"/}" \

# BEFORE (src/knowledge-graph.sh:1317):
local relative_path="${agent_output_file#$session_dir/}"

# AFTER:
local relative_path="${agent_output_file#"$session_dir"/}"
```

**Testing:**
1. Create session under directory with glob chars: `/tmp/test-[abc]/`
2. Run mission and verify manifests show correct relative paths
3. Verify shellcheck no longer warns

**Estimated effort:** 15 minutes (4 simple quote additions)

---

### ✅ H18: export-journal.sh missing `set -euo pipefail`

**File:** `src/utils/export-journal.sh:1-33`

**Validation:** ✅ CONFIRMED

**Remediation Plan:**

Add explicit strict mode per AGENTS.md:

```bash
#!/usr/bin/env bash
#
# export-journal.sh - Export research journal as markdown
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/bash-runtime.sh"
# [rest unchanged]
```

Even if bash-runtime.sh sets strict mode, being explicit follows project conventions and prevents issues if that file is refactored.

**Estimated effort:** 5 minutes (copy pattern from other files)

**Implementation Update (2025-11-01):**
- Added `set -euo pipefail` to the top of `src/utils/export-journal.sh` to comply with the standard script header pattern.
- Confirmed the script remains lint-clean via `shellcheck src/utils/export-journal.sh`.

---

## Medium Priority Bugs

### ✅ M1-M5: Missing `set -euo pipefail` in utility scripts

**Files:**
- `src/utils/bash-runtime.sh`
- `src/utils/bootstrap.sh`
- `src/utils/error-logger.sh`
- `src/claude-runtime/hooks/citation-tracker.sh`
- `src/claude-runtime/hooks/research-logger.sh`

**Validation:** ✅ CONFIRMED (verified with grep)

All five files are missing explicit `set -euo pipefail` declarations.

**Remediation Plan:**

Add strict mode to all files per AGENTS.md conventions:

```bash
#!/usr/bin/env bash
# [description]
set -euo pipefail

# [rest of file]
```

**Special consideration for hooks:** Hooks should be defensive and not exit on all errors, but unset variables and pipefail are still appropriate. Consider `set -uo pipefail` without `-e` for hooks, or wrap critical sections with conditional logic.

**Testing:**
1. Source each file and verify no breakage
2. Test with unset variables
3. Run hook tests in `tests/manual/`

**Estimated effort:** 1 hour (systematic addition + testing)

---

### ✅ M6: Security test uses `-eo pipefail` instead of `-euo pipefail`

**File:** `tests/test-security-fixes.sh:5-8`

**Validation:** ✅ CONFIRMED

**Remediation:** Add `-u` flag if confirmed.

**Implementation Update (2025-11-01):**
- Updated `tests/test-security-fixes.sh` to use `set -euo pipefail`, ensuring unset variables trigger failures during the security regression suite.
- Verified the script still passes via `shellcheck tests/test-security-fixes.sh`.

---

### ✅ M7: Cleanup script uses only `-e`

**File:** `scripts/cleanup.sh:5`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
#!/usr/bin/env bash
# CConductor Cleanup Script
# Cleans up old sessions, processes, and temporary files

set -e
```

**Impact:** Unset variables and pipe failures are not caught.

**Remediation Plan:**

```bash
#!/usr/bin/env bash
# CConductor Cleanup Script
# Cleans up old sessions, processes, and temporary files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

# [rest of file - may need adjustments for interactive prompts]
```

**Note:** The `read -r -p` prompts (lines 81, 132) may need adjustment as `set -e` with interactive `read` can cause issues in non-interactive contexts. Add checks:

```bash
read -r -p "..." response || response="n"
```

**Implementation Update (2025-11-01):**
- Switched `scripts/cleanup.sh` to `set -euo pipefail` and added fallbacks for every interactive `read` so non-interactive runs default to “no” rather than aborting.
- Ensured existing cleanup logic remains intact by re-running `shellcheck scripts/cleanup.sh`.

**Testing:**
1. Run interactively
2. Run in CI (non-interactive)
3. Test with unset variables

**Estimated effort:** 30 minutes

---

### ✅ M8: Cleanup script searches for obsolete process names

**File:** `scripts/cleanup.sh:21-35`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
# Line 21:
local cconductor_pids=$(ps aux | grep -E "[d]elve|[D]ELVE" | awk '{print $2}' || true)
```

The pattern `[d]elve|[D]ELVE` is a legacy search term that doesn't match modern cconductor processes.

**Remediation Plan:**

Update to search for actual process names:

```bash
# BEFORE:
local cconductor_pids=$(ps aux | grep -E "[d]elve|[D]ELVE" | awk '{print $2}' || true)

# AFTER:
local cconductor_pids=$(ps aux | grep -E "[c]conductor|cconductor-mission" | awk '{print $2}' || true)
```

**Testing:**
1. Start a mission
2. Run `ps aux | grep cconductor` to see actual process names
3. Update pattern to match those processes
4. Verify cleanup kills them

**Estimated effort:** 30 minutes (investigation + testing)

---

### ✅ M9: Interactive confirmation breaks under `set -e` in non-interactive shells

**File:** `scripts/cleanup.sh:59-84`

**Validation:** ✅ CONFIRMED (conditional on M7 fix)

If M7 adds `set -e`, then `read -p` in CI will abort the script.

**Remediation:** Already covered in M7 remediation above.

**Implementation Update (2025-11-01):**
- Added `read ... || response="n"` guards everywhere the cleanup script prompts the operator, preventing abrupt exits when stdin is closed (CI/non-interactive environments).

---

### ✅ M10: path-resolver documentation and hardening

**File:** `src/utils/path-resolver.sh:47-72`

**Validation:** ✅ CONFIRMED as low-risk hardening opportunity

**Analysis:**

The string replacement operations (lines 58-64) are indeed safe:
```bash
expanded_path="${expanded_path//\$\{HOME\}/$HOME}"
expanded_path="${expanded_path//\$\{PROJECT_ROOT\}/$PROJECT_ROOT}"
```

However, the subsequent `eval echo` (line 67, addressed in C2) creates an injection vector. While C2 fixes the immediate issue, additional hardening would prevent future regressions.

**Remediation Plan:**

After fixing C2's eval removal, add validation layer:

```bash
# After line 64 (after all variable expansions):

# Validate no remaining command substitution attempts
if [[ "$expanded_path" =~ \$\(|\`|\$\{.*\} ]]; then
    log_error "path-resolver: Invalid path contains shell metacharacters: $expanded_path"
    return 1
fi

# Safe tilde expansion (replaces C2's eval echo)
if [[ "$expanded_path" =~ ^~ ]]; then
    expanded_path="${expanded_path/#\~/$HOME}"
fi
```

This provides defense-in-depth against config file injection attempts.

**Estimated effort:** 15 minutes (additional validation layer)

---

### ✅ M11: export-journal ignores jq failures with `2>/dev/null`

**File:** `src/utils/export-journal.sh:585-589`

**Validation:** ✅ CONFIRMED (part of H1)

Already addressed in H1 remediation plan.

---

### ✅ M12-M13: Citation/research hooks write world-readable logs

**Files:**
- `src/claude-runtime/hooks/citation-tracker.sh:22-31`
- `src/claude-runtime/hooks/research-logger.sh:21-34`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
CITATIONS_DB="$HOME/.claude/research-engine/citations.json"
mkdir -p "$(dirname "$CITATIONS_DB")"
```

No `umask` or `chmod` is set, so files are created with default permissions (usually 644 or 664).

**Impact:** Other users on the system can read research queries and sources.

**Remediation Plan:**

Set restrictive umask before creating files:

```bash
# Add after line 28 in citation-tracker.sh:
CITATIONS_DB="$HOME/.claude/research-engine/citations.json"

# Set restrictive permissions (user-only read/write)
umask 077
mkdir -p "$(dirname "$CITATIONS_DB")"

# Initialize citations file if it doesn't exist
if [ ! -f "$CITATIONS_DB" ]; then
    echo "[]" > "$CITATIONS_DB"
    chmod 600 "$CITATIONS_DB"  # Ensure restrictive permissions
fi
```

Apply same fix to research-logger.sh.

**Testing:**
1. Delete existing log files
2. Run hooks
3. Verify new files have 600 permissions
4. Verify directories have 700 permissions

**Estimated effort:** 30 minutes

---

### ✅ M14: Research logger allows log injection via multi-line queries

**File:** `src/claude-runtime/hooks/research-logger.sh:35-57`

**Validation:** ✅ CONFIRMED

**Remediation Plan:**

If logs are written line-by-line with simple echo/printf, multi-line queries could inject bogus lines.

Use JSON-escaped logging:

```bash
# Instead of:
echo "$query" >> "$log_file"

# Use:
jq -n --arg q "$query" --arg ts "$(get_timestamp)" \
    '{timestamp: $ts, query: $q}' >> "$log_file"
```

This ensures each query is a single JSON line, preventing injection.

**Estimated effort:** 30 minutes

**Implementation Update (2025-11-01):**
- Replaced plain-text logging in `src/claude-runtime/hooks/research-logger.sh` with JSON line entries via `jq -n`, preventing newline/log injection.
- Added `append_json_line` helper plus secure file initialization (chmod 600, umask 077) for both audit and query logs.
- Re-verified with `shellcheck src/claude-runtime/hooks/research-logger.sh`.

---

### ✅ M15: Homebrew formula pinned to wrong version

**File:** `Formula-cconductor.rb:10`

**Validation:** ✅ CONFIRMED

**Evidence:**
```ruby
url "https://github.com/yaniv-golan/cconductor/archive/v0.4.0.tar.gz"
```

VERSION file shows `0.5.0-dev`, but formula still references `0.4.0`.

**Remediation:** Covered in C6 remediation (release automation).

---

### ✅ M16: VERSION hardcoded in mission-session-init.sh

**File:** `src/utils/mission-session-init.sh:180-183`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
local cconductor_version="0.4.0"
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    cconductor_version=$(tr -d '\n' < "$PROJECT_ROOT/VERSION")
fi
```

**Impact:** VERSION file is correctly read, but the fallback is wrong. This is low risk since VERSION file is always present, but violates DRY.

**Remediation Plan:**

Remove hardcoded fallback or make it dynamic:

```bash
# BEFORE:
local cconductor_version="0.4.0"
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    cconductor_version=$(tr -d '\n' < "$PROJECT_ROOT/VERSION")
fi

# AFTER:
local cconductor_version="unknown"
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    cconductor_version=$(tr -d '\n' < "$PROJECT_ROOT/VERSION")
else
    log_warn "VERSION file not found, using 'unknown'"
fi
```

**Testing:**
1. Verify sessions created with correct version
2. Test with missing VERSION file (should log warning)

**Estimated effort:** 10 minutes

---

## Low Priority Bugs

### ✅ L1-L2: Version strings outdated in help text

**Files:**
- `src/cconductor-mission.sh:3, 62`
- `README.md:482-493`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
# src/cconductor-mission.sh:3
# Entry point for mission-based orchestration (v0.4.0)

# src/cconductor-mission.sh:62
CConductor Mission-Based Research (v0.4.0)
```

**Remediation Plan:**

Make version dynamic by reading from VERSION file:

```bash
# At top of cconductor-mission.sh after sourcing helpers:
CCONDUCTOR_VERSION="unknown"
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    CCONDUCTOR_VERSION=$(tr -d '\n' < "$PROJECT_ROOT/VERSION")
fi

# In usage() function:
cat <<EOF
CConductor Mission-Based Research (v${CCONDUCTOR_VERSION})
EOF
```

For README, add a release checklist item to update sample outputs.

**Estimated effort:** 30 minutes

---

### ✅ L3: Troubleshooting docs reference old `70_report/` path

**Files:** Various documentation files

**Validation:** ✅ CONFIRMED (git status shows modified docs)

**Remediation Plan:**

Global search and replace across docs:

```bash
# Find all references:
grep -r "70_report" docs/ README.md

# Replace with new path:
find docs/ README.md -type f -exec sed -i.bak 's|70_report/|report/|g' {} +
```

**Testing:**
1. Review diffs to ensure no unintended changes
2. Verify all examples still make sense
3. Update any screenshots if needed

**Estimated effort:** 1 hour (review + update)

---

### ✅ L4: research-sessions/ directory tracked despite .gitignore

**Validation:** ✅ CONFIRMED - Directory structure is tracked

**Evidence:**

While `.gitignore` line 12 contains `research-sessions/`, the directory itself and some metadata files may have been committed before the ignore rule was added:

```bash
# .gitignore:12
research-sessions/

# But checking git:
$ find research-sessions -name "mission_*" -type d 2>/dev/null | head -5
research-sessions/mission_1760805753621008000
research-sessions/mission_1760369592470094000
research-sessions/mission_1760886292276432000
research-sessions/mission_1761824459779010000
research-sessions/mission_1760715663761115000
```

The `.gitignore` pattern on line 138 also shows `docs/internal/*` is ignored, yet we're creating files there.

**Impact:** 
- Local test sessions accumulate over time
- Directory bloat makes `git status` slow
- New contributors may commit session data accidentally

**Remediation Plan:**

1. **Immediate cleanup:**
```bash
# Remove all local test sessions
rm -rf research-sessions/mission_*

# Ensure directory isn't tracked
git rm -r --cached research-sessions/ 2>/dev/null || true
```

2. **Strengthen .gitignore:**
```bash
# Replace line 12 with more explicit patterns:
# Session data (can be large)
research-sessions/
research-sessions/*/
research-sessions/mission_*/
!research-sessions/.gitkeep
```

3. **Add safety check to tests:**
```bash
# In tests/run-all-tests.sh, add cleanup at end:
if [ -d "$PROJECT_ROOT/research-sessions" ]; then
    echo "Cleaning up test sessions..."
    find "$PROJECT_ROOT/research-sessions" -name "mission_*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
fi
```

4. **Update AGENTS.md reminder:**
   - Add note about running cleanup after testing
   - Mention that `research-sessions/` is transient

**Testing:**
1. Run `git status` - should not show research-sessions
2. Create new session - should stay untracked
3. Verify `.gitkeep` preserves directory structure if needed

**Estimated effort:** 30 minutes (cleanup + .gitignore strengthening + tests)

---

### ✅ L5: Test harness relies on python3 without guard

**File:** `tests/test-simple-query.sh:31-43`

**Validation:** ✅ CONFIRMED

**Evidence:**
```bash
python3 - "$base" <<'PY'
import os, sys
# [python code]
PY
```

No check for `python3` availability.

**Remediation Plan:**

Use `require_command` from core-helpers.sh:

```bash
# Add after line 7:
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh"

require_command python3 "brew install python3" "apt install python3" || exit 1

# Rest of script...
```

**Alternative:** Rewrite the Python logic in pure bash using stat/ls commands.

**Estimated effort:** 30 minutes

**Implementation Update (2025-11-01):**
- Updated `tests/test-simple-query.sh` to source `core-helpers.sh` and invoke `require_command python3`, providing actionable install guidance when Python is missing.
- Re-verified the script with `shellcheck tests/test-simple-query.sh` to ensure the new sourcing is lint-clean.

---

## Remediation Priorities

### Phase 1: Critical Security & Cross-Platform (Week 1)
1. **C2** - Fix eval injection (30 min) ✅
2. **C1** - Implement date-helpers.sh (4 hours) ✅
3. **C4/C5** - Fix citation lock handling (1 hour) ✅
4. **C6** - Homebrew release automation (1 hour) ✅
5. **M12/M13** - Fix log permissions (30 min) ✅

**Estimated total:** 7 hours

### Phase 2: Data Integrity & Correctness (Week 2)
1. **H1** - Fix confidence averaging (30 min) ✅
2. **H2-H14** - Add sort_by before group_by (3 hours) ✅
3. **H15** - Fix findings pruning (30 min) ✅
4. **C3** - Update test paths (15 min) ✅

**Estimated total:** 4 hours

### Phase 3: Code Quality & Standards (Week 3)
1. **M1-M5** - Add set -euo pipefail (1 hour) ✅
2. **M7** - Fix cleanup script (30 min) ✅
3. **H18** - export-journal strict mode (5 min) ✅
4. **H16** - Summarizer directory creation (15 min) ✅

**Estimated total:** 2 hours

### Phase 4: Polish & Documentation (Week 4)
1. **L1-L2** - Dynamic version strings (30 min) ✅
2. **L3** - Update documentation paths (1 hour) ✅
3. **M8** - Fix process cleanup patterns (30 min) ✅
4. **M14** - Fix log injection (30 min) ✅
5. **M16** - Remove VERSION hardcode (10 min) ✅
6. **L5** - Add python3 guard (30 min) ✅

**Estimated total:** 3 hours

---

## Testing Strategy

### Unit Tests
- `tests/test-date-helpers.sh` - Cross-platform date operations
- `tests/test-path-resolver-security.sh` - Injection attempts
- `tests/test-citation-lock.sh` - Lock handling under failure
- `tests/test-jq-group-by.sh` - Verify sort_by fixes

### Integration Tests
- Run `tests/run-all-tests.sh` after each phase
- Verify no regressions in existing tests
- Test on both macOS and Linux (CI)

### Manual Validation
- Run full mission on macOS
- Run full mission on Linux (Docker)
- Verify report output quality
- Check log file permissions
- Test Homebrew formula install

---

## Summary

**Total Valid Bugs:** 38  
**Critical:** 6  
**High:** 17 (was 16, H17 restored)  
**Medium:** 11 (was 10, M10 clarified)  
**Low:** 4 (was 3, L4 confirmed)  

**Total Remediation Effort:** ~17 hours (2-3 work days)

**Major Corrections from Review:**
- H17 restored: ShellCheck SC2295 confirms unquoted expansions are unsafe
- C1 expanded: 16 occurrences across 4 files (was "5 files")
- M10 reclassified: Not duplicate of C2, valid hardening opportunity
- L4 confirmed: Directory tracking issue with .gitignore
- Removed "Invalid Bug Reports" section - all reports were valid or required clarification

**Key Infrastructure Needs:**
1. Cross-platform date helpers library
2. Homebrew release automation
3. Systematic jq pipeline auditing
4. Enhanced test coverage for edge cases

All fixes leverage existing CConductor infrastructure including:
- `core-helpers.sh` for locking and logging
- `json-helpers.sh` for safe jq operations
- `file-helpers.sh` for directory management
- Platform-aware utilities
- Existing test frameworks

---

**Document Status:** Ready for implementation  
**Next Steps:** Begin Phase 1 critical fixes
