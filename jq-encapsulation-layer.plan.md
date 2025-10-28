# jq Safety Layer & Consolidation Plan (REVISED)

## Implementation Status (2025-10-27)

### ✅ COMPLETED
- **Phase 1**: Extended `src/utils/json-helpers.sh` with all safety helpers
  - `jq_validate_json()` - validates JSON using `printf '%s'`, handles empty strings
  - `jq_escape_string()` - converts shell strings to JSON literals
  - `jq_build_argjson()` - validates JSON values and appends `--argjson` triples to a caller-supplied array (no word-splitting), logging failures via `log_system_error`
  - `jq_slurp_array()` - alias for `json_slurp_array`
  - `jq_read_object()` - reads JSON object with fallback, validates type
  - `safe_jq_from_json()` / `safe_jq_from_file()` - shared execution helpers with logging + raw/JSON modes
- **Phase 2**: Fixed quality-gate.sh line 206 with data loss tracking
  - Added validation loop for `uncategorized_samples`
  - Tracks skipped invalid JSON in `DOMAIN_UNCATEGORIZED_SKIPPED`
  - Surfaces `skipped_invalid_json` and `data_loss_warning` in summary
- **Phase 3**: Created comprehensive unit tests (updated again for new helpers)
  - `tests/test-json-helpers-jq.sh` now covers safe_jq helpers, return codes, logging fallbacks
  - All tests passing (verified error paths, logging, return codes)
- **Phase 4**: Created audit script + cleared all critical callsites
  - `scripts/audit-jq-usage.sh` - categorizes jq patterns by risk
  - **Latest Audit (0 files, 0 callsites as of 2025-10-27 09:35 UTC):**
    - Category A (--argjson without validation): **0**
    - Category B (silent errors): **0**
    - Category C (temp files without guards): **0**
    - Category D (atomic_json_update with --argjson): **0**
- **Phase 4a**: Migrated all critical silent-failure callsites
  - Hardened `src/utils/mission-orchestration.sh`, `src/utils/invoke-agent.sh`, `src/knowledge-graph.sh`, and `src/claude-runtime/hooks/quality-gate.sh`
  - Added contextual logging, source validation, and safe helper usage across 60+ callsites
  - Reran `scripts/audit-jq-usage.sh` (2025-10-27) to confirm zero critical patterns and updated counts
- **Phase 5**: Added `scripts/lint-jq-patterns.sh` and wired it into workflow to block regressions (no outstanding violations)

### 🚧 IN PROGRESS
- **Phase 6**: Documentation updates (AGENTS.md, ORCHESTRATOR_UTILITIES.md) still pending

### 📋 TODO
- **Phase 6**: Update documentation (AGENTS.md, ORCHESTRATOR_UTILITIES.md)
- **Phase 7**: Regression testing (full test suite + 5+ missions)

## Overview
Add targeted jq safety functions to existing `src/utils/json-helpers.sh` (avoiding competing abstractions), fix critical quality-gate.sh bugs with data loss tracking, establish patterns with comprehensive tests, then incrementally migrate high-risk callsites starting with silent failure hot paths. Enable enforcement only after migration completes.

## Phase 1: Consolidate Helpers into json-helpers.sh

### 1.1 Extend `src/utils/json-helpers.sh` (Not New File)
Add functions to **existing** `json-helpers.sh` to avoid duplication:

**Safe argument validation:**
- `jq_validate_json VALUE` - Returns 0 if valid JSON, 1 otherwise
  - Uses `printf '%s' "$value" | jq empty 2>/dev/null` (not echo - avoids escape sequence issues)
  - Handles multi-line JSON correctly, preserves whitespace
  
- `jq_escape_string STRING` - Escapes shell string to JSON string literal
  - Implementation: `jq -n --arg val "$string" '$val'`
  - For manual string→JSON conversions

