# Session Resume Guide

## Overview

The CConductor research engine supports **resuming existing research sessions**. This allows you to:

- Continue research when interrupted
- Improve quality scores by running additional iterations
- Fix issues (API limits, network failures) and resume where you left off
- Build on previous research without starting from scratch

## How Sessions Work

### Session Persistence

Each research session creates a directory with complete state in your OS-appropriate data directory:

**Session locations**:

- **macOS**: `~/Library/Application Support/CConductor/research-sessions/mission_XXXXX/`
- **Linux**: `~/.local/share/cconductor/research-sessions/mission_XXXXX/`

**Session structure**:

```
mission_1760000000000000000/
├── INDEX.json                  # Session manifest (checksums, quick links)
├── README.md                   # Human-readable navigation map for the mission
├── artifacts/                  # Agent-produced files with manifest.json
├── cache/                      # Web/search cache reused within the mission
├── evidence/                   # Footnote bundles, bibliography exports, QA data
├── inputs/                     # Original prompt, attachments, supplemental files
├── argument/                   # Argument Event Graph logs, materialised graph, and quality metrics
├── knowledge/knowledge-graph.json   # Consolidated entities, claims, gaps, sources
├── library/                    # Mission-scoped Library Memory digests
├── logs/                       # Event stream, quality gate diagnostics, errors
├── meta/session.json           # Mission metadata, status, runtime versions, budget
├── report/mission-report.md    # Final mission report
├── report/research-journal.md  # Mission journal (generated via export)
├── viewer/                     # Interactive dashboard assets
└── work/                       # Agent working directories and intermediate outputs
```

### Session State

The session tracks:

- **Research question** - Original question
- **Knowledge graph** - All entities, claims, relationships, citations discovered
- **Mission profile** - Mission name, objective, configuration, and constraints
- **Progress metrics** - Iterations completed, mission status, timestamps, watchdog metrics
- **Budget tracking** - Claude usage, remaining budget, overruns (when watchdog enabled)
- **Confidence scores** - Structured confidence surface exported by the quality gate
- **Gaps & contradictions** - Knowledge graph gaps surfaced for follow-up iterations
- **Engine version** - For compatibility checking

## Using Resume

### Basic Usage

```bash
# Start new research
./cconductor "What is quantum computing?"

# Later, resume that session
./cconductor resume mission_1234567890
```

### Finding Sessions

List all available sessions:

```bash
./cconductor sessions
```

Output:

```
Available research sessions:

SESSION ID                QUESTION                                           STATUS
----------                --------                                           ------
mission_1234567890        What is quantum computing?                         active
mission_1234567891        CRISPR gene editing advances                       completed
mission_1234567892        Market size for AI coding assistants               resumed
```

Find your latest session:

```bash
./cconductor sessions latest
```

### When to Resume

**1. Low Quality Scores**

```bash
# Initial run finishes with Quality Score: 65/100
./cconductor resume mission_1234567890
# Expected: +10-20 quality points per additional iteration
```

**2. Research Interrupted**

```bash
# Ctrl+C during research, or system crash, or API limits
./cconductor resume mission_1234567890
# Picks up where it left off, completed work is preserved
```

**3. Iterative Deep Dive**

```bash
# First pass: overview (score 75)
./cconductor "quantum computing"

# Second pass: more depth (score 88)
./cconductor resume mission_XYZ

# Third pass: publication quality (score 94)
./cconductor resume mission_XYZ
```

**4. Found Gaps After Review**

```bash
# Read your report and realize more research needed
./cconductor resume mission_1234567890
# Coordinator will identify and address remaining gaps
```

## What Happens When Resuming

### Step 1: Session Validation

```bash
./cconductor resume mission_1234567890
```

The system:

1. **Locates session** - Searches your OS-appropriate sessions directory
2. **Validates structure** - Checks for required files (meta/session.json, knowledge/knowledge-graph.json)
3. **Checks compatibility** - Verifies engine version matches session version
4. **Updates metadata** - Sets `last_opened` timestamp and status to `resumed`

**To find your sessions directory**:

```bash
./src/utils/path-resolver.sh resolve session_dir
```

### Step 2: State Display

Shows current progress:

```
Current State:
  • Iteration: 3
  • Confidence: 0.75
  • Tasks: 12 completed, 5 pending
  • Entities: 45
  • Claims: 78
  • Unresolved gaps: 3
```

### Regenerating Missing Artifacts

