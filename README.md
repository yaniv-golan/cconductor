# Delve 🔍

**Deep Research, Done Right**

Delve is a multi-agent AI research system that conducts comprehensive, adaptive research on any topic. Powered by Claude and specialized AI agents, it finds, analyzes, and synthesizes information from academic papers, web sources, PDFs, and code repositories—delivering well-cited, validated research reports.

---

## Why Delve?

- 🧠 **Multi-Agent Intelligence** - Specialized agents for planning, research, synthesis, and validation work together
- 📚 **Multi-Source Research** - Handles academic papers, web content, PDFs, code, and market data
- ✅ **Built-In Validation** - Automatic fact-checking, citation tracking, and quality assessment
- 🎯 **Adaptive Research** - Identifies gaps, explores leads, and improves iteratively until high confidence
- 📊 **Quality Scores** - Know exactly how reliable your research is (0-100 with detailed breakdown)
- 🔒 **Configurable Security** - Control which domains to trust with flexible security profiles
- 🌍 **Cross-Platform** - Works on macOS, Linux, and Windows (WSL/Git Bash)

---

## Quick Start

Get up and running in 1 command:

```bash
./delve "What is quantum computing?"
```

On first run, Delve will automatically set up directories and configuration (takes ~5 seconds).

Your research report will be in `research-sessions/` with full citations and quality assessment.

**View your results**:

```bash
./delve latest
```

---

## What You Can Do

### Academic Research

Comprehensive research with full citations and bibliography.

```bash
./delve "Latest advances in CRISPR gene editing 2023-2024"
```

### Market Analysis

Business intelligence with market data and competitive insights.

```bash
./delve "SaaS CRM market size and growth 2024"
```

### Technical Deep-Dives

Detailed technical research with architecture and examples.

```bash
./delve "How does Docker containerization work?"
```

### General Research

Balanced research on any topic.

```bash
./delve "What causes climate change?"
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

### v0.1.0 Features

- ✨ **Citations & Bibliography** - Automatic source tracking and reference generation
- 🔒 **Configurable Security** - Three profiles (strict/permissive/max_automation)
- 📊 **Quality Validation** - Research quality gates prevent incomplete results
- 🌍 **Cross-Platform Support** - Works on Windows, macOS, and Linux
- 📖 **Extensible Knowledge** - Add your own domain expertise without modifying code
- 🔍 **Progress Tracking** - See what's happening during research
- 💬 **Better Error Messages** - Clear explanations and recovery steps
- 🧮 **Safe Calculations** - Accurate math using Python, not LLM estimation

---

## Requirements

- **Claude Code** (required - Delve is a Claude Code extension)
  - Delve uses Claude Code's Task tool to invoke specialized AI agents
  - Cannot run standalone with just an API key
  - Available through Claude Pro/Max subscriptions or API/pay-as-you-go
  - See [Understanding Claude Code Access](#understanding-claude-code-access) below for details
- **Bash shell** (4.0+)
- **jq** (JSON processor)
- **curl** (for web requests)
- **Python 3** (for calculations, optional but recommended)

### Installing Dependencies

**macOS**:

```bash
brew install jq curl
# bash and python3 pre-installed
```

**Linux** (Ubuntu/Debian):

```bash
sudo apt-get install jq curl bash python3
```

**Windows**:

```bash
# Use WSL (Windows Subsystem for Linux) or Git Bash
# In WSL: sudo apt-get install jq curl bash python3
```

---

## Installation

### Quick Install (Recommended)

One command to install and set up everything:

```bash
curl -fsSL https://github.com/yaniv-golan/delve/releases/latest/download/install.sh | bash
```

This will:

- Download the latest stable release
- Verify checksums automatically  
- Install to `~/.delve`
- Run first-time setup automatically
- Optionally add to your PATH

Then use from anywhere:

```bash
delve "your research question"
```

### Verified Install (High Security)

For production or security-sensitive environments:

```bash
# Download installer and checksum
curl -LO https://github.com/yaniv-golan/delve/releases/latest/download/install.sh
curl -LO https://github.com/yaniv-golan/delve/releases/latest/download/install.sh.sha256

# Verify integrity
sha256sum -c install.sh.sha256

# Install
bash install.sh
```

### Specific Version

```bash
export DELVE_VERSION=v0.1.0
curl -fsSL https://github.com/yaniv-golan/delve/releases/download/v0.1.0/install.sh | bash
```

### Manual Install (Development)

```bash
# Clone the repository
git clone https://github.com/yaniv-golan/delve.git
cd delve

# Start researching!
chmod +x delve
./delve "your research question"
```

**Note:** If you get "Permission denied", run: `chmod +x delve`

Setup happens automatically on first run.

## Updates

Delve automatically checks for updates once per day.

**Update manually:**

```bash
delve --update
```

**Check for updates:**

```bash
delve --check-update
```

**Disable update checks:**

```bash
# Temporarily
delve --no-update-check "your question"

# Permanently - edit ~/.config/delve/delve-config.json:
{
  "update_settings": {
    "check_for_updates": false
  }
}
```

---

## Understanding Claude Code Access

Delve requires Claude Code to function and cannot run with just an Anthropic API key.

### What is Claude Code?

Claude Code allows Claude to run integrated developer workflows from your terminal/IDE. Delve uses Claude Code's Task tool to orchestrate its multi-agent research system.

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
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/delve/main/install.sh | bash -s /custom/path
```

**Manual initialization:**

```bash
./delve --init              # Interactive mode
./delve --init --yes        # Non-interactive (for scripts)
```

---

## Usage

### Basic Commands