**Explicit argument helpers (NO auto-detection):**
- `jq_build_argjson ARRAY_NAME VAR_NAME VALUE` - Validates VALUE is JSON and appends the `--argjson` triple to the provided nameref array
  - **Returns 0 on success, 1 on failure** (never exits)
  - On failure: logs via `log_system_error` (from debuggability plan) and returns non-zero
  - **Standard usage patterns:**
  
  ```bash
  # Pattern 1: Build an args array and pass to jq
  local jq_args=()
  jq_build_argjson jq_args "items" "$items_json" || return 1
  jq "${jq_args[@]}" '.items = $items' file.json

  # Pattern 2: Compose multiple argjson values
  local jq_args=()
  jq_build_argjson jq_args "field1" "$json1" || return 1
  jq_build_argjson jq_args "field2" "$json2" || return 1
  jq "${jq_args[@]}" '.field1 = $field1 | .field2 = $field2' file.json
  ```

**Safe file readers (extend existing patterns):**
- Keep `json_slurp_array` as-is for backward compat
- Add alias: `jq_slurp_array FILE [FALLBACK]` → calls `json_slurp_array` internally
- Add: `jq_read_object FILE [FALLBACK]` - Read object from file, default to `{}` if empty/missing

**Common operations:**
- Keep existing `json_array_append`, `json_set_field`, etc. - NO new duplicates

**Atomic helpers:**
- Keep `atomic_json_update` as low-level primitive in `shared-state.sh` - NO wrapper

### 1.2 Validation Strategy & Error Handling

**Validation implementation:**
```bash
jq_validate_json() {
    local value="$1"
    # Use printf to avoid echo's escape sequence interpretation
    # Handles multi-line JSON, preserves whitespace
    if printf '%s' "$value" | jq empty 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

jq_build_argjson() {
    local -n _jq_arg_array="$1"
    shift
    local var_name="$1"
    shift
    local value="$1"
    local session_dir="${CCONDUCTOR_SESSION_DIR:-}"

    if ! jq_validate_json "$value"; then
        if [[ -n "$session_dir" ]]; then
            log_system_error "$session_dir" "jq_build_argjson" \
                "Invalid JSON for --argjson '$var_name'" \
                "value: ${value:0:200}"
        else
            log_error "[jq_build_argjson] Invalid JSON for '$var_name': ${value:0:200}"
        fi
        return 1
    fi

    _jq_arg_array+=("--argjson" "$var_name" "$value")
    return 0
}
```

**Error handling leverages debuggability plan:**
- ✅ Uses `log_system_error` / `log_system_warning` (implemented in core-helpers.sh)
- ✅ Structured logging to `logs/system-errors.log` for session-scoped errors
- ✅ Self-aware log_error/log_warn fallback when no session context

### 1.3 Sourcing Strategy
- `json-helpers.sh` already sources `shared-state.sh` and `core-helpers.sh`
- Add new functions at end of file
- No circular dependencies

### 1.4 Removed Complex Features
- ❌ `run_jq` wrapper - stdout/stderr routing too complex
- ❌ Auto-detection helpers - ambiguous
- ❌ `jq_atomic_update` - atomic_json_update sufficient

## Phase 2: Fix Critical Bug with Data Loss Tracking

### 2.1 Fix quality-gate.sh Line 206 + Surface Skipped Samples

**Root cause:** `uncategorized_samples[@]` may contain raw strings, not JSON. When piped to `jq -s`, it fails.

**Fix with data loss visibility:**
```bash
# BEFORE (line 206):
DOMAIN_UNCATEGORIZED_SAMPLES_JSON=$(printf '%s\n' "${uncategorized_samples[@]}" | jq -s '.' 2>/dev/null || echo '[]')

# AFTER:
DOMAIN_UNCATEGORIZED_SKIPPED=0
if (( ${#uncategorized_samples[@]} > 0 )); then
    # Validate each sample is JSON before slurping
    local valid_samples=()
    local skipped_count=0
    for sample in "${uncategorized_samples[@]}"; do
        if jq_validate_json "$sample"; then
            valid_samples+=("$sample")
        else
            log_system_warning "$session_dir" "quality_gate_validation" \
                "Skipping invalid JSON sample" "${sample:0:100}"
            ((skipped_count++))
        fi
    done
    
    DOMAIN_UNCATEGORIZED_SKIPPED=$skipped_count
    
    if (( ${#valid_samples[@]} > 0 )); then
        local temp_samples
        temp_samples=$(create_temp_file "qg-samples")
        printf '%s\n' "${valid_samples[@]}" > "$temp_samples"
        DOMAIN_UNCATEGORIZED_SAMPLES_JSON=$(jq_slurp_array "$temp_samples" '[]')
        rm -f "$temp_samples"
    else
        DOMAIN_UNCATEGORIZED_SAMPLES_JSON='[]'
    fi
else
    DOMAIN_UNCATEGORIZED_SAMPLES_JSON='[]'
fi
```

