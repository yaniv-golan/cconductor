# CConductor User Guide

**Complete guide to using CConductor for research**

**Version**: 0.1.0  
**Last Updated**: October 2025  
**For**: Semi-technical users (CLI comfortable, no coding required)

---

## Table of Contents

### Part 1: Getting Started

1. [Installation & Setup](#installation--setup)
   - [Understanding Claude Code](#understanding-claude-code)
2. [Your First Research](#your-first-research)
3. [Understanding Sessions](#understanding-sessions)

### Part 2: Core Features

4. [Research System](#research-system)
5. [Working with Results](#working-with-results)
6. [Managing Research](#managing-research)

### Part 3: Configuration

7. [Understanding Configuration](#understanding-configuration)
8. [Security Settings](#security-settings)
9. [Adding Custom Knowledge](#adding-custom-knowledge)

### Part 4: Advanced Usage

10. [Quality & Citations](#quality--citations)
11. [Multi-Session Research](#multi-session-research)

### Part 5: Tips & Best Practices

12. [Writing Good Research Questions](#writing-good-research-questions)
13. [Organizing Research](#organizing-research)

### Appendix

- [Command Reference](#command-reference)
- [Configuration Files](#configuration-files-overview)
- [Glossary](#glossary)

---

# Part 1: Getting Started

## Installation & Setup

### System Requirements

Before installing CConductor, verify you have:

#### Required Software

**Check if you have bash**:

```bash
bash --version
# Should show: GNU bash, version 4.0 or higher
```

**Check if Claude Code is authenticated**:

```bash
claude whoami
# Should show your authenticated account
# If not authenticated, run: claude login
```

**Check if you have jq**:

```bash
jq --version
# Should show: jq-1.6 or similar
```

**Check if you have curl**:

```bash
curl --version
# Should show: curl 7.x or higher
```

**Check if you have bc** (required for calculations):

```bash
bc --version
# Should show: bc version
```

#### Installing Missing Dependencies

**macOS**:

```bash
# Install Homebrew if you don't have it
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install jq curl

# bash and bc are pre-installed on macOS
```

**Linux** (Ubuntu/Debian):

```bash
sudo apt-get update
sudo apt-get install jq curl bash bc
```

**Windows**:

- Install [WSL (Windows Subsystem for Linux)](https://docs.microsoft.com/en-us/windows/wsl/install)
- Or use [Git Bash](https://git-scm.com/downloads)
- Then follow Linux instructions above

#### Claude Code Requirement

**Important**: CConductor requires Claude Code to function. It cannot run with just an Anthropic API key.

**Check if you have access**:

- Do you have a Claude Pro or Max subscription? ✅ You have access
- Do you have Anthropic API credits? ✅ You have access (pay-per-use)
- Are you unsure? See [Understanding Claude Code](#understanding-claude-code) below

### Understanding Claude Code

Before installing CConductor, it's important to understand how Claude Code access works.

#### What is Claude Code?

Claude Code is Anthropic's developer-focused interface that allows Claude to:

- Run integrated workflows in your terminal/IDE
- Invoke specialized tools and agents
- Orchestrate complex multi-step tasks

CConductor uses Claude Code's Task tool to coordinate its multi-agent research system. Each research session involves multiple Claude interactions:

1. Research planning
2. Parallel research execution (multiple agents)
3. Synthesis and validation
4. Report generation

#### How to Get Access

Claude Code is available through two routes:

**Option 1: Claude Subscription (Pro/Max)**

- Includes Claude Code usage within your plan quota
- Pro and Max plans have different quota limits
- Usage is shared between regular Claude chat and Claude Code
- Best for: Regular users who want predictable monthly costs

**Option 2: API/Pay-as-you-go**

- Purchase API credits from Anthropic Console
- Pay per token/prompt used
- No monthly subscription needed
- Billed separately from any Claude chat subscription
- Best for: Variable usage patterns or exceeding plan limits

**Both can work together**: If you have a subscription and exceed your quota, usage falls back to API billing (if you have credits).

#### Understanding the Billing Model

This can be confusing, so here's the key point:

> **Your Claude chat subscription and API usage are separate billing systems.**

- A Claude Pro/Max subscription includes *some* Claude Code usage
- If you exceed that included amount, you'll need API credits
- API usage is tracked and billed separately via Anthropic Console
- Having a subscription does NOT give unlimited Claude Code access

#### Cost Considerations

**What affects cost**:

- Research complexity (simple questions vs. comprehensive research)
- Number of iterations (basic vs. resume for higher quality)
- Research mode (general vs. literature review)
- Sources accessed (web vs. PDFs vs. academic databases)

**Typical usage**:

- Simple research: ~5-10 prompts
- Comprehensive research: ~15-30 prompts
- Literature review: ~30-50 prompts
- Resume/iteration: +10-20 prompts per iteration

**Which plan do I need?**

- **Occasional research** (1-3 sessions/week): Pro plan likely sufficient
- **Frequent research** (daily use): Max plan recommended
- **Intensive research** (multiple daily sessions): Max + API credits
- **Enterprise/team use**: Consider dedicated API setup

#### Checking Your Usage

**For Claude subscriptions**:

- View usage in your Claude account settings
- Monitor "Code usage" separately from "Chat usage"
- You'll be notified when approaching limits

**For API usage**:

- Check [Anthropic Console](https://console.anthropic.com)
- View detailed cost and usage reports
- Set up spending alerts

#### What Happens if I Run Out?

**If you have a subscription only**:

- You'll receive a notice when approaching quota
- Options: Wait for quota reset (5-hour windows) or add API credits
- No work is lost; you can resume later

**If you have API credits**:

- Usage automatically continues on API billing
- Transparent cost tracking in Console
- Add more credits as needed

#### Official Resources

**For current pricing and plan details**:

- [Anthropic Pricing](https://www.anthropic.com/pricing) - Current plans and pricing
- [Using Claude Code with Plans](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan) - Subscription details
- [API Usage Payment](https://support.anthropic.com/en/articles/8977456-how-do-i-pay-for-my-api-usage) - API billing
- [Why Separate Billing?](https://support.anthropic.com/en/articles/9876003-i-subscribe-to-a-paid-claude-ai-plan-why-do-i-have-to-pay-separately-for-api-usage-on-console) - Explanation

**Note**: Plan features, quotas, and pricing change regularly. Always verify current details with Anthropic before making decisions.

---

### Installing CConductor

#### Quick Install (Recommended)

The easiest way to install CConductor:

```bash
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash
```

This installer will:

- Install CConductor to `~/.cconductor` (or custom location)
- Auto-install missing dependencies (jq, curl)
- Run first-time setup automatically
- Optionally add `cconductor` to your PATH

After installation, use from anywhere:

```bash
cconductor "your research question"
```

#### Manual Install

If you prefer manual installation:

1. **Clone the repository**:

```bash
cd ~/Documents/code  # Or your preferred location
git clone https://github.com/yaniv-golan/cconductor.git
cd cconductor
```

2. **Start using it immediately**:

```bash
./cconductor "your research question"
```

**Note:** If you get "Permission denied", run: `chmod +x cconductor`

**What happens on first run**:

On your first run, CConductor automatically performs setup (~5 seconds):

- Checks dependencies (jq, curl, bash)
- Offers to auto-install missing dependencies
- Creates necessary directories
- Sets up configuration files from templates
- Configures .gitignore to protect your data
- Makes scripts executable
- Validates all configurations

You'll see a prompt like:

```
┌─────────────────────────────────────────────────────┐
│ Welcome to CConductor! First-time setup required.        │
└─────────────────────────────────────────────────────┘

I will now:
  1. Check for dependencies (jq, curl, bash)
  2. Create directories (research-sessions/, logs/, config/)
  3. Set up configuration files from templates
  4. Configure .gitignore to protect your data
  5. Make scripts executable
  6. Validate all configurations

This takes ~5 seconds. Run initialization? [Y/n]
```

Press Enter to proceed, then research begins!

3. **Verify installation**:

```bash
./cconductor --version
# Output: CConductor v0.1.0

./cconductor --help
# Output: Full help text
```

If both commands work, you're ready!

---

## Your First Research

### Basic Syntax

The simplest way to use CConductor:

```bash
./cconductor "your research question here"
```

**Important**:

- Put your question in quotes
- Be specific for better results
- No complex syntax needed

### Example: Simple Research

```bash
./cconductor "What causes climate change?"
```

### Example: Research from File (Complex Queries)

For complex, multi-part research queries, use a markdown file instead of command-line text:

```bash
./cconductor --question-file research-query.md
```

**Why use a question file**:

- **Complex queries**: Multiple sub-questions, structured context, and background information
- **Reusable templates**: Save and reuse research protocols
- **Version control**: Track changes to your research questions over time
- **Better formatting**: Use markdown for headers, lists, and emphasis
- **No escaping**: Avoid command-line quoting and escaping issues

**Example question file** (`research-query.md`):

```markdown
# Research Query: Market Analysis for AI Chatbots

## Research Objective
Comprehensive market analysis of the AI chatbot industry focusing on enterprise 
adoption, key players, and growth trends 2023-2025.

## Core Questions
1. What is the current market size and projected growth?
2. Who are the top 5 players and their market share?
3. What are the main use cases in enterprise?
4. What are the key technological differentiators?

## Keywords
- AI chatbot market size
- Enterprise chatbot adoption
- Conversational AI trends
- ChatGPT competitors

## Expected Outputs
- Market size with sources
- Competitive landscape analysis
- Technology trend analysis
```

**Combine with other flags**:

```bash
# Non-interactive research from file
./cconductor --question-file research-query.md --non-interactive

# Question file + local materials
./cconductor --question-file research-query.md --input-dir ./materials/
```

### Example: Research with Local Files

If you have PDFs, documents, or notes to analyze alongside web research:

```bash
./cconductor "Analyze this pitch deck" --input-dir ./pitch-materials/
```

**What files are supported**:

- **PDFs** (`.pdf`) - Automatically cached and analyzed  
- **Markdown** (`.md`) - Loaded into session context
- **Text files** (`.txt`) - Loaded into session context

**What happens**:

- CConductor discovers files in the directory
- PDFs are cached (content-based deduplication)
- Text files are copied to session knowledge
- Research coordinator analyzes your materials FIRST
- Then expands research with web/academic sources

**Common use cases**:

- Investment due diligence with company materials
- Research with existing reports/notes
- Analysis of company materials
- Academic research with your PDFs

**What happens**:

1. **Session Created**:

```
Latest session marker: session_1759420487

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Deep CConductor
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Research Question: What causes climate change?
Session: session_1759420487
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

2. **Research Phases Execute**:

```
This research will proceed through the following phases:

1. 📋 Understanding & Clarification
2. 🎯 Task Decomposition
3. 🔍 Parallel Research Execution
4. 🔄 Synthesis
5. ✅ Validation
6. 📄 Output Generation

Claude Code will now orchestrate the research agents...
```

3. **Completion**:

```
Research Complete!

Report: research-sessions/session_1759420487/research-report.md
Quality Score: 82/100 - VERY GOOD
```

### Where Results Go

After research completes:

```
research-sessions/
  session_1759420487/           ← Your session directory
    research-report.md          ← Main report (read this!)
    metadata.json               ← Session info
    raw/                        ← Raw research data
    intermediate/               ← Processing files
    final/                      ← Final outputs
```

**Quick access**:

```bash
./cconductor latest
```

### Understanding Output

Your `research-report.md` contains:

#### 1. Header

```markdown
# Research Report

Generated by: CConductor v0.1.0
Date: October 2, 2025

🔍 Research Question: What causes climate change?
📊 Quality Score: 82/100 - VERY GOOD
📚 Sources: 35 (15 academic, 14 web, 6 PDF)
⏱️  Duration: 15 minutes
```

#### 2. Quality Assessment

```markdown
Overall Score: 82/100 - VERY GOOD ✅

Breakdown:
  Confidence:        0.85/1.00  (HIGH)
  Citation Coverage: 32/35      (91%)
  Contradictions:    0           (NONE)
  Coverage:          82%         (GOOD)
```

#### 3. Executive Summary

High-level overview of findings.

#### 4. Main Findings

Detailed research with citations:

```markdown
Climate change is primarily caused by human activities [1].
CO2 from fossil fuels is the dominant driver [2]...
```

#### 5. Bibliography

Complete list of sources with URLs/references.

---

## Understanding Sessions

### What is a Session?

A **session** is one research execution. Each time you run `./cconductor "question"`, you create a new session.

**Think of it as**:

- One session = one research project
- Each session is independent
- Sessions stored permanently
- You can have unlimited sessions

### Session Naming

**Default naming**:

```
session_1759420487  ← Timestamp-based ID
```

**Why timestamps**: Ensures unique names, sorts chronologically.

**Note**: Custom session naming (e.g., `my-research-2024`) is planned for v0.2.

### Finding Your Research

#### Method 1: Use `./cconductor latest`

```bash
./cconductor latest
```

**Output**:

```
Latest session: session_1759420487
Location: /Users/you/cconductor/research-sessions/session_1759420487

✓ Report available: .../research-report.md

View with:
  cat /path/to/research-report.md
  open /path/to/research-report.md
```

#### Method 2: List all sessions

```bash
./cconductor sessions
```

**Output**: Shows all sessions, newest first

#### Method 3: Navigate directly

```bash
cd research-sessions/
ls -lt  # Shows newest first
cd session_1759420487/
cat research-report.md
```

### The `.latest` Marker

CConductor tracks your most recent session:

```bash
cat research-sessions/.latest
# Output: session_1759420487
```

**Use it**:

```bash
# Navigate to latest
cd research-sessions/$(cat research-sessions/.latest)/

# Open latest report
cat research-sessions/$(cat research-sessions/.latest)/research-report.md

# Or just use
./cconductor latest  # Simpler!
```

---

# Part 2: Core Features

## Research System

CConductor uses multiple specialized AI agents working together:

### How It Works

```
Question → Understanding → Decomposition → Research → Synthesis → Report
```

**Agents involved**:

- **Research Planner** - Understands your question, creates plan
- **Web Researcher** - Searches and analyzes web sources
- **Academic Researcher** - Finds papers and journals
- **PDF Analyzer** - Extracts insights from PDFs
- **Market Analyzer** - Business intelligence
- **Code Analyzer** - Technical analysis
- **Synthesis Agent** - Combines all findings
- **Fact Checker** - Validates claims

### Research Modes

CConductor supports different approaches (configured in `config/cconductor-modes.json`):

#### Available Modes

**default** - General balanced research

- Mixed sources
- Good for exploration
- 10-20 minutes typical

**scientific** - Academic/scientific focus

- Peer-reviewed sources
- Full citations
- 20-35 minutes typical

**market** - Business/market focus

- Industry sources
- Market data
- 10-20 minutes typical

**technical** - Technical deep-dives

- Documentation focus
- Code analysis
- 15-25 minutes typical

**literature_review** - Comprehensive academic reviews

- 20-30 papers
- Citation networks
- 30-45 minutes typical

**Note**: v0.1 automatically selects the best mode based on your question. Explicit mode selection via CLI will be available in v0.2.

---

## Working with Results

### Finding Your Report

#### Quick Method

```bash
./cconductor latest
```

#### Manual Method

```bash
# List sessions
ls research-sessions/

# Navigate to session
cd research-sessions/session_1759420487/

# Read report
cat research-report.md
```

### Viewing the Research Journal

CConductor automatically launches a **Research Journal Viewer** when you start research. This real-time dashboard shows:

- **Live Progress**: See what agents are working on right now
- **Research Timeline**: Complete history of research activities
- **Entities & Claims**: Clickable cards showing discovered entities and validated claims
- **Agent Statistics**: Papers found, searches performed, gaps identified
- **System Health**: Early warnings about potential issues
- **Cost Tracking**: Running total of API usage

**Auto-launched**: The viewer opens automatically when research begins, updating every 3 seconds.

**Manual access**: If you closed it or want to view a completed session:

```bash
./cconductor view-dashboard                    # View latest session
./cconductor view-dashboard session_123        # View specific session
```

The dashboard shows your research unfold in real-time, like watching the research process happen.

### Exporting Research Journal

Export a comprehensive markdown timeline of your research session:

```bash
# Export latest session's journal
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
bash src/utils/export-journal.sh "$SESSION_DIR/$(cat "$SESSION_DIR/.latest")"

# Export specific session
bash src/utils/export-journal.sh research-sessions/session_123
```

The exported journal (`research-journal.md`) includes:
- Complete timeline of all research activities
- All entities discovered with descriptions
- All claims validated with evidence
- All relationships identified
- Agent-specific statistics and metadata
- Tool usage history

### Understanding Reports

Your report has this structure:

#### Quality Scores

**Overall Score** (0-100):

- 90-100: EXCELLENT - Ready for any use
- 80-89: VERY GOOD - High quality
- 70-79: GOOD - Solid research
- 60-69: FAIR - Acceptable with caveats
- <60: NEEDS WORK - Run more iterations

**What affects quality**:

- **Confidence** - How certain about findings (0.0-1.0)
- **Citation Coverage** - Percentage of claims cited
- **Contradictions** - Conflicts in sources (0 is ideal)
- **Coverage** - Percentage of topic explored

#### Reading Citations

Citations show where information came from:

**In the text**:

```markdown
Docker uses container technology [1]. Released in 2013 [2].
```

**In the bibliography**:

```markdown
[1] Docker Inc. (2024). "What is Docker?" https://docs.docker.com/
[2] Merkel, D. (2014). "Docker: lightweight Linux containers..."
```

### Copying Reports

```bash
# Copy latest report
cp research-sessions/$(cat research-sessions/.latest)/research-report.md ~/Documents/
```

---

## Managing Research

### Listing Sessions

```bash
./cconductor sessions
```

Shows all your research, newest first.

### Finding Specific Research

**By recency**:

```bash
./cconductor latest              # Most recent
./cconductor sessions | head -5  # 5 most recent
```

**By date**:

```bash
ls -lt research-sessions/  # Newest first
ls -ltr research-sessions/ # Oldest first
```

**By content**:

```bash
grep -r "keyword" research-sessions/*/research-report.md
```

### Resuming Research

Continue previous research to improve quality:

```bash
./cconductor resume session_1759420487
```

**When to resume**:

- Quality score too low for your needs
- Want more depth
- Found gaps in coverage
- Need more citations

**Expected improvement**: +10-20 quality points per iteration

### Checking Status

See if research is running:

```bash
./cconductor status
```

**Possible outputs**:

- "No active sessions" - Nothing running
- "Active: cconductor-adaptive.sh..." - Research in progress

### Organizing Sessions

**Archive old research**:

```bash
mkdir -p archive/2024-q3/
mv research-sessions/session_old* archive/2024-q3/
```

---

# Part 3: Configuration

## Understanding Configuration

CConductor uses JSON configuration files stored in OS-appropriate locations.

### Configuration Philosophy

**Two types of files**:

1. **Default configs** (`.default.json`) - In project, git-tracked, never edit
2. **User configs** (`.json`) - In your home directory, customize these!

**File Locations**:

```
# Default configs (project directory - don't edit)
PROJECT_ROOT/config/*.default.json

# User configs (home directory - edit these!)
~/.config/cconductor/*.json                  (macOS/Linux)
%APPDATA%\CConductor\*.json                  (Windows)
```

**How it works**:

- CConductor loads defaults from the project
- Your customizations from `~/.config/cconductor/` override defaults
- Your configs survive project deletion/reinstallation!

### Main Configuration Files

| File | Purpose |
|------|---------|
| `cconductor-config.json` | Main research settings |
| `security-config.json` | Security profiles |
| `cconductor-modes.json` | Research mode definitions |
| `knowledge-config.json` | Knowledge sources |
| `paths.json` | Directory locations |

### Creating Custom Configurations

Use the config tool to create customizable configs:

```bash
# List available configs
./src/utils/config-loader.sh list

# Create a custom config
./src/utils/config-loader.sh init cconductor-config

# This creates ~/.config/cconductor/cconductor-config.json
# Now edit it
vim ~/.config/cconductor/cconductor-config.json
```

### Editing Configuration

**Safe editing**:

1. **Create user config** (if not exists):

   ```bash
   ./src/utils/config-loader.sh init cconductor-config
   ```

2. **Edit**:

   ```bash
   nano ~/.config/cconductor/cconductor-config.json
   ```

3. **Validate**:

   ```bash
   jq empty ~/.config/cconductor/cconductor-config.json
   # No output = valid JSON
   ```

4. **View your changes**:

   ```bash
   ./src/utils/config-loader.sh diff cconductor-config
   ```

### Resetting Configuration

If you break something:

```bash
# Delete your custom config (reverts to defaults)
rm ~/.config/cconductor/cconductor-config.json

# Or reset to defaults
./src/utils/config-loader.sh init cconductor-config
# This will warn if file exists - delete it first
```

### Finding Your Configs

```bash
# Show where a config is located
./src/utils/config-loader.sh where cconductor-config

# List all configs and their status
./src/utils/config-loader.sh list
```

---

## Security Settings

Control which domains CConductor can access.

### Security Profiles

**Edit**: `~/.config/cconductor/security-config.json` (create with `./src/utils/config-loader.sh init security-config`)

#### Strict Mode (Default) 🔒

**Best for**: Academic, sensitive data, corporate

```json
{
  "security_profile": "strict"
}
```

**What it does**:

- Auto-allows: .edu, .gov, major academic sites
- Prompts for: Unknown domains
- Blocks: Known malicious sites

**Pros**: Maximum safety  
**Cons**: More prompts

#### Permissive Mode ⚡

**Best for**: Business research, trusted networks

```json
{
  "security_profile": "permissive"
}
```

**What it does**:

- Auto-allows: Major sites (Wikipedia, GitHub, etc.)
- Prompts less frequently
- Blocks: Known malicious sites

**Pros**: Fewer prompts, faster  
**Cons**: Less control

#### Max Automation Mode 🚀

**Best for**: Testing, sandboxed environments **ONLY**

```json
{
  "security_profile": "max_automation"
}
```

⚠️ **Warning**: Only use in VMs or containers!

**Pros**: Minimal prompts  
**Cons**: Less safety

### Changing Your Profile

1. **Open config**:

   ```bash
   nano config/security-config.json
   ```

2. **Change value**:

   ```json
   "security_profile": "strict"       // or
   "security_profile": "permissive"   // or
   "security_profile": "max_automation"
   ```

3. **Save and close**

### When You Get Prompted

```
⚠️  Security Check: Unfamiliar Domain

Domain: research-example-site.com
Context: Fetching research data

[A] Allow once
[S] Allow always
[D] Deny
```

**Choose**:

- **A (Allow once)** - Safe default when unsure
- **S (Allow always)** - For sites you trust and use often
- **D (Deny)** - For suspicious domains

**Decision guide**:

- ✅ Professional domain? → Allow
- ✅ HTTPS? → Good sign
- ✅ Matches research? → Allow
- ❌ Suspicious URL? → Deny

---

## Adding Custom Knowledge

Teach CConductor about your domain.

### Quick Start

1. **Create file**:

   ```bash
   nano knowledge-base-custom/my-company.md
   ```

2. **Add knowledge**:

   ```markdown
   ## Overview
   Brief description of what this covers.

   ## Key Concepts
   - Term 1: Definition
   - Term 2: Definition

   ## Important Facts
   - Fact about your domain
   ```

3. **Save and use**:

   ```bash
   ./cconductor "question about your domain"
   ```

CConductor automatically discovers and uses it!

### Complete Example

**File**: `knowledge-base-custom/acme-products.md`

```markdown
## Overview
ACME Corp product line and market positioning.

## Product Portfolio
- **ACME Widget Pro**: Enterprise, $999/mo, 500+ customers
- **ACME Widget Lite**: SMB, $99/mo, 2000+ customers

## Market Position
- Target: Mid-market B2B SaaS
- Geography: North America, expanding EMEA
- Competitors: WidgetCo, FastWidget

## Key Differentiators
- Only provider with AI integration
- 99.9% uptime SLA (competitors: 99.5%)
- 24/7 support included

## Important Dates
- Founded: 2015
- Series C: $50M, 2023
```

Now when you research ACME, CConductor knows your products!

### Where to Put Files

```
knowledge-base-custom/
  my-company.md
  my-industry.md
  regional-info.md
```

CConductor finds all `.md` files automatically.

### Best Practices

**Do**:

- ✅ Be specific: "Founded 2015" not "recently"
- ✅ Include numbers: "$50M Series C"
- ✅ Cite sources: "According to..."
- ✅ Add dates: "As of 2024..."

**Don't**:

- ❌ Too vague: "Popular product"
- ❌ No sources: Unverifiable claims
- ❌ Outdated: Old stats without dates

---

# Part 4: Advanced Usage

## Quality & Citations

### Understanding Quality Scores

Every session gets a quality assessment:

```
Overall Score: 85/100 - EXCELLENT ✅

Breakdown:
  Confidence:        0.87/1.00  (HIGH)
  Citation Coverage: 45/50      (90%)
  Contradictions:    0           (NONE)
  Coverage:          85%         (GOOD)
```

**What each metric means**:

- **Confidence** (0.0-1.0) - How certain about findings
- **Citation Coverage** (X/Y) - Claims with citations
- **Contradictions** - Unresolved conflicts (0 is ideal)
- **Coverage** (%) - Percentage of topic explored

### When Quality is "Good Enough"

**For academic papers**:

- Minimum: 80/100
- Citations: 90%+
- Contradictions: 0-1

**For business decisions**:

- Minimum: 70/100
- Citations: 70%+
- Contradictions: 0-2

**For learning**:

- Any score acceptable
- Use judgment

### Improving Quality

**Most effective method**:

```bash
./cconductor resume session_123
```

**What happens**:

- Identifies gaps
- Adds more sources
- Resolves contradictions
- Improves coverage

**Expected improvement**: +10-20 points per iteration

---

## Multi-Session Research

Build comprehensive understanding through multiple sessions:

### Progressive Approach

```bash
# 1. Overview
./cconductor "Quantum computing overview"

# 2. Deep dive
./cconductor "Quantum error correction methods"

# 3. Applications
./cconductor "Quantum computing applications"
```

**Result**: Three focused reports providing comprehensive coverage.

### Comparative Approach

Research same topic from different angles:

```bash
# Academic perspective
./cconductor "AI impact on employment - academic research"

# Business perspective  
./cconductor "AI impact on employment - market analysis"
```

---

# Part 5: Tips & Best Practices

## Writing Good Research Questions

Quality of your question dramatically affects results.

### Specific vs. Vague

**Vague** → Poor results:

- ❌ "Tell me about AI"
- ❌ "Market research"

**Specific** → Great results:

- ✅ "Latest advances in large language models 2023-2024"
- ✅ "Total addressable market for SaaS CRM North America 2024"

### Question Formula

**Good questions include**:

1. **What** you want to know
2. **Scope** (specific aspect)
3. **Timeframe** (when relevant)
4. **Geography** (when relevant)

**Template**:

```
"What [specific aspect] of [topic] in [context/geography]
as of [timeframe]?"
```

**Example**:

```
"What are the key technical challenges in quantum error
correction as of 2024, including current solutions?"
```

### Before/After Examples

#### Technology

**Before**: "Explain Kubernetes"  
**After**: "How does Kubernetes handle container orchestration, including scheduling and scaling?"

#### Market Research

**Before**: "Market size"  
**After**: "What is the total addressable market for AI-powered customer service in 2024?"

#### Academic

**Before**: "CRISPR research"  
**After**: "What are the latest advances in CRISPR gene editing for therapeutic applications, 2023-2024?"

---

## Organizing Research

### Archive Structure

```bash
mkdir -p archive/2024/{q1,q2,q3,q4}/
```

**Archive by quarter**:

```bash
mv research-sessions/2024-01-* archive/2024/q1/
mv research-sessions/2024-04-* archive/2024/q2/
```

### Backup Strategy

**What to backup**:

- `~/.config/cconductor/` - Your configs
- `~/Library/Application Support/CConductor/` (macOS) or `~/.local/share/cconductor/` (Linux) - Your data
  - Research sessions
  - Custom knowledge
  - Citations database

**Simple backup**:

```bash
# macOS
tar -czf cconductor-backup-$(date +%Y%m%d).tar.gz \
  ~/.config/cconductor/ \
  ~/Library/Application\ Support/CConductor/

# Linux
tar -czf cconductor-backup-$(date +%Y%m%d).tar.gz \
  ~/.config/cconductor/ \
  ~/.local/share/cconductor/
```

**Or backup specific items**:

```bash
# Just your configs
tar -czf cconductor-configs-$(date +%Y%m%d).tar.gz ~/.config/cconductor/

# Just research sessions (if you know the location)
tar -czf sessions-backup.tar.gz ~/Library/Application\ Support/CConductor/research-sessions/
```

---

# Appendix

## Command Reference

| Command | Purpose |
|---------|---------|
| `./cconductor "question"` | Start new research |
| `./cconductor latest` | Show most recent session |
| `./cconductor sessions` | List all sessions |
| `./cconductor resume SESSION` | Continue research |
| `./cconductor status` | Check if research running |
| `./cconductor configure` | View configuration |
| `./cconductor --init` | Run/re-run initialization |
| `./cconductor --help` | Show help |
| `./cconductor --version` | Show version |

---

## Configuration Files Overview

**Location**: `~/.config/cconductor/` (macOS/Linux) or `%APPDATA%\CConductor\` (Windows)

| File | Purpose | Edit? | Create With |
|------|---------|-------|-------------|
| `cconductor-config.json` | Main settings | Rarely | `./src/utils/config-loader.sh init cconductor-config` |
| `security-config.json` | Security profiles | Often | `./src/utils/config-loader.sh init security-config` |
| `cconductor-modes.json` | Mode definitions | Rarely | `./src/utils/config-loader.sh init cconductor-modes` |
| `knowledge-config.json` | Knowledge sources | Sometimes | `./src/utils/config-loader.sh init knowledge-config` |
| `paths.json` | Directory paths | Rarely | `./src/utils/config-loader.sh init paths` |

**Default configs** (in project directory): `PROJECT_ROOT/config/*.default.json` - Never edit these!

**How configs work**:

1. CConductor loads defaults from project
2. Your user config overrides defaults
3. Your configs survive project updates

---

## Glossary

**Session**: One research execution

**Quality Score**: 0-100 rating of research reliability

**Confidence**: 0.0-1.0 measure of certainty about findings

**Citation**: Reference to source material

**Bibliography**: Complete list of sources at end of report

**Mode**: Research approach (default, scientific, market, technical, literature_review)

**Security Profile**: Setting controlling domain access (strict, permissive, max_automation)

**Custom Knowledge**: Domain expertise you add in `knowledge-base-custom/`

**.latest**: File containing ID of most recent session

---

## What's Coming

### v0.2 Planned Features

The following features are **planned but not yet available in v0.1**:

🚧 **CLI Options** (not yet implemented):

```bash
# These will work in v0.2, but DO NOT work in v0.1:
./cconductor "question" --mode scientific    # Explicit mode selection
./cconductor "question" --speed fast         # Control research depth
./cconductor "question" --output html        # HTML/JSON output formats
./cconductor "question" --name my-research   # Custom session names
./cconductor "question" --iterations 5       # Control iteration count
./cconductor "question" --interactive        # Guided research mode
./cconductor "question" --quiet              # Minimal output
```

**Current v0.1 workarounds**:

- Mode selection: Automatic based on keywords in your question
- Speed control: Edit `config/cconductor-config.json` settings
- Session naming: Use timestamp-based names (session_TIMESTAMP)

🚧 **Enhanced Output**:

- HTML reports with styling
- JSON export for processing
- Multiple citation styles (APA, MLA, Chicago)
- BibTeX export for reference managers

🚧 **Better UX**:

- Real-time progress indicators
- Enhanced session management UI
- Interactive configuration wizard
- Session tagging and search

See internal roadmap for complete feature list.

---

## Next Steps

**Continue Learning**:

- [Quick Reference](QUICK_REFERENCE.md) - Command cheat sheet
- [Citations Guide](CITATIONS_GUIDE.md) - Deep dive on citations
- [Security Guide](SECURITY_GUIDE.md) - Advanced security
- [Quality Guide](QUALITY_GUIDE.md) - Mastering quality
- [Custom Knowledge](CUSTOM_KNOWLEDGE.md) - Adding domain expertise
- [PDF Research](PDF_RESEARCH_GUIDE.md) - Working with academic papers

**Start Researching**:

```bash
./cconductor "your question"
```

**Get Help**:

- Problems? → [Troubleshooting](TROUBLESHOOTING.md)
- Questions? → README.md for overview

---

**Happy researching with CConductor!** 🔍
