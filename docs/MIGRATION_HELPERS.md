# Helper Function Migration Guide

This guide helps you migrate existing scripts to use the new centralized helper functions.

## Why Migrate?

- **Code Reduction**: Eliminate hundreds of lines of duplicate code
- **Consistency**: Unified timestamp formats, error messages, and patterns
- **Reliability**: Tested, peer-reviewed implementations
- **Maintainability**: Fix bugs once, benefit everywhere
- **Discoverability**: Find helpers easily instead of reinventing wheels

## Quick Migration Checklist

- [ ] Add helper sources at top of script
- [ ] Replace timestamp calls with `get_timestamp()` / `get_epoch()`
- [ ] Replace dependency checks with `require_command()`
- [ ] Replace error messages with `error_*()` or `log_error()`
- [ ] Replace JSON validation with `is_valid_json()`
- [ ] Replace locking patterns with `atomic_json_update()` or `with_lock()`
- [ ] Test your changes
- [ ] Run shellcheck

## Common Migration Patterns

### 1. Source Helpers (Required First Step)

**Before**:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**After**:
```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source core helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"
```

**For Hook Scripts** (need graceful degradation):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Source with fallback (hooks must never fail)
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%S.%6NZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    log_error() { echo "Error: $*" >&2; }
}
```

---

### 2. Timestamps

**Before**:
```bash
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
start=$(date +%s)
```

**After**:
```bash
timestamp=$(get_timestamp)
start=$(get_epoch)
```

**Benefits**: Cross-platform, microsecond precision when available, consistent format.

---

### 3. Dependency Checks

**Before**:
```bash
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    echo "Install with: brew install jq or apt install jq" >&2
    return 1
fi
```

**After**:
```bash
require_command "jq" "jq" "brew install jq or apt install jq"
```

**For Silent Checks**:
```bash
if ! require_command "dialog" "" "" "silent"; then
    # Fallback behavior
fi
```

**Benefits**: Consistent error messages, installation hints, optional silent mode.

---

### 4. Error Messages

**Before**:
```bash
echo "Error: Configuration file not found: $config_file" >&2
return 1
```

**After**:
```bash
error_missing_file "$config_file" "Configuration file not found"
return 1
```

**Other Error Patterns**:
```bash
# Generic error
log_error "Failed to process request"

# Missing dependency
error_dependency_missing "jq" "jq" "brew install jq"

# Invalid argument
error_invalid_argument "timeout" "$timeout" "positive integer"

# Network failure
error_network_failure "API request" "https://api.example.com"

# Permission denied
error_permission_denied "/var/log/app.log" "Run with sudo"

# Rate limit
error_rate_limit "Claude API" "60 seconds"
```

**Benefits**: Consistent formatting, actionable guidance, easier to grep logs.

---

### 5. Warnings

**Before**:
```bash
echo "Warning: Cache is disabled" >&2
```

**After**:
```bash
log_warn "Cache is disabled"
```

---

### 6. JSON Validation

**Before**:
```bash
if ! echo "$json" | jq '.' >/dev/null 2>&1; then
    echo "Error: Invalid JSON" >&2
    return 1
fi
```

**After**:
```bash
if ! is_valid_json "$json"; then
    log_error "Invalid JSON"
    return 1
fi
```

---

### 7. File Validation

**Before**:
```bash
if [ ! -f "$file" ] || [ ! -r "$file" ]; then
    echo "Error: File not found or not readable: $file" >&2
    return 1
fi
```

**After**:
```bash
if ! is_valid_file "$file"; then
    error_missing_file "$file" "File required"
    return 1
fi
```

---

### 8. Directory Creation

**Before**:
```bash
if [ ! -d "$dir" ]; then
    mkdir -p "$dir" || {
        echo "Error: Failed to create directory: $dir" >&2
        return 1
    }
fi
```

**After**:
```bash
ensure_dir "$dir" || return 1
```

---

### 9. Atomic JSON Updates

**Before**:
```bash
# Unsafe - race condition!
content=$(cat "$file")
updated=$(echo "$content" | jq '.counter += 1')
echo "$updated" > "$file"
```

**After**:
```bash
atomic_json_update "$file" '.counter += 1'
```

**Complex Updates**:
```bash
# Add item to array
atomic_json_update "list.json" '.items += [{"name": "'"$name"'"}]'

# Update nested field
atomic_json_update "config.json" '.settings.timeout = 30'

# Conditional update
atomic_json_update "state.json" 'if .status == "pending" then .status = "active" else . end'
```

---

### 10. File Locking

**Before**:
```bash
(
    flock -w 10 200 || exit 1
    # Critical section
    echo "data" >> file.txt
) 200>/var/lock/myapp.lock
```

**After**:
```bash
append_data() {
    echo "data" >> file.txt
}

with_lock "/var/lock/myapp.lock" append_data
```

---

### 11. Conditional Helper Usage

For scripts that might run before helpers are available:

**Pattern**:
```bash
if command -v log_error &>/dev/null; then
    log_error "Something failed"
else
    echo "Error: Something failed" >&2
