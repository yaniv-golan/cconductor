# Knowledge Graph Artifact Pattern

## Overview

The Knowledge Graph (KG) Artifact Pattern allows agents to update the knowledge graph without directly manipulating large JSON files. Instead, agents write small, structured metadata files to an `artifacts/` directory and create a lockfile signal. The orchestrator automatically detects the lockfile, validates the artifacts, and merges them into the knowledge graph.

## Rationale

**Problem**: Agents with only Read/Write tools cannot safely manipulate large, complex JSON files like `knowledge-graph.json` (often 100KB+). Directly editing such files in LLM context is:
- Error-prone (syntax errors, truncation)
- Slow (large context window usage)
- Risky (potential to corrupt the entire file)

**Solution**: The artifact pattern provides:
- **Small files**: Agents write multiple small JSON files (<64KB each)
- **Clear structure**: Each file has a specific purpose (completion, confidence, coverage, etc.)
- **Atomic merge**: Orchestrator performs safe, atomic merge with validation
- **Retry-able**: Failed merges create retry instructions for next cycle
- **Future-proof**: Any agent can adopt this pattern

## How It Works

### Agent Side (Simple)

1. **Write artifacts**: Create `artifacts/<agent-name>/` directory and write small JSON files
2. **Create lockfile**: Write empty file `<agent-name>.kg.lock` in session root
3. **Done**: Orchestrator handles the rest

### Orchestrator Side (Automatic)

1. **Detect lockfile**: After agent completes, check for `<agent-name>.kg.lock`
2. **Validate artifacts**: Check JSON syntax, file sizes, directory structure
3. **Atomic merge**: Use `jq` to merge artifacts into knowledge graph under agent's namespace
4. **Cleanup**: Remove lockfile on success, or rename to `.error` and create retry instructions on failure

## Implementation Guide

### For Agent Developers

To add KG artifact support to an agent:

#### 1. Update Agent Metadata

Edit `src/claude-runtime/agents/<agent-name>/metadata.json`:

```json
{
  "name": "my-agent",
  "produces_kg_artifacts": true,
  "artifact_files_required": [
    "completion.json",
    "my-data.json"
  ]
}
```

#### 2. Update Agent Prompt

Add to the agent's system prompt:

````markdown
## Output: Knowledge Graph Artifacts

After completing your task, write structured metadata to share with the orchestrator:

1. Create directory: `artifacts/<agent-name>/`

2. Write JSON files (keep each <64KB):
   - `completion.json` - Basic completion metadata
   - `<your-data>.json` - Your agent-specific data

3. Create signal file: `<agent-name>.kg.lock` (empty file in session root)

Example:
```json
// artifacts/my-agent/completion.json
{
  "completed_at": "2025-10-11T19:30:00Z",
  "status": "success"
}

// artifacts/my-agent/my-data.json
{
  "items_processed": 42,
  "confidence": 0.85
}
```

After writing artifacts, create the signal:
```bash
Write to: ./my-agent.kg.lock
Content: (empty file)
```
````

#### 3. Test

Run agent in mission and verify:
- Artifacts written to correct location
- Lockfile created
- Knowledge graph updated with agent's namespace
- No errors in logs

### Artifact File Structure

Each agent gets its own namespace in the knowledge graph:

```json
{
  "entities": [...],
  "claims": [...],
  "synthesis-agent": {
    "synthesized_at": "2025-10-11T19:30:00Z",
    "overall_confidence": 0.68,
    "coverage": {...}
  },
  "my-agent": {
    "completed_at": "2025-10-11T19:45:00Z",
    "items_processed": 42
  }
}
```

## File Format Specifications

### Lockfile

- **Location**: `<session-root>/<agent-name>.kg.lock`
- **Content**: Empty file (0 bytes)
- **Purpose**: Signal to orchestrator that artifacts are ready

### Artifact Files

- **Location**: `<session-root>/artifacts/<agent-name>/*.json`
- **Format**: Valid JSON (validated with `jq`)
- **Size limit**: 64KB per file
- **Naming**: Use descriptive names (completion.json, confidence-scores.json, etc.)

### Example: synthesis-agent

```
research-sessions/session_123/
├── mission-report.md
├── knowledge-graph.json
├── synthesis-agent.kg.lock          # Signal file
└── artifacts/
    └── synthesis-agent/
        ├── completion.json           # Basic metadata
        ├── confidence-scores.json    # Confidence data
        ├── coverage.json            # Coverage stats
        └── key-findings.json        # Research findings
```

## Error Handling

### Validation Failures

If artifacts fail validation (invalid JSON, too large, missing files):

1. Lockfile renamed to `<agent-name>.kg.lock.error`
2. Retry instructions written to `<agent-name>.retry-instructions.json`
3. Orchestrator logs warning
4. Mission continues (agent completed, just artifacts failed)

### Retry Instructions Format

```json
{
  "agent": "synthesis-agent",
  "error": "validation_failed",
  "timestamp": "2025-10-11T19:30:00Z",
  "instructions": [
    "The synthesis-agent produced artifacts that failed validation.",
    "Error: validation_failed",
    "The lockfile has been renamed to synthesis-agent.kg.lock.error",
    "On the next cycle, the orchestrator should:",
    "1. Review artifacts in artifacts/synthesis-agent/",
    "2. Check for JSON syntax errors or files exceeding 64KB",
    "3. Decide whether to re-invoke synthesis-agent or continue without artifacts"
  ],
  "artifact_location": "artifacts/synthesis-agent/",
  "lock_file_renamed_to": "synthesis-agent.kg.lock.error"
}
```

