# Delve Quick Reference

**Command cheat sheet for daily use** - v0.1.0

---

## 🚀 Most Common Commands

```bash
# Start research
./delve "your question"

# Research with local files (PDFs, markdown, text)
./delve "your question" --input-dir /path/to/files/

# View latest results
./delve latest

# List all sessions
./delve sessions

# Continue previous research
./delve resume session_1759420487

# Check if running
./delve status

# Run/re-run initialization
./delve --init

# Show help
./delve --help

# Show version
./delve --version

# View configuration
./delve configure
```

---

## 📁 Important Locations

**Note**: Delve uses OS-appropriate data directories. Find exact paths with:

```bash
./src/utils/path-resolver.sh resolve session_dir
```

### macOS

| Location | What's There |
|----------|-------------|
| `~/Library/Application Support/Delve/research-sessions/` | All your research |
| `~/Library/Application Support/Delve/knowledge-base-custom/` | Your custom knowledge |
| `~/Library/Caches/Delve/pdfs/` | PDF cache |
| `~/Library/Logs/Delve/` | Log files |
| `~/.config/delve/` | User configuration files |
| Project: `config/*.default.json` | Config templates (never edit) |

### Linux

| Location | What's There |
|----------|-------------|
| `~/.local/share/delve/research-sessions/` | All your research |
| `~/.local/share/delve/knowledge-base-custom/` | Your custom knowledge |
| `~/.cache/delve/pdfs/` | PDF cache |
| `~/.local/state/delve/` | Log files |
| `~/.config/delve/` | User configuration files |
| Project: `config/*.default.json` | Config templates (never edit) |

### Quick Access

```bash
# Latest report (use delve command)
./delve latest

# View latest report directly
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cat "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/research-report.md
```

---

## 🔧 Configuration Files

**Location**: User configs in `~/.config/delve/`, defaults in project `config/*.default.json`

| File | Purpose | Edit Often? |
|------|---------|-------------|
| `delve-config.json` | Main settings | Rarely |
| `security-config.json` | Security profiles | Often |
| `delve-modes.json` | Mode definitions | Rarely |
| `knowledge-config.json` | Knowledge sources | Sometimes |
| `paths.json` | Directory paths | Rarely |
| `adaptive-config.json` | Advanced tuning | Advanced only |

### Quick Edits

```bash
# Create user config first (if doesn't exist)
./src/utils/config-loader.sh init security-config

# Then edit in your home directory
nano ~/.config/delve/security-config.json
# Change: "security_profile": "strict" → "permissive"

# Reset to defaults: delete user config
rm ~/.config/delve/security-config.json
```

---

## 🆘 Quick Troubleshooting

| Error | Cause | Quick Fix |
|-------|-------|-----------|
| "Command not found" | Not in directory | `cd /path/to/delve` first |
| "Permission denied" | Not executable | `chmod +x delve` |
| "No such file" | Config missing | `./delve --init` |
| "Session not found" | Invalid session ID | Use `./delve sessions` to list |
| "Quality score too low" | Incomplete | `./delve resume SESSION_ID` |
| ".latest file not found" | No research yet | Run `./delve "test"` first |
| "jq: command not found" | Missing dependency | `brew install jq` (macOS) |

**For detailed troubleshooting**: See [Troubleshooting Guide](TROUBLESHOOTING.md)

---

## 💡 Copy-Paste Examples

### Basic Research

```bash
# Simple question
./delve "What is Docker?"

# Detailed question
./delve "What are the latest advances in CRISPR gene editing?"

# Business question
./delve "Total addressable market for AI SaaS tools in 2024"

# Technical question
./delve "How does Kubernetes handle container orchestration?"
```

### Research with Local Files

```bash
# Analyze pitch deck
./delve "Evaluate this startup" --input-dir ./pitch-materials/

# Research with context documents
./delve "Summarize findings" --input-dir ~/Documents/research/

# Market analysis with local reports
./delve "Market size analysis" --input-dir ./market-reports/

# Supported: PDFs (.pdf), Markdown (.md), Text (.txt)
```

### Academic Research

