# Issue Analysis: Stale System Observations on Dashboard

**Date**: 2025-10-07  
**Session**: `session_1759842915552654000`  
**Severity**: Medium (False alarm, not actual data loss)

---

## Summary

Dashboard shows "Knowledge graph completely empty" warning despite the knowledge graph being properly populated with 11 entities, 12 claims, and 9 relationships. This is a **timing/ordering issue**, not a data integration failure.

---

## Root Cause

### Timeline of Events

1. **Iteration 1 starts** (13:15:50)
2. **Coordinator receives empty knowledge graph** as input
3. **Coordinator generates system_observation**: "graph empty despite 15 completed tasks"
4. **Same coordinator output includes knowledge_graph_updates**: 11 entities, 12 claims, etc.
5. **Updates are applied** → Knowledge graph now populated
6. **System observation remains in events.jsonl** and displays on dashboard

### The Problem

**Coordinator generates system observations BEFORE its own updates are applied.**

```bash
# cconductor-adaptive.sh lines 1240-1282
observations=$(jq '.system_observations // []' "$coordinator_cleaned")
# ...logs observations to events.jsonl...

# Then AFTER logging observations:
echo "→ Updating knowledge graph..."
update_knowledge_graph "$session_dir" "$coordinator_cleaned"
```

The coordinator correctly observes "graph is empty" at the START of its analysis, then immediately fixes it by generating updates. But the observation persists on the dashboard indefinitely.

---

## Evidence

### Current Knowledge Graph State
```json
{
  "total_entities": 11,
  "total_claims": 12,
  "total_relationships": 9,
  "total_citations": 0,
  "total_gaps": 8,
  "unresolved_gaps": 8
}
```

### Coordinator's System Observation
```json
{
  "severity": "critical",
  "component": "knowledge_graph",
  "observation": "Knowledge graph completely empty (0 entities, 0 claims, 0 relationships) despite 15 completed tasks",
  "evidence": {
    "actual": "All knowledge graph arrays empty: entities=[], claims=[], relationships=[]"
  },
  "iteration_detected": 1
}
```

### Coordinator's Knowledge Graph Updates (Same Output!)
```json
{
  "entities_discovered": [
    {"name": "Mitochondrial Function", ...},
    {"name": "Polygenic Risk Scores (PRS)", ...},
    ... (11 total)
  ],
  "claims": [
    {"statement": "Mitochondrial markers distinguish SSRI responders...", ...},
    ... (12 total)
  ]
}
```

---

## Why This Happens

### Coordinator Prompt Instructions
From `research-coordinator/system-prompt.md` lines 308-337:

```markdown
## System Health Monitoring

As you analyze research progress, you may observe system-level issues...

**When to Report:**
- Knowledge graph not reflecting agent outputs (empty entities/claims 
  despite completed tasks)
```

The coordinator is **instructed** to report when the graph is empty. It does so based on its INPUT state, then generates updates to FIX the issue. This is actually correct behavior - the coordinator is self-correcting!

The problem is the dashboard doesn't distinguish between:
- ❌ "Observation: issue detected and UNRESOLVED"
- ✅ "Observation: issue detected and RESOLVED by coordinator"

---

## Impact

### User Experience
- ❌ **False alarm**: Dashboard shows critical error when everything is working
- ❌ **Confusing**: Knowledge graph is populated but dashboard says it's empty
- ❌ **Obscures real issues**: If there were actual problems, users might ignore them

### Technical Impact
- ✅ **No data loss**: Knowledge graph is correctly populated
- ✅ **No functional issues**: System is working as designed
- ✅ **Self-correcting**: Coordinator detects and fixes the issue automatically

---

## Solution Options

### Option A: Post-Update Validation ✅ RECOMMENDED
**Add a post-update validation step that clears resolved observations**

```bash
# After updating knowledge graph:
update_knowledge_graph "$session_dir" "$coordinator_cleaned"

# Re-validate observations
validate_and_filter_observations "$session_dir" "$observations"
```

**Pros**:
- Automatically clears resolved issues
- Maintains audit trail (observations logged, then marked resolved)
- No prompt changes needed
- Works for all observation types

**Cons**:
- Requires new validation logic
- Slightly more complex

---

### Option B: Move Observations to End of Coordinator Output
**Instruct coordinator to generate system_observations AFTER knowledge_graph_updates**

Change coordinator prompt order:
```markdown
1. Analyze state
2. Generate knowledge_graph_updates
3. **Then** generate system_observations (only for issues NOT resolved by your updates)
```

**Pros**:
- Simple concept
- Observations only reflect UNRESOLVED issues
- No code changes needed

**Cons**:
- Requires prompt update
- Coordinator must "remember" initial state while generating updates
- May miss transient issues that were fixed

