# Knowledge Extension Guide

This guide explains how to add custom domain knowledge to the CConductor without modifying core files.

**For Technical Deep Dive**: See [Knowledge System Technical Documentation](KNOWLEDGE_SYSTEM_TECHNICAL.md) for complete system architecture, step-by-step impact traces, and debugging guides.

## Overview

The CConductor uses a **WordPress-style extensible knowledge system** with convention-based auto-discovery and priority-based loading.

### Directory Structure

```
research-engine/
├── knowledge-base/              # Core knowledge (git-tracked)
│   ├── business-methodology.md
│   ├── scientific-methodology.md
│   └── research-methodology.md
│
├── knowledge-base-custom/       # Your custom knowledge (gitignored)
│   ├── TEMPLATE.md             # Template for creating new knowledge
│   ├── healthcare-policy.md    # Your custom domains
│   └── crypto-markets.md
│
└── research-sessions/
    └── mission_X/knowledge/     # Session-specific overrides (ephemeral)
        └── temporary-methodology.md
```

### Priority System

When loading knowledge, the system checks in this order:

1. **Session Override** (highest priority) - `research-sessions/mission_X/knowledge/`
2. **User Custom** - `knowledge-base-custom/`
3. **Core Default** (lowest priority) - `knowledge-base/`

**Result**: You can override any core knowledge without modifying git-tracked files!

## Why This Matters

### Before (Problems)

```bash
# User adds healthcare knowledge to business-methodology.md
vim knowledge-base/business-methodology.md  # Edit core file

# Later: git pull
git pull origin main
# ❌ CONFLICT! Merge conflict in knowledge-base/business-methodology.md
# User must manually resolve conflicts every time

# OR: User commits customization
git add knowledge-base/business-methodology.md
git commit -m "Add healthcare knowledge"
# Now can't pull updates without merge conflicts
```

### After (Solution)

```bash
# User adds healthcare knowledge to custom directory
vim knowledge-base-custom/healthcare-policy.md  # Gitignored!

# Later: git pull
git pull origin main
# ✅ No conflicts! Custom knowledge preserved
```

## Quick Start

### 1. Create Custom Knowledge

```bash
# Create directory (if not exists)
mkdir -p knowledge-base-custom

# Copy template
cp knowledge-base-custom/TEMPLATE.md knowledge-base-custom/my-domain.md

# Edit your custom knowledge
vim knowledge-base-custom/my-domain.md
```

### 2. Auto-Discovery (Default)

Custom knowledge is **automatically discovered** and loaded by agents!

```bash
# Run research - your custom knowledge is automatically included
./cconductor "Research question about my domain"
```

**How it works:**
- When agents are built, the system scans `knowledge-base-custom/`
- Knowledge is injected into agent prompts at build time
- Agents receive knowledge prepended to their system prompts
- Priority: Session > Custom > Core

### 3. Verify Loading

```bash
# List all available knowledge
./src/utils/knowledge-loader.sh all

# Check what knowledge an agent sees
./src/utils/knowledge-loader.sh list market-analyzer

# Find specific knowledge file
./src/utils/knowledge-loader.sh find my-domain
```

## Advanced Usage

### Manual Configuration

If you want to control which agents use which knowledge:

```bash
# Create custom config
./src/utils/config-loader.sh init knowledge-config

# Edit agent mappings
vim config/knowledge-config.json
```

Example configuration:

```json
{
  "agent_knowledge_map": {
    "market-analyzer": ["business-methodology", "healthcare-policy"],
    "web-researcher": ["scientific-methodology"],
    "synthesis-agent": ["*"]
  },
  "auto_discover": true
}
```

### Manual Import in Claude Code

You have three options for making knowledge available to Claude Code agents:

**Option 1: Template (affects all new sessions)**

Edit `src/claude-runtime/CLAUDE.md` to add imports that will be included in all future research sessions:

```markdown
## Custom Knowledge Imports

@../../knowledge-base-custom/healthcare-policy.md
@../../knowledge-base-custom/crypto-markets.md
@../../knowledge-base-custom/legal-compliance.md
```

