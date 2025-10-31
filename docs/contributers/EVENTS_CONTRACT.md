# Event Stream Contract

## Overview

CConductor logs structured events to `session/logs/events.jsonl` for real-time monitoring, research journal generation, and dashboard display.

This document defines the event schema contract, ensuring backward compatibility and enabling extensions.

## Event Format

All events follow this base schema:

```json
{
  "timestamp": "2025-10-09T23:00:00Z",
  "type": "event_type",
  "message": "Human-readable message",
  "data": {},
  "agent": "optional-agent-name",
  "task_id": "optional-task-id",
  "artifact": "optional-artifact-path",
  "cost": 0.15,
  "duration": 45.2
}
```

### Required Fields

- **timestamp** (string, ISO8601): Event timestamp in UTC
- **type** (string): Event type identifier
- **message** (string): Human-readable description

### Optional Fields

- **data** (object): Event-specific structured data
- **agent** (string): Agent that generated the event
- **task_id** (string): Associated task identifier
- **artifact** (string): Path to related artifact
- **cost** (number): Estimated cost in USD
- **duration** (number): Duration in seconds

## Core Event Types (Preserved)

### Research Lifecycle

#### `research_started`
```json
{
  "type": "research_started",
  "message": "Research started: <question>",
  "data": {
    "question": "string",
    "session_id": "string"
  }
}
```

#### `research_completed`
```json
{
  "type": "research_completed",
  "message": "Research completed",
  "data": {
    "total_iterations": 5,
    "final_confidence": 0.87
  },
  "duration": 180.5
}
```

### Task Events

#### `task_created`
```json
{
  "type": "task_created",
  "message": "Task created: <description>",
  "task_id": "task_001",
  "data": {
    "task_description": "string",
    "priority": "high"
  }
}
```

#### `task_started`
```json
{
  "type": "task_started",
  "message": "Starting task: <description>",
  "task_id": "task_001",
  "agent": "web-researcher"
}
```

#### `task_completed`
```json
{
  "type": "task_completed",
  "message": "Task completed: <description>",
  "task_id": "task_001",
  "agent": "web-researcher",
  "duration": 45.2,
  "cost": 0.15
}
```

### Agent Events

#### `agent_invoked`
```json
{
  "type": "agent_invoked",
  "message": "Invoked <agent> for <task>",
  "agent": "academic-researcher",
  "task_id": "task_001",
  "data": {
    "tools": ["WebSearch", "Read"]
  }
}
```

#### `agent_output`
```json
{
  "type": "agent_output",
  "message": "Agent output received",
  "agent": "academic-researcher",
  "artifact": "intermediate/findings.json",
  "data": {
    "output_size": 1024
  }
}
```

### Knowledge Graph Events

#### `entity_added`
```json
{
  "type": "entity_added",
  "message": "Added entity: <name>",
  "data": {
    "entity_id": "entity_001",
    "entity_type": "organization",
    "entity_name": "OpenAI"
  }
}
```

#### `claim_added`
```json
{
  "type": "claim_added",
  "message": "Added claim: <claim>",
  "data": {
    "claim_id": "claim_001",
    "claim_text": "string",
    "confidence": 0.85,
    "cited": true
  }
}
```

#### `gap_identified`
```json
{
  "type": "gap_identified",
  "message": "Identified gap: <gap>",
  "data": {
    "gap_id": "gap_001",
    "gap_description": "string",
    "priority": 8
  }
}
```

#### `contradiction_detected`
```json
{
  "type": "contradiction_detected",
  "message": "Contradiction detected",
  "data": {
    "contradiction_id": "contradiction_001",
    "claim_a": "claim_001",
    "claim_b": "claim_003",
    "description": "string"
  }
}
```

## Mission System Event Types

### Mission Lifecycle

#### `mission_started`
```json
{
  "type": "mission_started",
  "message": "Mission started: <mission_name>",
  "data": {
    "mission_name": "market-research",
    "mission_objective": "string",
    "max_iterations": 8,
    "budget_usd": 10.0
  }
}
```

#### `mission_completed`
```json
{
  "type": "mission_completed",
  "message": "Mission completed: <mission_name>",
  "data": {
    "mission_name": "market-research",
    "success": true,
    "iterations_used": 5,
    "cost_usd": 7.50,
    "duration_minutes": 23
  },
  "duration": 1380.0
}
```

#### `mission_budget_exceeded`
```json
{
  "type": "mission_budget_exceeded",
  "message": "Mission budget exceeded",
  "data": {
    "spent_usd": 10.15,
    "limit_usd": 10.0,
    "limit_type": "budget"
  }
}
```

### Orchestrator Events

#### `orchestrator_plan`
```json
{
  "type": "orchestrator_plan",
  "message": "Orchestrator formed initial plan",
  "agent": "mission-orchestrator",
  "data": {
    "strategy": "string",
    "agents_to_invoke": ["market-analyzer", "web-researcher"],
    "critical_path": "string"
  }
}
```

