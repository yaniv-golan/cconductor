# CConductor Quick Reference

**Command cheat sheet for daily use** - v0.1.0

---

## 🚀 Most Common Commands

```bash
# Interactive mode (dialog-based TUI)
./cconductor

# Start research
./cconductor "your question"

# Research with specific mission type
./cconductor "your question" --mission market-research
./cconductor "your question" --mission academic-research

# Complex research from markdown file
./cconductor --question-file research-query.md

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
./cconductor view-dashboard session_123  # Specific session
```

### Export Research Journal

Export comprehensive markdown timeline:

```bash
# Latest session
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
bash src/utils/export-journal.sh "$SESSION_DIR/$(cat "$SESSION_DIR/.latest")"

# Specific session
bash src/utils/export-journal.sh research-sessions/session_123

# Output: research-journal.md with complete timeline
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
./cconductor latest

# View latest report directly
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cat "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/research-report.md
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
# Simple question
./cconductor "What is Docker?"

# Detailed question
./cconductor "What are the latest advances in CRISPR gene editing?"

# Business question
./cconductor "Total addressable market for AI SaaS tools in 2024"

# Technical question
./cconductor "How does Kubernetes handle container orchestration?"
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
# Latest research
./cconductor "Latest advances in CRISPR gene editing 2023-2024"

# Specific topic
./cconductor "Machine learning in healthcare diagnostics"

# Methodology focus
./cconductor "Quantum error correction methods and effectiveness"
```

### Market Research

```bash
# Market sizing
./cconductor "SaaS CRM market size and growth 2024"

# Competitive analysis
./cconductor "Compare top 5 CRM platforms: features and pricing"

# Industry trends
./cconductor "Emerging trends in fintech 2024-2025"
```

### Technical Research

```bash
# Architecture
./cconductor "Docker containerization architecture"

# Comparison
./cconductor "Kubernetes vs Docker Swarm comparison"

# Best practices
./cconductor "Best practices for implementing OAuth 2.0"
```

---

## ⚡ Workflow Shortcuts

### Quick Research + View

```bash
./cconductor "question" && ./cconductor latest
```

### Continue Previous

```bash
# Resume most recent session
./cconductor latest  # Shows session ID
./cconductor resume <session_id_from_above>
```

### Export Latest Report

```bash
# Use cconductor latest to get the path, then copy
./cconductor latest  # Shows the path
# Or use path-resolver
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cp "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/research-report.md ~/Documents/
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
./cconductor resume session_123  # Most effective way
```

---

## 📚 Session Management

### List Sessions

```bash
./cconductor sessions
```

### Find Latest

```bash
./cconductor latest
```

### Resume Research

```bash
./cconductor resume session_1759420487
./cconductor resume $(cat research-sessions/.latest)  # Resume latest
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
dlr session_123                # Resume
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
   ./cconductor latest
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

## 🚧 Coming in v0.2

The following features are **planned but not yet available**:

```bash
# CLI options (NOT available in v0.1, coming in v0.2)
./cconductor "question" --mode scientific    # Explicit mode selection
./cconductor "question" --speed fast         # Control research depth
./cconductor "question" --output html        # HTML/JSON output formats
./cconductor "question" --name my-research   # Custom session names
./cconductor "question" --iterations 5       # Control iteration count
./cconductor "question" --interactive        # Guided research mode
./cconductor "question" --quiet              # Minimal output
```

**v0.1 alternatives**:

- Mode selection: Use keywords in question (e.g., "peer-reviewed research on...")
- Speed control: Edit `config/cconductor-config.json`
- Session naming: Use timestamp-based names (session_TIMESTAMP)
- Output format: Markdown only (HTML/JSON in v0.2)

See internal roadmap for complete feature list.

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

**Quick Start**: `./cconductor "your question"` → `./cconductor latest`

That's it! 🔍
