![CConductor Banner](assets/banner.png)

# CConductor 🔍

**AI Research, Orchestrated**

CConductor is a multi-agent AI research system that conducts comprehensive, adaptive research on any topic. Powered by Claude and specialized AI agents, it finds, analyzes, and synthesizes information from academic papers, web sources, PDFs, and code repositories—delivering well-cited, validated research reports.

---

## Why CConductor?

- 🧠 **Multi-Agent Intelligence** - Specialized agents for planning, research, synthesis, and validation work together
- 📚 **Multi-Source Research** - Handles academic papers, web content, PDFs, code, and market data
- ✅ **Built-In Validation** - Automatic fact-checking, citation tracking, and quality assessment
- 🎯 **Adaptive Research** - Identifies gaps, explores leads, and improves iteratively until high confidence
- 📊 **Quality Scores** - Know exactly how reliable your research is (0-100 with detailed breakdown)
- 🔒 **Configurable Security** - Control which domains to trust with flexible security profiles
- 🌍 **Cross-Platform** - Works on macOS, Linux, and Windows (WSL2)

---

## Getting Started

### Prerequisites
- **Claude Code CLI access** – You need a Claude Pro/Max subscription or API credits plus the Claude Code CLI (run `claude`, then `/status` to confirm your account). Install via the native script (`curl -fsSL https://claude.ai/install.sh | bash`) or, if you already have Node.js 18+, `npm install -g @anthropic-ai/claude-code`.
- **Supported platforms** – macOS 10.15+, Linux distros with GNU coreutils (Ubuntu 20.04+, Debian 10+, Fedora 33+), or Windows via WSL2.
- **System packages** – Bash ≥ 4.0, `git`, `jq`, `curl`, `bc`, and `ripgrep`. The quick-start commands below install them for you.
- **Python 3** – Used for knowledge graph tooling (pre-installed on most systems).
- **Optional (installed in quick start):** `dialog` for the full interactive TUI experience.

### Quick Start (Non-Technical)
Use the commands for your platform to go from zero to your first mission. Replace `sudo` with your preferred privilege escalation tool if needed.

#### macOS (Homebrew)
```bash
# 1. Install Claude Code CLI and authenticate
curl -fsSL https://claude.ai/install.sh | bash
claude
# In the Claude prompt (looks like ">"), type:
#   /login    # opens browser-based OAuth flow
# After the browser flow completes, type:
#   /status   # confirms account, version, and connectivity

# 2. Install required system packages
# (Install Homebrew first if you do not already have it: 
#  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)")
brew install bash jq curl bc ripgrep git dialog

# 3. Install CConductor (accept the PATH prompt when offered)
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash

# 4. Launch the guided experience
cconductor
```

#### Ubuntu / Debian / WSL2
```bash
# 1. Install Claude Code CLI and authenticate
curl -fsSL https://claude.ai/install.sh | bash
claude
# In the Claude prompt (looks like ">"), type:
#   /login
#   /status

# 2. Install required system packages
sudo apt-get update
sudo apt-get install -y git jq curl bc ripgrep dialog

# 3. Install CConductor (installs to ~/.cconductor by default)
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash

# 4. Launch the guided experience
cconductor
```

> WSL2 users should run the Linux commands inside their WSL distribution. The quick installer does not install the Claude CLI or other system packages, so completing steps 1-2 first is required.