**Surface in summary (update uncategorized_summary construction ~line 671):**
```bash
uncategorized_summary=$(jq -n \
    --argjson count "${DOMAIN_UNCATEGORIZED_COUNT:-0}" \
    --argjson total "${DOMAIN_TOTAL_SOURCES:-0}" \
    --arg pct "${DOMAIN_UNCATEGORIZED_PCT:-0}" \
    --argjson samples "$samples_json" \
    --argjson skipped "${DOMAIN_UNCATEGORIZED_SKIPPED:-0}" \
    --arg action "$action_msg" \
    --argjson alert "$threshold_flag" \
    '{
        count: $count,
        total: $total,
        percentage: ($pct | tonumber),
        samples: $samples,
        skipped_invalid_json: $skipped,
        action_required: (if ($alert == true and $count > 0) then $action else null end),
        data_loss_warning: (if $skipped > 0 then "Skipped \($skipped) invalid JSON entries; check logs/system-errors.log" else null end)
    }')
```

**Reviewers can now detect evidence loss** by checking `artifacts/quality-gate.json`:
- `uncategorized_sources.skipped_invalid_json` - count of dropped samples
- `uncategorized_sources.data_loss_warning` - human-readable alert

### 2.2 Source json-helpers.sh in quality-gate.sh
```bash
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/json-helpers.sh"
```

## Phase 3: Unit Tests Before Migration

### 3.1 Create `tests/test-json-helpers-jq.sh`

**Test specifications (must pass 100% before migration):**

```bash
#!/usr/bin/env bash
# Test suite for jq safety helpers

# Setup test session for logging
TEST_SESSION_DIR=$(mktemp -d)
mkdir -p "$TEST_SESSION_DIR/meta" "$TEST_SESSION_DIR/logs"
echo '{"session_id":"test"}' > "$TEST_SESSION_DIR/meta/session.json"
export CCONDUCTOR_SESSION_DIR="$TEST_SESSION_DIR"

test_jq_validate_json_valid() {
    # Valid JSON cases
    jq_validate_json '{"key":"value"}' || fail "Object failed"
    jq_validate_json '["item"]' || fail "Array failed"
    jq_validate_json '"string"' || fail "String failed"
    jq_validate_json '42' || fail "Number failed"
    jq_validate_json 'true' || fail "Boolean failed"
    jq_validate_json 'null' || fail "Null failed"
    
    # Multi-line JSON with whitespace
    local multiline='
    {
      "key": "value with\nnewline"
    }'
    jq_validate_json "$multiline" || fail "Multi-line failed"
}

test_jq_validate_json_invalid() {
    # Invalid JSON cases (should return non-zero)
    ! jq_validate_json 'not json' || fail "Bare string should fail"
    ! jq_validate_json '{broken' || fail "Incomplete object should fail"
    ! jq_validate_json '' || fail "Empty string should fail"
}

test_jq_build_argjson_success() {
    local jq_args=()

    jq_build_argjson jq_args "test" '{"key":"value"}' || fail "Expected zero exit code"

    [[ ${#jq_args[@]} -eq 3 && "${jq_args[0]}" == "--argjson" ]] || \
        fail "Arguments not appended as expected"

    echo '{}' | jq "${jq_args[@]}" '.field = $test' >/dev/null || \
        fail "Generated args should work with jq"
}

test_jq_build_argjson_failure() {
    local jq_args=()
    local exit_code=0

    jq_build_argjson jq_args "test" "not json" || exit_code=$?
    [[ $exit_code -ne 0 ]] || fail "Expected non-zero exit code for invalid JSON"
    [[ ${#jq_args[@]} -eq 0 ]] || fail "Array should remain unchanged on failure"

    grep -q '"operation":"jq_build_argjson"' "$TEST_SESSION_DIR/logs/system-errors.log" \
        || fail "Expected error logged to system-errors.log"
}

test_jq_escape_string() {
    local result
    
    # Test special characters
    result=$(jq_escape_string 'hello "world"')
    echo "$result" | jq empty || fail "Output not valid JSON"
    
    # Test newlines
    result=$(jq_escape_string $'line1\nline2')
    echo "$result" | jq empty || fail "Newline handling failed"
}

test_jq_slurp_array_empty() {
    local temp_file
    temp_file=$(mktemp)
    
    # Empty file
    result=$(jq_slurp_array "$temp_file" '[]')
    [[ "$result" == "[]" ]] || fail "Expected fallback for empty file"
    
    rm -f "$temp_file"
}

test_jq_read_object_missing() {
    result=$(jq_read_object "/nonexistent/file.json" '{}')
    [[ "$result" == "{}" ]] || fail "Expected fallback for missing file"
}

# Cleanup
trap "rm -rf $TEST_SESSION_DIR" EXIT
```

