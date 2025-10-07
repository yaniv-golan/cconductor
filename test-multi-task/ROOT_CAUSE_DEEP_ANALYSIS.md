# Deep Root Cause Analysis: Session 1759822984807227000

**Analysis Date**: 2025-10-07
**Method**: Systematic examination of session data files and code

---

## EXECUTIVE SUMMARY

**Primary Root Cause #1**: Agent exceeded Claude API's 32K output token limit
**Primary Root Cause #2**: `timeout` command not available on macOS (exit 127)
**Secondary Issue**: web-researcher lacks multi-task instructions

---

## ROOT CAUSE #1: Output Token Limit Exceeded

### Evidence

**File**: `research-sessions/session_1759822984807227000/raw/academic-researcher-output.json`

```json
{
  "type": "result",
  "subtype": "success",
  "is_error": true,
  "duration_ms": 1008623,
  "num_turns": 129,
  "result": "API Error: Claude's response exceeded the 32000 output token maximum. To configure this behavior, set the CLAUDE_CODE_MAX_OUTPUT_TOKENS environment variable.",
  "output_tokens": 37725,  ← EXCEEDED 32,000 LIMIT
  "total_cost_usd": 3.34
}
```

### Analysis

1. **Agent received**: 15 research tasks in array format
2. **Agent processed**: Attempted to generate comprehensive findings for all 15 tasks
3. **Agent output**: Generated 37,725 output tokens (18% over limit)
4. **Claude API**: Rejected the response due to token limit
5. **Result**: Error message instead of research findings

### Cost Impact

- **Total cost**: $3.34 USD for failed attempt
- **Tokens used**: 
  - Input: 301,208 tokens (with cache)
  - Output: 37,725 tokens (exceeded limit)
- **Turns**: 129 turns before hitting limit

### Why This Happened

The multi-task prompt instructed the agent to process ALL 15 tasks and return an array of findings. The agent complied and generated comprehensive findings for each task, but the total output exceeded Claude's 32K token limit.

**Each task generated approximately**: 37,725 / 15 = 2,515 tokens per task

With 15 tasks: 15 × 2,515 = 37,725 tokens total

---

## ROOT CAUSE #2: Missing `timeout` Command on macOS

### Evidence

**File**: `src/utils/session-manager.sh` line 247

```bash
if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

**System Check**:
```bash
$ which timeout
timeout not found
```

**Error in session**:
```
✗ Agent research-coordinator failed with code 127
```

Exit code 127 = "command not found"

### Analysis

1. **Iteration 1**: Coordinator started with `start_agent_session()` → Success
   - Uses `invoke-agent.sh` which does NOT use `timeout` (macOS compatible)
   
2. **Iteration 2**: Coordinator continued with `continue_agent_session()` → Failed
   - Uses `session-manager.sh` which DOES use `timeout` (not macOS compatible)
   - Shell tries to execute: `timeout 600 claude ...`
   - `timeout` command not found → exit 127

### Why This Is Inconsistent

**File**: `src/utils/invoke-agent.sh` lines 218-220 (CORRECT)

```bash
# Note: timeout command not available on macOS by default, so we run without it
# The claude CLI has its own timeout mechanisms
if echo "$task" | "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

**File**: `src/utils/session-manager.sh` line 247 (BUG)

```bash
if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

The code has a comment acknowledging the issue but only fixed it in one file!

---

## SECONDARY ISSUE: web-researcher Lacks Multi-Task Instructions

### Evidence

**Check for multi-task instructions**:
```bash
$ jq -r '.systemPrompt' .claude/agents/web-researcher.json | grep -A 10 "IMPORTANT.*array"
(no results)
```

**web-researcher output**:
```json
{
  "task_id": "t15,t16,t17,t18,t19",  ← COMMA-SEPARATED, NOT ARRAY
  "query": "Metabolic capacity mitochondrial function...",
  "status": "completed",
  "entities_discovered": [...]
}
```

### Analysis

1. **web-researcher received**: 5 tasks in array format
2. **web-researcher prompt**: No multi-task instructions
3. **web-researcher behavior**: Combined all tasks into single response
4. **Output format**: Single object with comma-separated task IDs
5. **Result**: Not parseable as array of findings

### Impact

Even if coordinator hadn't failed, the web-researcher findings would not have been correctly extracted because:
- System expects array: `[{task_id: "t15", ...}, {task_id: "t16", ...}]`
- Agent returned single object: `{task_id: "t15,t16,t17,t18,t19", ...}`

---

## CASCADING FAILURE SEQUENCE

```
Iteration 1:
  1. Planning agent generates 15 tasks → SUCCESS
  2. academic-researcher receives 15 tasks
  3. academic-researcher processes all 15 tasks
  4. academic-researcher generates 37,725 output tokens
  5. Claude API rejects: exceeds 32K limit
  6. academic-researcher-output.json contains error message
  7. invoke-agent.sh sees is_error=true → EXIT 1
  
  8. Coordinator analyzes with empty findings
  9. Coordinator generates 5 new web-researcher tasks
  10. Coordinator session saved successfully

Iteration 2:
  11. web-researcher receives 5 tasks
  12. web-researcher combines all tasks (no multi-task instructions)
  13. web-researcher completes successfully → 27,934 char output
  
  14. System tries to continue coordinator session
  15. continue_agent_session() invokes: timeout 600 claude ...
  16. Shell cannot find 'timeout' command → EXIT 127
  
  17. coordinator-output-2.json is empty (1 byte)
  18. No coordinator decisions extracted
  19. jq fails: invalid JSON passed to --argjson
  20. Knowledge graph update fails
  21. No new tasks generated
  22. Termination check detects quality insufficient
  23. Research stops
