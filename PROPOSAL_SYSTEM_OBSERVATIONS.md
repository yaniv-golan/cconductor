# Proposal: Structured System Observations Field

## Problem Statement

Agents (especially the coordinator) can detect system issues but have no proper channel to report them:

**Current Behavior:**
- Coordinator detected empty knowledge graph in iteration 2
- Violated JSON-only rule to report it: "I notice there's a critical issue..."
- This broke the extraction pipeline, preventing the fix from being applied
- Created a catch-22: agent detects problem → reports problem incorrectly → makes problem worse

**Impact:**
- Agents can't warn us about issues they observe
- Breaking format rules to communicate defeats the purpose
- We lose valuable diagnostic information
- System issues go unreported until catastrophic failure

## Proposed Solution

Add a structured `system_observations` field to coordinator output:

```json
{
  "iteration": 2,
  "analysis": "Standard analysis here...",
  
  "system_observations": [
    {
      "severity": "critical|warning|info",
      "component": "knowledge_graph|task_queue|agents|pipeline",
      "observation": "Human-readable description",
      "evidence": {
        "expected": "KG should have 50+ entities after 10 tasks",
        "actual": "KG shows 0 entities",
        "metric": "entities_count"
      },
      "suggestion": "Check kg_bulk_update integration",
      "iteration_detected": 2
    }
  ],
  
  "knowledge_graph_updates": {
    ...
  }
}
```

### Field Definitions

**severity**:
- `critical`: System malfunction, research results invalid
- `warning`: Potential issue, may affect quality
- `info`: Observation for monitoring, no action needed

**component**:
- `knowledge_graph`: Issues with KG population/integration
- `task_queue`: Task status or execution issues
- `agents`: Agent behavior or output problems
- `pipeline`: Data flow or integration issues
- `session`: Session state or continuity issues

**observation**: Clear description of what the agent observed

**evidence**: Structured data supporting the observation
- `expected`: What should happen
- `actual`: What is happening
- `metric`: Specific metric or field affected

**suggestion**: Agent's recommendation for investigation

## Benefits

### For Agents
✅ Can report issues without breaking format rules
✅ Structured field keeps them JSON-compliant
✅ Can continue task while reporting concerns
✅ Multi-issue reporting (array of observations)

### For System
✅ Parse and display observations separately
✅ Log to events.jsonl for monitoring
✅ Trigger automatic diagnostics based on severity
✅ Track issue history across iterations

### For Users
✅ See agent-detected issues in dashboard
✅ Early warning before catastrophic failure
✅ Better debugging with agent insights
✅ Transparency into system health

## Implementation Plan

### Phase 1: Add Field (Low Risk)
1. Update coordinator system prompt to include `system_observations` field
2. Make field optional (empty array if no observations)
3. Update `kg_bulk_update` to ignore this field (won't break existing logic)
4. No changes to other code yet

### Phase 2: Extract and Log
5. Extract observations after coordinator runs
6. Log to events.jsonl: `{"type": "system_observation", "data": {...}}`
7. Display in terminal with appropriate formatting (⚠️/ℹ️ symbols)

### Phase 3: Dashboard Integration
8. Add "System Health" panel to dashboard
9. Show recent observations grouped by severity
10. Color-code: red (critical), yellow (warning), blue (info)

### Phase 4: Automated Response
11. On `critical` severity, run diagnostics automatically
12. For known issues (empty KG), suggest specific commands
13. Create incident report with full context

## Example Scenarios

### Scenario 1: Empty Knowledge Graph
```json
{
  "system_observations": [
    {
      "severity": "critical",
      "component": "knowledge_graph",
      "observation": "Knowledge graph remains empty despite 10 completed tasks with rich outputs",
      "evidence": {
        "expected": "50+ entities, 60+ claims based on agent outputs",
        "actual": "0 entities, 0 claims in KG",
        "metric": "stats.total_entities"
      },
      "suggestion": "Check kg_bulk_update() integration and coordinator output structure",
      "iteration_detected": 2
    }
  ]
}
```

### Scenario 2: Agent Consistently Failing
```json
{
  "system_observations": [
    {
      "severity": "warning",
      "component": "agents",
      "observation": "academic-researcher failing consistently (3/3 tasks)",
      "evidence": {
        "expected": "Successful task completion",
        "actual": "Empty .result field, 69 turns, $1.67 cost per failure",
        "metric": "agent_failures"
      },
      "suggestion": "Check agent system prompt or tool restrictions",
      "iteration_detected": 1
    }
  ]
}
```

### Scenario 3: Low Confidence Plateau
```json
{
  "system_observations": [
    {
      "severity": "info",
      "component": "knowledge_graph",
      "observation": "Confidence plateaued at 0.72 for 3 iterations",
      "evidence": {
        "expected": "Gradual confidence increase to 0.85+",
        "actual": "Stuck at 0.72 despite new findings",
        "metric": "overall_confidence"
      },
      "suggestion": "May indicate research topic exhaustion or need for different sources",
      "iteration_detected": 4
    }
  ]
}
```

## Coordinator Prompt Addition

Add to research-coordinator system prompt:

```markdown
## System Health Monitoring

As you analyze findings, you may observe system-level issues. Report these in the `system_observations` array:

**When to Report:**
- Knowledge graph not reflecting agent outputs (empty or stale)
- Agents consistently failing or returning empty results
- Task queue anomalies (tasks stuck, duplicates)
- Confidence or coverage not improving despite work
- Session state inconsistencies

**How to Report:**
Use the structured format:
- `severity`: "critical" (blocks research), "warning" (affects quality), "info" (monitoring only)
- `component`: "knowledge_graph", "task_queue", "agents", "pipeline", "session"
- `observation`: What you observed
- `evidence`: Expected vs actual state with metrics
- `suggestion`: Your diagnostic recommendation

**Important:** Report issues objectively. Continue your analysis normally - system observations are supplementary, not your primary output.
```

## Testing Strategy

1. **Unit Test**: Verify observations field is optional and ignored by kg_bulk_update
2. **Integration Test**: Add observations manually to coordinator output, verify extraction
3. **Live Test**: Run research, check if coordinator reports known empty KG issue
4. **Dashboard Test**: Verify observations display in UI

## Risks & Mitigation

**Risk**: Agents over-report, creating noise
- **Mitigation**: Clear guidelines on severity levels, examples in prompt

**Risk**: Breaking changes to coordinator output structure
- **Mitigation**: Make field optional, backward compatible

**Risk**: Observations themselves violate JSON format
- **Mitigation**: Validate observations schema separately before adding to output

## Success Criteria

1. ✅ Coordinator can report empty KG issue without breaking pipeline
2. ✅ Observations logged to events.jsonl
3. ✅ Dashboard shows system health panel
4. ✅ No false positives in 10 test runs
5. ✅ Catches 100% of empty KG cases in testing

## Future Enhancements

- **Auto-remediation**: System automatically fixes known issues
- **Trend Analysis**: Track observation patterns over time
- **Smart Alerts**: Notify user only for new/escalating issues
- **Agent Feedback**: Use observations to improve agent prompts

## Decision

- [ ] **Approve**: Proceed with implementation
- [ ] **Modify**: Needs changes (specify below)
- [ ] **Reject**: Not worth the complexity

**Modifications needed:** ___________________________________

**Rationale:** ____________________________________________