**All tests must:**
- Verify helpers return (not exit) on failure
- Check stderr/log output for errors
- Assert args array state for jq_build_argjson

### 3.2 Integration Test
- Run quality gate with intentionally malformed samples
- Verify `skipped_invalid_json` count in output
- Check logs/system-errors.log for warnings

## Phase 4: Incremental Migration (Reprioritized)

### 4.1 Phase 4a: Critical Silent Failures First (Category B Hot Paths)
**PULLED FORWARD - These cause real data loss:**

**Files with silent error suppression in critical paths (~15 callsites):**
1. **mission-orchestration.sh** - orchestrator decision parsing, budget checks
   - Line 379: `result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)`
   - Pattern: Replace with validation before jq, log failures
   
2. **quality-gate.sh** - summary construction, claim aggregation
   - Lines 624-643: `claim_results`, `session_checks` slurping
   - Pattern: Use `jq_slurp_array` with validation
   
3. **knowledge-graph.sh** - entity/claim integration
   - Various: `jq -c '.entities[]?' ... 2>/dev/null`
   - Pattern: Validate input file first, log on failure
   
4. **invoke-agent.sh** - agent response validation
   - Line 677: `result=$(jq -r '.result // empty' "$output_file" 2>/dev/null)`
   - Pattern: Check file exists and is valid JSON first

**Migration pattern for Category B:**
```bash
# BEFORE
result=$(jq '.field' file.json 2>/dev/null || echo "fallback")

# AFTER
local result
if [[ -f file.json ]] && jq empty file.json 2>/dev/null; then
    result=$(jq -r '.field // "fallback"' file.json)
else
    log_system_warning "$session_dir" "jq_read_failure" \
        "Invalid or missing file.json, using fallback"
    result="fallback"
fi
```

### 4.2 Phase 4b: High-Risk --argjson (Category A)
**After Category B hot paths stabilize:**

**Files with --argjson without validation (~27 callsites):**
1. `quality-gate.sh` (19 calls) - use `jq_build_argjson` pattern
2. `knowledge-graph.sh` (12 calls) - validate before --argjson
3. Others as identified

**Migration pattern:**
```bash
# BEFORE
jq --argjson items "$items_json" '.items = $items' file.json

# AFTER
local argjson_args
if argjson_args=$(jq_build_argjson "items" "$items_json"); then
    jq $argjson_args '.items = $items' file.json
else
    return 1  # Error already logged
fi
```

### 4.3 Phase 4c: Empty File Handling (Category C)
**Files with temp file jq usage (~38 callsites):**
- Replace `jq -s '.' tempfile` with `jq_slurp_array tempfile '[]'`

### 4.4 Phase 4d: Document & Remaining
- Update AGENTS.md after patterns stabilize
- Category D (atomic_json_update) - document best practices

## Phase 5: Audit Script with Noise Mitigation

### 5.1 Create `scripts/audit-jq-usage.sh`

**Detection with false positive filtering:**
```bash
#!/usr/bin/env bash
# Audit jq usage patterns

# Category A: --argjson with shell vars
rg '--argjson\s+\w+\s+"?\$' src/ \
    --context 3 \
    --json | \
jq -s 'map(select(
    # Exclude comments
    (.data.lines.text | startswith("#") | not) and
    # Exclude already-safe patterns (jq_build_argjson nearby)
    (.data.context_before // [] | map(.text) | join("") | contains("jq_build_argjson") | not)
))' 

# Category B: Silent error suppression with severity scoring
rg 'jq.*2>/dev/null.*\|\|' src/ --json | \
jq -s 'map({
    file: .data.path.text,
    line: .data.line_number,
    snippet: .data.lines.text,
    severity: (
        if (.data.path.text | test("mission-orchestration|quality-gate|knowledge-graph|invoke-agent"))
        then "critical"
        elif (.data.path.text | test("cache|dashboard"))
        then "medium"
        else "low"
        end
    )
}) | group_by(.severity)'

# Output JSON with guidance
```

