# Complete Analysis: Why Agent Processed Only 1 of 15 Tasks

## Executive Summary

**Root Cause**: Session initialized with OLD prompt that lacked multi-task instructions. System prompts are **embedded** into sessions at initialization time and don't update when source files change.

**Impact**: Agent processed only first task because it had no instructions to handle multiple tasks.

**Solution**: Need new session with updated prompt to test multi-task functionality.

---

## Evidence Chain

### 1. File Modification Timestamps (Corrected)

```bash
$ stat -f "%Sm %N" -t "%Y-%m-%d %H:%M:%S" <files>

2025-10-07 03:34:16  .../academic-researcher-input.json    ← Session started
2025-10-07 03:42:44  .../academic-researcher-output.json   ← Agent completed
2025-10-07 03:46:29  .../session.json                      ← Session finalized
2025-10-07 03:53:28  .../system-prompt.md                  ← Source updated
```

**Conclusion**: Agent ran **before** source prompt was updated (03:34-03:42 vs 03:53).

### 2. Embedded Prompt in Session

```bash
$ jq -r '.systemPrompt' session/.claude/agents/academic-researcher.json | head -5

"# Domain Knowledge\n\nYou have access to..."
"You are an academic research specialist in an adaptive research system..."
"## PDF-Centric Workflow"
```

**Content**: OLD PROMPT (no multi-task instructions)

**Location**: Embedded in session's agent definition JSON

**Size**: 42,982 characters of embedded system prompt

### 3. Source Prompt (Current)

```bash
$ head -10 src/claude-runtime/agents/academic-researcher/system-prompt.md

You are an academic research specialist in an adaptive research system.

## Input Format

**IMPORTANT**: You will receive an **array** of research tasks in JSON format.
Process **ALL tasks** and return an **array** of findings, one per task.
```

**Content**: NEW PROMPT (with multi-task instructions)

**Updated**: 2025-10-07 03:53:28 (after session ran)

---

## How System Prompts Are Embedded

### Session Initialization Flow

**Source**: `src/cconductor-adaptive.sh` lines 179-189

```bash
# Copy Claude runtime context to session
cp -r "$PROJECT_ROOT/src/claude-runtime" "$session_dir/.claude"

# Build agent JSON files from source (metadata.json + system-prompt.md)
bash "$PROJECT_ROOT/src/utils/build-agents.sh" "$session_dir/.claude/agents" "$session_dir"
```

### Build Process

**Source**: `src/utils/build-agents.sh` lines 47-57

```bash
# Read base system prompt
base_prompt=$(cat "$prompt_file")  ← Reads from source file

# Inject knowledge context
enhanced_prompt=$(inject_knowledge_context "$agent_name" "$base_prompt" "$session_dir")

# Combine into agent JSON with enhanced prompt
jq --arg prompt "$enhanced_prompt" \
    '. + {systemPrompt: $prompt}' \    ← Embeds prompt into JSON
    "$metadata_file" > "$output_file"
```

### Agent Execution

**Source**: `src/utils/invoke-agent.sh` line 121

```bash
# Extract systemPrompt from agent definition
system_prompt=$(jq -r '.systemPrompt' "$agent_file" 2>/dev/null)
                                       ↑
                            Reads from session's embedded copy
```

**Key**: Agent NEVER reads from source file, only from session's embedded copy.

---

## Why Agent Processed Only 1 Task

### Agent Input (15 tasks)

```bash
$ jq 'length' academic-researcher-input.json
15

$ jq '.[0].id' academic-researcher-input.json
"t0"
```

### Agent Instructions (Old Prompt)

```
✓ "You are an academic research specialist..."
✓ "## PDF-Centric Workflow"
✓ "**Step 1: Search for Academic Papers**"
✓ "**CRITICAL**: Respond with ONLY the JSON object."

❌ NO mention of processing multiple tasks
❌ NO array input format example
❌ NO "Process **ALL tasks**" instruction
❌ NO array output format example
```

### Agent Behavior (Default LLM)

Given:
- Array input: `[task0, task1, ..., task14]`
- No multi-task instructions
- General instruction to "respond with ONLY the JSON object" (singular)

Agent applied **default LLM behavior**:
1. Parsed array structure
2. Extracted first element
3. Processed t0 thoroughly
4. Returned single JSON object

### Agent Output