#### `orchestrator_reflection`
```json
{
  "type": "orchestrator_reflection",
  "message": "Orchestrator reflection after agent invocation",
  "agent": "mission-orchestrator",
  "data": {
    "after_agent": "market-analyzer",
    "decision": "invoke next agent",
    "rationale": "string",
    "progress": 0.6
  }
}
```

#### `orchestrator_adaptation`
```json
{
  "type": "orchestrator_adaptation",
  "message": "Orchestrator adapted strategy",
  "agent": "mission-orchestrator",
  "data": {
    "change": "string",
    "reason": "string",
    "previous_plan": "string",
    "new_plan": "string"
  }
}
```

#### `agent_handoff`
```json
{
  "type": "agent_handoff",
  "message": "Agent handoff: <from> → <to>",
  "data": {
    "from_agent": "market-sizing-expert",
    "to_agent": "lool-investment-analyst",
    "handoff_id": "handoff_001",
    "artifacts": ["intermediate/market-sizing.json"],
    "task": "string"
  }
}
```

#### `early_exit`
```json
{
  "type": "early_exit",
  "message": "Mission exiting early",
  "agent": "mission-orchestrator",
  "data": {
    "reason": "string",
    "achieved_outputs": ["market_sizing_table"],
    "missing_outputs": [],
    "partial_results_useful": true
  }
}
```

### Decision Events

#### `decision_logged`
```json
{
  "type": "decision_logged",
  "message": "Decision: <type>",
  "agent": "mission-orchestrator",
  "data": {
    "decision_type": "agent_selection",
    "rationale": "string",
    "alternatives_considered": ["option_a", "option_b"],
    "expected_impact": "string"
  }
}
```

## Event Guidelines

### For Event Producers

1. **Required Fields**: Always include timestamp, type, message
2. **ISO8601 Timestamps**: Use UTC with 'Z' suffix
3. **Structured Data**: Put machine-readable data in `data` object
4. **Human Messages**: Keep `message` field readable and concise
5. **Cost Tracking**: Include `cost` for agent invocations when available
6. **Duration**: Include `duration` for operations with measurable time

### For Event Consumers

1. **Graceful Degradation**: Handle missing optional fields
2. **Type Checking**: Verify event types exist before processing
3. **Forward Compatibility**: Ignore unknown fields
4. **Backward Compatibility**: Don't break on missing v0.2 fields

## Event Stream Files

### Primary Stream
- **Path**: `session/logs/events.jsonl`
- **Format**: JSONL (one JSON object per line)
- **Rotation**: At 10MB, rotate to `events.1.jsonl`, `events.2.jsonl`, etc.
- **Consumers**: Dashboard, journal exporter, TUI

### Orchestration Log
- **Path**: `session/logs/orchestration.jsonl`
- **Format**: JSONL
- **Content**: High-level orchestrator decisions
- **Purpose**: Separate detailed orchestration reasoning from event stream

### Dashboard Metrics
- **Path**: `session/viewer/dashboard-metrics.json`
- **Format**: JSON
- **Purpose**: Aggregated metrics for dashboard display
- **Update**: Real-time as events occur

## Backward Compatibility

### Legacy Events (Preserved)
All existing event types remain unchanged. Dashboard and journal export continue working with legacy sessions.

### Mission System Events (Additive)
Event types for mission system are added incrementally. Old consumers can ignore them gracefully.

### Contract Guarantees

1. Required fields never removed
2. Field types never changed
3. New optional fields may be added
4. New event types may be added
5. Event type names never reused

## Real-Time Consumption

### Tailing Events
```bash
tail -f session/logs/events.jsonl | while read line; do
  echo "$line" | jq -r '.message'
done
```

### Dashboard Integration
```bash
# Dashboard polls logs/events.jsonl every second
# Parses new lines and updates UI
```

### Journal Export
```bash
# At mission completion, export all events to markdown
cconductor export journal <session_dir>
```

## Testing Event Contracts

```bash
# Validate event schema
cat session/logs/events.jsonl | while read line; do
  echo "$line" | jq -e '.timestamp and .type and .message' >/dev/null || \
    echo "Invalid event: $line"
done

# Count event types
cat session/logs/events.jsonl | jq -r '.type' | sort | uniq -c

# Filter by agent
cat session/logs/events.jsonl | jq 'select(.agent == "market-analyzer")'
```

## Migration Notes

### Session Compatibility
- No migration needed for session upgrades
- Old sessions remain readable
- Newer sessions may include additional event types
- Consumers should check event type before processing

### Event Schema Versioning
Events don't carry version numbers. Instead, consumers:
1. Check for presence of new fields
2. Gracefully handle missing fields
3. Use event type as primary discriminator