**Output format:**
```json
{
  "scan_date": "2025-10-26T...",
  "by_category": {
    "A": {
      "count": 27,
      "callsites": [
        {"file": "quality-gate.sh", "line": 672, "confidence": "high"}
      ]
    },
    "B": {
      "count": 102,
      "critical": 15,
      "callsites": [
        {"file": "mission-orchestration.sh", "line": 379, "severity": "critical"}
      ]
    }
  },
  "triage_guidance": {
    "B_critical": "Fix immediately - these cause data loss",
    "A_high": "Migrate next - validation missing",
    "C": "Verify temp file handling",
    "false_positives": "Add # lint-allow: <reason> to suppress"
  }
}
```

**Manual triage:**
1. Review "critical" severity first
2. Check file at line number
3. If false positive: add `# lint-allow: <tag>`
4. Re-run after each batch

## Phase 6: Lint Rule with Exception Mechanism

### 6.1 Create `scripts/lint-jq-patterns.sh`
**Enable post-migration via `CCONDUCTOR_LINT_JQ=1`**

**Allowlist:**
- `src/utils/json-helpers.sh`, `src/shared-state.sh`
- `tests/` directory (may test failures intentionally)

**Per-line exceptions:**
```bash
# lint-allow: direct-jq reason="testing failure behavior"
result=$(jq '.field' broken.json 2>/dev/null || echo "fallback")

# lint-allow: validated-argjson reason="json validated 3 lines above"
jq --argjson items "$items_json" '.items = $items' file.json

# lint-allow: performance reason="hot path, validation too expensive"
value=$(jq -r '.field' file.json 2>/dev/null)
```

