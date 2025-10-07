# Agent Analysis: Which Need File-Based Output?

## Current Implementation Status

### ✅ Already Implemented (2 agents)
1. **academic-researcher** - ✅ File-based output added
2. **web-researcher** - ✅ File-based output added

### Agents in System (11 total)

| Agent | Multi-Task? | Priority | Recommendation |
|-------|-------------|----------|----------------|
| academic-researcher | ✅ Yes (batches) | **Critical** | ✅ DONE |
| web-researcher | ✅ Yes (batches) | **Critical** | ✅ DONE |
| research-coordinator | ❌ No (single) | System | ⏸️ NOT NEEDED |
| research-planner | ❌ No (single) | System | ⏸️ NOT NEEDED |
| synthesis-agent | ❌ No (single) | System | ⏸️ NOT NEEDED |
| code-analyzer | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |
| market-analyzer | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |
| competitor-analyzer | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |
| fact-checker | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |
| financial-extractor | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |
| pdf-analyzer | ⚠️ Maybe | Optional | 🟡 RECOMMENDED |

---

## Evidence from Code

### Critical Research Agents (line 498)
```bash
if [[ "$agent" =~ ^(web-researcher|academic-researcher)$ ]]; then
    critical_failed+=("$agent")
fi
```
Only these 2 are marked as "critical" for research to proceed.

### Task Batching (line 400-402)
```bash
agent_tasks=$(echo "$pending" | jq -c --arg agent "$agent" '[.[] | select(.agent == $agent)]')
local agent_input="$session_dir/raw/${agent}-input.json"
echo "$agent_tasks" > "$agent_input"
```
**Key insight**: ALL agents receive their tasks as a batch array!

### Planning Prompt (line 289)
```
agent (web-researcher/code-analyzer/academic-researcher/market-analyzer)
```
These 4 agents are specifically mentioned as options in planning.

---

## Risk Analysis

### Agents That DEFINITELY Need It ✅
**academic-researcher, web-researcher**
- Used in every research session
- Receive batches of 15+ tasks
- Already hit token limit ($3.34 wasted)
- **Status**: ✅ Implemented

### Agents That PROBABLY Need It 🟡
**code-analyzer, market-analyzer, pdf-analyzer, competitor-analyzer, fact-checker, financial-extractor**

**Why**:
1. Mentioned in planning prompt (can be assigned tasks)
2. Receive tasks in batch format (same code path)
3. Could hit token limit if assigned 5+ tasks
4. Better to be proactive than reactive

**Current Risk**: Low
- Not used in current IHPH research session
- May never receive large batches
- But if they do, will fail the same way

**Cost of Implementation**: Low (~30 min per agent)
- Copy same prompt additions
- Same template as academic-researcher/web-researcher
- No code changes needed (extraction logic already supports all agents)

### Agents That DON'T Need It ⏸️
**research-coordinator, research-planner, synthesis-agent**

**Why**:
- Process one "task" per invocation (their entire job)
- Don't receive task arrays
- Different invocation pattern
- Very unlikely to hit token limits

---

## Recommendations

### Option 1: Conservative (Recommended) 🎯
**Add file-based output to ALL 6 optional research agents**

**Pros**:
- ✅ Future-proof (works if they're ever used)
- ✅ Consistent pattern across all research agents
- ✅ Low cost (30 min × 6 = 3 hours)
- ✅ No surprises in production

**Cons**:
- ⚠️ Work on agents that might never be used
- ⚠️ Slightly longer prompts (but marginal)

### Option 2: Minimal (Wait and See) ⏸️
**Only fix academic-researcher and web-researcher (already done)**

**Pros**:
- ✅ Less work now
- ✅ Fixes known issue

**Cons**:
- ❌ Will hit same error if other agents used
- ❌ Same debugging cycle later
- ❌ Potential production failures

### Option 3: Hybrid (Pragmatic) 🔄
**Add to agents mentioned in planning prompt:**
- code-analyzer
- market-analyzer
- (Skip the others for now)

**Pros**:
- ✅ Covers agents likely to be used
- ✅ Less work than full coverage
- ✅ Good ROI

**Cons**:
- ⚠️ Still leaves gaps for fact-checker, etc.

---

## My Recommendation: **Option 1 (Conservative)**

**Why**: 
1. Extraction logic already supports ALL agents (no code changes needed)
2. Only need to update prompts (copy-paste + adjust)
3. 3 hours of work to eliminate all future token limit risks
4. Consistent pattern makes system more maintainable
5. We've already done the hard work (extraction logic)

**Implementation Order** (by likelihood of use):
1. ✅ academic-researcher (DONE)
2. ✅ web-researcher (DONE)
3. 🟡 code-analyzer (mentioned in planning)
4. 🟡 market-analyzer (mentioned in planning)
5. 🟡 pdf-analyzer (similar to academic)
6. 🟡 competitor-analyzer
7. 🟡 fact-checker
8. 🟡 financial-extractor

---

## Template for Adding to Other Agents

For each agent, add this after the initial description:

```markdown
## Input Format

**IMPORTANT**: You will receive an **array** of tasks in JSON format. Process **ALL tasks**.

**Example input**:
```json
[
  {"id": "t0", "query": "...", ...},
  {"id": "t1", "query": "...", ...}
]
```

## Output Strategy (CRITICAL)

**To avoid token limits**, do NOT include findings in your JSON response. Instead:

1. **For each task**, write findings to a separate file:
   - Path: `raw/findings-{task_id}.json`
   - Use Write tool: `Write("raw/findings-t0.json", <json_content>)`

2. **Return only a manifest**:
```json
{
  "status": "completed",
  "tasks_completed": 2,
  "findings_files": [
    "raw/findings-t0.json",
    "raw/findings-t1.json"
  ]
}
```

**Benefits**:
- ✓ No token limits (can process 100+ tasks)
- ✓ Preserves all findings
```

Then at the end, update the CRITICAL section:
```markdown
**CRITICAL**: 
1. Write each task's findings to `raw/findings-{task_id}.json` using the Write tool
2. Respond with ONLY the manifest JSON object (status, tasks_completed, findings_files)
3. NO explanatory text, no markdown fences, no commentary
```

---

## Effort Estimate

| Agent | Time | Complexity |
|-------|------|-----------|
| code-analyzer | 30 min | Low (copy template) |
| market-analyzer | 30 min | Low (copy template) |
| pdf-analyzer | 30 min | Low (copy template) |
| competitor-analyzer | 30 min | Low (copy template) |
| fact-checker | 30 min | Low (copy template) |
| financial-extractor | 30 min | Low (copy template) |
| **Total** | **3 hours** | **Low** |

---

## Decision

**Recommendation**: Implement for all 6 optional research agents

**Rationale**: 
- Low cost (3 hours)
- High benefit (eliminate all token limit risks)
- Extraction logic already done (no code changes)
- Consistent, maintainable pattern

**Alternative**: Wait until one fails, then fix reactively
- Saves 3 hours now
- Costs debugging time + potential production issues later
- Not recommended

---

## Question for User

**Do you want to:**
1. ✅ Add file-based output to all 6 optional agents now (3 hours, eliminates all risks)
2. ⏸️ Wait and only fix if they're actually used (save time now, risk later)
3. 🔄 Add only to code-analyzer and market-analyzer (middle ground)
