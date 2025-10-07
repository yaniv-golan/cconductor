# ROOT CAUSE FOUND: Session Used Embedded Old Prompt

## Critical Discovery

The system prompt is **embedded** into the session's agent definition at initialization time.

### Evidence

```bash
$ cat research-sessions/session_1759797219182720000/.claude/agents/academic-researcher.json
```

The `systemPrompt` field contains the **OLD PROMPT**:

```
"You are an academic research specialist in an adaptive research system..."
"## PDF-Centric Workflow"
"**CRITICAL**: Respond with ONLY the JSON object..."
```

**Missing**:
- ❌ No "Process **ALL tasks**" instruction
- ❌ No array input/output format
- ❌ No multi-task handling guidance

---

## How Prompt Loading Works

### Initialization Flow

1. Session starts
2. System copies prompt from source file → session's `.claude/agents/academic-researcher.json`
3. Agent runs with **embedded copy** (not source file)
4. Source file updated later → **doesn't affect running session**

### This Explains Everything

```
File Timestamps:
03:34:16  Session agent definition created (with OLD prompt embedded)
03:42:44  Agent ran (using embedded OLD prompt)
03:53:28  Source file updated (doesn't affect session)
```

---

## Why Agent Processed Only 1 Task

With the old prompt embedded in the session:

**Agent received**: Array of 15 tasks
**Agent saw in instructions**: No multi-task guidance
**Agent behavior**: Processed first element (default LLM behavior)
**Agent returned**: Single object with task_id="t0"

This is **correct behavior** given the prompt it actually saw.

---

## Verification

Compare prompts:

### Embedded Prompt (What Agent Saw)
```bash
$ jq -r '.systemPrompt' session/.claude/agents/academic-researcher.json | head -10
```
Starts with: "# Domain Knowledge\n\nYou have access to..."
Then: "You are an academic research specialist..."
Then: "## PDF-Centric Workflow"

**No multi-task instructions!**

### Source File (What Was Updated Later)
```bash
$ head -10 src/claude-runtime/agents/academic-researcher/system-prompt.md
```
Starts with: "You are an academic research specialist..."
Then: "## Input Format"
Then: "**IMPORTANT**: You will receive an **array** of research tasks..."

**Has multi-task instructions!**

---

## Test Plan Updated

To properly test multi-task functionality:

### Test 1: New Session with Current Prompt
Start a fresh session AFTER the prompt fix to verify:
- Session embeds NEW prompt
- Agent processes all tasks
- Returns array of findings

### Test 2: Verify Session Initialization
Check when/how prompt is copied to session directory

### Test 3: Prompt Update Strategy
Determine if/how to update prompts in running sessions

---

## Conclusion

**User was correct**: File modification times matter, not commit times.

**Analysis corrected**: Session's embedded prompt shows OLD version (no multi-task instructions).

**Root cause confirmed**: Agent ran with old prompt because prompt is embedded at session init, not loaded dynamically from source file.

**Secondary issue**: System doesn't update embedded prompts when source files change. This is likely by design (session isolation) but means testing requires new sessions.