```bash
# Latest research
./delve "Latest advances in CRISPR gene editing 2023-2024"

# Specific topic
./delve "Machine learning in healthcare diagnostics"

# Methodology focus
./delve "Quantum error correction methods and effectiveness"
```

### Market Research

```bash
# Market sizing
./delve "SaaS CRM market size and growth 2024"

# Competitive analysis
./delve "Compare top 5 CRM platforms: features and pricing"

# Industry trends
./delve "Emerging trends in fintech 2024-2025"
```

### Technical Research

```bash
# Architecture
./delve "Docker containerization architecture"

# Comparison
./delve "Kubernetes vs Docker Swarm comparison"

# Best practices
./delve "Best practices for implementing OAuth 2.0"
```

---

## ⚡ Workflow Shortcuts

### Quick Research + View

```bash
./delve "question" && ./delve latest
```

### Continue Previous

```bash
# Resume most recent session
./delve latest  # Shows session ID
./delve resume <session_id_from_above>
```

### Export Latest Report

```bash
# Use delve latest to get the path, then copy
./delve latest  # Shows the path
# Or use path-resolver
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
cp "$SESSION_DIR"/$(cat "$SESSION_DIR"/.latest)/research-report.md ~/Documents/
```

### Archive Old Sessions

```bash
# Find your session directory first
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
mkdir -p "$HOME/delve-archive/"
mv "$SESSION_DIR"/session_old* "$HOME/delve-archive/"
```

### Monitor Progress

```bash
watch -n 5 './delve status'
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
./delve resume session_123  # Most effective way
```

---

## 📚 Session Management

### List Sessions

```bash
./delve sessions
```

### Find Latest

```bash
./delve latest
```

### Resume Research

```bash
./delve resume session_1759420487
./delve resume $(cat research-sessions/.latest)  # Resume latest
```

### Check Status

```bash
./delve status
```

### Organize Sessions

```bash
# Get session directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)

# Create project folders
mkdir -p "$SESSION_DIR/project-alpha/"
mv "$SESSION_DIR"/quantum-* "$SESSION_DIR/project-alpha/"

# Archive by date
mkdir -p "$HOME/delve-archive/2024-q3/"
mv "$SESSION_DIR"/session_old* "$HOME/delve-archive/2024-q3/"
```

---

## 🛠️ Shell Aliases

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Shortcuts (adjust path to your delve installation)
alias dl='/path/to/delve/delve'
alias dll='/path/to/delve/delve latest'
alias dls='/path/to/delve/delve sessions'
alias dlr='/path/to/delve/delve resume'

# Helper to get session directory
alias dldir='$(cd /path/to/delve && ./src/utils/path-resolver.sh resolve session_dir)'
```

**Usage after aliasing**:

```bash
dl "your question"              # Instead of ./delve
dll                            # Show latest
dls                            # List sessions
dlr session_123                # Resume
```

---

## 🎓 Learning Path

**New to Delve?** Try these in order:

1. **Test it works**:

   ```bash
   ./delve "What is Docker?"
   ```

2. **Check the result**:

   ```bash
   ./delve latest
   ```

3. **Try different topics**:

   ```bash
   ./delve "AI advances 2024"
   ./delve "SaaS market size"
   ```

4. **Resume to improve**:

   ```bash
   ./delve resume $(cat research-sessions/.latest)
   ```

---

## 🚧 Coming in v0.2

The following features are **planned but not yet available**:

```bash
# CLI options (NOT available in v0.1, coming in v0.2)
./delve "question" --mode scientific    # Explicit mode selection
./delve "question" --speed fast         # Control research depth
./delve "question" --output html        # HTML/JSON output formats
./delve "question" --name my-research   # Custom session names
./delve "question" --iterations 5       # Control iteration count
./delve "question" --interactive        # Guided research mode
./delve "question" --quiet              # Minimal output
```

**v0.1 alternatives**:

- Mode selection: Use keywords in question (e.g., "peer-reviewed research on...")
- Speed control: Edit `config/delve-config.json`
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

**Quick Start**: `./delve "your question"` → `./delve latest`

That's it! 🔍
