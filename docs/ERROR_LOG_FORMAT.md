# Error Log Format Reference

---

## Overview

CConductor now includes comprehensive error logging to capture issues that would otherwise be silenced. All errors and warnings are logged to `logs/system-errors.log` in each session directory.

## Log Location

```
research-sessions/mission_<timestamp>/logs/system-errors.log
```

## Log Format

The error log uses **JSONL format** (JSON Lines): one JSON object per line.

### Entry Structure

```json
{
  "timestamp": "2025-10-11T09:25:56Z",
  "severity": "error",
  "operation": "dashboard_launch",
  "message": "Dashboard viewer failed to launch",
  "context": "Exit code: 1, stderr: ..."
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `timestamp` | string | ISO 8601 timestamp (UTC) |
| `severity` | string | Either `"error"` or `"warning"` |
| `operation` | string | What operation was being attempted |
| `message` | string | Human-readable error description |
| `context` | string | Additional context (optional) |

### Severity Levels

- **error**: Critical failure that prevents an operation from completing
- **warning**: Non-fatal issue that doesn't block execution

## Common Error Patterns

### Dashboard Errors

```json
{
  "operation": "dashboard_launch",
  "message": "Dashboard viewer failed to launch",
  "severity": "error"
}
```

**Cause**: Dashboard generation or web server failed  
**Action**: Check if port 8890+ is available, verify jq is installed

```json
{
  "operation": "dashboard_source",
  "message": "Failed to source dashboard.sh",
  "severity": "error"
}
```

**Cause**: Dashboard utility script not found or has syntax errors  
**Action**: Verify `src/utils/dashboard.sh` exists and has no syntax errors

### Budget Errors

```json
{
  "operation": "budget_limit",
  "message": "Budget limit reached at iteration 3",
  "severity": "warning"
}
```

**Cause**: Session exceeded configured budget limit  
**Action**: Normal - research stops generating partial results

### Agent Invocation Errors

```json
{
  "operation": "invalid_json",
  "message": "Agent synthesis-agent returned invalid JSON",
  "severity": "error",
  "context": "Output sample: <html>Error 500..."
}
```

**Cause**: Agent returned non-JSON output (likely an error page or crash)  
**Action**: Check Claude CLI authentication, network connection

### Validation Errors

```json
{
  "operation": "invalid_json",
  "message": "Decision data is not valid JSON, wrapping as string",
  "severity": "warning"
}
```

**Cause**: Orchestrator returned malformed JSON (recoverable)  
**Action**: Usually auto-recovered, but may indicate orchestrator issues

## Viewing Error Logs

### View All Errors

```bash
# View raw log
cat research-sessions/mission_XXX/logs/system-errors.log

# View only error entries (skip comments)
grep -v '^#' research-sessions/mission_XXX/logs/system-errors.log | jq .

# Count errors by operation
grep '"severity": "error"' research-sessions/mission_XXX/logs/system-errors.log | \
    jq -r '.operation' | sort | uniq -c | sort -rn
```

### View Recent Errors

```bash
# Last 10 entries
tail -10 research-sessions/mission_XXX/logs/system-errors.log | jq .

# Errors from last hour
jq -r 'select(.timestamp > "'$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)'")' \
    research-sessions/mission_XXX/logs/system-errors.log
```

### Filter by Severity

```bash
# Errors only
grep '"severity": "error"' research-sessions/mission_XXX/logs/system-errors.log | jq .

# Warnings only
grep '"severity": "warning"' research-sessions/mission_XXX/logs/system-errors.log | jq .
```

## Integration with Dashboard

The dashboard automatically displays error/warning counts in the `system_health` section:

```json
{
  "system_health": {
    "errors": 2,
    "warnings": 1,
    "observations": [...]
  }
}
```

Errors and warnings are visible in the dashboard metrics panel.

## Debug Mode

Enable debug mode for more verbose error output:

```bash
export CCONDUCTOR_DEBUG=1
./cconductor "research question"
```

With debug mode enabled:
- All errors are printed to stderr immediately
- Timing information is included
- Function entry/exit is traced (with `set -x`)

## Error Recovery

Most errors are handled gracefully:

| Error Type | Recovery Behavior |
|------------|------------------|
| Dashboard failure | Mission continues without dashboard |
| Budget limit | Partial results generated |
| Agent JSON invalid | Mission stops, error logged |
| Validation failure | Data wrapped/sanitized, warning logged |

## Best Practices

1. **Check error log after failed missions**:
   ```bash
   grep '"severity": "error"' research-sessions/mission_XXX/logs/system-errors.log
   ```

2. **Monitor warnings during long research**:
   ```bash
   tail -f research-sessions/mission_XXX/logs/system-errors.log
   ```

3. **Use debug mode for troubleshooting**:
   ```bash
   CCONDUCTOR_DEBUG=1 ./cconductor resume session_XXX
   ```

4. **Archive error logs for debugging**:
   ```bash
   cp research-sessions/mission_XXX/logs/system-errors.log ~/error-logs/
   ```

## API for Scripts

Scripts can use error logging functions:

```bash
#!/usr/bin/env bash
source "$CCONDUCTOR_ROOT/src/utils/error-logger.sh"

# Initialize log
init_error_log "$session_dir"

# Log an error
log_error "$session_dir" "my_operation" "Something failed" "extra context"

# Log a warning
log_warning "$session_dir" "my_check" "Non-critical issue"

# Get error summary
get_error_summary "$session_dir"

# Get error counts
get_error_counts "$session_dir"

# Check if errors exist
if has_critical_errors "$session_dir"; then
    echo "Session has critical errors"
fi
```

## Troubleshooting

### Log file not created

**Symptom**: No `logs/system-errors.log` in session directory  
**Cause**: `init_error_log()` not called during session init  
**Fix**: Normal for old sessions created before error logging was introduced

### Empty log file

**Symptom**: Log exists but contains only comments  
**Cause**: No errors occurred (good!)  
**Action**: None needed

### Duplicate entries

**Symptom**: Same error logged multiple times  
**Cause**: Operation retried or called from multiple places  
**Action**: Check operation logic, may be intentional

### Log file growing large

**Symptom**: Log file > 1MB  
**Cause**: Many errors during research  
**Action**: Investigate root cause, consider stopping session

## Version History

- Initial implementation (2025-10):
  - Added `logs/system-errors.log` to session structure
  - Implemented error/warning logging
  - Integrated with dashboard metrics
  - Added debug mode support

## See Also

- [Troubleshooting Guide](TROUBLESHOOTING.md) - General troubleshooting
- [User Guide](USER_GUIDE.md) - Complete CConductor usage
- [Dashboard Guide](DASHBOARD_GUIDE.md) - Dashboard features