**Option 2: User-wide (affects all sessions globally)**

Add to `~/.claude/CLAUDE.md` (user-wide Claude Code configuration):

```markdown
## Custom Knowledge Imports

@/absolute/path/to/cconductor/knowledge-base-custom/healthcare-policy.md
@/absolute/path/to/cconductor/knowledge-base-custom/crypto-markets.md
```

**Option 3: Session-specific (one session only)**

After creating a session, edit `$session_dir/.claude/CLAUDE.md`:

```markdown
## Session-Specific Knowledge

@../../knowledge-base-custom/specialized-knowledge.md
```

This makes knowledge available to Claude Code directly without going through knowledge-loader.sh.

### Session-Specific Overrides

For one-off research with special methodology:

```bash
# Create session-specific knowledge
SESSION_DIR="research-sessions/session_1234567890"
mkdir -p "$SESSION_DIR/knowledge"

# Override core methodology for this session only
cat > "$SESSION_DIR/knowledge/business-methodology.md" <<'EOF'
# Temporary Override: 2024 Business Methodology

Use updated metrics for this specific research:
- ARR multiples adjusted for 2024 market
- New funding stage definitions
...
EOF

# Run research - uses session override
./cconductor "Business question" --resume session_1234567890

# Other sessions still use default business-methodology.md
```

## Creating Domain Knowledge

### Step 1: Use the Template

```bash
cp knowledge-base-custom/TEMPLATE.md knowledge-base-custom/fintech-analysis.md
```

### Step 2: Fill in Domain Details

```markdown
# Fintech Analysis Methodology

## Overview

Specialized methodology for analyzing fintech companies and market dynamics.

**When to use**:
- Payment processing research
- Digital banking analysis
- Cryptocurrency market sizing
- Regulatory compliance questions

## Key Concepts

- **Payment Volume**: Total transaction value processed
- **Take Rate**: Revenue as % of payment volume
- **Interchange**: Fee paid by merchant's bank to cardholder's bank

## Methodologies

### Market Sizing

**When to use**: Estimating TAM/SAM/SOM for fintech products

**Approach**:
1. Identify target payment flows (e.g., B2B payments)
2. Calculate total addressable volume
3. Apply realistic take rates
4. Adjust for competitive capture

**Data sources**:
- Central bank payment statistics
- Industry reports (McKinsey, BCG fintech reports)
- Public company disclosures (Stripe, Square, PayPal)

**Validation**:
- Cross-reference multiple sources
- Check if TAM assumptions are realistic
- Validate take rate against industry benchmarks

### Competitive Analysis

...

## Common Pitfalls

### Pitfall 1: Confusing Payment Volume with Revenue

**Problem**: Payment volume != revenue. Revenue = volume × take rate

**How to avoid**: Always clarify whether figures are GMV or revenue

### Pitfall 2: Ignoring Regional Regulations

**Problem**: Payment regulations vary significantly by region

**How to avoid**: Segment analysis by regulatory jurisdiction

## Quality Standards

1. **Source Requirements**:
   - Minimum 3 independent sources for market size
   - At least one regulatory source for compliance questions
   - Public filings for competitive metrics

2. **Validation Standards**:
   - Cross-check take rates against public company disclosures
   - Verify regulatory claims with official sources
   - Sanity-check market sizes with top-down + bottom-up

## Resources

### Primary Sources
- Federal Reserve Payment Studies: [https://...]
- BIS Payment Statistics: [https://...]
- Company 10-Ks: SEC EDGAR

### Secondary Sources
- McKinsey Global Payments Report: [https://...]
- a16z Fintech Newsletter: [https://...]
```

### Step 3: Verify Integration

```bash
# Check if knowledge is discovered
./src/utils/knowledge-loader.sh discover

# Test knowledge loading for specific agent
./src/utils/knowledge-loader.sh list market-analyzer | jq .

# Should include your fintech-analysis.md file
```

## Knowledge Discovery Details

### Auto-Discovery Rules

From `config/knowledge-config.default.json`:

```json
{
  "discovery_rules": {
    "pattern": "*.md",
    "exclude": ["README.md", "LICENSE.md", "TEMPLATE.md"]
  }
}
```

