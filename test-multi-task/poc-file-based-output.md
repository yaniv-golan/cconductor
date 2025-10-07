# POC: File-Based Task Output Strategy

## Concept

Instead of returning all findings in JSON response (hits token limits), agent writes each task's findings to a separate file and returns only file paths.

**Current approach** (broken):
```json
{
  "result": "[{task_id: 't0', entities: [...1000 tokens...]}, {task_id: 't1', entities: [...1000 tokens...]}, ...]"
}
```
→ 15 tasks × 2,500 tokens = 37,500 tokens (exceeds 32K limit)

**Proposed approach** (scalable):
```json
{
  "result": {
    "tasks_completed": 15,
    "findings_files": [
      "raw/findings-t0.json",
      "raw/findings-t1.json",
      ...
    ]
  }
}
```
→ ~500 tokens total (fits easily)

---

## Advantages

1. ✅ **No token limits**: File paths are tiny compared to full findings
2. ✅ **Unlimited scalability**: Could handle 100+ tasks without issue  
3. ✅ **Natural separation**: One file per task = easier debugging
4. ✅ **Streaming-friendly**: Agent can write files as it completes tasks
5. ✅ **Cacheable**: Findings stored on disk, reusable across sessions

---

## Implementation Requirements

### 1. Agent Prompt Modification

Add to system prompt:

```markdown
## Output Strategy

**IMPORTANT**: Do NOT return findings in the JSON response. Instead:

1. For each task, write findings to a separate file:
   - Path: `raw/findings-{task_id}.json`
   - Format: Single finding object (not array)
   
2. Return only a manifest:
   ```json
   {
     "tasks_completed": <count>,
     "findings_files": ["raw/findings-t0.json", "raw/findings-t1.json", ...],
     "status": "completed"
   }
   ```

**Example workflow**:
- Receive: [task t0, task t1, task t2]
- Write: raw/findings-t0.json, raw/findings-t1.json, raw/findings-t2.json
- Return: {tasks_completed: 3, findings_files: [...]}

This avoids token limits while preserving all findings.
```

### 2. Extraction Logic Modification

Modify findings extraction in `src/cconductor-adaptive.sh`:

```bash
# Current (reads from .result)
parsed_json=$(echo "$result_text" | awk '...')

# Proposed (reads from files)
if jq -e '.findings_files' "$output_file" >/dev/null 2>&1; then
    # File-based output
    findings_files=$(jq -r '.findings_files[]' "$output_file")
    
    new_findings="[]"
    for finding_file in $findings_files; do
        if [ -f "$session_dir/$finding_file" ]; then
            finding=$(cat "$session_dir/$finding_file")
            new_findings=$(echo "$new_findings" | jq --argjson f "$finding" '. += [$f]')
        fi
    done
else
    # Legacy inline output (fallback)
    parsed_json=$(echo "$result_text" | awk '...')
    # ... existing logic
fi
```

### 3. Tool Access

Ensure agent has Write tool access (already configured for academic-researcher).

---

## POC Test

Let me create a proof-of-concept using the actual session data.
