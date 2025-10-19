# Usage Guide - CConductor

**How to use CConductor for AI-powered research**

Version: 0.1.0

---

## Quick Start

### Installation

**Easiest way:**

```bash
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash
```

Then use from anywhere:

```bash
cconductor "Your research question here"
```

**Manual install:**

```bash
git clone https://github.com/yaniv-golan/cconductor.git
cd cconductor
./cconductor "Your research question here"
```

**Note:** If you get "Permission denied", run: `chmod +x cconductor`

### What Happens When You Run CConductor

**First time:**

1. Setup runs automatically (~5 seconds)
2. Dependencies auto-installed (if needed)
3. Session created automatically
4. Research begins immediately
5. Progress shown in terminal
6. Report generated when complete

**Subsequent runs:**

1. Session created automatically
2. Research begins immediately
3. Progress shown in terminal
4. Report generated when complete

**Example**:

```bash
./cconductor "What is Docker containerization?"
```

**Complex queries from files**:

For multi-part research with structured context:

```bash
./cconductor --question-file research-query.md
```

See [Complex Research](#complex-research-from-files) section for details.

### Viewing Results

```bash
# Show latest research
./cconductor latest

# List all sessions
./cconductor sessions

# View specific report
cat research-sessions/session_1759420487/output/mission-report.md
```

---

## How CConductor Works

### The Research Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│  1. Understanding & Decomposition                            │
│     • Analyzes research question                             │
│     • Detects research type (academic, market, etc.)         │
│     • Creates focused sub-tasks                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  2. Parallel Research (multi-agent)                          │
│     • Web Researcher → Web search & analysis                 │
│     • Academic Researcher → Papers & journals                │
│     • PDF Analyzer → Document analysis                       │
│     • Market Analyzer → Business intelligence                │
│     • Code Analyzer → Technical research                     │
│     • Specialist agents work simultaneously                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  3. Synthesis & Integration                                  │
│     • Combines findings from all agents                      │
│     • Resolves contradictions                                │
│     • Identifies gaps                                        │
│     • Builds knowledge graph                                 │
│     • Tracks citations and sources                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  4. Validation & Quality Assessment                          │
│     • Fact-checking against sources                          │
│     • Citation coverage analysis                             │
│     • Confidence scoring                                     │
│     • Gap identification                                     │
│     • Quality gate enforcement                               │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  5. Report Generation                                        │
│     • Formatted report with citations                        │
│     • Complete bibliography                                  │
│     • Quality score and breakdown                            │
│     • Markdown output (HTML/JSON in v0.2)                    │
└─────────────────────────────────────────────────────────────┘
```

### Research Modes

CConductor supports different research approaches (configured in `config/cconductor-modes.json`):

#### Available Modes

**default** - General research mode

- Balanced approach
- Mixed source types
- Good for exploration
- 10-20 minutes typical

**scientific** - Academic/scientific research

- Peer-reviewed sources
- Full citations
- Methodology focus
- 20-35 minutes typical

**market** - Business/market research

- Business sources
- Market data focus
- Industry reports
- 10-20 minutes typical

**technical** - Technical deep-dives

- Official documentation
- Code analysis
- Architecture focus
- 15-25 minutes typical

**literature_review** - Comprehensive academic reviews

- Systematic analysis
- 20-30 papers
- Citation networks
- 30-45 minutes typical

**Note**: v0.1 uses automatic mode selection based on your question. Explicit mode selection via CLI options will be available in v0.2.

---

## Output and Results

### Where Results Go

All research is saved in `research-sessions/`:

```
research-sessions/
  session_1759420487/          # Timestamp-based ID
    output/                    # User-facing deliverables
      mission-report.md        # Main report ← Read this!
      research-journal.md      # Sequential journal timeline
    artifacts/                 # Diagnostics & agent artifacts
      manifest.json            # Agent artifact registry
      quality-gate.json        # Quality gate diagnostics
      quality-gate-summary.json
    metadata.json              # Session metadata
    raw/                       # Raw research data
      quality-remediation-*.json # Auto remediation findings (present after gate retries)
    intermediate/              # Processing artifacts
```

### Finding Your Latest Research

**Quick method**:

```bash
./cconductor latest
```

**Output shows**:

- Session ID
- Location
- Report status
- Quick view commands

**Manual method**:

```bash
# List all sessions
ls -lt research-sessions/

# Read latest report
cat research-sessions/$(cat research-sessions/.latest)/output/mission-report.md
```

### Understanding Your Report

Every report includes:

#### 1. Header with Metadata

```markdown
Generated by: CConductor v0.1.0
Date: October 2, 2025
Session: session_1759420487

🔍 Research Question: What is Docker containerization?
📊 Quality Score: 82/100 - VERY GOOD
📚 Sources: 35 (15 academic, 14 web, 6 PDF)
⏱️  Duration: 15 minutes
```

#### 2. Quality Assessment

```markdown
Research Quality Assessment

Overall Score: 82/100 - VERY GOOD ✅

Breakdown:
  Confidence:        0.85/1.00  (HIGH)
  Citation Coverage: 32/35      (91%)
  Contradictions:    0           (NONE)
  Coverage:          82%         (GOOD)

Recommendation: Ready for use
```

**Quality scores**:

- **90-100**: EXCELLENT - Publication ready
- **80-89**: VERY GOOD - High confidence
- **70-79**: GOOD - Solid research
- **60-69**: FAIR - Usable with caveats
- **<60**: NEEDS WORK - Run more iterations

If the quality gate blocks completion, CConductor will skip this report section, mark the session as `blocked_quality_gate`, and save detailed remediation guidance to `artifacts/quality-gate.json`. Review the flagged claims, resume the session, and the gate will rerun automatically once fixes are in place.

#### 3. Executive Summary

High-level overview of findings.

#### 4. Main Findings

Detailed research results with citations.

**Citations format**:

```markdown
Docker uses containerization to isolate applications [1].
Released in 2013 [2], it became widely adopted [3].
```

#### 5. Bibliography

Complete list of sources:

```markdown
## References

[1] Docker Inc. (2024). "What is Docker?" 
    https://docs.docker.com/

[2] Merkel, D. (2014). "Docker: lightweight Linux 
    containers..." Linux Journal.
```

---

## Configuration

### Security Settings

Control which domains CConductor can access.

**Configuration file**: `config/security-config.json`

**Three profiles**:

```json
{
  "security_profile": "strict"       // Maximum safety (default)
}
```

**Available profiles**:

- **strict** - Academic/sensitive, prompts for unknown domains (default)
- **permissive** - Business research, fewer prompts
- **max_automation** - Testing only, minimal prompts (use in VMs)

**To change**:

```bash
# Edit config file
nano config/security-config.json

# Change profile value, save, and close
```

See [Security Guide](docs/SECURITY_GUIDE.md) for detailed information.

### Research Preferences

**Configuration file**: `config/cconductor-config.json`

Controls:

- Source preferences
- Agent behavior
- Quality thresholds
- Logging and audit settings

See [Configuration Reference](docs/CONFIGURATION_REFERENCE.md) for all options.

### Custom Knowledge

Add your own domain expertise to CConductor.

**Create file**: `knowledge-base-custom/my-domain.md`

**Format** (simple markdown):

```markdown
## Overview
What this knowledge covers.

## Key Concepts
- Term 1: Definition
- Term 2: Definition

## Important Facts
- Fact about your domain
```

**Automatic discovery**: CConductor finds and uses all `.md` files in `knowledge-base-custom/`

See [Custom Knowledge Guide](docs/CUSTOM_KNOWLEDGE.md) for detailed guide.

---

## Command Reference

### Basic Commands

```bash
# Start research
./cconductor "question"

# View latest
./cconductor latest

# List sessions
./cconductor sessions

# Resume research
./cconductor resume SESSION_ID

# Check status
./cconductor status

# View configuration
./cconductor configure

# Run/re-run initialization
./cconductor --init
./cconductor --init --yes   # Non-interactive for scripts

# Help
./cconductor --help

# Version
./cconductor --version
```

### Examples

```bash
# Research any topic
./cconductor "What is quantum computing?"

# Academic research
./cconductor "Latest mRNA vaccine research"

# Business research
./cconductor "AI coding assistant market landscape"

# Technical research
./cconductor "Kubernetes architecture and components"
```

---

## Advanced Usage

### Complex Research from Files

For multi-part research queries with structured context, use markdown files instead of command-line text:

```bash
./cconductor --question-file research-query.md
```

**Why use question files:**

- **Complex queries**: Multiple sub-questions with structured background
- **Reusable templates**: Save and version-control research protocols
- **Rich formatting**: Use markdown headers, lists, and emphasis
- **No escaping**: Avoid command-line quoting issues
- **Embedded context**: Include keywords, expected outputs, and search strategies

**Example question file** (`research-query.md`):

```markdown
# Research Query: Metabolic Psychiatry Evidence

## Research Objective
Validate or invalidate the hypothesis that metabolic interventions show 
broad efficacy across psychiatric disorders.

## Core Questions

### 1. Treatment Response Prediction
Does pre-treatment metabolic capacity predict treatment response better 
than genetic risk scores?

**Search for:**
- Studies comparing metabolic markers to polygenic risk scores
- Meta-analyses of treatment response predictors
- Precision psychiatry studies

### 2. Transdiagnostic Efficacy
Do metabolic interventions show broad, cross-diagnostic efficacy?

**Search for:**
- Exercise intervention trials across disorders
- Ketogenic diet studies in mental health
- Meta-analyses of lifestyle interventions

## Keywords
- Metabolic psychiatry
- Treatment response prediction
- Transdiagnostic interventions
- Exercise psychiatry meta-analysis

## Expected Outputs
- Evidence organized by prediction
- Quality assessment of supporting/contradicting evidence
- Identification of key research gaps
```

**Combine with other features:**

```bash
# Question file + non-interactive mode
./cconductor --question-file research-query.md --non-interactive

# Question file + local materials
./cconductor --question-file research-query.md --input-dir ./papers/
```

**Real example**: See `research-sessions/IHPH_research_query.md` for a comprehensive research protocol.

### Resuming Research

Continue a previous session to improve quality:

```bash
./cconductor resume session_1759420487
```

**When to resume**:

- Quality score lower than needed
- Want more depth or coverage
- Found gaps in the research
- Need more citations

**Expected improvement**: +10-20 quality points per iteration

### Multi-Session Research

Build comprehensive understanding through multiple focused sessions:

```bash
# Overview first
./cconductor "Quantum computing overview"

# Then specific aspects
./cconductor "Quantum error correction methods"
./cconductor "Quantum computing applications"
```

### PDF Research

Research with PDF documents:

1. Create pdfs directory:

   ```bash
   mkdir pdfs/
   ```

2. Add your PDFs:

   ```bash
   cp paper1.pdf paper2.pdf pdfs/
   ```

3. Research referencing PDFs:

   ```bash
   ./cconductor "Summarize key findings from papers in pdfs/"
   ```

---

## Session Management

### Listing Sessions

```bash
./cconductor sessions
```

Shows all research sessions, newest first.

### Finding Specific Research

**By recency**:

```bash
./cconductor latest              # Most recent
./cconductor sessions | head -5  # 5 most recent
```

**By content**:

```bash
grep -r "keyword" research-sessions/*/output/mission-report.md
```

### Organizing Sessions

**Archive old research**:

```bash
mkdir -p archive/2024-q3/
mv research-sessions/session_old* archive/2024-q3/
```

---

## Quality and Citations

### Understanding Quality Scores

Every session receives a quality assessment with:

- **Overall Score** (0-100) - Reliability rating
- **Confidence** (0.0-1.0) - Certainty about findings
- **Citation Coverage** (X/Y) - Claims with citations
- **Contradictions** - Unresolved conflicts in sources
- **Coverage** (%) - Percentage of topic explored

See [Quality Guide](docs/QUALITY_GUIDE.md) for detailed explanation.

### Quality Gate Failures

- In the default **advisory** mode, reports still complete but the heading shows a “Quality Issues Detected” banner and the session status becomes `completed_with_advisory`.
- Inspect `research-sessions/<session>/artifacts/quality-gate.json` (full diagnostics) or `artifacts/quality-gate-summary.json` (compact summary) for the list of failing claims, reasons, and suggested fixes.
- Address the issues—adding independent sources, refreshing stale evidence, improving confidence—and run `./cconductor resume <session>` to re-run the gate.
- Set `mode` to `enforce` in `~/.config/cconductor/quality-gate.json` if you want runs to stop entirely until everything passes.

### Cached Web Sources

- Successful WebFetch calls are written to the shared cache (`$cache_dir/web-fetch/`) and surfaced in each agent prompt under “Cached Sources Available”.
- Cached files are materialized inside `<session>/cache/web-fetch/` and can be inspected with the `Read` tool before hitting the network again.
- To force a fresh fetch when a cached copy is outdated, append `?fresh=1` (or `?refresh=1`) to the URL you provide to WebFetch.

### Citations and Bibliography

Every report includes:

**In-text citations**:

```markdown
Docker uses containerization [1]. Released in 2013 [2].
```

**Complete bibliography** at end of report.

See [Citations Guide](docs/CITATIONS_GUIDE.md) for details.

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| "Command not found" | `cd` to cconductor directory |
| "Permission denied" | `chmod +x cconductor` |
| "Config error" | `cp config/*.default.json config/` |
| "Session not found" | Use `./cconductor sessions` to list |
| "Quality too low" | `./cconductor resume SESSION_ID` |

### Getting Help

1. **Check error message** - CConductor provides helpful errors
2. **Review logs** - Check `logs/` directory
3. **Consult docs** - See [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
4. **File issue** - GitHub Issues if problem persists

---

## What's Coming

### v0.2 Planned Features

The following features are **planned but not yet available in v0.1**:

🚧 **CLI Options** - Advanced command-line options (not yet implemented):

```bash
# These will work in v0.2, but DO NOT work in v0.1:
./cconductor "question" --mode scientific    # Explicit mode selection
./cconductor "question" --speed fast         # Control research depth
./cconductor "question" --output html        # HTML/JSON output formats
./cconductor "question" --name my-research   # Custom session names
```

**Current v0.1 alternatives**:

- Mode: Automatic detection based on question keywords
- Speed: Configure via `config/cconductor-config.json`
- Session naming: Timestamp-based (session_TIMESTAMP)

🚧 **Enhanced Output** - Multiple formats:

- HTML reports with styling
- JSON export for processing
- Multiple citation styles (APA, MLA, Chicago)
- BibTeX export

🚧 **Better UX** - Improved experience:

- Real-time progress indicators
- Enhanced session management
- Interactive configuration wizard

See project roadmap for more planned features.

---

## Documentation

### For Users

- **[User Guide](docs/USER_GUIDE.md)** - Comprehensive guide
- **[Quick Reference](docs/QUICK_REFERENCE.md)** - Command cheat sheet
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Fix problems

### Feature Guides

- **[Citations Guide](docs/CITATIONS_GUIDE.md)** - Using citations
- **[Security Guide](docs/SECURITY_GUIDE.md)** - Security configuration
- **[Quality Guide](docs/QUALITY_GUIDE.md)** - Understanding quality
- **[Custom Knowledge](docs/CUSTOM_KNOWLEDGE.md)** - Adding expertise
- **[PDF Research](docs/PDF_RESEARCH_GUIDE.md)** - Working with papers

### Reference

- **[Configuration Reference](docs/CONFIGURATION_REFERENCE.md)** - All configs

---

**Start researching**: `./cconductor "your question"` 🔍