**What gets discovered**:

- All `.md` files in `knowledge-base-custom/`
- Excludes: README, LICENSE, TEMPLATE

**How to exclude a file**: Add it to `exclude` list in `config/knowledge-config.json`

### Agent Mappings

Default agent mappings:

| Agent | Knowledge Loaded |
|-------|------------------|
| market-analyzer | business-methodology |
| competitor-analyzer | business-methodology |
| financial-extractor | business-methodology |
| web-researcher | scientific-methodology, research-methodology |
| academic-researcher | scientific-methodology, research-methodology |
| synthesis-agent | * (all knowledge) |
| fact-checker | * (all knowledge) |

`*` means all discovered knowledge is loaded.

## Testing Your Knowledge

### Test 1: Discovery

```bash
# Create test knowledge
echo "# Test Domain" > knowledge-base-custom/test-domain.md

# Verify it's discovered
./src/utils/knowledge-loader.sh discover | grep test-domain
# Should output: .../knowledge-base-custom/test-domain.md
```

### Test 2: Priority Order

```bash
# Create core knowledge
echo "# CORE VERSION" > knowledge-base/test.md

# Create user override
echo "# USER VERSION" > knowledge-base-custom/test.md

# Check which one loads (should be USER)
./src/utils/knowledge-loader.sh find test
# Should output: .../knowledge-base-custom/test.md
```

### Test 3: Session Override

```bash
# Create session
SESSION_DIR="research-sessions/test_session"
mkdir -p "$SESSION_DIR/knowledge"

# Create session override
echo "# SESSION VERSION" > "$SESSION_DIR/knowledge/test.md"

# Check priority (should be SESSION)
./src/utils/knowledge-loader.sh find test "$SESSION_DIR"
# Should output: .../research-sessions/test_session/knowledge/test.md
```

### Test 4: Agent Integration

```bash
# Check what knowledge synthesis-agent sees
./src/utils/knowledge-loader.sh list synthesis-agent | jq .

# Should include all discovered knowledge files
```

## Troubleshooting

### Knowledge Not Loading

**Problem**: Custom knowledge not appearing in agent output

**Diagnosis**:

```bash
# Check if file is discovered
./src/utils/knowledge-loader.sh all

# Check if agent is mapped to knowledge
./src/utils/knowledge-loader.sh list <agent-name> | jq .

# Check file syntax
jq '.' config/knowledge-config.json
```

**Solutions**:

1. Ensure filename ends with `.md`
2. Check file isn't in exclude list
3. Verify file exists in `knowledge-base-custom/`
4. Try manual import in `src/claude-runtime/CLAUDE.md` (template) or `~/.claude/CLAUDE.md` (user-wide)

### Git Conflicts

**Problem**: Getting merge conflicts in custom knowledge

**Cause**: Custom knowledge files were accidentally committed to git

**Solution**:

```bash
# Remove from git (keeps local file)
git rm --cached knowledge-base-custom/*.md
git commit -m "Remove custom knowledge from git"

# Verify gitignore
grep "knowledge-base-custom/" .gitignore
# Should show: knowledge-base-custom/

# Now git pull works cleanly
git pull origin main
```

### Knowledge File Errors

**Problem**: Syntax errors or formatting issues

**Solution**:

- Use TEMPLATE.md as a guide
- Keep markdown simple (no complex HTML)
- Test with smaller files first
- Use markdown linters if available

## Best Practices

### 1. Keep Knowledge Focused

**Good**:

```markdown
# SaaS Metrics Methodology

Focus on SaaS-specific metrics and analysis.
```

**Bad**:

```markdown
# Everything About Software

Trying to cover too many domains in one file.
```

### 2. Cite Sources

Always include sources in your custom knowledge:

```markdown
## Data Sources

- Source 1: [URL] - What it provides
- Source 2: [URL] - What it provides
```

### 3. Version Your Knowledge

Add a changelog section:

```markdown
## Changelog

| Date | Changes | Author |
|------|---------|--------|
| 2024-10-01 | Initial creation | You |
| 2024-10-15 | Added fintech regulations | You |
```

