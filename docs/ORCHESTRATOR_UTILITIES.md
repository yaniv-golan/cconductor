# Orchestrator Utility Scripts

## Overview

The orchestrator agent has access to pre-vetted utility scripts for safe data operations. These scripts provide:

- ✅ **Security**: Whitelisted, audited implementations
- ✅ **Performance**: Fast bash/jq operations
- ✅ **Reliability**: Tested, validated behavior
- ✅ **Structured Output**: JSON results easy to parse

## Architecture

### Security Model

```
┌─────────────────────────────────────────┐
│   Mission Orchestrator Agent            │
│                                          │
│   Can ONLY call:                         │
│   - src/utils/calculate.sh               │
│   - src/utils/kg-utils.sh                │
│   - src/utils/data-utils.sh              │
└─────────────────────────────────────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │  pre-tool-use Hook   │
         │  Validates Command   │
         └──────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
    ✅ Allowed            ❌ Blocked
    Utility Script        Other Bash
```

### Why Not Arbitrary Scripts?

The orchestrator **cannot** write or execute:
- ❌ Python scripts
- ❌ Node.js scripts
- ❌ Arbitrary bash commands
- ❌ System utilities (curl, wget, etc.)

**Reason**: LLMs can generate syntactically valid but semantically wrong code. Pre-vetted utilities are safer and more reliable.

## Available Utilities

### 1. Calculate (`src/utils/calculate.sh`)

**Purpose**: Accurate mathematical operations (LLMs are unreliable at arithmetic)

**Operations**:
- `calc <expression>` - Evaluate math expression
- `percentage <part> <whole>` - Calculate percentage
- `growth <old> <new>` - Calculate growth rate
- `cagr <start> <end> <years>` - Calculate CAGR

**Examples**:
```bash
# TAM calculation
Bash: src/utils/calculate.sh calc "500000000 * 50"
# Output: {"result": 25000000000, "error": null}

# Market share
Bash: src/utils/calculate.sh percentage 5000000 50000000
# Output: {"percentage": 10.0, "error": null}

# Revenue growth
Bash: src/utils/calculate.sh growth 10000000 15000000
# Output: {"growth_rate": 50.0, "multiplier": 1.5, "error": null}
```

**Safety Features**:
- Input validation (only numbers and operators)
- Pure bash + bc/awk (no external interpreters)
- JSON output
- Error handling

### 2. Knowledge Graph Utils (`src/utils/kg-utils.sh`)

**Purpose**: Query and analyze knowledge graph without manual jq operations

**Operations**:
- `extract-claims [kg_file]` - Extract all claims
- `extract-entities [kg_file]` - Extract all entities
- `stats [kg_file]` - Comprehensive statistics
- `filter-confidence [kg_file] [min]` - Filter by confidence
- `filter-category [kg_file] <category>` - Filter by category
- `list-categories [kg_file]` - List unique categories

**Examples**:
```bash
# Get comprehensive stats
Bash: src/utils/kg-utils.sh stats knowledge-graph.json
# Output: {total_claims: 42, avg_confidence: 0.85, claims_by_status: {...}, ...}

# Get high-confidence claims
Bash: src/utils/kg-utils.sh filter-confidence knowledge-graph.json 0.8
# Output: {filtered_claims: [...], total: 28}

# Get claims in specific category
Bash: src/utils/kg-utils.sh filter-category knowledge-graph.json "efficacy"
# Output: {filtered_claims: [...], total: 15}

# List all categories
Bash: src/utils/kg-utils.sh list-categories knowledge-graph.json
# Output: {categories: ["efficacy", "safety", "dosage", ...]}
```

**Use Cases**:
- Assess research progress
- Identify gaps by category
- Filter claims for synthesis
- Quality assessment

### 3. Data Utils (`src/utils/data-utils.sh`)

**Purpose**: Transform and consolidate research data files

**Operations**:
- `merge <file1> <file2> ...` - Merge JSON objects
- `consolidate [pattern]` - Consolidate findings files
- `extract-claims [pattern]` - Extract unique claims from findings
- `to-csv <json_file>` - Convert JSON to CSV
- `summarize <json_file> [title]` - Create markdown summary
- `group-by <json_file> <field>` - Group items by field

**Examples**:
```bash
# Consolidate all findings
Bash: src/utils/data-utils.sh consolidate "findings-*.json" > all-findings.json
# Output: {consolidated: [...], total: 5, files: [...]}

# Extract unique claims
Bash: src/utils/data-utils.sh extract-claims
# Output: {unique_claims: [...], total: 42}

# Merge analysis files
Bash: src/utils/data-utils.sh merge stats1.json stats2.json > combined.json

# Group findings by category
Bash: src/utils/data-utils.sh group-by findings.json "category"
# Output: [{key: "efficacy", count: 15, items: [...]}, ...]
```

