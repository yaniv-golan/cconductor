# Helper Functions Reference

This document provides a comprehensive reference for all centralized helper functions in cconductor.

## Table of Contents

1. [Core Helpers](#core-helpers) (`src/utils/core-helpers.sh`)
2. [Error Messages](#error-messages) (`src/utils/error-messages.sh`)
3. [Validation](#validation) (`src/utils/validation.sh`)
4. [JSON Helpers](#json-helpers) (`src/utils/json-helpers.sh`)
5. [File Helpers](#file-helpers) (`src/utils/file-helpers.sh`)
6. [Shared State](#shared-state) (`src/utils/shared-state.sh`)

---

## Core Helpers

**Location**: `src/utils/core-helpers.sh`

### Dependency Checking

#### `require_command()`

Checks if a required command is available, with optional error handling and suggestions.

**Signature**:
```bash
require_command <command> [package_name] [install_hint] [mode]
```

**Parameters**:
- `command`: Command to check for
- `package_name`: (Optional) Package name for error message
- `install_hint`: (Optional) Installation instructions
- `mode`: (Optional) `"silent"` to suppress errors

**Returns**: 0 if command exists, 1 otherwise

**Example**:
```bash
require_command "jq" "jq" "brew install jq or apt install jq"
require_command "dialog" "" "" "silent"  # No error output
```

---

### Timestamps

#### `get_timestamp()`

Returns ISO 8601 timestamp with microsecond precision (when available).

**Signature**:
```bash
get_timestamp
```

**Returns**: ISO 8601 timestamp (e.g., `2025-10-22T15:30:45.123456Z` or `2025-10-22T15:30:45Z`)

**Example**:
```bash
timestamp=$(get_timestamp)
echo "Event occurred at: $timestamp"
```

#### `get_epoch()`

Returns current Unix epoch time (seconds since 1970-01-01).

**Signature**:
```bash
get_epoch
```

**Returns**: Unix timestamp (e.g., `1729606245`)

**Example**:
```bash
start_time=$(get_epoch)
# ... do work ...
elapsed=$(($(get_epoch) - start_time))
echo "Elapsed: ${elapsed}s"
```

---

### Locking

#### `acquire_simple_lock()`

Acquires a simple file lock using mkdir (atomic, cross-platform).

**Signature**:
```bash
acquire_simple_lock <lockfile> [timeout_seconds]
```

**Parameters**:
- `lockfile`: Path to lock file
- `timeout_seconds`: (Optional) Max wait time (default: 30)

**Returns**: 0 on success, 1 on timeout

**Example**:
```bash
if acquire_simple_lock "/tmp/myapp.lock" 10; then
    # Critical section
    release_simple_lock "/tmp/myapp.lock"
fi
```

#### `release_simple_lock()`

Releases a simple file lock.

**Signature**:
```bash
release_simple_lock <lockfile>
```

**Parameters**:
- `lockfile`: Path to lock file

**Example**:
```bash
release_simple_lock "/tmp/myapp.lock"
```

---

### Path Utilities

#### `ensure_dir()`

Creates a directory if it doesn't exist, with error handling.

**Signature**:
```bash
ensure_dir <directory>
```

**Parameters**:
- `directory`: Path to create

**Returns**: 0 on success, 1 on failure

**Example**:
```bash
ensure_dir "$PROJECT_ROOT/cache"
ensure_dir "$HOME/.local/share/cconductor"
```

#### `safe_cd()`

Changes directory with validation and error handling.

**Signature**:
```bash
safe_cd <directory>
```

**Parameters**:
- `directory`: Target directory

**Returns**: 0 on success, 1 on failure

**Example**:
```bash
if safe_cd "$PROJECT_ROOT"; then
    # Working in project root
fi
```

---

### Validation

#### `is_valid_json()`

Validates that input is valid JSON.

**Signature**:
```bash
is_valid_json <json_string>
```

**Parameters**:
- `json_string`: String to validate

**Returns**: 0 if valid JSON, 1 otherwise

**Example**:
```bash
if is_valid_json "$response"; then
    echo "$response" | jq '.field'
else
    echo "Invalid JSON response" >&2
fi
```

#### `is_valid_file()`

Checks if a file exists and is readable.

**Signature**:
```bash
is_valid_file <filepath>
```

**Parameters**:
- `filepath`: Path to check

**Returns**: 0 if valid file, 1 otherwise

**Example**:
```bash
if is_valid_file "$config_file"; then
    source "$config_file"
fi
```

---

### Logging

#### `log_error()`

Logs error message to stderr.

**Signature**:
```bash
log_error <message>
```

**Parameters**:
- `message`: Error message

**Example**:
```bash
log_error "Failed to connect to database"
```

#### `log_warn()`

Logs warning message to stderr.

**Signature**:
```bash
log_warn <message>
```

**Parameters**:
- `message`: Warning message

**Example**:
```bash
log_warn "Cache is disabled, performance may be impacted"
```

#### `log_info()`

Logs informational message to stdout.

**Signature**:
```bash
log_info <message>
```

**Parameters**:
- `message`: Info message

**Example**:
```bash
log_info "Processing 15 tasks"
```

---

## Error Messages

**Location**: `src/utils/error-messages.sh`

Provides consistent, user-friendly error messages with actionable guidance.

### `error_missing_file()`

Reports a missing file error with context.

**Signature**:
```bash
error_missing_file <filepath> [context]
```

**Parameters**:
- `filepath`: Path that was not found
- `context`: (Optional) Additional context

**Example**:
```bash
error_missing_file "$config_file" "Configuration file not found"
```

### `error_dependency_missing()`

Reports a missing dependency with installation hints.

**Signature**:
```bash
error_dependency_missing <command> [package_name] [install_hint]
```

**Parameters**:
- `command`: Missing command
- `package_name`: (Optional) Package name
- `install_hint`: (Optional) How to install

**Example**:
```bash
error_dependency_missing "jq" "jq" "brew install jq"
```

### `error_invalid_argument()`

Reports an invalid argument error.

**Signature**:
```bash
error_invalid_argument <arg_name> <value> [expected]
```

**Parameters**:
- `arg_name`: Argument name
- `value`: Invalid value
- `expected`: (Optional) What was expected

**Example**:
```bash
error_invalid_argument "timeout" "$timeout" "positive integer"
```

### `error_network_failure()`

Reports a network operation failure.

**Signature**:
```bash
error_network_failure <operation> [url]
```

**Parameters**:
- `operation`: Operation that failed
- `url`: (Optional) Target URL

**Example**:
```bash
error_network_failure "API request" "https://api.example.com"
```

### `error_permission_denied()`

Reports a permission error.

**Signature**:
```bash
error_permission_denied <resource> [hint]
```

**Parameters**:
- `resource`: Resource that was denied
- `hint`: (Optional) How to fix

**Example**:
```bash
error_permission_denied "/var/log/app.log" "Run with sudo or fix permissions"
```

### `error_rate_limit()`

Reports a rate limit error.

**Signature**:
```bash
error_rate_limit <service> [retry_after]
```

**Parameters**:
- `service`: Service that rate limited
- `retry_after`: (Optional) When to retry

**Example**:
```bash
error_rate_limit "Claude API" "60 seconds"
```

---

## Validation

**Location**: `src/utils/validation.sh`

Provides validation functions for data integrity and safety checks.

### `validate_session_id()`

Validates session ID format.

**Signature**:
```bash
validate_session_id <session_id>
```

**Returns**: 0 if valid, 1 otherwise

### `validate_json_file()`

Validates that a file contains valid JSON.

**Signature**:
```bash
validate_json_file <filepath>
```

**Returns**: 0 if valid JSON file, 1 otherwise

### `validate_timestamp()`

Validates ISO 8601 timestamp format.

**Signature**:
```bash
validate_timestamp <timestamp>
```

**Returns**: 0 if valid, 1 otherwise

### `validate_command()`

Validates that a command is safe to execute (no dangerous patterns).

**Signature**:
```bash
validate_command <command>
```

**Returns**: 0 if safe, 1 if potentially dangerous

**Example**:
```bash
if validate_command "$user_input"; then
    eval "$user_input"
fi
```

### `validate_agent_metadata()`

Validates agent metadata JSON structure.

**Signature**:
```bash
validate_agent_metadata <metadata_json>
```

**Returns**: 0 if valid metadata, 1 otherwise

---

## JSON Helpers

**Location**: `src/utils/json-helpers.sh`

Provides safe JSON operations with error handling.

### `json_get_field()`

Extracts a field from JSON with fallback.

**Signature**:
```bash
json_get_field <json> <field> [fallback]
```

**Parameters**:
- `json`: JSON string
- `field`: Field path (e.g., `.items[0].name`)
- `fallback`: (Optional) Default value if field missing

**Example**:
```bash
name=$(json_get_field "$response" ".user.name" "Unknown")
```

### `json_has_field()`

Checks if a field exists in JSON.

**Signature**:
```bash
json_has_field <json> <field>
```

**Returns**: 0 if field exists, 1 otherwise

**Example**:
```bash
if json_has_field "$response" ".error"; then
    handle_error
fi
```

### `json_merge_files()`

Merges two JSON files (second overlays first).

**Signature**:
```bash
json_merge_files <file1> <file2> <output>
```

**Example**:
```bash
json_merge_files "default.json" "user.json" "merged.json"
```

### `json_array_append()`

Appends item to JSON array in file (with locking).

**Signature**:
```bash
json_array_append <file> <new_item>
```

**Example**:
```bash
json_array_append "events.json" '{"type":"user_login","timestamp":"2025-10-22T15:30:45Z"}'
```

---

## File Helpers

**Location**: `src/utils/file-helpers.sh`

Provides safe file operations with error handling.

### `create_temp_dir()`

Creates a temporary directory with unique name.

**Signature**:
```bash
create_temp_dir [prefix]
```

**Parameters**:
- `prefix`: (Optional) Prefix for temp dir name

**Returns**: Path to created directory

**Example**:
```bash
tmpdir=$(create_temp_dir "myapp")
trap "rm -rf '$tmpdir'" EXIT
```

### `safe_write_file()`

Writes to file atomically (write to temp, then move).

**Signature**:
```bash
safe_write_file <filepath> <content>
```

**Example**:
```bash
safe_write_file "$config_file" "$new_config"
```

### `backup_file()`

Creates timestamped backup of file.

**Signature**:
```bash
backup_file <filepath>
```

**Returns**: Path to backup file

**Example**:
```bash
backup=$(backup_file "$important_file")
echo "Backup created: $backup"
```

### `file_age_seconds()`

Gets file age in seconds.

**Signature**:
```bash
file_age_seconds <filepath>
```

**Returns**: Age in seconds, or -1 if file doesn't exist

**Example**:
```bash
age=$(file_age_seconds "$cache_file")
if [[ $age -gt 3600 ]]; then
    echo "Cache is stale (> 1 hour old)"
fi
```

### `find_files_by_pattern()`

Finds files matching pattern, excluding certain directories.

**Signature**:
```bash
find_files_by_pattern <base_dir> <pattern> [exclude_pattern]
```

**Example**:
```bash
find_files_by_pattern "$PROJECT_ROOT" "*.json" "node_modules|.git"
```

---

## Shared State

**Location**: `src/utils/shared-state.sh`

Provides atomic operations for concurrent access to shared state.

### `atomic_json_update()`

Updates JSON file atomically using file locking.

**Signature**:
```bash
atomic_json_update <file> <jq_expression>
```

**Parameters**:
- `file`: JSON file to update
- `jq_expression`: jq expression to transform JSON

**Example**:
```bash
# Increment counter atomically
atomic_json_update "stats.json" '.counter += 1'

# Add item to array
atomic_json_update "list.json" '.items += [{"name": "new"}]'
```

### `with_lock()`

Executes a function with file locking.

**Signature**:
```bash
with_lock <lockfile> <function> [args...]
```

**Example**:
```bash
append_log() {
    echo "$1" >> log.txt
}

with_lock "/tmp/app.lock" append_log "New entry"
```

---

## Usage Guidelines

### Sourcing Helpers

Always source helpers at the start of your script:

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

### Hook Scripts (Graceful Degradation)

Hooks should never fail if helpers are unavailable:

```bash
# Source with fallback
# shellcheck disable=SC1091
source "$PROJECT_ROOT/src/utils/core-helpers.sh" 2>/dev/null || {
    # Minimal fallbacks
    get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
    log_error() { echo "Error: $*" >&2; }
}
```

### Error Handling Pattern

Use helpers for consistent error handling:

```bash
# Old way
if [ ! -f "$config_file" ]; then
    echo "Error: Config file not found: $config_file" >&2
    return 1
fi

# New way
if ! is_valid_file "$config_file"; then
    error_missing_file "$config_file" "Configuration file required"
    return 1
fi
```

### Conditional Usage

For scripts that may run before helpers are available:

```bash
if command -v log_error &>/dev/null; then
    log_error "Failed to process"
else
    echo "Error: Failed to process" >&2
fi
```

---

## See Also

- [CONTRIBUTING.md](../CONTRIBUTING.md) - Development guidelines
- [MIGRATION_HELPERS.md](MIGRATION_HELPERS.md) - Migration guide for existing scripts
- [HELPER_CONSOLIDATION_PROPOSAL.md](../HELPER_CONSOLIDATION_PROPOSAL.md) - Original consolidation plan

---

**Last Updated**: 2025-10-22  
**Version**: 0.2.0