### 4. Use Descriptive Filenames

**Good**: `healthcare-policy-2024.md`, `crypto-market-analysis.md`

**Bad**: `stuff.md`, `notes.md`, `v2.md`

### 5. Test Before Production

Test custom knowledge with simple queries before using in important research:

```bash
# Test query
./cconductor "Simple test question about my domain"

# Review output for knowledge integration
cat research-sessions/session_*/report/mission-report.md
```

## Examples

### Example 1: Healthcare Policy Knowledge

File: `knowledge-base-custom/healthcare-policy.md`

```markdown
# Healthcare Policy Research Methodology

## Overview
Specialized approach for analyzing healthcare policy, regulations, and market dynamics.

## Key Concepts
- **FDA Approval Pathway**: 510(k) vs PMA vs De Novo
- **Reimbursement**: CMS coverage decisions
- **HIPAA Compliance**: Privacy and security requirements

## Data Sources
- FDA approvals database
- CMS coverage determinations
- Health policy journals

...
```

Usage:

```bash
# Automatically loaded for relevant queries
./cconductor "Analyze FDA approval process for digital health devices"
```

### Example 2: Cryptocurrency Markets

File: `knowledge-base-custom/crypto-markets.md`

```markdown
# Cryptocurrency Market Analysis Methodology

## Overview
Framework for analyzing cryptocurrency projects, tokenomics, and market dynamics.

## Key Metrics
- **TVL (Total Value Locked)**: DeFi protocol health
- **Token Velocity**: Transaction frequency
- **Network Effects**: Active addresses, transactions

## Data Sources
- DeFiLlama (TVL data)
- Dune Analytics (on-chain metrics)
- Token Terminal (financial metrics)

...
```

Usage:

```bash
./cconductor "Analyze DeFi lending protocols market"
```

## Configuration Reference

### knowledge-config.json Schema

```json
{
  "knowledge_paths": {
    "core": "knowledge-base",                  // Core knowledge directory
    "user": "knowledge-base-custom",           // User custom directory
    "session": "{session_dir}/knowledge"       // Session override path
  },
  "agent_knowledge_map": {
    "agent-name": ["knowledge-file1", "knowledge-file2"],  // Specific files
    "synthesis-agent": ["*"]                                // All files
  },
  "auto_discover": true,                       // Auto-discover .md files
  "discovery_rules": {
    "pattern": "*.md",                         // File pattern to match
    "exclude": ["README.md", "TEMPLATE.md"]    // Files to exclude
  }
}
```

## FAQ

**Q: Do I need to restart anything after adding custom knowledge?**

A: No! Knowledge is loaded at runtime. Just start a new research session.

**Q: Can I override core knowledge?**

A: Yes! Create a file with the same name in `knowledge-base-custom/`. Your version takes priority.

**Q: Will my custom knowledge be lost during upgrades?**

A: No! Custom knowledge is gitignored, so `git pull` never touches it.

**Q: Can I version control my custom knowledge separately?**

A: Yes! Initialize a git repo in `knowledge-base-custom/` to track your own changes.

**Q: How many custom knowledge files can I add?**

A: No limit! Add as many as needed. Auto-discovery handles them all.

**Q: Can I use custom knowledge for just one research session?**

A: Yes! Use session overrides in `research-sessions/mission_X/knowledge/`.

## Command Reference

```bash
# List all available knowledge
./src/utils/knowledge-loader.sh all [session_dir]

# Find specific knowledge file
./src/utils/knowledge-loader.sh find <knowledge-name> [session_dir]

# List knowledge for specific agent
./src/utils/knowledge-loader.sh list <agent-name> [session_dir]

# Discover all knowledge files
./src/utils/knowledge-loader.sh discover [session_dir]

# Show help
./src/utils/knowledge-loader.sh help

# Create custom config
./src/utils/config-loader.sh init knowledge-config
```

---

**Happy researching with custom knowledge!** 🔬

For more information:

- Configuration Guide: `./src/utils/config-loader.sh help`
- Upgrade Guide: `UPGRADE.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`