fi
```

---

## Full Migration Example

### Before

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi

# Main function
process_data() {
    local input="$1"
    
    # Validate JSON
    if ! echo "$input" | jq '.' >/dev/null 2>&1; then
        echo "Error: Invalid JSON input" >&2
        return 1
    fi
    
    # Create output dir
    local output_dir="$SCRIPT_DIR/output"
    if [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir" || {
            echo "Error: Failed to create output directory" >&2
            return 1
        }
    fi
    
    # Add timestamp
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local output=$(echo "$input" | jq --arg ts "$timestamp" '. + {timestamp: $ts}')
    
    # Write result
    local output_file="$output_dir/result.json"
    echo "$output" > "$output_file"
    
    echo "Success: Data processed at $timestamp"
}

process_data "$1"
```

### After

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source helpers
# shellcheck disable=SC1091
source "$SCRIPT_DIR/core-helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/error-messages.sh"

# Check dependencies
require_command "jq" "jq" "brew install jq or apt install jq"

# Main function
process_data() {
    local input="$1"
    
    # Validate JSON
    if ! is_valid_json "$input"; then
        log_error "Invalid JSON input"
        return 1
    fi
    
    # Create output dir
    local output_dir="$SCRIPT_DIR/output"
    ensure_dir "$output_dir" || return 1
    
    # Add timestamp
    local timestamp=$(get_timestamp)
    local output=$(echo "$input" | jq --arg ts "$timestamp" '. + {timestamp: $ts}')
    
    # Write result
    local output_file="$output_dir/result.json"
    safe_write_file "$output_file" "$output"
    
    log_info "Data processed at $timestamp"
}

process_data "$1"
```

**Changes Made**:
1. ✅ Added helper sources
2. ✅ Replaced `command -v` with `require_command()`
3. ✅ Replaced manual JSON validation with `is_valid_json()`
4. ✅ Replaced `mkdir -p` with `ensure_dir()`
5. ✅ Replaced `date -u` with `get_timestamp()`
6. ✅ Replaced direct write with `safe_write_file()`
7. ✅ Replaced `echo "Error:"` with `log_error()`
8. ✅ Replaced `echo "Success:"` with `log_info()`

**Lines Saved**: 12 lines (28 → 16)

---

## Migration Strategy

### Recommended Order

1. **Start with high-traffic utilities** that are called frequently
2. **Then update hooks** (with graceful fallbacks)
3. **Finally update one-off scripts** and tests

### Testing After Migration

```bash
# 1. Run shellcheck
shellcheck src/utils/my-script.sh

# 2. Run unit tests (if available)
./tests/test-my-script.sh

# 3. Integration test
./cconductor --mission my-test-mission
```

### Rollback Plan

If migration causes issues:
1. Git revert is easy - all changes are in one commit per file
2. Old patterns still work - helpers are additive
3. Fallbacks ensure hooks never break execution

---

## Common Pitfalls

### ❌ Forgetting to Source Helpers

```bash
# This will fail!
timestamp=$(get_timestamp)  # get_timestamp: command not found
```

**Fix**: Always source helpers at the top.

### ❌ Using Absolute Paths

```bash
# Don't do this
source "/Users/alice/cconductor/src/utils/core-helpers.sh"
```

**Fix**: Use relative paths from `$SCRIPT_DIR` or `$PROJECT_ROOT`.

### ❌ Breaking Hooks

```bash
# Don't do this in hooks
source "$PROJECT_ROOT/src/utils/core-helpers.sh"  # Can fail in unusual setups
```

**Fix**: Always provide fallbacks in hooks:
```bash
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
}
```

### ❌ Overusing Helpers

Not everything needs to be a helper. Use helpers for:
- ✅ Code that appears in 3+ places
- ✅ Code that needs consistency (timestamps, errors)
- ✅ Code that's tricky to get right (locking, JSON updates)

Don't use helpers for:
- ❌ Script-specific logic
- ❌ One-off operations
- ❌ Trivial operations that are clearer inline

---

## Helper Function Cheat Sheet

| Old Pattern | New Helper | Module |
|-------------|------------|--------|
| `date -u +"%Y-%m-%dT%H:%M:%SZ"` | `get_timestamp` | core-helpers |
| `date +%s` | `get_epoch` | core-helpers |
| `command -v jq` | `require_command "jq"` | core-helpers |
| `echo "Error:" >&2` | `log_error` | core-helpers |
| `echo "Warning:" >&2` | `log_warn` | core-helpers |
| `jq '.' file.json` (validation) | `is_valid_json "$(cat file.json)"` | core-helpers |
| `[ -f "$file" ]` | `is_valid_file "$file"` | core-helpers |
| `mkdir -p "$dir"` | `ensure_dir "$dir"` | core-helpers |
| `flock ... { ... }` | `with_lock lock_file func` | shared-state |
| Manual JSON update | `atomic_json_update file expr` | shared-state |
| `mktemp -d` | `create_temp_dir` | file-helpers |
| `echo "$content" > "$file"` | `safe_write_file "$file" "$content"` | file-helpers |

---

## Getting Help

- **Reference**: [HELPER_FUNCTIONS.md](HELPER_FUNCTIONS.md) - Full API documentation
- **Examples**: Look at migrated files in `src/utils/` and `src/claude-runtime/hooks/`
- **Questions**: Open an issue with the `helper-migration` label

---

## Measuring Success

After migration, check:

```bash
# Count helper usage
grep -r "get_timestamp\|require_command\|log_error" src/ | wc -l

# Count old patterns (should decrease)
grep -r "date -u +\|command -v jq\|echo \"Error:" src/ | wc -l

# Run full test suite
./tests/run-all-tests.sh
```

---

**Last Updated**: 2025-10-22  
**Version**: 0.2.0

