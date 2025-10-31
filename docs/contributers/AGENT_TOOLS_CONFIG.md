# Agent Tool Restrictions Configuration Guide

**File**: `src/utils/agent-tools.json`  
**Purpose**: Define per-agent tool access policies for security and specialization  
**Since**: Phase 0 (October 2025)

---

## Overview

The `agent-tools.json` file controls which Claude Code tools each agent can use. This provides:

1. **Security**: Prevent agents from performing dangerous operations (e.g., `Bash` commands)
2. **Specialization**: Enforce agent roles by limiting tool access
3. **Domain Restrictions**: Limit web access to trusted domains

---

## File Format

```json
{
  "agent-name": {
    "allowed": ["Tool1", "Tool2"],
    "disallowed": ["Tool3", "Tool4"]
  }
}
```

### Fields

- **`agent-name`**: Name of agent (must match agent JSON filename without `.json`)
- **`allowed`**: Array of tools this agent CAN use (whitelist)
- **`disallowed`**: Array of tools this agent CANNOT use (blacklist)

### Rules

1. If `allowed` is specified, agent can ONLY use those tools
2. If `disallowed` is specified, agent cannot use those tools
3. Both can be used together (allowed list with specific exclusions)
4. If neither specified, agent has access to ALL tools (not recommended)

---

## Available Tools

### Read-Only Tools

- **`Read`**: Read files from disk
- **`Grep`**: Search file contents
- **`Glob`**: List files matching pattern
- **`ListDir`**: List directory contents

### Web Access Tools

- **`WebSearch`**: Perform web searches
- **`WebFetch`**: Fetch web pages
- **`WebFetch(domain)`**: Fetch from specific domain only
- **`WebFetch(*.tld)`**: Fetch from domains with specific TLD

### Write Tools

- **`Write`**: Write files to disk
- **`Edit`**: Edit existing files
- **`NotebookEdit`**: Edit Jupyter notebooks

### Execution Tools

- **`Bash`**: Execute shell commands (DANGEROUS - use with extreme caution)

### Other Tools

- **`Task`**: Delegate to sub-agents (used by coordinator agents)
- **`ManPage`**: Read Unix manual pages
- **`Lint`**: Run code linters

---

## Example Configurations

### Research Agent (Safe)

```json
{
  "web-researcher": {
    "allowed": [
      "WebSearch",
      "WebFetch(*.edu)",
      "WebFetch(*.gov)",
      "WebFetch(github.com)",
      "WebFetch(stackoverflow.com)",
      "Read",
      "Grep",
      "Glob"
    ],
    "disallowed": ["Bash", "Write", "Edit", "NotebookEdit"]
  }
}
```

**Rationale**: Can search web and fetch from trusted domains, can read local files, but cannot write or execute commands.

### Academic Researcher (Specialized)

```json
{
  "academic-researcher": {
    "allowed": [
      "WebSearch",
      "WebFetch(*.edu)",
      "WebFetch(arxiv.org)",
      "WebFetch(pubmed.ncbi.nlm.nih.gov)",
      "WebFetch(scholar.google.com)",
      "WebFetch(semanticscholar.org)",
      "Read",
      "Grep",
      "Glob"
    ],
    "disallowed": ["Bash", "Write", "Edit", "NotebookEdit"]
  }
}
```

**Rationale**: Specialized for academic sources only, no general web access.

### Synthesis Agent (Local Only)

```json
{
  "synthesis-agent": {
    "allowed": ["Read", "Grep", "Glob"],
    "disallowed": ["WebSearch", "WebFetch", "Bash", "Write", "Edit"]
  }
}
```

**Rationale**: Can only read local files, cannot access web or make changes.

### Coordinator (Orchestration Only)

```json
{
  "research-coordinator": {
    "allowed": ["Read", "Write", "Grep", "Glob"],
    "disallowed": ["WebSearch", "WebFetch", "Bash", "Edit"]
  }
}
```

**Rationale**: Can read/write coordination files, but cannot research or execute commands.

### Dangerous Configuration (Not Recommended)

```json
{
  "admin-agent": {
    "allowed": ["Read", "Write", "Bash", "WebFetch"]
  }
}
```

**⚠️ WARNING**: Allows command execution. Use only for trusted automation tasks with user supervision.

---

## Domain Restriction Syntax

### Exact Domain

```json
"WebFetch(github.com)"
```

Allows: `https://github.com/...`  
Denies: `https://gist.github.com/...`, `https://api.github.com/...`

### Wildcard Subdomain

```json
"WebFetch(*.edu)"
```

Allows: `https://stanford.edu/...`, `https://cs.mit.edu/...`  
Denies: `https://edu.com/...`, `https://fake-edu.com/...`

### Multiple Domains

```json
"allowed": [
  "WebFetch(arxiv.org)",
  "WebFetch(*.edu)",
  "WebFetch(pubmed.ncbi.nlm.nih.gov)"
]
```

Agent can fetch from any of these domains.