```

---

## VERIFICATION OF THEORIES

### Theory 1: Output Token Limit

**Test**:
```bash
$ jq '.output_tokens' academic-researcher-output.json
37725

$ jq '.is_error' academic-researcher-output.json  
true

$ jq -r '.result' academic-researcher-output.json
"API Error: Claude's response exceeded the 32000 output token maximum..."
```

✅ **CONFIRMED**: Agent hit 32K output token limit

### Theory 2: Missing timeout Command

**Test**:
```bash
$ which timeout
timeout not found

$ grep -n "timeout.*claude" src/utils/session-manager.sh
247:    if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then

$ grep -n "timeout.*claude" src/utils/invoke-agent.sh
(no results - correctly omits timeout)
```

✅ **CONFIRMED**: session-manager.sh uses unavailable timeout command

### Theory 3: web-researcher Output Format

**Test**:
```bash
$ jq -r '.result' web-researcher-output.json | head -5
Now let me compile the comprehensive research findings into the required JSON format:

```json
{
  "task_id": "t15,t16,t17,t18,t19",
  
$ jq -r '.result' web-researcher-output.json | jq '.task_id'
"t15,t16,t17,t18,t19"
```

✅ **CONFIRMED**: web-researcher returned single object, not array

---

## SOLUTIONS REQUIRED

### Solution 1: Handle Output Token Limit

**Options**:

A. **Batch size reduction** (Immediate fix)
   - Reduce max batch size from 15 to smaller number
   - Calculate: 32,000 / 2,500 tokens per task = ~12 tasks max
   - Safer limit: 8-10 tasks per batch

B. **Set CLAUDE_CODE_MAX_OUTPUT_TOKENS** (Env var)
   - Set higher limit if needed
   - May incur additional costs
   - Check Claude API limits

C. **Progressive processing** (Better long-term)
   - Process tasks incrementally
   - Stream results back
   - Don't wait for all tasks to complete before returning

D. **Output compression** (Optimize)
   - Instruct agent to be more concise
   - Reduce redundancy in output
   - Focus on key findings only

### Solution 2: Fix timeout Command on macOS

**File**: `src/utils/session-manager.sh` line 247

**Current (BROKEN)**:
```bash
if echo "$task" | timeout "$timeout" "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

**Fixed (COPY from invoke-agent.sh)**:
```bash
# Note: timeout command not available on macOS by default, so we run without it
# The claude CLI has its own timeout mechanisms
if echo "$task" | "${claude_cmd[@]}" > "$output_file" 2>&1; then
```

**Why this works**:
- Claude CLI has built-in timeout handling
- No need for external timeout command
- Consistent with invoke-agent.sh approach

### Solution 3: Add Multi-Task Instructions to web-researcher

**File**: `src/claude-runtime/agents/web-researcher/system-prompt.md`

**Add at beginning** (same as academic-researcher):
```markdown
## Input Format

**IMPORTANT**: You will receive an **array** of research tasks in JSON format. Process **ALL tasks** and return an **array** of findings, one per task.

**Example input**:
```json
[
  {"id": "t0", "query": "...", ...},
  {"id": "t1", "query": "...", ...}
]
```

**Required output**: Array of findings with same task IDs:
```json
[
  {"task_id": "t0", ...},
  {"task_id": "t1", ...}
]
```
```

---

## ESTIMATED EFFORT

### Solution 1: Batch Size Reduction
- **Effort**: 10 minutes
- **Risk**: Low
- **Impact**: Prevents token limit errors
- **File**: Task execution logic (find where batch size is determined)

### Solution 2: Fix timeout Command  
- **Effort**: 5 minutes
- **Risk**: Very Low
- **Impact**: Fixes coordinator continuation on macOS
- **File**: `src/utils/session-manager.sh` line 247

### Solution 3: web-researcher Multi-Task Prompt
- **Effort**: 5 minutes
- **Risk**: Low
- **Impact**: Enables consistent multi-task processing
- **File**: `src/claude-runtime/agents/web-researcher/system-prompt.md`

**Total Estimated Time**: 20 minutes to fix all issues

---

## PRIORITY

1. **CRITICAL**: Fix timeout command (blocks all session continuation on macOS)
2. **HIGH**: Reduce batch size (prevents expensive token limit failures)
3. **MEDIUM**: Add web-researcher multi-task prompt (consistency)

---

## LESSONS LEARNED

1. **Inconsistent Patterns**: Same functionality (agent invocation) implemented differently in two files
   - `invoke-agent.sh` → macOS compatible (no timeout)
   - `session-manager.sh` → Linux only (uses timeout)

2. **No Token Limit Check**: System doesn't estimate output size before invoking agent
   - 15 tasks × 2,500 tokens = 37,500 tokens (predictable failure)
   - Should have batch size limits based on token estimates

3. **Incomplete Prompt Rollout**: Multi-task instructions added to academic-researcher but not web-researcher
   - Need systematic prompt updates across all agents
   - Need verification that all agents handle same input format

4. **Expensive Failures**: $3.34 spent on failed research attempt
   - Need early validation before expensive API calls
   - Consider dry-run mode or cost estimation

---

## TESTING PLAN

After fixes applied:

1. **Test coordinator continuation on macOS**
   - Start coordinator session
   - Continue coordinator session
   - Verify no exit 127

2. **Test smaller batch sizes**
   - Run with 8 tasks
   - Verify output under 32K tokens
   - Verify all findings extracted

3. **Test web-researcher multi-task**
   - Submit 3 tasks to web-researcher
   - Verify array output format
   - Verify all task IDs present

4. **Full integration test**
   - Run complete research session
   - Verify all agents succeed
   - Verify findings extracted correctly
   - Verify knowledge graph populated