---

### Option C: Dashboard Filtering
**Filter observations in dashboard-metrics.sh based on current state**

```bash
# Only include observation if issue still exists
if [[ "$obs_component" == "knowledge_graph" ]] && [[ "$obs_text" =~ "empty" ]]; then
    local current_entities=$(jq '.stats.total_entities' "$kg_file")
    if [[ "$current_entities" -gt 0 ]]; then
        # Skip this observation - issue resolved
        continue
    fi
fi
```

**Pros**:
- No prompt changes
- Handles all past sessions automatically
- Simple to implement

**Cons**:
- Brittle (hardcoded checks for specific observation types)
- Doesn't scale well
- Loses audit trail

---

### Option D: Add Resolution Status
**Add a `resolved_at` field to observations**

```json
{
  "severity": "critical",
  "component": "knowledge_graph",
  "observation": "Knowledge graph empty...",
  "iteration_detected": 1,
  "resolved_at": "2025-10-07T13:23:26Z",
  "resolution": "Coordinator populated graph with 11 entities, 12 claims"
}
```

**Pros**:
- Full audit trail
- Can show "resolved" badge on dashboard
- Historical analysis possible

**Cons**:
- Most complex to implement
- Requires event log updates
- Need resolution detection logic

---

## Recommended Solution

**Implement Option A: Post-Update Validation**

### Implementation Plan

1. **Create validation function** in `cconductor-adaptive.sh`:
   ```bash
   validate_observations_post_update() {
       local session_dir="$1"
       local observations="$2"
       
       # For each observation, check if issue still exists
       echo "$observations" | jq -c '.[]' | while read -r obs; do
           local component=$(echo "$obs" | jq -r '.component')
           
           case "$component" in
               knowledge_graph)
                   validate_kg_observation "$session_dir" "$obs"
                   ;;
               # Add other component types as needed
           esac
       done
   }
   ```

2. **Add KG-specific validation**:
   ```bash
   validate_kg_observation() {
       local session_dir="$1"
       local obs="$2"
       
       local observation_text=$(echo "$obs" | jq -r '.observation')
       
       # If observation mentions "empty" but KG is now populated
       if [[ "$observation_text" =~ "empty" ]]; then
           local kg_file="$session_dir/knowledge-graph.json"
           local entities=$(jq '.stats.total_entities // 0' "$kg_file")
           
           if [[ "$entities" -gt 0 ]]; then
               # Issue resolved - log resolution
               log_observation_resolved "$session_dir" "$obs" \
                   "Knowledge graph populated with $entities entities"
               return 1  # Don't display this observation
           fi
       fi
       
       return 0  # Issue still exists, display observation
   }
   ```

3. **Update dashboard metrics** to skip resolved observations:
   ```bash
   # In dashboard-metrics.sh
   observations=$(cat "$session_dir/events.jsonl" 2>/dev/null | \
       jq -s 'map(select(.type == "system_observation" and .data.resolved_at == null)) | 
              .[-20:] | reverse' 2>/dev/null || echo '[]')
   ```

### Benefits of This Approach

✅ Automatic resolution detection  
✅ Maintains full audit trail  
✅ Extensible to other observation types  
✅ No prompt changes required  
✅ Works for all future sessions  

---

## Testing Plan

1. **Create test observation** that should resolve:
   ```bash
   # Log "empty graph" observation
   # Update graph
   # Verify observation marked resolved
   ```

2. **Create test observation** that should NOT resolve:
   ```bash
   # Log "empty graph" observation
   # Don't update graph
   # Verify observation still shows
   ```

3. **Verify dashboard** doesn't show resolved observations

---

## Current Workaround

**For existing sessions with false alarms**:

1. Refresh dashboard (observations are cached)
2. Or manually check knowledge graph stats:
   ```bash
   jq '.stats' research-sessions/SESSION_DIR/knowledge-graph.json
   ```

**For new sessions**:
- Understand that "empty graph" warnings at iteration 1 are expected
- Check if observation persists after iteration 1
- If it disappears by iteration 2, it was auto-resolved

---

## Related Issues

This same timing issue could affect other observation types:
- "Task queue stuck" → might resolve when tasks complete
- "Agent failures" → might resolve when retry succeeds
- "Low confidence" → might resolve when more research added

The solution should be general enough to handle all of these.

---

## Conclusion

**Not a bug in data integration** - the knowledge graph IS being populated correctly. This is a **display/UX issue** where resolved system observations continue to show on the dashboard.

**Recommended fix**: Implement post-update validation (Option A) to automatically mark observations as resolved when the underlying issue is fixed.

**Priority**: Medium - doesn't affect functionality, but creates false alarms that undermine user confidence in the system.