**Supported tags:**
- `direct-jq` - General exception
- `validated-argjson` - Value validated above (lint can't detect)
- `testing` - Test code
- `performance` - Hot path (rare, needs justification)

**Output:**
```
❌ jq pattern violations:

src/utils/file.sh:123: --argjson without validation
  Fix: Use jq_build_argjson or add # lint-allow: validated-argjson

Found 2 violations. See docs/ORCHESTRATOR_UTILITIES.md
```

## Phase 7: Documentation (Staged)

### 7.1 During Implementation
- Add docstrings to helpers
- Update AGENTS.md § "Coding Conventions" after Phase 4a

### 7.2 After Migration Stable
- docs/ORCHESTRATOR_UTILITIES.md - jq safety patterns
- memory-bank updates

## Phase 8: Testing & Validation

### 8.1-8.4: Same as before
- Unit tests → Integration tests → Smoke tests → Final validation

## Rollout Timeline (REVISED)

**Week 1:**
- Extend json-helpers.sh + unit tests
- Fix quality-gate.sh line 206 with data loss tracking

**Week 2:**
- Create audit script
- **Migrate Category B critical (silent failures in hot paths)** ← MOVED UP

**Week 3:**
- Migrate Category A (--argjson without validation)
- Integration tests

**Week 4:**
- Migrate Category C (temp file handling)
- Update AGENTS.md

**Week 5:**
- Migrate remaining Category B (low priority)
- Document patterns

**Week 6:**
- Final validation + lint rule

## Acceptance Criteria

- [x] json-helpers.sh extended with all helpers
- [x] `jq_build_argjson` documented with standard usage patterns
- [x] tests/test-json-helpers-jq.sh verifies error paths (return vs exit)
- [x] Quality-gate.sh tracks skipped samples in summary
- [x] jq_validate_json uses printf (not echo) for whitespace safety
- [x] Category B critical paths migrated first (data loss prevention) — confirmed via 2025-10-27 audit
- [x] Audit script filters comments/heredocs, scores by severity
- [x] Lint rule supports # lint-allow exceptions
- [ ] All tests pass, 5+ missions complete successfully

## Key Changes from Previous Version

**Clarified:**
- ✅ `jq_build_argjson` appends validated `--argjson` triples to a caller-provided array, returns 0/1, never exits
- ✅ Standard usage patterns documented with examples
- ✅ Quality gate surfaces skipped sample count in summary
- ✅ `jq_validate_json` uses `printf` not `echo` for whitespace safety
- ✅ Unit tests specify how to verify error behavior (stderr/logs/exit codes)

**Reprioritized:**
- ✅ Category B critical (silent failures) moved to Week 2 (was Week 5)
- ✅ Hot paths (orchestrator, quality gate, KG) fixed early

**Enhanced:**
- ✅ Audit script filters false positives, scores by severity
- ✅ Lint rule includes exception mechanism with tags
- ✅ Triage guidance for reviewing audit output

---

## Handoff Notes for Next Agent

### Current State
All foundation work is complete:
- ✅ Helper functions implemented in `src/utils/json-helpers.sh` (lines 277-367)
- ✅ Unit tests passing in `tests/test-json-helpers-jq.sh` (559 lines)
- ✅ Quality gate bug fixed with data loss tracking
- ✅ Latest audit (2025-10-27 09:35 UTC) reports zero remaining Category B/C/D patterns; lint script enforces guardrails

### Next Steps (Priority Order)

#### 1. Lessons Learned
- Safe helper adoption is complete across the repo; future contributors should rely on `safe_jq_from_file` / `safe_jq_from_json` and `jq_build_argjson` patterns captured in updated scripts.
- `scripts/lint-jq-patterns.sh` now blocks regressions—add `# lint-allow:` annotations only with documented justification.

#### 2. Migration Pattern Template
```bash
# BEFORE (unsafe - silently fails)
result=$(jq -r '.field // "default"' file.json 2>/dev/null || echo "fallback")

# AFTER (safe - logs failures)
local result="fallback"
if [[ -f file.json ]] && jq empty file.json 2>/dev/null; then
    result=$(jq -r '.field // "fallback"' file.json)
else
    log_system_warning "$session_dir" "jq_read_failure" \
        "Invalid or missing file.json" "field=fieldname"
fi
```

#### 3. Testing & Validation
```bash
# Run unit tests
./tests/test-json-helpers-jq.sh

# Run full test suite
./tests/run-all-tests.sh

# Spot check one mission
./cconductor "Quick test query" --mode non-interactive
```

#### 4. Documentation Updates (Phase 6)
- `AGENTS.md` - add jq discipline section
- `docs/ORCHESTRATOR_UTILITIES.md` - document safe patterns
- `memory-bank/techContext.md` - capture lessons learned

### Files to Reference
- **Helper implementations**: `src/utils/json-helpers.sh:277-367`
- **Test examples**: `tests/test-json-helpers-jq.sh`
- **Already-fixed example**: `src/claude-runtime/hooks/quality-gate.sh:206-247` (uncategorized samples fix)
- **Audit results**: Run `scripts/audit-jq-usage.sh audit-results.json` and review JSON

### Known Issues / Gotchas
1. **Session context**: `log_system_warning` requires `$session_dir` - check it's available in scope
2. **Fallback values**: Preserve exact semantics - if original used `"0"`, use `"0"` not `0`
3. **Array vs object**: Some patterns expect arrays, others objects - verify with `jq type`
4. **Incremental migration**: Work file-by-file, re-run the audit after each sweep to confirm reductions

### Success Criteria
- [x] Medium-severity cache readers (pdf-cache, web-search-cache) migrated to safe helpers
- [x] Category B callsites reduced to ≤20 with zero medium severity remaining (post-audit)
- [x] Lint rule (`scripts/lint-jq-patterns.sh`) prevents regressions
- [ ] Zero new regressions in `./tests/run-all-tests.sh`
- [ ] At least 3 full missions complete successfully
- [ ] `logs/system-errors.log` shows warnings (not silent failures) for invalid JSON scenarios encountered during testing
- [x] Re-run audit: `scripts/audit-jq-usage.sh` reflects updated counts and documents Category D decisions

### Estimated Effort
- Documentation & knowledge share: ~1 hour
- Remaining validation (full test suite re-run + mission spot-checks): ~3 hours

Lint rule is active and the codebase is fully migrated; only docs and extended validation remain.
