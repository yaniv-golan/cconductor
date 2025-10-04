# Critical Bug: Knowledge Graph Not Populating

## Root Cause

**Structure Mismatch** between coordinator output and kg_bulk_update expectations.

### What kg_bulk_update Expects
```json
{
  "entities_discovered": [...],
  "claims": [...],
  "relationships_discovered": [...]
}
```

### What Coordinator Actually Returns
```json
{
  "iteration": 1,
  "analysis": "...",
  "knowledge_graph_updates": {
    "entities_discovered": [...],
    "claims": [...],
    "relationships_discovered": [...]
  },
  "new_tasks": [...],
  "recommendations": [...]
}
```

## The Bug in kg_bulk_update

Line 616 in `src/knowledge-graph.sh`:
```bash
($new_data.entities_discovered // [])
```

Should be:
```bash
($new_data.knowledge_graph_updates.entities_discovered // [])
```

Same issue for:
- `.entities_discovered` → needs `.knowledge_graph_updates.entities_discovered`
- `.claims` → needs `.knowledge_graph_updates.claims`
- `.relationships_discovered` → needs `.knowledge_graph_updates.relationships_discovered`
- `.gaps_detected` → needs `.knowledge_graph_updates.gaps_detected`
- `.contradictions_detected` → needs `.knowledge_graph_updates.contradictions_detected`
- `.confidence_scores` → needs `.knowledge_graph_updates.confidence_scores`
- `.coverage` → needs `.knowledge_graph_updates.coverage`

## Impact

Knowledge graph remains at 0 entities/claims despite coordinator finding 23 entities and 20 claims.

## Evidence

Session: `session_1759618545415080000`
- Coordinator ran successfully (iteration 2)
- coordinator-cleaned-1.json has 23 entities, 20 claims
- knowledge-graph.json has 0 entities, 0 claims
- Manual jq test confirms entities CAN be added
- No errors in events log
- kg_bulk_update silently fails because jq paths return empty arrays

## Fix Required

Update all jq path references in `kg_bulk_update()` to include `.knowledge_graph_updates.` prefix.