If the session manifest flags missing Write-tool outputs while resuming:

1. Identify the failing slot via `jq '.artifact_contract' meta/session-manifest.json`.
2. Re-run the responsible agent (or craft a refinement) so it regenerates the required file—most commonly `artifacts/<agent>/output.md`.
3. After the artifact exists, validate in-place with:
   ```bash
   bash -lc 'source src/utils/artifact-manager.sh; artifact_finalize_manifest <session_dir> <agent>'
   ```
4. Resume the mission; the contract status should report `present`.

### Step 3: Resume Execution

- **If pending tasks exist** - Executes them and continues iterations
- **If no pending tasks** - Offers to run coordinator to generate new tasks
- **Continues iteration loop** - Picks up from last iteration number
- **Updates knowledge graph** - Builds on existing findings
- **Generates final report** - When termination conditions met

## Session States

Sessions track their status:

| Status | Meaning |
|--------|---------|
| `active` | Currently being researched |
| `completed` | Research finished, report generated |
| `resumed` | Was resumed from a previous run |
| `completed_no_report` | Finished but no report was generated |
| `unknown` | Status could not be determined |

## Scenarios

### Scenario 1: Continue After Interruption

```bash
# Research is running...
# User hits Ctrl+C or system crashes

$ ./cconductor sessions
SESSION ID                QUESTION                STATUS
mission_1234567890        What is Docker?         active

$ ./cconductor resume mission_1234567890
# Loads session, shows progress
# Asks if you want to continue or regenerate tasks
# Resumes from iteration 3 (if that's where it stopped)
```

### Scenario 2: Improve Quality Score

```bash
$ ./cconductor "What is quantum computing?"
# ... research completes ...
# Quality Score: 68/100 - FAIR
# 8 unresolved gaps

$ ./cconductor resume mission_1234567890
# Current State shows: Confidence: 0.68, Unresolved gaps: 8
# Runs coordinator to address gaps
# Quality Score improves to: 85/100 - VERY GOOD
```

### Scenario 3: API Rate Limit Hit

```bash
$ ./cconductor "comprehensive survey of AI safety research"
# ... makes many API calls ...
# Error: Rate limit exceeded

$ ./cconductor resume mission_1234567890
# Wait for rate limit to reset (check your API provider)
# Resume continues from where it failed
# Completed tasks aren't re-executed
```

### Scenario 4: No Pending Tasks

```bash
$ ./cconductor resume mission_1234567890

⚠️  No pending tasks found in session.

Generate new tasks and continue? [Y/n]
# If Y: Runs coordinator to identify new gaps/leads
# If n: Goes directly to final synthesis
```

## Technical Details

### Compatibility Checking

Sessions include the engine version they were created with:

```json
{
  "engine_version": "0.1.0",
  "session_id": "mission_1234567890",
  "research_question": "What is quantum computing?"
}
```

Resume validates:

- Major version must match (1.x.x compatible with 1.y.z)
- Minor/patch differences are allowed
- Warns if versions don't match, prompts to continue

### Atomic Operations

All session state updates use file locking:

- Prevents concurrent access corruption
- Detects and removes stale locks (from crashed processes)
- 30-second timeout on lock acquisition

### Budget Tracking

CConductor automatically tracks spending in `meta/budget.json`:

- **Per-invocation costs**: Each Claude API call's actual cost is recorded
- **Cumulative totals**: Running sum of all invocations
- **Agent attribution**: Cost broken down by agent type

The budget file is updated in real-time as agents complete their work.

### State Preservation

**What's preserved:**

- ✅ All completed tasks and their findings
- ✅ Knowledge graph (entities, claims, relationships)
- ✅ Citations and sources
- ✅ Identified gaps and contradictions
- ✅ Iteration count and confidence scores
- ✅ Budget tracking (cost per invocation)

**What's regenerated:**

- Tasks (coordinator can generate new ones based on current state)
- Final report (re-synthesized from knowledge graph)

## Troubleshooting

### Session Not Found

```bash
$ ./cconductor resume my-session
❌ Error: Session not found: my-session

Available sessions:
mission_1234567890
mission_1234567891
```

**Solution**: Use exact session ID from `./cconductor sessions`

### Version Incompatibility

```bash
⚠️  Warning: Session may be incompatible with current engine version

  Session version:  0.1.0
  Engine version:   2.0.0

Continue anyway? [y/N]
```

**Options**:

1. Try continuing (may work if changes are backward compatible)
2. Upgrade engine to session version
3. Start fresh with current engine