```bash
$ jq -r '.result' academic-researcher-output.json | head -5

Excellent! Now I have comprehensive data. Let me compile this into 
the final JSON output as required. I have extensive evidence comparing 
metabolic/mitochondrial markers to polygenic risk scores. Let me create 
the structured output:

```json
{
  "task_id": "t0",
  ...
}
```

**Note**: Agent says "the final JSON output" (singular), consistent with old prompt.

---

## Secondary Issues Identified

### Issue A: Task Status Tracking Bug

All 15 tasks marked "completed" despite only 1 processed.

```bash
$ jq '.tasks[0:3] | map({id, status})' task-queue.json
[
  {"id": "t0", "status": "completed"},
  {"id": "t1", "status": "completed"},  ← Wrong!
  {"id": "t2", "status": "completed"}   ← Wrong!
]
```

**Location**: Likely in task queue update logic after agent returns.

**Fix needed**: Only mark tasks as "completed" if their findings appear in output.

### Issue B: No Findings Count Validation

System didn't validate that findings count matched task count.

```bash
# 15 tasks submitted
$ jq '.stats.total_tasks' task-queue.json
15

# Only 1 finding extracted
$ jq '.new_findings | length' coordinator-input-1.json
1

# No warning generated!
```

**Fix needed**: Add assertion that `findings.length >= tasks_submitted.length` or generate warning.

### Issue C: All Tasks Share Same Findings File

```bash
$ jq '.tasks[0:5] | map(.findings_file) | unique | length' task-queue.json
1
```

All 15 tasks point to same output file. System can't distinguish which findings correspond to which tasks.

**Fix needed**: Either:
- Use task_id field in findings to map back to tasks
- Use separate output files per task (less efficient)
- Validate that all submitted task_ids appear in findings array

### Issue D: Premature Termination

```bash
# Session terminated with:
$ jq -r '.confidence_scores.overall' knowledge-graph.json
0.45    ← Well below 0.85 target

$ jq '.stats.unresolved_gaps' knowledge-graph.json
4       ← Critical gaps remain

# Yet system reported:
"✓ No pending tasks remaining"
"✓ Research appears complete"
```

**Fix needed**: Termination logic should check research quality, not just task queue status.

---

## Test Plan

### Test 1: Verify New Prompt Works

**Goal**: Confirm agent now processes all tasks with updated prompt.

**Method**:
1. Start NEW session (to get updated embedded prompt)
2. Submit 3 simple tasks
3. Verify agent returns array with 3 findings

**Expected**:
```json
[
  {"task_id": "t0", ...},
  {"task_id": "t1", ...},
  {"task_id": "t2", ...}
]
```

### Test 2: Verify Session Prompt Embedding

**Goal**: Confirm new sessions get new prompt.

**Method**:
```bash
# Create new session
./cconductor --question-file test-question.md

# Check embedded prompt
jq -r '.systemPrompt' <new-session>/.claude/agents/academic-researcher.json | head -20

# Should contain:
# "**IMPORTANT**: You will receive an **array** of research tasks"
```

### Test 3: Test Multi-Task Extraction

**Goal**: Verify findings extraction handles arrays correctly.

**Method**: Simulate agent returning array of 3 findings, verify all extracted.

### Test 4: Test Secondary Issue Fixes

Once secondary issues are fixed, verify:
- Task status only marks tasks present in findings
- Warning generated if findings count < task count
- Termination checks confidence + gaps, not just pending tasks

---

## Architectural Issue: Prompt Isolation

### Design Decision

System embeds prompts into sessions at initialization for **isolation**:
- ✅ Sessions are reproducible (prompt version locked)
- ✅ Source changes don't break running sessions
- ✅ Different sessions can use different prompt versions

### Tradeoff

- ❌ Testing new prompts requires new session
- ❌ Long-running sessions won't get prompt updates
- ❌ No way to "hot-reload" prompts mid-session

### Recommendation

This is likely **correct by design**. Sessions should be immutable.

To test prompt changes:
1. Update source file
2. Start NEW session (gets updated prompt)
3. Run test
4. Commit if successful

---

## Conclusion

**User's Question**: "Why did agent process only 1 of 15 tasks?"

**Answer**: Agent ran with OLD PROMPT embedded at session init (03:34), which lacked multi-task instructions. Source prompt was updated 19 minutes later (03:53) but session continued using embedded copy.

**Agent Behavior**: Correct given the prompt it saw. Processed first element of array input with no guidance to handle multiple tasks.

**Fix Verification**: Requires NEW session to test updated prompt. Existing session will always use old embedded prompt.

**Additional Issues Found**:
- Task status tracking bug (marks all tasks completed)
- No findings count validation
- Premature termination (ignores research quality)

**Next Steps**: Run new session with updated prompt to verify multi-task functionality works correctly.