```bash
# Start new research
./delve "your research question"

# View latest results
./delve latest

# List all sessions
./delve sessions

# Continue previous research
./delve resume session_1759420487

# Check if research is running
./delve status

# View configuration
./delve configure

# Run/re-run initialization
./delve --init

# Show help
./delve --help

# Show version
./delve --version
```

### Examples

```bash
# Research any topic
./delve "What is quantum computing?"

# Academic question
./delve "Latest research on mRNA vaccines"

# Business question
./delve "AI coding assistant market landscape"

# Technical question
./delve "Kubernetes architecture and components"

# Resume to improve quality
./delve resume session_1759420487
```

---

## Research Modes

Delve automatically selects the best approach based on your question, or you can configure the default mode in `~/.config/delve/delve-config.json`.

**Available modes** (defaults in `config/delve-modes.default.json`, customize in `~/.config/delve/delve-modes.json`):

- **default** - Balanced research for general topics
- **scientific** - Academic research with peer-reviewed sources
- **market** - Business and competitive analysis
- **technical** - Technical and architectural deep-dives  
- **literature_review** - Comprehensive academic literature reviews

**Mode selection in v0.1**: Automatic detection based on your question keywords.

**Coming in v0.2**: Explicit mode selection via `--mode` CLI option.

---

## Example Output

After running research, Delve generates comprehensive reports:

```markdown
# Research Report

Generated by: Delve v0.1.0 - Deep Research, Done Right
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

Delve is highly configurable without code changes.

### Security Profiles

Control which domains Delve can access:

**Location**: `~/.config/delve/security-config.json` (create with `./src/utils/config-loader.sh init security-config`)

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

Teach Delve about your domain:

**Location**:

- macOS: `~/Library/Application Support/Delve/knowledge-base-custom/my-domain.md`
- Linux: `~/.local/share/delve/knowledge-base-custom/my-domain.md`

```markdown
## Overview
What this knowledge covers.

## Key Concepts
- Term 1: Definition
- Term 2: Definition

## Important Facts
- Fact about your domain
```

Delve automatically discovers and uses all `.md` files in your custom knowledge directory!

**Tip**: Use `./src/utils/path-resolver.sh resolve knowledge_base_custom` to find your exact path.

See [Custom Knowledge Guide](docs/CUSTOM_KNOWLEDGE.md) for details.

### Research Preferences

**Location**: `~/.config/delve/delve-config.json` (create with `./src/utils/config-loader.sh init delve-config`)

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

Delve uses a multi-agent architecture with specialized agents:

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

### Project Directory (Application Code)

```
delve/
├── delve                      # Main CLI entry point
├── src/
│   ├── delve-adaptive.sh     # Adaptive research engine
│   ├── knowledge-graph.sh    # Knowledge tracking
│   ├── task-queue.sh         # Dynamic task management
│   ├── shared-state.sh       # Concurrent access control
│   ├── utils/                # Utility scripts (17 files)
│   └── formatters/           # Output formatters (6 files)
├── config/
│   ├── *.default.json        # Default configs (git-tracked, never edit)
│   └── README.md             # Config documentation
├── docs/                     # Documentation
├── knowledge-base/           # Built-in knowledge (git-tracked)
└── .claude/hooks/            # Research monitoring
```

### User Directory (Your Data - OS-Appropriate Locations)

**macOS**:

```
~/.config/delve/                           # Your configurations
├── delve-config.json
├── security-config.json
├── delve-modes.json
└── paths.json

~/Library/Application Support/Delve/      # Your data
├── research-sessions/                     # Your research output
├── knowledge-base-custom/                 # Your custom knowledge
└── citations.json

~/Library/Caches/Delve/                    # Cache
└── pdfs/

~/Library/Logs/Delve/                      # Logs
└── audit.log
```

**Linux**:

```
~/.config/delve/                           # Your configurations
~/.local/share/delve/                      # Your data
~/.cache/delve/                            # Cache
~/.local/state/delve/                      # Logs
```

**Windows**:

```
%APPDATA%\Delve\                           # Your configurations
%LOCALAPPDATA%\Delve\                      # Your data
```

**Benefits**: Configs and data survive project deletion/reinstallation, proper multi-user support, follows OS conventions.

---

## Development Status

**Current Version**: 0.1.0  
**Status**: Beta Release  
**Last Updated**: October 2025

### What's Working (v0.1.0)

- ✅ Multi-agent research system
- ✅ Adaptive research with dynamic task generation
- ✅ Citation tracking and bibliography
- ✅ Security configuration system
- ✅ Quality validation gates
- ✅ Custom knowledge base
- ✅ Cross-platform support
- ✅ Comprehensive documentation

### Coming in v0.2.0

- 🚧 HTML and JSON output formats
- 🚧 Enhanced PDF extraction
- 🚧 Multi-language support
- 🚧 Progress indicators
- 🚧 Enhanced session management

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For technical documentation:

- [Implementation Status](docs/technical/IMPLEMENTATION_STATUS.md)
- [Agent Migration Guide](docs/technical/AGENT_MIGRATION_GUIDE.md)
- [Adaptive Research Plan](docs/technical/ADAPTIVE_RESEARCH_PLAN.md)

---

## License

[Your License Here - e.g., MIT]

---

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/yaniv-golan/delve/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yaniv-golan/delve/discussions)

---

## Acknowledgments

Built with:

- [Claude](https://anthropic.com/claude) by Anthropic
- [jq](https://stedolan.github.io/jq/) for JSON processing
- bash for reliable scripting

---

**Delve** - Deep Research, Done Right 🔍
