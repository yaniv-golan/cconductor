# CConductor Quick Reference

**Command cheat sheet for daily use**

---

## 🚀 Most Common Commands

```bash
# Interactive mode (dialog-based TUI) - RECOMMENDED FOR NEW USERS
./cconductor
# Tip: install the optional `dialog` package (brew install dialog / sudo apt install dialog)
# to enable the full menu experience. Without it, a simple text menu is used.

# Start research (command-line mode)
./cconductor "your question"

# Research with specific mission type
./cconductor "your question" --mission academic-research
./cconductor "your question" --mission market-research
./cconductor "your question" --mission competitive-analysis
./cconductor "your question" --mission technical-analysis

# Complex research from markdown file
./cconductor --question-file research-query.md
./cconductor --question-file research-query.md --mission academic-research

# Research with local files (PDFs, markdown, text)
./cconductor "your question" --input-dir /path/to/files/

# Session management
./cconductor sessions list               # List all sessions
./cconductor sessions latest             # View latest results
./cconductor sessions viewer mission_123 # View research journal
./cconductor sessions resume mission_123 # Continue research
./cconductor sessions resume mission_123 --refine "Focus on X"  # Resume with refinement

# Export research journal as markdown
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
bash src/utils/export-journal.sh "$SESSION_DIR/$(cat "$SESSION_DIR/.latest")"

# Verbose mode (real-time progress) - ENABLED BY DEFAULT
./cconductor "your question" --verbose   # Show detailed progress
./cconductor "your question" --quiet     # Minimal output only

# Check running processes
./cconductor status

# Run/re-run initialization
./cconductor --init

# Show help
./cconductor --help

# Show version
./cconductor --version

# View configuration
./cconductor configure
```

---

## 📊 Research Dashboard & Journal

### Real-Time Dashboard

CConductor automatically launches a **Research Journal Viewer** when research starts.

**Features**:
- Live progress updates (refreshes every 3 seconds)
- Current agent activities ("in progress" entries)
- Clickable Entities/Claims cards with details
- Agent statistics (papers found, searches, gaps)
- System health monitoring
- Cost tracking

**Commands**:
```bash
# Auto-launched during research, or view manually:
./cconductor view-dashboard              # Latest session
./cconductor view-dashboard mission_123  # Specific session
```

### Export Research Journal

Export comprehensive markdown timeline:

```bash
# Latest session
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
bash src/utils/export-journal.sh "$SESSION_DIR/$(cat "$SESSION_DIR/.latest")"

# Specific session
bash src/utils/export-journal.sh research-sessions/mission_123

# Output: report/research-journal.md with complete timeline
```

**Includes**:
- Complete event timeline
- All entities with descriptions
- All claims with evidence
- Relationships discovered
- Agent metadata & statistics

---

## 📁 Important Locations

**Note**: CConductor uses OS-appropriate data directories. Find exact paths with:

```bash
./src/utils/path-resolver.sh resolve session_dir
```

### macOS

| Location | What's There |
|----------|-------------|
| `~/Library/Application Support/CConductor/research-sessions/` | All your research |
| `~/Library/Application Support/CConductor/knowledge-base-custom/` | Your custom knowledge |
| `~/Library/Caches/CConductor/pdfs/` | PDF cache |
| `~/Library/Logs/CConductor/` | Log files |
| `~/.config/cconductor/` | User configuration files |
| Project: `config/*.default.json` | Config templates (never edit) |

### Linux

| Location | What's There |
|----------|-------------|
| `~/.local/share/cconductor/research-sessions/` | All your research |
| `~/.local/share/cconductor/knowledge-base-custom/` | Your custom knowledge |
| `~/.cache/cconductor/pdfs/` | PDF cache |
| `~/.local/state/cconductor/` | Log files |
| `~/.config/cconductor/` | User configuration files |
| Project: `config/*.default.json` | Config templates (never edit) |

### Quick Access

```bash
# Latest report (use cconductor command)
./cconductor sessions latest

# View latest report directly
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cat "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/report/mission-report.md
```

---

## 🔧 Configuration Files

**Location**: User configs in `~/.config/cconductor/`, defaults in project `config/*.default.json`

| File | Purpose | Edit Often? |
|------|---------|-------------|
| `cconductor-config.json` | Main settings | Rarely |
| `security-config.json` | Security profiles | Often |
| `cconductor-modes.json` | Mode definitions | Rarely |
| `knowledge-config.json` | Knowledge sources | Sometimes |
| `paths.json` | Directory paths | Rarely |
| `adaptive-config.json` | Advanced tuning | Advanced only |