**Use Cases**:
- Pre-synthesis data consolidation
- Deduplication
- Format conversion
- Statistical grouping

## Usage Patterns

### Pattern 1: Assess Progress
```bash
# Check knowledge graph state
Bash: src/utils/kg-utils.sh stats knowledge-graph.json

# Read the output (saved to a file)
Read: kg-stats.json

# Analyze: "We have 42 claims, avg confidence 0.85, need 5 more in 'safety' category"
```

### Pattern 2: Calculate Market Metrics
```bash
# TAM calculation
Bash: src/utils/calculate.sh calc "10000000 * 50"

# Market share
Bash: src/utils/calculate.sh percentage 2500000 10000000

# Use results in reasoning: "TAM is $500M, our client has 25% market share"
```

### Pattern 3: Pre-Synthesis Consolidation
```bash
# Consolidate findings before synthesis
Bash: src/utils/data-utils.sh consolidate > all-findings.json

# Extract high-confidence claims
Bash: src/utils/kg-utils.sh filter-confidence knowledge-graph.json 0.8 > high-conf.json

# Pass to synthesis agent as artifacts
```

### Pattern 4: Gap Analysis
```bash
# List categories
Bash: src/utils/kg-utils.sh list-categories knowledge-graph.json

# Get claims per category
Bash: src/utils/kg-utils.sh filter-category knowledge-graph.json "safety"

# Identify: "Safety category only has 3 claims, need more research"
```

## Hook Enforcement

The `pre-tool-use.sh` hook validates all Bash commands from the orchestrator:

```bash
# ✅ ALLOWED
Bash: src/utils/calculate.sh calc "123 * 456"
Bash: src/utils/kg-utils.sh stats knowledge-graph.json
Bash: src/utils/data-utils.sh consolidate

# ❌ BLOCKED
Bash: python3 my_script.py
Bash: curl https://example.com
Bash: rm -rf findings/
Bash: cat /etc/passwd
```

**Error Message**:
```
ERROR: Orchestrator can only use whitelisted utility scripts
  Blocked command: python3 my_script.py
  
  Allowed utilities:
    - src/utils/calculate.sh (math operations)
    - src/utils/kg-utils.sh (knowledge graph queries)
    - src/utils/data-utils.sh (data transformation)
```

## Extending Utilities

### Adding a New Utility

1. **Create Script**: `src/utils/my-util.sh`
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   
   my_function() {
       local input="$1"
       # Safe, validated implementation
       jq -n --arg in "$input" '{result: $in}'
   }
   
   export -f my_function
   
   if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
       my_function "$@"
   fi
   ```

2. **Add to Whitelist**: `src/utils/hooks/pre-tool-use.sh`
   ```bash
   if [[ "$command" =~ ^(src/utils/calculate\.sh|src/utils/kg-utils\.sh|src/utils/data-utils\.sh|src/utils/my-util\.sh) ]]; then
   ```

3. **Document in Prompt**: `agents/mission-orchestrator/system-prompt.md`

4. **Update Agent Tools**: `src/utils/agent-tools.json`
   ```json
   "allowed": [
       "Bash(src/utils/my-util.sh)"
   ]
   ```

### Design Principles

✅ **Input Validation**: Sanitize all inputs  
✅ **Error Handling**: Return JSON with error field  
✅ **JSON Output**: Structured, parseable results  
✅ **Pure Functions**: No side effects  
✅ **Self-Documented**: Include help/examples  
✅ **Tested**: Verify with shellcheck  

## Best Practices

### For Orchestrator Agents

1. **Use utilities instead of reasoning**: Don't calculate in your head, use `calculate.sh`
2. **Check progress with stats**: Use `kg-utils.sh stats` to assess state
3. **Consolidate before synthesis**: Use `data-utils.sh` to prepare artifacts
4. **Save utility output to files**: Write results to JSON files for later reading

### For Developers

1. **Keep utilities simple**: Single-purpose, focused functions
2. **Return JSON**: Enables structured parsing
3. **Validate inputs**: Prevent injection attacks
4. **Test thoroughly**: Shell scripts are error-prone
5. **Document examples**: Show real usage patterns

## Troubleshooting

### "ERROR: Orchestrator can only use whitelisted utility scripts"

**Cause**: Orchestrator tried to run a non-whitelisted command  
**Fix**: Use one of the three allowed utilities or request a new utility be added

### "File not found" errors

**Cause**: Utility script path is relative to project root  
**Fix**: Always use full path from project root: `src/utils/calculate.sh`

### jq parse errors

**Cause**: Input JSON is malformed or has special characters  
**Fix**: Utilities handle this gracefully with error messages in JSON output

## See Also

- [Agent Tools Configuration](AGENT_TOOLS_CONFIG.md)
- [Security Guide](SECURITY_GUIDE.md)
- [Mission Orchestration](docs/USER_GUIDE.md#mission-based-orchestration)