---

## Security Best Practices

### 1. Principle of Least Privilege

Give each agent ONLY the tools it needs for its specific role.

**Good**:

```json
{
  "pdf-analyzer": {
    "allowed": ["Read", "Grep", "Glob"]
  }
}
```

**Bad**:

```json
{
  "pdf-analyzer": {
    "allowed": ["Read", "Bash", "WebFetch", "Write"]
  }
}
```

### 2. Never Allow Bash Without Justification

`Bash` tool allows arbitrary command execution. Extremely dangerous.

**Acceptable Use Cases**:

- Automated testing with user supervision
- Development/debugging environments only
- Sandboxed environments

**Never Allow**:

- Production research agents
- User-facing agents
- Agents processing untrusted input

### 3. Use Domain Restrictions for Web Access

Don't allow unrestricted `WebFetch`.

**Good**:

```json
"allowed": ["WebFetch(*.edu)", "WebFetch(arxiv.org)"]
```

**Bad**:

```json
"allowed": ["WebFetch"]
```

### 4. Separate Read and Write Agents

Agents that read should not write, and vice versa (when possible).

**Research Agent** (Read-only):

```json
"allowed": ["WebSearch", "Read", "Grep"]
```

**Coordinator Agent** (Write-only):

```json
"allowed": ["Read", "Write", "Grep"]
"disallowed": ["WebSearch", "WebFetch"]
```

---

## Configuration Loading

### Load Order

1. **Default**: `$CCONDUCTOR_ROOT/src/utils/agent-tools.json` (git-tracked)
2. **User Override**: `~/.config/cconductor/agent-tools.json` (optional, user-specific)
3. **Session Override**: `$session_dir/agent-tools.json` (optional, per-session)

Later files override earlier ones for matching agent names.

### Example: User Override

**Default** (`src/utils/agent-tools.json`):

```json
{
  "web-researcher": {
    "allowed": ["WebSearch", "WebFetch(*.edu)"]
  }
}
```

**User Override** (`~/.config/cconductor/agent-tools.json`):

```json
{
  "web-researcher": {
    "allowed": ["WebSearch", "WebFetch(*.edu)", "WebFetch(*.gov)"]
  }
}
```

**Result**: Agent can access `.edu` and `.gov` domains.

---

## Validation

### Testing Tool Restrictions

Use `validation_tests/test-04-allowed-tools.sh`:

```bash
cd validation_tests
bash test-04-allowed-tools.sh
```

Verifies that `--allowedTools` flag is enforced by Claude CLI.

### Testing Domain Restrictions

Use `validation_tests/test-06-domain-restrictions.sh`:

```bash
cd validation_tests
bash test-06-domain-restrictions.sh
```

Verifies that `WebFetch(domain)` syntax works correctly.

---

## Troubleshooting

### Agent Cannot Access Needed Tool

**Symptom**: Agent fails with "Tool not available" error.

**Solution**: Add tool to agent's `allowed` list in `agent-tools.json`.

### Agent Accessing Blocked Domain

**Symptom**: Agent fetches from domain it shouldn't access.

**Solution**:

1. Check domain restriction syntax (e.g., `WebFetch(*.edu)` not `WebFetch(.edu)`)
2. Verify `agent-tools.json` is being loaded (check `invoke_agent_v2` output)
3. Check for user/session overrides that might be more permissive

### Configuration Not Being Applied

**Symptom**: Changes to `agent-tools.json` not taking effect.

**Solution**:

1. Verify JSON syntax with `jq empty agent-tools.json`
2. Check file location (should be `src/utils/agent-tools.json`)
3. Restart CConductor session (agent definitions loaded at session start)

### Permission Denied Errors

**Symptom**: Agent has permission but still fails.

**Solution**:

1. Tool restriction is separate from file system permissions
2. Check actual file/directory permissions
3. Verify agent is running in correct session directory

---

## Default Configuration

The default `src/utils/agent-tools.json` includes these agents:

| Agent | Web Access | Write Access | Command Execution |
|-------|-----------|--------------|-------------------|
| web-researcher | ✅ (*.edu,*.gov) | ❌ | ❌ |
| academic-researcher | ✅ (academic only) | ❌ | ❌ |
| synthesis-agent | ❌ | ❌ | ❌ |
| fact-checker | ✅ (unrestricted) | ❌ | ❌ |
| pdf-analyzer | ❌ | ❌ | ❌ |
| research-coordinator | ❌ | ✅ (coordination files) | ❌ |

**Note**: NO agents have `Bash` access by default.

---

## Related Documentation

- **validation_tests/README.md**: Test suite overview
- **docs/SECURITY_GUIDE.md**: Overall security architecture
- **docs/TROUBLESHOOTING.md**: Common issues and solutions

---

## Version History

- **Phase 0 (October 2025)**: Initial implementation
  - Native Claude Code CLI tool restriction support
  - Domain-based web access control
  - Validated patterns from test suite