### Corrupted Session

```bash
❌ Error: Invalid session (missing knowledge/knowledge-graph.json)
```

**Causes**:

- Incomplete initialization
- File system corruption
- Manual deletion of files

**Solutions**:

1. Check session directory for required files
2. Restore from backup if available
3. Start new session

### Lock Timeout

```bash
❌ Research session is locked

Waited: 30 seconds
File: knowledge/knowledge-graph.json

What to do:
1. Check for running research:
   ps aux | grep cconductor
2. If no process found, remove stale lock from your sessions directory:
   SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
   rm -rf "$SESSION_DIR"/mission_*/knowledge/knowledge-graph.json.lock
```

## Best Practices

### When to Resume vs Start New

**Resume when:**

- ✅ Building on existing research
- ✅ Quality score not high enough
- ✅ Research was interrupted
- ✅ Want more depth on same question

**Start new when:**

- 🆕 Different research question
- 🆕 Want fresh perspective
- 🆕 Previous research was off-track
- 🆕 Session is corrupted

### Multiple Resume Iterations

You can resume multiple times:

```bash
./cconductor "question"          # Iteration 1-3
./cconductor resume mission_XYZ  # Iteration 4-6
./cconductor resume mission_XYZ  # Iteration 7-9
```

Each resume:

- Builds on previous work
- Can improve quality further
- Has diminishing returns (law of diminishing marginal returns)

### Session Naming

Currently sessions use timestamps:

```
mission_1234567890
```

Future enhancement (planned for future release):

```bash
./cconductor "question" --name my-research-2024
./cconductor resume my-research-2024
```

### Regenerating Synthesis Artifacts

If a resumed session reports malformed or missing synthesis artifacts (for example, the quality gate fails because `completion.json` or `coverage.json` is out of schema), rebuild the required files with the regeneration helper:

```bash
./src/utils/regenerate-synthesis-artifacts.sh --force research-sessions/mission_1234567890
```

The script:

- Recreates schema-compliant skeletons for `completion.json`, `key-findings.json`, `coverage.json`, and `confidence-scores.json`
- Pulls iteration counts, claim totals, and other safe defaults from the current knowledge graph when available
- Overwrites existing files only when `--force` is supplied (omit the flag to keep existing data)

After regeneration, rerun the applicable quality gate or resume the mission:

```bash
./tests/test-quality-gate.sh            # optional local verification
./cconductor resume mission_1234567890  # continue the mission
```

## Advanced Usage

### Direct Path Resume

```bash
# Can use full path instead of session ID
./cconductor resume mission_1234567890

# Find your session directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
echo $SESSION_DIR
```

### Programmatic Access

Session state is all JSON - you can query programmatically:

```bash
# Find your sessions directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)

# Get session metadata
jq '.' "$SESSION_DIR/mission_1234567890/meta/session.json"

# Get knowledge graph summary
jq '{
  entities: .stats.total_entities,
  claims: .stats.total_claims,
  confidence: .confidence_scores.overall,
  gaps: .stats.unresolved_gaps
}' "$SESSION_DIR/mission_1234567890/knowledge/knowledge-graph.json"

# Get mission metrics (duration, cost, watchdog status)
jq '{
  status,
  started_at,
  completed_at,
  duration_seconds,
  total_cost_usd
}' "$SESSION_DIR/mission_1234567890/meta/mission-metrics.json"
```

### Session Migration (Future)

For major version upgrades:

```bash
# Not yet implemented
./cconductor migrate mission_1234567890 --to-version 2.0.0
```

## FAQ

**Q: Can I resume a completed session?**
A: Yes! It will generate new tasks based on remaining gaps and continue improving.

**Q: Will resume re-execute completed tasks?**
A: No. Only pending tasks are executed. Completed findings are preserved.

**Q: How many times can I resume a session?**
A: Unlimited, but returns diminish after 5-10 iterations typically.

**Q: Can I edit a session's JSON files manually?**
A: Technically yes, but not recommended. The system expects valid schema.

**Q: What if I have multiple sessions I want to merge?**
A: Not currently supported. Planned for v1.2.

**Q: Can I resume on a different machine?**
A: Yes, if you copy the entire session directory and have the same engine version.

## See Also

- [USER_GUIDE.md](USER_GUIDE.md) - Complete user documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [QUALITY_GUIDE.md](QUALITY_GUIDE.md) - Improving research quality
