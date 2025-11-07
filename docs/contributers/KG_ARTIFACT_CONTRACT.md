# Knowledge Graph Artifact Contract

This document defines the contract that agents must follow when producing knowledge graph (KG) artifacts.

## Overview

Agents that produce KG artifacts (claims, entities, relationships) must follow a specific pattern to ensure the orchestrator can discover and process their outputs.

## Contract Requirements

### 1. Artifact Location

Agents MUST write JSON artifacts to:
```
artifacts/<agent-name>/*.json
```

For example:
- `artifacts/domain-heuristics/domain-heuristics.json`
- `artifacts/quality-remediator/quality-remediation-*.json`
- `artifacts/synthesis-agent/completion.json`

### 2. Lock File Location

Agents MUST create a lock file in the **SESSION ROOT** (not in `artifacts/` or `work/`):

```
<agent-name>.kg.lock
```

**Correct Examples:**
- `domain-heuristics.kg.lock` (in session root)
- `quality-remediator.kg.lock` (in session root)
- `synthesis-agent.kg.lock` (in session root)

**Incorrect Examples:**
- `artifacts/domain-heuristics/domain-heuristics.kg.lock` ❌
- `work/quality-remediator/quality-remediator.kg.lock` ❌

### 3. Lock File Purpose

The lock file serves as a signal to the orchestrator that:
1. The agent has completed writing KG artifacts
2. The artifacts are ready for processing
3. The orchestrator should invoke `kg-artifact-processor` to merge artifacts into the knowledge graph

### 4. Processing Flow

1. Agent writes JSON artifacts to `artifacts/<agent-name>/`
2. Agent creates `<agent-name>.kg.lock` in session root
3. Orchestrator's `process_agent_kg_artifacts` function detects the lock file
4. Orchestrator invokes `kg-artifact-processor` to merge artifacts into `knowledge/knowledge-graph.json`
5. Lock file is processed and artifacts are integrated

## Validation

The orchestrator validates lock file locations:

- If a lock file is found in `artifacts/<agent>/` instead of session root, a warning is logged
- Lock files in incorrect locations are ignored
- This helps identify misconfigured agents during development

## Agent Implementation Checklist

When implementing a new agent that produces KG artifacts:

- [ ] Write JSON artifacts to `artifacts/<agent-name>/*.json`
- [ ] Create `<agent-name>.kg.lock` in session root (not in artifacts/)
- [ ] Document the artifact structure in agent's system prompt
- [ ] Test that `process_agent_kg_artifacts` detects and processes the lock file
- [ ] Verify artifacts are merged into knowledge graph correctly

## Examples

### Domain Heuristics Agent

```bash
# Write artifacts
Write artifacts/domain-heuristics/domain-heuristics.json
Write artifacts/domain-heuristics/output.md

# Create lock file in session root
touch domain-heuristics.kg.lock
```

### Quality Remediator Agent

```bash
# Write artifacts
Write artifacts/quality-remediator/quality-remediation-<slug>.json
Write artifacts/quality-remediator/output.md

# Create lock file in session root
touch quality-remediator.kg.lock
```

## Related Documentation

- `docs/contributers/ARGUMENT_AGENT_CONTRACT.md` - Contract for argument event protocol
- `src/utils/kg-artifact-processor.sh` - Implementation of artifact processing
- `src/utils/mission-orchestration.sh` - `process_agent_kg_artifacts` function

