# Prompt Parser

Extract the core research objective from user prompts, separating substantive research goals from presentation requirements.

## Task

The user's research prompt is saved in a file called `user-prompt.txt` in your working directory. 

Use the Read tool to read this file, then parse it to extract:

1. **Core Objective**: The research question/goal (remove format/style instructions)
2. **Output Specification**: Presentation requirements (structure, format, style) or null if none
3. **Full Prompt**: Preserve complete original request

## Output Schema

After reading the prompt file:

1. Use the **Write** tool (single call—do **not** use the Plan skill) to create `artifacts/prompt-parser/output.md` containing exactly:
   ```
   ## Objective
   <one-sentence cleaned objective>

   ## Output Specification
   <presentation instructions or "None">

   ## Original Prompt
   ```text
   <verbatim prompt>
   ```
   ```
2. Respond with ONLY valid JSON in this exact format:

```json
{
  "objective": "<clean research goal for agents>",
  "output_specification": "<format requirements or null>",
  "research_question": "<full original prompt>"
}
```

## Examples

**Example 1: Simple prompt**

File `user-prompt.txt` contains:
```
Research the effectiveness of SSRIs for depression
```

Expected output:
```json
{
  "objective": "Research the effectiveness of SSRIs for depression",
  "output_specification": null,
  "research_question": "Research the effectiveness of SSRIs for depression"
}
```

---

**Example 2: Prompt with format instructions**

File `user-prompt.txt` contains:
```
Research SSRIs for depression. Format: Classification → Evidence → Studies → Limitations
```

Expected output:
```json
{
  "objective": "Research SSRIs for depression",
  "output_specification": "Format: Classification → Evidence → Studies → Limitations",
  "research_question": "Research SSRIs for depression. Format: Classification → Evidence → Studies → Limitations"
}
```

---

**Example 3: Complex prompt with detailed format requirements**

File `user-prompt.txt` contains:
```
Analyze market trends for electric vehicles in Europe.

**Output format:**
- Executive summary (2-3 paragraphs)
- Key findings with bullet points
- Data visualization recommendations
```

Expected output:
```json
{
  "objective": "Analyze market trends for electric vehicles in Europe",
  "output_specification": "Output format: Executive summary (2-3 paragraphs), Key findings with bullet points, Data visualization recommendations",
  "research_question": "Analyze market trends for electric vehicles in Europe.\n\n**Output format:**\n- Executive summary (2-3 paragraphs)\n- Key findings with bullet points\n- Data visualization recommendations"
}
```

## Instructions

1. Read `user-prompt.txt` using the Read tool (no planning tools—go straight to the Read request).
2. Identify the core research question or goal (what needs to be researched).
3. Separate any formatting, style, or presentation instructions (how results should be presented).
4. If no format instructions exist, set `output_specification` to `null`.
5. Preserve the complete original prompt exactly in `research_question`.
6. Immediately call the Task tool with `{"command":"exit_plan_mode"}` (if it is available) to ensure planning mode is disabled, then call the Write tool with `{"path":"artifacts/prompt-parser/output.md","content":"..."}` to populate the Markdown sections described above. The Write call must succeed before you continue.
7. After the Write call completes, call ExitPlanMode if necessary, then respond with the JSON object and end the turn.
8. If any required tool call fails (Task or Write), emit a JSON error instead of completing silently (include a short message in an `"error"` field).

## CRITICAL OUTPUT REQUIREMENTS

Your ENTIRE final response must be ONLY the JSON object. Do not write:
- ❌ "Here is the JSON..."
- ❌ "I've extracted..."
- ❌ "The JSON has been generated..."
- ❌ Any explanatory text before or after the JSON

✅ START your response with `{` and END with `}`
✅ Include NOTHING except valid JSON

Example of correct full response:
```
{
  "objective": "Research the effectiveness of SSRIs",
  "output_specification": null,
  "research_question": "Research the effectiveness of SSRIs for depression"
}
```

The Markdown file is written via the Write tool; the text you return after that must be just the JSON. Never invoke the Plan tool during this task.
