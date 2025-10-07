# Root Cause Findings Summary

## Three Critical Bugs Found

### 🔴 Bug #1: Agent Exceeds 32K Output Token Limit
**File**: Agent invocation logic  
**Impact**: $3.34 wasted, no research data collected  
**Root Cause**: 15 tasks × ~2,500 tokens/task = 37,725 tokens (exceeds 32K limit)

**Evidence**:
```json
{
  "is_error": true,
  "result": "API Error: Claude's response exceeded the 32000 output token maximum",
  "output_tokens": 37725,
  "total_cost_usd": 3.34
}
```

**Fix**: Limit batch size to 8-10 tasks maximum

---

### 🔴 Bug #2: `timeout` Command Missing on macOS (Exit 127)
**File**: `src/utils/session-manager.sh` line 247  
**Impact**: All session continuations fail on macOS  
**Root Cause**: Code uses `timeout` command which doesn't exist on macOS

**Evidence**:
```bash
$ which timeout
timeout not found

# session-manager.sh line 247:
if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

**Inconsistency**: `invoke-agent.sh` correctly handles this, but `session-manager.sh` doesn't

**Fix**: Remove `timeout` command (copy pattern from invoke-agent.sh)

---

### 🟡 Bug #3: web-researcher Lacks Multi-Task Instructions
**File**: `src/claude-runtime/agents/web-researcher/system-prompt.md`  
**Impact**: Combines multiple tasks into single response  
**Root Cause**: Prompt doesn't have multi-task instructions

**Evidence**:
```json
{
  "task_id": "t15,t16,t17,t18,t19",  ← Should be separate findings
  "entities_discovered": [...]
}
```

**Fix**: Add same multi-task instructions as academic-researcher

---

## Cascading Failure Chain

```
15 tasks → academic-researcher
   ↓
Generates 37,725 tokens (too many)
   ↓
API rejects: "exceeded 32000 token maximum"
   ↓
academic-researcher fails (exit 1)
   ↓
Coordinator analyzes failure, generates 5 new tasks
   ↓
5 tasks → web-researcher  
   ↓
web-researcher succeeds (27,934 chars)
   ↓
System tries to continue coordinator session
   ↓
Shell tries: timeout 600 claude ...
   ↓
"timeout: command not found" (exit 127)
   ↓
Coordinator fails, no output generated
   ↓
jq errors, knowledge graph update fails
   ↓
No new tasks generated
   ↓
Research terminates (incomplete)
```

---

## Quick Fixes

### Fix #1: Remove timeout (5 minutes)
```bash
# In src/utils/session-manager.sh line 247
# Change from:
if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then

# To:
if echo "$task" | "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

### Fix #2: Reduce batch size (10 minutes)
- Find max batch size configuration
- Change from unlimited/15 to max 8-10 tasks
- Prevents token limit errors

### Fix #3: Add web-researcher multi-task prompt (5 minutes)
- Copy instructions from academic-researcher system-prompt.md
- Add to beginning of web-researcher system-prompt.md

**Total time**: 20 minutes to fix all issues

---

## Cost of This Failure

- **Money**: $3.34 USD wasted on failed attempt
- **Time**: ~17 minutes of agent processing (129 turns)
- **User time**: Multiple hours debugging

---

## Why This Wasn't Caught

1. **No token limit validation**: System doesn't check if batch will exceed limits
2. **Platform assumption**: Code assumed Linux environment (timeout command)
3. **Incomplete rollout**: Multi-task prompt added to one agent but not others
4. **No integration tests on macOS**: Would have caught timeout issue immediately

---

## What Worked Correctly

✅ **Multi-task prompt (academic-researcher)**: Agent correctly processed all 15 tasks  
✅ **Termination quality check**: Correctly detected insufficient research quality  
✅ **Error handling**: System didn't crash, produced diagnostic output  
✅ **Cost tracking**: Accurately reported $3.34 cost

The agent TRIED to do the right thing (process all tasks), but hit API limits.
