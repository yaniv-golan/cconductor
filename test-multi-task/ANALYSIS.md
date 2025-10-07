# Deep Analysis: Issue 1 - Agent Only Processed 1 of 15 Tasks

## Timeline Discovery

**Critical Finding**: Session ran with **OLD PROMPT** that had no multi-task instructions!

### Timeline Evidence

```bash
# Session created (UTC)
$ jq -r '.created_at' session.json
2025-10-07T00:33:40Z
# = 2025-10-07 03:33:40 local time (assuming UTC+3)

# Prompt updated (local time)
$ git log -1 --format="%ci" -- system-prompt.md
2025-10-07 03:53:06 +0300

# Session ran 20 minutes BEFORE the prompt fix!
```

### Commit History

```
83a9b8286  2025-10-07 03:53:06  "Fix multi-task findings extraction bug"  ← NEW PROMPT
7a966fbe4  2025-10-05 01:51:52  "fix: add explicit loop prevention"      ← OLD PROMPT
```

---

## Old Prompt (What Agent Actually Saw)

```markdown
You are an academic research specialist in an adaptive research system. 
Your findings contribute to a shared knowledge graph.

## PDF-Centric Workflow

**Step 1: Search for Academic Papers**
[...standard instructions for finding papers...]
```

**No mention of**:
- Processing multiple tasks
- Returning an array
- Expected input format

---

## New Prompt (What We Thought Agent Saw)

```markdown
**IMPORTANT**: You will receive an **array** of research tasks in JSON format. 
Process **ALL tasks** and return an **array** of findings, one per task.

**Example input**:
```json
[
  {"id": "t0", "query": "...", ...},
  {"id": "t1", "query": "...", ...},
  {"id": "t2", "query": "...", ...}
]
```

**Required output**: Array of findings with same task IDs:
```json
[
  {"task_id": "t0", "query": "...", "entities_discovered": [...], ...},
  {"task_id": "t1", "query": "...", "entities_discovered": [...], ...},
  {"task_id": "t2", "query": "...", "entities_discovered": [...], ...}
]
```
```

---

## Agent Behavior Analysis

### Input Received (15 tasks)
```bash
$ jq 'length' academic-researcher-input.json
15

$ jq '.[0:3] | map(.id)' academic-researcher-input.json
["t0", "t1", "t2"]
```

### Output Produced (1 task)
```bash
$ jq -r '.result' academic-researcher-output.json | grep '"task_id"'
  "task_id": "t0",
```

### Agent's Own Words
```
"Excellent! Now I have comprehensive data. Let me compile this into 
the final JSON output as required. I have extensive evidence comparing 
metabolic/mitochondrial markers to polygenic risk scores."
```

Agent mentions:
- ✓ "the final JSON output" (singular)
- ✓ Evidence for metabolic vs genetic markers (first task only)
- ✗ No mention of other 14 tasks
- ✗ No indication it saw an array

---

## Root Cause Analysis

### How Agent Likely Interpreted Input

Without multi-task instructions, agent saw JSON array and likely:

1. **Parsed the JSON** - Saw array of 15 task objects
2. **Applied default behavior** - Process first element
3. **Ignored rest** - No instruction to handle multiple tasks
4. **Returned single object** - Default output format

This is standard LLM behavior when:
- Given array input without explicit "process all" instructions
- No example showing array output
- No loop or iteration guidance

### Why This Wasn't Caught

1. **Task queue marked all tasks "completed"** - Status tracking bug
2. **All tasks pointed to same output file** - File management bug
3. **No validation of findings count** - Missing assertion
4. **Coordinator only saw 1 finding** - But didn't validate count

---

## Evidence From Agent Output

The agent's output structure confirms it expected to process ONE task:

```json
{
  "task_id": "t0",   ← Single task, not array
  "query": "...",    ← Query from first task only
  "status": "completed",
  "entities_discovered": [...],
  ...
  "access_issues": [...]  ← Comprehensive, suggests agent worked hard on THIS ONE task
}
```

The output is:
- ✓ Well-structured single object
- ✓ Comprehensive findings for t0
- ✓ Detailed metadata
- ✗ Not an array
- ✗ No other task_ids

---

## Secondary Issues Discovered

### Issue A: Task Queue Status Tracking
All 15 tasks marked "completed" despite only 1 processed.

```bash
$ jq '.stats' task-queue.json
{"total_tasks": 15, "completed": 15, "in_progress": 0, "pending": 0}

$ jq '.tasks[0:3] | map(.status)' task-queue.json
["completed", "completed", "completed"]
```

**Where**: Likely in task queue update logic after agent returns

### Issue B: Findings File Assignment
All tasks point to same findings file, should be unique per task or batch.

```bash
$ jq '.tasks[0:3] | map(.findings_file) | unique | length' task-queue.json
1  # Should be 15 or at least distinguish which tasks share results
```

### Issue C: No Findings Count Validation
System didn't validate that findings count matched task count.

```bash
# Coordinator received 1 finding for 15 tasks - no warning!
$ jq '.new_findings | length' coordinator-input-1.json
1
```

---

## Test Plan

### Test 1: Verify New Prompt Works
**Input**: 3 simple tasks (created in `test-multi-task/input.json`)
**Expected**: Agent returns array with 3 findings

### Test 2: Verify Findings Extraction
**Input**: Multi-finding agent output (simulated)
**Expected**: All findings extracted and passed to coordinator

### Test 3: Verify Task Status Logic
**Input**: Task batch with partial results
**Expected**: Only tasks with findings marked "completed"

### Test 4: Verify Termination Logic
**Input**: Low confidence (0.45) + pending tasks = 0
**Expected**: System detects quality issue, doesn't terminate

---

## Conclusion

**Root Cause**: Session ran with OLD PROMPT lacking multi-task instructions.

**Why Agent Processed Only 1 Task**: 
- Received array of 15 tasks
- No instructions to process all
- Applied default LLM behavior: process first element
- Returned single object as expected for single-task processing

**Secondary Issues**:
- Task queue incorrectly marked all tasks "completed"
- No validation that findings count matches task count
- Termination logic ignored research quality metrics

**User's Assessment**: ✓ Fixes were applied, but session ran BEFORE fixes committed!