### Manual Recovery

To retry after fixing artifacts:

```bash
# 1. Fix the artifact files (correct JSON syntax, reduce size, etc.)
cd research-sessions/session_123/artifacts/synthesis-agent/

# 2. Validate manually
jq . completion.json  # Should parse without error

# 3. Remove .error extension from lockfile
mv ../synthesis-agent.kg.lock.error ../synthesis-agent.kg.lock

# 4. Re-run orchestrator or wait for next cycle
```

## Lock File Semantics

### States

1. **No lockfile**: Agent didn't produce KG artifacts (normal for most agents)
2. **`<agent>.kg.lock` exists**: Artifacts ready for processing
3. **`<agent>.kg.lock.error` exists**: Artifacts failed validation, needs retry
4. **Lockfile removed**: Artifacts successfully processed

### Concurrency

- Lock detection happens after agent completes (no race conditions)
- Only one agent runs at a time in current architecture
- Future: If parallel agents supported, mkdir-based locking prevents conflicts

## Implementation Details

### Merge Strategy

Artifacts are merged under the agent's namespace using shallow merge:

```bash
# Read all agent artifacts
merged=$(jq -s 'reduce .[] as $item ({}; . * $item)' artifacts/my-agent/*.json)

# Merge into KG under agent's namespace
jq --arg agent "my-agent" \
   --argjson artifacts "$merged" \
   '. + {($agent): $artifacts}' \
   knowledge-graph.json
```

### Atomic Operations

1. Merge to temporary file: `knowledge-graph.json.tmp`
2. Validate merged result with `jq`
3. Atomic move: `mv knowledge-graph.json.tmp knowledge-graph.json`
4. macOS-compatible lock: `mkdir .kg-merge.lock`

### Performance

- Validation: O(n) where n = number of artifact files (<100ms typical)
- Merge: O(1) shallow merge (<50ms typical)
- Lock acquisition: <1s typical, 30s timeout

## Benefits

### For Agents

- **Simple**: Just write small JSON files and create lockfile
- **Safe**: No risk of corrupting main knowledge graph
- **Flexible**: Write as many or few files as needed
- **Debuggable**: Each file is human-readable

### For System

- **Robust**: Failed merges don't break the session
- **Observable**: Clear audit trail of what was merged when
- **Extensible**: Easy to add more agents
- **Maintainable**: Centralized merge logic in one place

### For Users

- **Reliable**: Atomic operations prevent corruption
- **Transparent**: Artifacts are inspectable in `artifacts/` directory
- **Recoverable**: Failed merges can be retried manually

## Migration Notes

### From Direct KG Updates (v0.2.0 → v0.2.1)

**Old pattern** (synthesis-agent in v0.2.0):
```markdown
2. **Knowledge Graph Update**: `knowledge-graph.json`
   - Read existing KG from session root
   - Add entities, claims, relationships
   - Write back to same location
```

**New pattern** (v0.2.1+):
```markdown
2. **Synthesis Metadata** (in artifacts directory)
   - Write artifacts to: `artifacts/synthesis-agent/*.json`
   - Create lockfile: `synthesis-agent.kg.lock`
   - Orchestrator handles merge
```

**No backward compatibility**: v0.2.0 sessions using old pattern will complete successfully (synthesis-agent wrote KG directly), but new sessions will use artifact pattern.

## Testing

### Unit Test

```bash
# Test artifact processor directly
./src/utils/kg-artifact-processor.sh research-sessions/session_123/ synthesis-agent
```

### Integration Test

```bash
# Run mission with synthesis
./cconductor "test query" --mission academic-research

# Verify artifacts created
ls research-sessions/latest/artifacts/synthesis-agent/

# Verify KG updated
jq '.["synthesis-agent"]' research-sessions/latest/knowledge-graph.json
```

### Error Test

```bash
# Create invalid artifact
echo "invalid json" > research-sessions/session_123/artifacts/test-agent/bad.json

# Create lockfile
touch research-sessions/session_123/test-agent.kg.lock

# Run processor
./src/utils/kg-artifact-processor.sh research-sessions/session_123/

# Verify error handling
ls research-sessions/session_123/*.error
cat research-sessions/session_123/test-agent.retry-instructions.json
```

## Future Enhancements

### Potential Extensions

1. **Schema validation**: Validate artifact contents against JSON schemas
2. **Compression**: Support gzip for large artifacts
3. **Incremental updates**: Append-only artifact logs
4. **Versioning**: Track artifact format versions
5. **Rollback**: Undo artifact merges if needed

### Compatibility

The pattern is designed to support future extensions without breaking existing agents:
- Additional artifact files are optional
- Unknown fields in artifacts are preserved
- Agents can evolve their output format gradually

## References

- Implementation: `src/utils/kg-artifact-processor.sh`
- Example agent: `src/claude-runtime/agents/synthesis-agent/`
- Orchestration integration: `src/utils/mission-orchestration.sh`
- Design discussion: `/knowledge-graph-artifact-pattern.plan.md`

## Support

For questions or issues:
1. Check `<agent>.retry-instructions.json` for specific error details
2. Review artifacts in `artifacts/<agent>/` directory
3. Check orchestrator logs for merge failures
4. See troubleshooting in main documentation