### Quick Edits

```bash
# Create user config first (if doesn't exist)
./src/utils/config-loader.sh init security-config

# Then edit in your home directory
nano ~/.config/cconductor/security-config.json
# Change: "security_profile": "strict" → "permissive"

# Reset to defaults: delete user config
rm ~/.config/cconductor/security-config.json
```

---

## 🆘 Quick Troubleshooting

| Error | Cause | Quick Fix |
|-------|-------|-----------|
| "Command not found" | Not in directory | `cd /path/to/cconductor` first |
| "Permission denied" | Not executable | `chmod +x cconductor` |
| "No such file" | Config missing | `./cconductor --init` |
| "Session not found" | Invalid session ID | Use `./cconductor sessions` to list |
| "Quality score too low" | Incomplete | `./cconductor resume SESSION_ID` |
| ".latest file not found" | No research yet | Run `./cconductor "test"` first |
| "jq: command not found" | Missing dependency | `brew install jq` (macOS) |

**For detailed troubleshooting**: See [Troubleshooting Guide](TROUBLESHOOTING.md)

---

## 💡 Copy-Paste Examples

### Basic Research

```bash
# Simple question (auto-selects best mission)
./cconductor "What is Docker?"

# Academic research with peer-reviewed sources
./cconductor "What are the latest advances in CRISPR gene editing?" --mission academic-research

# Market research with business focus
./cconductor "Total addressable market for AI SaaS tools in 2024" --mission market-research

# Technical analysis
./cconductor "How does Kubernetes handle container orchestration?" --mission technical-analysis

# Competitive analysis
./cconductor "Compare top 5 CRM platforms" --mission competitive-analysis
```

### Research with Local Files

```bash
# Analyze pitch deck
./cconductor "Evaluate this startup" --input-dir ./pitch-materials/

# Research with context documents
./cconductor "Summarize findings" --input-dir ~/Documents/research/

# Market analysis with local reports
./cconductor "Market size analysis" --input-dir ./market-reports/

# Supported: PDFs (.pdf), Markdown (.md), Text (.txt)
```

### Academic Research

```bash
# Latest research with academic mission
./cconductor "Latest advances in CRISPR gene editing 2023-2024" --mission academic-research

# Specific topic with peer-reviewed focus
./cconductor "Machine learning in healthcare diagnostics" --mission academic-research

# Methodology focus
./cconductor "Quantum error correction methods and effectiveness" --mission academic-research
```

### Market Research

```bash
# Market sizing with market research mission
./cconductor "SaaS CRM market size and growth 2024" --mission market-research

# Competitive analysis mission
./cconductor "Compare top 5 CRM platforms: features and pricing" --mission competitive-analysis

# Industry trends
./cconductor "Emerging trends in fintech 2024-2025" --mission market-research
```

### Technical Research

```bash
# Architecture with technical analysis mission
./cconductor "Docker containerization architecture" --mission technical-analysis

# Technical comparison
./cconductor "Kubernetes vs Docker Swarm comparison" --mission technical-analysis

# Best practices
./cconductor "Best practices for implementing OAuth 2.0" --mission technical-analysis
```

---

## ⚡ Workflow Shortcuts

### Quick Research + View

```bash
./cconductor "question" && ./cconductor sessions latest
```

### Continue Previous

```bash
# Resume most recent session
./cconductor sessions latest  # Shows session ID
./cconductor resume <session_id_from_above>
```

### Export Latest Report

```bash
# Use cconductor latest to get the path, then copy
./cconductor sessions latest  # Shows the path
# Or use path-resolver
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cp "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/report/mission-report.md ~/Documents/
```

### Archive Old Sessions

```bash
# Find your session directory first
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
mkdir -p "$HOME/cconductor-archive/"
mv "$SESSION_DIR"/session_old* "$HOME/cconductor-archive/"
```

### Monitor Progress

```bash
watch -n 5 './cconductor status'
```

---

## 🔐 Security Profiles Quick Reference

Edit `config/security-config.json`:

```json
{
  "security_profile": "strict"       // Maximum safety (default)
  "security_profile": "permissive"   // Balanced
  "security_profile": "max_automation" // Speed (testing only)
}
```