> Prefer a Homebrew-managed install on macOS? Jump to [Option 2: Homebrew (macOS)](#option-2-homebrew-macos) in the Installation Options section.

### Verify Installation
```bash
claude
#   /status          # Confirms CLI version, account, and connectivity
cconductor --help    # Shows available commands (use ./cconductor if running from a cloned repo)
```

### Run Your First Mission
- **Interactive mode:** `cconductor` (or `./cconductor`) launches the dialog-based TUI for guided setup. Install `dialog` for the full menu experience.
- **Direct command:** `cconductor "What is quantum computing?"`
- **Choose a mission type:**
  ```bash
  cconductor "your question" --mission market-research       # Market analysis
  cconductor "your question" --mission academic-research     # Scholarly sources
  cconductor "your question" --mission competitive-analysis  # Competitor research
  cconductor "your question" --mission technical-analysis    # Technical deep-dive
  # Default: general-research (flexible for any topic)
  ```
- **View your results:** `cconductor sessions latest`

On first run, CConductor automatically creates the session workspace and configuration (about five seconds). Research reports live under `research-sessions/` with full citations and quality assessments.

### Platform Notes
- **Supported operating systems:** macOS 10.15+, Linux distributions with GNU coreutils (Ubuntu 20.04+, Debian 10+, Fedora 33+), and Windows via WSL2.
- **Known limitations:** FreeBSD/OpenBSD use a different `date` implementation that can break timestamp formatting; Windows native shells are not supported—run inside WSL2 instead.
- **Time formatting:** All scripts use `date -u +"%Y-%m-%dT%H:%M:%SZ"`, which works on macOS (BSD date) and GNU/Linux. Adjust the command if your environment uses a non-standard `date`.

---

## What You Can Do

### Academic Research

Comprehensive research with full citations and bibliography.

```bash
cconductor "Latest advances in CRISPR gene editing 2023-2024"
```

### Complex Research from Files

For multi-part research queries with structured context, use a markdown file:

```bash
cconductor --question-file research-query.md
```

**Benefits:**
- Structured queries with background, sub-questions, and keywords
- Reusable research templates
- Version control for your research questions
- No command-line escaping issues

**Example file:**
```markdown
# Research Query: AI Safety Mechanisms

## Background
Need to understand current state of AI alignment research...

## Core Questions
1. What are the main approaches to AI alignment?
2. Which approaches show most promise?
3. What are the open challenges?

## Keywords
- AI alignment, RLHF, Constitutional AI...
```

### Research with Local Files

Analyze your own PDFs, documents, and notes alongside web research.

```bash
# Analyze pitch decks
cconductor "Evaluate this pitch deck" --input-dir ./pitch-materials/

# Research with context documents
cconductor "Summarize findings" --input-dir ~/Documents/research-reports/
```

**Supported formats:**

- PDFs (`.pdf`) - Automatically cached and analyzed
- Markdown (`.md`) - Loaded into session context
- Text files (`.txt`) - Loaded into session context

### Market Analysis

Business intelligence with market data and competitive insights.

```bash
cconductor "SaaS CRM market size and growth 2024"
```

### Technical Deep-Dives

Detailed technical research with architecture and examples.

```bash
cconductor "How does Docker containerization work?"
```

### General Research

Balanced research on any topic.

```bash
cconductor "What causes climate change?"
```

---

## Features

### Core Capabilities

- **Adaptive Intelligence** - Dynamic knowledge graph tracks findings and identifies gaps
- **Multi-Agent System** - 10+ specialized agents for different research domains
- **PDF Research** - Automatic PDF caching and full-text analysis
- **Academic Databases** - Direct integration with arXiv, Semantic Scholar, PubMed
- **Parallel Execution** - Multiple research tasks run simultaneously
- **Citations & Bibliography** - Automatic source tracking and reference generation
- **Quality Assessment** - Every session receives a comprehensive quality score
- **Complete Audit Trail** - Every source and decision is logged

### Key Features

- ✨ **Citations & Bibliography** - Automatic source tracking and reference generation
- 📺 **Real-Time Dashboard** - Live research journal viewer showing progress, entities, claims, and agent activities (auto-launches)
- 📝 **Journal Export** - Export comprehensive markdown timeline of your research with all findings and metadata
- 📁 **Local File Analysis** - Analyze your own PDFs, markdown, and text files with `--input-dir`
- 🔒 **Configurable Security** - Three profiles (strict/permissive/max_automation)
- 📊 **Quality Validation** - Hard gating on every mission with automatic remediation passes; failures produce diagnostics in `artifacts/quality-gate.json` before prompting for any remaining manual fixes
- ♻️ **Web Fetch Cache** - Successful WebFetch calls are cached and surfaced to agents; reuse cached files via `Read` and append `?fresh=1` when a live refresh is required
- ♻️ **Web Search Cache** - WebSearch queries store snippets in the shared cache; check `Cached Sources Available` or run `bash library-memory/show-search.sh --query "<terms>"` before launching a new search.
- 🧰 **Cache Controls** - Run once with `--no-cache` (or selectively `--no-web-fetch-cache`, `--no-web-search-cache`) when you need live results without touching the caches.
- 🌍 **Cross-Platform Support** - Works on Windows, macOS, and Linux
- 📖 **Extensible Knowledge** - Add your own domain expertise without modifying code
- 🔍 **Progress Tracking** - See what's happening during research
- 💬 **Better Error Messages** - Clear explanations and recovery steps
- 🧮 **Safe Calculations** - Accurate math using bc (arbitrary precision calculator), not LLM estimation

---

### Quality Gate Enforcement

Every mission finishes with an automated quality gate that reviews each claim for:

- **Evidence coverage** – minimum sources and independent domains
- **Source trust** – weighted credibility (peer-reviewed, official, etc.)
- **Confidence and recency** – claim confidence and time-bound evidence

The gate now defaults to **advisory mode**:

- Reports still complete, but the top of the document shows a “Quality Issues Detected” banner when thresholds are missed.
- Sessions end with status `completed_with_advisory`, and the full diagnostics live in `artifacts/quality-gate.json` plus a compact summary in `artifacts/quality-gate-summary.json`.
- The orchestrator (or a manual resume) can read those files to follow the remediation checklist and rerun the gate.
- User-facing deliverables live in `report/` (mission report, research journal); supporting diagnostics remain in `artifacts/`.

Switch the config to `mode: "enforce"` if you prefer to block finalization until every threshold is satisfied. All thresholds and mode settings live in `~/.config/cconductor/quality-gate.json`.

---

## Installation Options

> Completed the prerequisites above? Pick the workflow that fits your environment and compliance requirements.

### Option 1: Quick Install Script (Recommended for individual laptops)
```bash
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash
```
**What it does**
- Clones the latest release into `~/.cconductor` (or a path you pass as the first argument).
- Runs `cconductor --init --yes` to prepare caches, config directories, and quality gates.
- Prompts to add `cconductor` to your `PATH` so you can run it from anywhere.

**Remember:** This script expects the Claude Code CLI and system packages from the quick-start steps to already be installed.

### Option 2: Homebrew (macOS)
```bash
brew tap yaniv-golan/cconductor
brew install cconductor

# Install Claude Code CLI (native installer recommended)
curl -fsSL https://claude.ai/install.sh | bash
claude
#   /login
#   /status

# Install supporting tools if you skipped the quick start
brew install bash jq curl bc ripgrep git
```
Homebrew installs the CLI into your PATH automatically. Re-run `claude`, then `/status`, along with `cconductor --help` to verify everything is available.

### Option 3: Manual Git Clone (Advanced / Contributors)
```bash
git clone https://github.com/yaniv-golan/cconductor.git
cd cconductor

# Prepare the workspace (non-interactive)
./cconductor --init --yes

# Run from the repo root
./cconductor "your research question"
```
Use this path if you plan to contribute code, track the `main` branch closely, or run from a fork. Add the repository directory to your PATH if you want to call `cconductor` without the leading `./`.

### Option 4: Docker & CI Pipelines
- **Quick start (existing Claude credentials):**
  ```bash
  docker run -v ~/.claude:/root/.claude \
    -v ~/research:/data/research-sessions \
    ghcr.io/yaniv-golan/cconductor:latest \
    "What is quantum computing?"
  ```
- **Using an API key in automation:**
  ```bash
  echo "ANTHROPIC_API_KEY=sk-ant-xxx" > .env
  docker run --env-file .env \
    -v ~/research:/data/research-sessions \
    ghcr.io/yaniv-golan/cconductor:latest \
    "What is quantum computing?"
  ```
- **Production (Docker Swarm example):**
  ```bash
  echo "sk-ant-xxx" | docker secret create anthropic_api_key -
  docker service create \
    --secret anthropic_api_key \
    --mount type=volume,source=research-data,target=/data \
    ghcr.io/yaniv-golan/cconductor:latest
  ```
Review [docs/DOCKER.md](docs/DOCKER.md) for extended configuration, health checks, and volume layouts.

### Offline or Pinned Version Install
```bash
# Download installer and checksum
curl -LO https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh
curl -LO https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh.sha256

# Verify integrity
sha256sum -c install.sh.sha256

# Install (defaults to ~/.cconductor)
bash install.sh
```
To install a specific release, export `CCONDUCTOR_VERSION` or download the pinned installer:
```bash
export CCONDUCTOR_VERSION=v0.3.1
curl -fsSL https://github.com/yaniv-golan/cconductor/releases/download/${CCONDUCTOR_VERSION}/install.sh | bash
```

---

## Upgrade & Maintenance

- **Quick install / manual clone:** `git -C ~/.cconductor pull` (replace the path if you chose a custom install directory). Run `cconductor --init --yes` after pulling if new migrations are introduced.
- **Homebrew:** `brew upgrade cconductor`
- **Docker:** `docker pull ghcr.io/yaniv-golan/cconductor:latest`
- **Pinned version:** rerun the installer with the desired `CCONDUCTOR_VERSION`.

Built-in commands:
```bash
cconductor --update          # Manually fetch the latest release metadata
cconductor --check-update    # Check if an update is available
cconductor --no-update-check "your question"  # Skip the automatic update probe for a single run
```
To disable background update checks entirely, edit `~/.config/cconductor/cconductor-config.json`:
```json
{
  "update_settings": {
    "check_for_updates": false
  }
}
```

---

## Understanding Claude Code Access

CConductor requires Claude Code to function and cannot run with just an Anthropic API key.

### What is Claude Code?

Claude Code allows Claude to run integrated developer workflows from your terminal/IDE. CConductor uses the Claude Code CLI in headless mode with allowed tools to orchestrate its multi-agent research system.

### Getting Access

Claude Code is available through:

- **Claude Pro/Max subscriptions** - Includes Claude Code usage within your plan quota
- **API/Pay-as-you-go** - Billed separately per usage when you exceed plan limits

### Understanding Costs

- Your Claude subscription (Pro, Max) includes a quota of Claude Code usage
- Usage beyond your quota falls back to API billing (pay-per-use)
- API and subscription billing are separate systems
- Research sessions typically use multiple prompts (planning, research, synthesis, validation)

### Which Plan Do I Need?

- **Pro Plan** - Suitable for occasional research sessions
- **Max Plan** - Better for frequent or intensive research
- **API Credits** - Available for usage beyond plan limits

**For current pricing and plan details**, see:

- [Anthropic Pricing](https://www.anthropic.com/pricing)
- [Using Claude Code with Plans](https://support.anthropic.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- [API Usage Billing](https://support.anthropic.com/en/articles/8977456-how-do-i-pay-for-my-api-usage)

**Note**: Plan features, quotas, and pricing are subject to change. Always verify current details with Anthropic.

---

### Advanced Options

**Custom install location:**

```bash
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/cconductor/main/install.sh | bash -s /custom/path
```

**Manual initialization:**

```bash
./cconductor --init              # Interactive mode
./cconductor --init --yes        # Non-interactive (for scripts)
```

---

## Usage

> Use `cconductor` (or `./cconductor` if you are running directly from a cloned repository without updating `PATH`).

### Basic Commands

```bash
# Start new research (auto-launches real-time dashboard)
cconductor "your research question"

# View latest results
cconductor sessions latest

# View research dashboard (auto-launched during research)
cconductor view-dashboard              # Latest session
cconductor view-dashboard mission_123  # Specific session

# Export research journal as markdown
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
bash src/utils/export-journal.sh "$SESSION_DIR/$(cat "$SESSION_DIR/.latest")"

# List all sessions
cconductor sessions

# Continue previous research
cconductor resume mission_1759420487

# Check if research is running
cconductor status

# View configuration
cconductor configure

# Run/re-run initialization
cconductor --init

# Show help
cconductor --help

# Show version
cconductor --version
```

### Session Outputs & Storage

Every mission writes to a timestamped directory under `research-sessions/mission_<id>/` with an organized session tree (v0.4.0):

- `INDEX.json` – Session manifest with file counts, checksums, and quick navigation
- `README.md` – "start here" session map with quick links and stats
- `meta/` – Session metadata, provenance, budgeting, and orchestrator state
- `inputs/` – Original research question and user-provided files
- `cache/` – Web/search cache artifacts reused within the mission
- `work/` – Agent working directories and intermediate findings
- `knowledge/` – Knowledge graph and session knowledge files
- `artifacts/` – Agent-produced artifacts with manifest
- `evidence/` – Footnotes, bibliographies, and quality gate exports wired into the final report
- `library/` – Mission-scoped Library Memory digests for reuse across missions
- `logs/` – Events, orchestration decisions, quality gate diagnostics, system errors
- `report/` – Final mission report and research journal
- `viewer/` – Interactive dashboard (HTML/JS)

**Key Files**:
- `report/mission-report.md` – User-facing research report
- `report/research-journal.md` – Chronological mission journal
- `knowledge/knowledge-graph.json` – Structured knowledge state
- `viewer/index.html` – Real-time research dashboard

Two additional storage locations matter for reuse:

- **Platform cache** – transient WebFetch/WebSearch assets stored under the OS cache root (`~/Library/Caches/CConductor/` on macOS, `${XDG_CACHE_HOME:-~/.cache}/cconductor/` on Linux). Clearing it only forces fresh network calls next time.
- **Library** – durable digests in the repository's `library/` directory (or `LIBRARY_MEMORY_ROOT`). Populated by `src/utils/digital-librarian.sh` from knowledge-graph citations and reused through the LibraryMemory skill.

### Built-in Skills

- **Cache-Aware Web Research** — shared guidance for canonical query reuse, LibraryMemory digests, and deciding when to bypass caches with `?fresh=1`. Copied into each session’s `.claude/skills/` directory.
- **LibraryMemory** — hash, digest, and cached search helpers for reusing previously collected evidence (also copied into `.claude/skills/`).

### Examples

```bash
# Research any topic
./cconductor "What is quantum computing?"

# Academic question
./cconductor "Latest research on mRNA vaccines"

# Business question
./cconductor "AI coding assistant market landscape"

# Technical question
./cconductor "Kubernetes architecture and components"

# Resume to improve quality
./cconductor resume mission_1759420487
```

---

## Research Modes

CConductor automatically selects the best approach based on your question, or you can configure the default mode in `~/.config/cconductor/cconductor-config.json`.

**Available modes** (defaults in `config/cconductor-modes.default.json`, customize in `~/.config/cconductor/cconductor-modes.json`):

- **default** - Balanced research for general topics
- **scientific** - Academic research with peer-reviewed sources
- **market** - Business and competitive analysis
- **technical** - Technical and architectural deep-dives  
- **literature_review** - Comprehensive academic literature reviews

**Mode selection**: Automatic detection based on your question keywords.

**Coming in future releases**: Additional mode selection options and configuration. See [User Guide](docs/USER_GUIDE.md) for complete feature status.

---

## Example Output

After running research, CConductor generates comprehensive reports:

```markdown
# Research Report

Generated by: CConductor - Deep Research, Done Right
Date: October 2, 2025
Session: session_1759420487

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔍 Research Question: What is quantum computing?
📊 Quality Score: 87/100 - EXCELLENT
📚 Sources: 42 (18 academic, 16 web, 8 PDF)
⏱️  Duration: 18 minutes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Executive Summary

Quantum computing is a revolutionary computing paradigm that leverages
quantum mechanical phenomena—superposition and entanglement—to process
information [1]. Unlike classical computers that use bits (0 or 1),
quantum computers use quantum bits or qubits that can exist in multiple
states simultaneously [2]...

## Bibliography

[1] Nielsen, M. & Chuang, I. (2010). Quantum Computation and Quantum
    Information. Cambridge University Press.
[2] IBM Research. (2024). "What is Quantum Computing?" Retrieved from
    https://research.ibm.com/quantum-computing
...
```

---

## Configuration

CConductor is highly configurable without code changes.

### Security Profiles

Control which domains CConductor can access:

**Location**: `~/.config/cconductor/security-config.json` (create with `./src/utils/config-loader.sh init security-config`)

**Default configuration** (`config/security-config.default.json`):
```json
{
  "security_profile": "strict"
}
```

**Available profiles**:
```json
{
  "security_profile": "strict"       // Maximum safety (default)
  // OR
  "security_profile": "permissive"   // Balanced approach
  // OR
  "security_profile": "max_automation" // Testing only (use in VMs)
}
```

**Profiles**:

- **strict** - Academic/sensitive data, prompts for unknown domains
- **permissive** - Business research, fewer prompts, trusted networks
- **max_automation** - Testing/sandboxed only, minimal prompts

See [Security Guide](docs/SECURITY_GUIDE.md) for details.

### Custom Knowledge

Teach CConductor about your domain:

**Location**:

- macOS: `~/Library/Application Support/CConductor/knowledge-base-custom/my-domain.md`
- Linux: `~/.local/share/cconductor/knowledge-base-custom/my-domain.md`

**Note**: Capitalization follows platform conventions: macOS uses `CConductor` (Title Case) while Linux/Windows use `cconductor` (lowercase).

```markdown
## Overview
What this knowledge covers.

## Key Concepts
- Term 1: Definition
- Term 2: Definition

## Important Facts
- Fact about your domain
```

CConductor automatically discovers and uses all `.md` files in your custom knowledge directory!

**Tip**: Use `./src/utils/path-resolver.sh resolve knowledge_base_custom` to find your exact path.

See [Custom Knowledge Guide](docs/CUSTOM_KNOWLEDGE.md) for details.

### Research Preferences

**Location**: `~/.config/cconductor/cconductor-config.json` (create with `./src/utils/config-loader.sh init cconductor-config`)

Configure default behavior, agent settings, output preferences, and quality standards.

See [Configuration Reference](docs/CONFIGURATION_REFERENCE.md) for all options.

---

## Documentation

📖 **Start here**:

- **[User Guide](docs/USER_GUIDE.md)** - Comprehensive guide for all features
- **[Quick Reference](docs/QUICK_REFERENCE.md)** - Command cheat sheet

🎯 **Feature guides**:

- **[Citations & Bibliography](docs/CITATIONS_GUIDE.md)** - Using citations effectively
- **[Security Configuration](docs/SECURITY_GUIDE.md)** - Security profiles explained
- **[Quality Scores](docs/QUALITY_GUIDE.md)** - Understanding and improving quality
- **[Custom Knowledge](docs/CUSTOM_KNOWLEDGE.md)** - Adding domain expertise
- **[PDF Research](docs/PDF_RESEARCH_GUIDE.md)** - Working with academic papers

🔧 **Reference**:

- **[Configuration Reference](docs/CONFIGURATION_REFERENCE.md)** - All config files
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Fix common problems

---

## Architecture

CConductor uses a multi-agent architecture with specialized agents:

- **Research Planner** - Understands questions and creates research plans
- **Web Researcher** - Searches and analyzes web sources
- **Academic Researcher** - Finds and analyzes academic papers
- **PDF Analyzer** - Extracts insights from PDF documents
- **Market Analyzer** - Business and market intelligence
- **Code Analyzer** - Technical and architectural analysis
- **Synthesis Agent** - Combines findings into coherent reports
- **Fact Checker** - Validates claims and detects contradictions

Research uses an **Adaptive System** that dynamically iterates with gap detection, contradiction resolution, and lead exploration until high confidence is achieved.

---

## Project Structure

### Visual Project Architecture

```mermaid
graph TD
    subgraph "CConductor Project"
        A[Application Code<br/>cconductor/]
        B[User Data<br/>OS-Specific]
        C[Configuration<br/>Overlay Pattern]

        A --> D[Core Engine<br/>src/cconductor-mission.sh]
        A --> E[Utilities<br/>src/utils/]
        A --> F[Documentation<br/>docs/]
        A --> G[Agent Templates<br/>src/claude-runtime/]

        B --> I[macOS<br/>~/Library/]
        B --> J[Linux<br/>~/.local/]
        B --> K[Windows<br/>%APPDATA%]

        C --> L[Defaults<br/>config/*.default.json]
        C --> M[User Overrides<br/>~/.config/cconductor/]
    end

    D --> N[Adaptive Research<br/>Multi-agent orchestration]
        E --> O[Knowledge Injection<br/>Custom domain expertise]
        E --> P[Session Management<br/>Conversation continuity]
        E --> Q[PDF Processing<br/>Document analysis]

    I --> S[Application Support<br/>research-sessions/]
    I --> T[Caches<br/>pdfs/]
    I --> U[Logs<br/>audit.log]

    J --> V[Share<br/>research-sessions/]
    J --> W[Cache<br/>pdfs/]
    J --> X[State<br/>audit.log]

    style A fill:#e1f5ff
    style B fill:#f0f8e1
    style C fill:#fff4e1
    style D fill:#e8f5e8
    style I fill:#ffeaa7
    style J fill:#ffeaa7
```

### Detailed Directory Structure

#### Application Code (Git-Tracked)

```
cconductor/
├── cconductor                      # Main CLI entry point
├── src/
│   ├── cconductor-mission.sh      # Mission-based research engine
│   ├── knowledge-graph.sh         # Knowledge state tracking
│   ├── task-queue.sh             # Dynamic task management
│   ├── shared-state.sh           # Concurrent access control
│   ├── utils/                    # Utility scripts (17 files)
│   │   ├── knowledge-loader.sh   # Custom knowledge injection
│   │   ├── invoke-agent.sh       # Agent invocation
│   │   └── config-loader.sh      # Configuration management
├── config/
│   ├── *.default.json           # Default configs (never edit)
│   └── README.md                # Configuration documentation
├── docs/                        # Documentation (this file!)
├── knowledge-base/              # Built-in domain knowledge
└── src/claude-runtime/          # Claude Code agent templates
```

#### User Data (OS-Appropriate, Git-Ignored)

**macOS**:
```
~/Library/Application Support/CConductor/
├── research-sessions/          # Your research output
├── knowledge-base-custom/      # Your custom knowledge files
└── citations.json             # Citation database

~/Library/Caches/CConductor/     # PDF cache and temp files
└── pdfs/                      # Downloaded and processed PDFs

~/Library/Logs/CConductor/      # System logs
└── audit.log                  # Security and usage audit log
```

**Linux** (XDG Base Directory):
```
~/.local/share/cconductor/      # Your research data
├── research-sessions/         # Research session outputs
├── knowledge-base-custom/     # Custom knowledge files
└── citations.json            # Citation tracking

~/.cache/cconductor/           # Cache directory
└── pdfs/                     # PDF processing cache

~/.local/state/cconductor/     # State and logs
└── audit.log                 # Audit trail
```

**Windows**:
```
%LOCALAPPDATA%\CConductor\     # User data directory
├── research-sessions/        # Research outputs
├── knowledge-base-custom/    # Custom knowledge
└── citations.json           # Citations

%TEMP%\CConductor\            # Temporary files
└── cache\                   # PDF and processing cache
```

**Directory Structure Benefits**:

- **Separation of Concerns**: Code, data, and configuration are clearly separated
- **Cross-Platform**: Works on macOS, Linux, and Windows with appropriate paths
- **User Isolation**: Each user has their own data and configurations
- **Upgrade Safety**: User data survives project reinstallation
- **Git-Friendly**: Only application code is tracked, user data is ignored

---

### What's Working

- ✅ Mission-based orchestration with autonomous agent coordination
- ✅ Multi-agent research system with specialized agents
- ✅ Knowledge graph integration (production-ready)
- ✅ Interactive research wizard and verbose progress mode
- ✅ Citation tracking and bibliography
- ✅ Security configuration system
- ✅ Quality validation gates
- ✅ Custom knowledge base
- ✅ Cross-platform support
- ✅ Comprehensive documentation

### Roadmap

- 🚧 Mission resume/refinement capabilities
- 🚧 Enhanced PDF extraction
- 🚧 Multi-language support
- 🚧 Progress indicators
- 🚧 Enhanced session management

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For technical documentation:

- [Knowledge System Technical Deep Dive](docs/KNOWLEDGE_SYSTEM_TECHNICAL.md) - Complete architecture and debugging
- [Implementation Status](docs/technical/IMPLEMENTATION_STATUS.md)
- [Agent Migration Guide](docs/technical/AGENT_MIGRATION_GUIDE.md)
- [Adaptive Research Plan](docs/technical/ADAPTIVE_RESEARCH_PLAN.md)

---

## License

MIT License - See [LICENSE](LICENSE) file for details

---

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/yaniv-golan/cconductor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yaniv-golan/cconductor/discussions)

---

## Acknowledgments

Built with:

- [Claude](https://anthropic.com/claude) by Anthropic
- [jq](https://stedolan.github.io/jq/) for JSON processing
- bash for reliable scripting

---

**CConductor** - AI Research, Orchestrated 🔍