**Profile Comparison**:

| Profile | Prompts | Use Case |
|---------|---------|----------|
| **strict** | Most | Academic, sensitive |
| **permissive** | Some | Business, trusted networks |
| **max_automation** | Few | Testing, sandboxed only |

---

## 📈 Quality Scores Quick Reference

| Score | Rating | Meaning |
|-------|--------|---------|
| 90-100 | EXCELLENT | Publication ready |
| 80-89 | VERY GOOD | High quality |
| 70-79 | GOOD | Solid research |
| 60-69 | FAIR | Usable with caveats |
| <60 | NEEDS WORK | Run more iterations |

**Improve quality**:

```bash
./cconductor resume mission_123  # Most effective way
```

---

## 📚 Session Management

### List Sessions

```bash
./cconductor sessions
```

### Find Latest

```bash
./cconductor sessions latest
```

### Resume Research

```bash
./cconductor sessions resume mission_1759420487
./cconductor sessions resume mission_1759420487 --refine "Focus on recent papers"
./cconductor sessions resume $(cat research-sessions/.latest)  # Resume latest
```

### Check Status

```bash
./cconductor status
```

### Organize Sessions

```bash
# Get session directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)

# Create project folders
mkdir -p "$SESSION_DIR/project-alpha/"
mv "$SESSION_DIR"/quantum-* "$SESSION_DIR/project-alpha/"

# Archive by date
mkdir -p "$HOME/cconductor-archive/2024-q3/"
mv "$SESSION_DIR"/session_old* "$HOME/cconductor-archive/2024-q3/"
```

---

## 🛠️ Shell Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Shortcuts (adjust path to your cconductor installation)
alias dl='/path/to/cconductor/cconductor'
alias dll='/path/to/cconductor/cconductor latest'
alias dls='/path/to/cconductor/cconductor sessions'
alias dlr='/path/to/cconductor/cconductor resume'

# Helper to get session directory
alias dldir='$(cd /path/to/cconductor && ./src/utils/path-resolver.sh resolve session_dir)'
```

**Usage after aliasing**:

```bash
dl "your question"              # Instead of ./cconductor
dll                            # Show latest
dls                            # List sessions
dlr mission_123                # Resume
```

---

## 🎓 Learning Path

**New to CConductor?** Try these in order:

1. **Test it works**:

   ```bash
   ./cconductor "What is Docker?"
   ```

2. **Check the result**:

   ```bash
   ./cconductor sessions latest
   ```

3. **Try different topics**:

   ```bash
   ./cconductor "AI advances 2024"
   ./cconductor "SaaS market size"
   ```

4. **Resume to improve**:

   ```bash
   ./cconductor resume $(cat research-sessions/.latest)
   ```

---

## 🎉 Recent Features

**Mission-Based Orchestration**:
- Use `--mission` flag to specify research type
- Available missions: academic-research, market-research, competitive-analysis, technical-analysis
- Autonomous agent selection based on research needs

**Interactive Mode**:
- Run `./cconductor` without arguments for guided setup
- Dialog-based TUI with session browser

**Enhanced Observability**:
- Verbose mode shows real-time progress (enabled by default)
- Agent reasoning visible in dashboard
- Use `--quiet` for minimal output

**Session Management**:
- Unified `sessions` command with list/latest/viewer/resume subcommands
- Resume with refinement guidance

## 🚧 Coming in Future Versions

- Custom mission templates
- Parallel agent invocation
- Session comparison and merging
- Enhanced knowledge graph visualization

See CHANGELOG.md for complete roadmap.

---

## 📖 More Help

- **Full Guide**: [User Guide](USER_GUIDE.md) - Comprehensive documentation
- **Citations**: [Citations Guide](CITATIONS_GUIDE.md) - Using citations
- **Security**: [Security Guide](SECURITY_GUIDE.md) - Security configuration
- **Quality**: [Quality Guide](QUALITY_GUIDE.md) - Understanding quality
- **Custom Knowledge**: [Custom Knowledge](CUSTOM_KNOWLEDGE.md) - Adding expertise
- **Troubleshooting**: [Troubleshooting](TROUBLESHOOTING.md) - Fix problems
- **Config Reference**: [Configuration Reference](CONFIGURATION_REFERENCE.md) - All configs

---

**Quick Start**: `./cconductor "your question"` → `./cconductor sessions latest`

That's it! 🔍
