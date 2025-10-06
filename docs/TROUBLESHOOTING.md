# CConductor Troubleshooting Guide

**Solve common issues and get research back on track**

**Version**: 0.1.0  
**Last Updated**: October 2025  
**For**: All users

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Installation & Setup Issues](#installation--setup-issues)
3. [Research Execution Problems](#research-execution-problems)
4. [Quality & Results Issues](#quality--results-issues)
5. [Performance Problems](#performance-problems)
6. [Security & Permissions](#security--permissions)
7. [Configuration Problems](#configuration-problems)
8. [Session & File Issues](#session--file-issues)
9. [Getting Help](#getting-help)

---

## Quick Diagnostics

**Before diving into specific issues**, run these basic checks:

```bash
# 1. Check CConductor is installed correctly
./cconductor --version

# 2. Check for running research
ps aux | grep cconductor

# 3. Check disk space
df -h

# 4. Check recent sessions
./cconductor sessions

# 5. Check latest session status
./cconductor latest

# 6. Check for errors in logs (use your OS-appropriate log path)
# macOS: tail -50 ~/Library/Logs/CConductor/research.log
# Linux: tail -50 ~/.local/state/cconductor/research.log

# 7. Check for lock files in your sessions directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
find "$SESSION_DIR" -name "*.lock"
```

**If any of these fail**, proceed to relevant section below.

---

## Installation & Setup Issues

### CConductor Command Not Found

**Symptoms**:

```bash
$ ./cconductor "question"
-bash: ./cconductor: No such file or directory
```

**Causes**:

- Not in the CConductor directory
- File was deleted or moved
- Wrong working directory

**Solutions**:

**1. Verify you're in the right directory**:

```bash
pwd
# Should show: /path/to/cconductor or /path/to/research-engine

ls -la cconductor
# Should show executable file
```

**2. If not in directory, navigate to it**:

```bash
cd /path/to/cconductor
./cconductor --version
```

**3. If file doesn't exist, check installation**:

```bash
# Check if git repository
git status

# If it's a git repo, check if cconductor exists
ls -la | grep cconductor

# If missing, restore from git
git checkout cconductor
chmod +x cconductor
```

**4. Set up path (optional)**:

```bash
# Add to ~/.bashrc or ~/.zshrc:
export PATH="/path/to/cconductor:$PATH"
alias cconductor="/path/to/cconductor/cconductor"

# Then:
source ~/.bashrc  # or ~/.zshrc
cconductor --version   # Should work from anywhere
```

---

### Claude Code CLI Not Found

**Symptoms**:

```bash
$ ./cconductor "question"
❌ Error: Claude Code CLI not found

CConductor requires Claude Code CLI to function.
```

**Cause**: Claude Code CLI is not installed, or Node.js/npm is missing.

**Solution**:

**1. Install Node.js first** (if not installed):

```bash
# Check if Node.js is installed
node --version

# If not installed:

# macOS
# First check if Homebrew is installed:
brew --version

# If Homebrew is not installed, install it first:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Then install Node.js:
brew install node

# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify
node --version  # Should be v18 or higher
npm --version   # npm comes with Node.js
```

**2. Install Claude Code CLI**:

```bash
npm install -g @anthropic-ai/claude-code
```

**3. Verify installation**:

```bash
claude --version
# Should show: claude-code/x.x.x
```

**4. If installation fails with permissions error**:

```bash
# Option 1: Use sudo (not recommended)
sudo npm install -g @anthropic-ai/claude-code

# Option 2: Fix npm permissions (better)
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.zshrc
source ~/.zshrc
npm install -g @anthropic-ai/claude-code
```

**Requirements**:
- Node.js 18 or newer
- Claude.ai or Console account (Pro/Max subscription or API credits)

---

### Bash Version Error (macOS)

**Symptoms**:

```bash
$ ./cconductor "question"
Error: Bash 4.0 or higher is required for CLI parser
Current version: 3.2.57(1)-release

On macOS, install with: brew install bash
Then run with: /usr/local/bin/bash or /opt/homebrew/bin/bash
```

**Cause**: macOS ships with Bash 3.2 (from 2007) for licensing reasons, but CConductor requires Bash 4.0+ for associative arrays used in the CLI parser.

**Solutions**:

**1. Install Bash 4+ via Homebrew** (recommended):

```bash
brew install bash
```

**2. Run CConductor with the newer Bash**:

```bash
# Apple Silicon Mac
/opt/homebrew/bin/bash ./cconductor "what is quantum tunneling?"

# Intel Mac
/usr/local/bin/bash ./cconductor "what is quantum tunneling?"
```

**3. Create a permanent alias** (add to `~/.zshrc`):

```bash
alias cconductor='/opt/homebrew/bin/bash /path/to/cconductor/cconductor'
```

**4. Or update the shebang** in the `cconductor` script:

```bash
# Change first line from:
#!/usr/bin/env bash

# To (Apple Silicon):
#!/opt/homebrew/bin/bash

# Or (Intel):
#!/usr/local/bin/bash
```

**Verify installation**:

```bash
/opt/homebrew/bin/bash --version
# Should show: GNU bash, version 5.x or higher
```

---

### Permission Denied

**Symptoms**:

```bash
$ ./cconductor "question"
-bash: ./cconductor: Permission denied
```

**Cause**: File is not executable.

**Solution**:

```bash
chmod +x cconductor
chmod +x src/*.sh
chmod +x src/utils/*.sh
./cconductor --version  # Should work now
```

---

### Missing Dependencies

**Symptoms**:

- `jq: command not found`
- `curl: command not found`
- API errors

**Solutions**:

**Install jq**:

```bash
# macOS
# First check if Homebrew is installed:
brew --version
# If not: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install jq

# Linux (Ubuntu/Debian)
sudo apt-get install jq

# Linux (Fedora/RHEL)
sudo dnf install jq

# Verify
jq --version
```

**Install curl** (usually pre-installed on macOS and most Linux):

```bash
# Check if already installed
curl --version

# macOS (if needed)
brew install curl

# Linux (if needed)
sudo apt-get install curl

# Verify
curl --version
```

**Set Claude API key**:

```bash
# Check if set
echo $ANTHROPIC_API_KEY

# If empty, set it
export ANTHROPIC_API_KEY="your-key-here"

# Make permanent (add to ~/.bashrc or ~/.zshrc)
echo 'export ANTHROPIC_API_KEY="your-key-here"' >> ~/.bashrc
source ~/.bashrc
```

---

## Research Execution Problems

### Research Starts But Immediately Fails

**Symptoms**:

- Research begins but errors out in first minute
- No output in session directory
- Error in logs

**Check logs first**:

```bash
tail -50 logs/research.log
# Look for error messages
```

**Common causes**:

**1. API Key Issues**:

```bash
# Check key is set
echo $ANTHROPIC_API_KEY

# Test API connection
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}'

# Should return a response, not an error
```

**2. Network Issues**:

```bash
# Test internet connection
ping -c 3 api.anthropic.com

# Test HTTPS
curl -I https://api.anthropic.com

# Check proxy settings if needed
echo $HTTP_PROXY
echo $HTTPS_PROXY
```

**3. Invalid Research Question**:

```bash
# Question too short or empty
./cconductor ""  # ❌ Will fail

# Solution: Provide meaningful question
./cconductor "What is CRISPR and how does it work?"  # ✅
```

---

### Research Hangs or Freezes

**Symptoms**:

- Research starts but makes no progress
- No new output for 5+ minutes
- Process is running but seemingly stuck

**Diagnosis**:

**1. Check if process is actually running**:

```bash
ps aux | grep cconductor
# Should show running process

# Check CPU usage
top -p $(pgrep -f cconductor)
# Should show some activity
```

**2. Check for network issues**:

```bash
# Monitor network activity
netstat -an | grep ESTABLISHED | grep 443

# Check if waiting on API
tail -f logs/research.log
# Should see activity
```

**Solutions**:

**If genuinely stuck**:

```bash
# Find PID
ps aux | grep cconductor

# Interrupt gracefully
kill -INT <PID>

# Wait 30 seconds, then force if needed
kill -9 <PID>

# Resume research
./cconductor sessions
./cconductor resume session_name
```

**If waiting on slow API**:

- Be patient, especially for first few minutes
- Academic PDF fetching can be slow
- Large research topics take time (20-40 minutes normal)

**If repeatedly hanging**:

- Check network stability
- Try simpler question first
- Check API rate limits

---

### Session Locked Error

**Symptoms**:

```
❌ Research session is locked

Another research process is using this session, or a previous
session didn't exit cleanly.

Waited: 30 seconds
```

**Causes**:

- Another research is running on same session
- Previous research crashed
- Stale lock files

**Solutions**:

**Step 1: Check for active research**:

```bash
ps aux | grep cconductor-wrapper
ps aux | grep adaptive-research

# If found, check if it's legitimately running
tail -f logs/research.log
```

**Step 2: If process is stuck, kill it**:

```bash
# Get PID from ps output
kill <PID>

# If doesn't respond:
kill -9 <PID>
```

**Step 3: Remove stale locks**:

```bash
# Find locks
find research-sessions -name "*.lock"

# Remove all locks
find research-sessions -name "*.lock" -exec rm -rf {} +

# Or for specific session
rm -rf research-sessions/session_*/knowledge-graph.json.lock
rm -rf research-sessions/session_*/task-queue.json.lock
```

**Step 4: Resume research**:

```bash
./cconductor resume session_name
```

**Prevention**:

- Don't Ctrl+C during research
- Let research complete naturally
- Use `./cconductor status` before starting new research

---

### Can't Resume Session

**Symptoms**:

```bash
$ ./cconductor resume my-session
Error: Session not found
```

**Solutions**:

**1. List available sessions**:

```bash
./cconductor sessions
# Copy exact session name from output
```

**2. Check session directory exists**:

```bash
ls -la research-sessions/ | grep my-session
```

**3. If session exists but not listed**:

```bash
# Session might be corrupted
# Check for required files:
ls research-sessions/my-session/

# Should have:
# - raw/ directory
# - intermediate/ directory
# - research-question.txt (in raw/)
# - research-plan.json (in raw/)
```

**4. If session is corrupted**:

```bash
# You may need to start fresh with similar question
./cconductor "original question again"
```

---

## Quality & Results Issues

### Low Quality Score

**Symptoms**:

- Quality score below 70
- Report says "NEEDS WORK" or "ACCEPTABLE"
- Missing citations or sources

**See**: [Quality Guide](QUALITY_GUIDE.md) for complete troubleshooting.

**Quick fixes**:

**1. Resume research** (most effective):

```bash
./cconductor resume session_name
# Adds 10-15 points typically
```

**2. Ask more specific question**:

```bash
# Instead of:
./cconductor "AI trends"  # Too vague

# Try:
./cconductor "peer-reviewed research on large language model safety techniques 2023-2024"
```

**3. Provide PDF sources**:

```bash
mkdir -p pdfs/
cp your-papers/*.pdf pdfs/
./cconductor "question related to papers"
```

**4. Let research complete fully**:

- Don't interrupt early
- First 10 min: ~65 score
- 20 min: ~75 score  
- 30+ min: ~85+ score

---

### Missing or Poor Citations

**Symptoms**:

- Few or no citations in report
- Citation coverage below 70%
- No bibliography section

**See**: [Citations Guide](CITATIONS_GUIDE.md) for complete troubleshooting.

**Quick fixes**:

**1. Resume research**:

```bash
./cconductor resume session_name
# Citations improve significantly
```

**2. Use academic keywords**:

```bash
./cconductor "peer-reviewed studies on [topic]"
./cconductor "published research on [topic]"
./cconductor "academic literature on [topic]"
```

**3. Configure for academic mode**:
Edit `config/cconductor-config.json`:

```json
{
  "research": {
    "min_source_credibility": "high",
    "min_sources_per_claim": 5
  }
}
```

**4. Provide academic PDFs**:

```bash
mkdir -p pdfs/
# Add PDFs of papers
./cconductor "question about these papers"
```

---

### Results Are Wrong or Outdated

**Symptoms**:

- Information is factually incorrect
- Data is from wrong year
- Contradicts known facts

**Causes**:

- Question wasn't specific enough
- Sources were outdated
- Low quality research

**Solutions**:

**1. Check source dates in report**:
Look at bibliography - when were sources published?

**2. Specify time frame in question**:

```bash
# Instead of:
./cconductor "market size for CRM software"

# Try:
./cconductor "market size for CRM software in 2024 based on recent reports"
```

**3. Resume research for more sources**:

```bash
./cconductor resume session_name
# Gets additional verification
```

**4. Check quality score**:

```bash
./cconductor latest
# Scroll to quality assessment
# If below 75, consider restarting with better question
```

**5. Provide authoritative sources**:
Add known good sources to `knowledge-base-custom/`:

```markdown
## Authoritative Sources
- Source 1: https://official-data.com
- Source 2: https://industry-report.com
```

---

### Research Doesn't Answer My Question

**Symptoms**:

- Report is about wrong topic
- Doesn't address what I asked
- Too general or too specific

**Causes**:

- Question was ambiguous
- Wrong research mode triggered
- Question was too broad or narrow

**Solutions**:

**1. Restart with clearer question**:

```bash
# Be more specific about what you want
./cconductor "What are the therapeutic mechanisms of action for CAR-T cell therapy in treating B-cell lymphomas?"

# Not:
./cconductor "CAR-T therapy"
```

**2. Check what mode was used**:

```bash
# Look in research-sessions/[session]/raw/research-plan.json
jq '.mode' research-sessions/[session]/raw/research-plan.json
```

**3. Specify domain in question**:

```bash
# For academic:
./cconductor "peer-reviewed research on [topic]"

# For market:
./cconductor "market size and competitive landscape for [product]"

# For technical:
./cconductor "technical architecture and implementation of [technology]"
```

---

## Performance Problems

### Research Is Very Slow

**Symptoms**:

- Taking hours for simple questions
- Much slower than expected
- Progress seems minimal

**Diagnosis**:

**1. Check what's happening**:

```bash
tail -f logs/research.log
# Should see activity
```

**2. Check if it's normal for your question**:

- Complex topics: 30-60 minutes normal
- Academic with many PDFs: 40-90 minutes
- Simple questions: 10-20 minutes
- Market research: 20-40 minutes

**3. Check network speed**:

```bash
# Test API latency
time curl -s -o /dev/null -w "%{time_total}\n" https://api.anthropic.com
# Should be < 1 second
```

**Solutions**:

**If too slow**:

**1. Check parallel execution**:
Edit `config/cconductor-config.json`:

```json
{
  "agents": {
    "parallel_execution": true,
    "max_parallel_agents": 4
  }
}
```

**2. Reduce depth for faster results**:

```json
{
  "research": {
    "max_web_searches": 3,
    "sources_per_search": 5,
    "min_sources_per_claim": 2
  }
}
```

**3. Simplify question**:

```bash
# Break complex question into parts
# Do multiple focused researches instead of one huge one
```

**4. Check system resources**:

```bash
# CPU
top

# Memory
free -h

# Disk I/O
iostat

# If system is overloaded, that's your bottleneck
```

---

### High API Costs

**Symptoms**:

- Unexpected high costs
- Using more tokens than expected

**Understanding costs**:

- Complex research: $2-10
- Simple research: $0.50-$2
- Academic (with PDFs): $5-15
- Very thorough research: $10-25

**Reduce costs**:

**1. Limit searches**:
Edit `config/cconductor-config.json`:

```json
{
  "research": {
    "max_web_searches": 3,
    "sources_per_search": 5
  }
}
```

**2. Reduce parallel agents**:

```json
{
  "agents": {
    "max_parallel_agents": 2
  }
}
```

**3. Disable expensive features**:

```json
{
  "research": {
    "include_code_analysis": false
  },
  "research_modes": {
    "scientific": {
      "track_citation_network": false
    }
  }
}
```

**4. Use shorter timeouts**:

```json
{
  "agents": {
    "agent_timeout_minutes": 5
  }
}
```

**5. Ask focused questions**:

- Specific questions cost less than broad ones
- Break big questions into smaller parts

---

## Security & Permissions

### Security Prompts Too Frequent

**Symptoms**:

- Constantly asked about domains
- Interrupts research flow
- Prompts for trusted sites

**Solution**: Switch security profile.

Edit `config/security-config.json`:

```json
{
  "security_profile": "permissive"
}
```

**Profiles**:

- `"strict"` (default): Maximum prompts, maximum safety
- `"permissive"`: Fewer prompts for trusted sites
- `"max_automation"`: Minimal prompts (VMs only!)

**See**: [Security Guide](SECURITY_GUIDE.md) for details.

---

### Can't Access Needed Sources

**Symptoms**:

- Research blocked from important domain
- Source is denied access
- "Security: blocked domain" in logs

**Solutions**:

**1. Check if domain is blocked**:

```bash
jq '.domain_lists.blocked' config/security-config.json
# See if your domain is listed
```

**2. Add domain to trusted list**:
Edit `config/security-config.json`:

```json
{
  "domain_lists": {
    "commercial": [
      "your-needed-domain.com"
    ]
  }
}
```

**3. Temporarily use permissive mode**:

```json
{
  "security_profile": "permissive"
}
```

**4. For academic domain, add to academic list**:

```json
{
  "domain_lists": {
    "academic": [
      "your-university.edu",
      "research-institute.org"
    ]
  }
}
```

---

### API Key Errors

**Symptoms**:

```
Error: API key not found
Error: Invalid API key
Error: Authentication failed
```

**Solutions**:

**1. Check key is set**:

```bash
echo $ANTHROPIC_API_KEY
# Should show your key
```

**2. If not set**:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."

# Make permanent
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
source ~/.bashrc
```

**3. Verify key is valid**:

```bash
# Test API call
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4-5","max_tokens":10,"messages":[{"role":"user","content":"test"}]}'
```

**4. Check for typos**:

- Key should start with `sk-ant-`
- No spaces before or after
- Complete key copied

**5. Generate new key if needed**:

- Go to console.anthropic.com
- API Keys section
- Generate new key
- Update `ANTHROPIC_API_KEY`

---

## Configuration Problems

### Config File Syntax Errors

**Symptoms**:

```
Error: Invalid JSON in config file
Error: Unexpected token in config
```

**Solutions**:

**1. Validate JSON syntax**:

```bash
jq empty config/cconductor-config.json
# No output = valid
# Error message = fix syntax
```

**2. Common JSON mistakes**:

```json
// ❌ Wrong:
{
  "option": "value",  // ← trailing comma
}

// ✅ Correct:
{
  "option": "value"
}

// ❌ Wrong:
{
  option: "value"  // ← unquoted key
}

// ✅ Correct:
{
  "option": "value"
}
```

**3. Reset to default**:

```bash
cp config/cconductor-config.default.json config/cconductor-config.json
# Start fresh with defaults
```

**4. Use JSON validator**:

- Copy config contents
- Paste into jsonlint.com
- Fix reported errors

---

### Configuration Not Taking Effect

**Symptoms**:

- Changed config but behavior unchanged
- Settings seem ignored
- Old behavior persists

**Solutions**:

**1. Verify you edited right file**:

```bash
# Should edit .json (NOT .default.json)
ls -la config/*.json

# Check your edits are there
jq . config/cconductor-config.json | grep "your-setting"
```

**2. Check for syntax errors**:

```bash
jq empty config/cconductor-config.json
```

**3. Restart any running research**:

```bash
# Changes only apply to new sessions
# Not to already-running research
```

**4. Check file permissions**:

```bash
ls -la config/cconductor-config.json
# Should be readable (-rw-r--r--)
```

**5. Check environment variable overrides**:

```bash
# These override config files
echo $CCONDUCTOR_SECURITY_PROFILE
echo $RESEARCH_MODE
echo $LOG_LEVEL

# Unset if needed
unset CCONDUCTOR_SECURITY_PROFILE
```

---

### Unknown Configuration Option

**Symptoms**:

- Warning about unknown config option
- Config option has no effect
- Documentation mentions option not in config

**Cause**: Option might be planned for v0.2 but not yet implemented.

**Check**: [Configuration Reference](CONFIGURATION_REFERENCE.md) for all v0.1 options.

**If option is missing**:

- Feature may be planned for a future release
- Use workaround if available
- Check GitHub issues or open a new one if critical

---

## Session & File Issues

### Can't Find Research Results

**Symptoms**:

- Completed research but can't find report
- Don't know where output went
- Lost session name

**Solutions**:

**1. Find latest session**:

```bash
./cconductor latest
# Shows info about most recent research
```

**2. List all sessions**:

```bash
./cconductor sessions
# Shows all research sessions
```

**3. Find report file**:

```bash
# Report is always here:
ls research-sessions/*/research-report.md

# Or for specific session:
cat research-sessions/session_*/research-report.md
```

**4. Check .latest marker**:

```bash
cat research-sessions/.latest
# Shows latest session ID

# View that report:
cat research-sessions/$(cat research-sessions/.latest)/research-report.md
```

---

### Session Directory Is Huge

**Symptoms**:

- Session taking gigabytes of space
- Disk space warning
- Slow file operations

**Diagnosis**:

```bash
# Check session sizes
du -sh research-sessions/*

# Find largest sessions
du -sh research-sessions/* | sort -h | tail -5

# Check what's using space
du -sh research-sessions/session_*/raw
du -sh research-sessions/session_*/intermediate
```

**Common causes**:

- Many large PDFs downloaded
- Extensive web fetches
- Long-running adaptive research

**Solutions**:

**1. Clean old sessions** (safe):

```bash
# Remove sessions older than 30 days
find research-sessions -name "session_*" -type d -mtime +30 -exec rm -rf {} +
```

**2. Remove test/failed sessions** (safe):

```bash
# List sessions to identify test ones
./cconductor sessions

# Remove specific session
rm -rf research-sessions/test-session-name
```

**3. Archive old research** (safe):

```bash
# Create archive directory
mkdir -p research-sessions-archive

# Move old sessions
mv research-sessions/session_old* research-sessions-archive/

# Or compress
tar -czf research-archive-$(date +%Y%m).tar.gz research-sessions/session_old*
rm -rf research-sessions/session_old*
```

**4. Limit raw data retention** (advanced):

```bash
# Keep only final reports, remove intermediate data
# WARNING: Can't resume these sessions afterward
for session in research-sessions/session_*; do
  # Keep: research-report.md, research-question.txt
  # Remove: raw/, intermediate/ (large)
  rm -rf "$session/raw"
  rm -rf "$session/intermediate"
done
```

---

### Corrupted Session Data

**Symptoms**:

```
Error: Invalid JSON in knowledge-graph.json
Error: Cannot read session data
jq parse error
```

**Diagnosis**:

```bash
# Check which file is corrupted
jq empty research-sessions/session_*/knowledge-graph.json
jq empty research-sessions/session_*/task-queue.json

# Check file sizes (0 bytes = corrupted)
ls -lh research-sessions/session_*/*.json
```

**Solutions**:

**If research is still running**:

1. Stop research (kill process)
2. Remove lock files
3. Restart research (will reinitialize)

**If research completed but files corrupted**:

1. Check if `research-report.md` is intact:

   ```bash
   cat research-sessions/session_*/research-report.md
   ```

2. If report is good, you have your results (other files don't matter)
3. If report is corrupted, research must be restarted

**Prevention**:

- Don't force-kill research (use `kill`, not `kill -9`)
- Ensure adequate disk space
- Don't edit session files manually
- Let research complete naturally

---

## Getting Help

### Collecting Diagnostic Information

**Before asking for help**, collect this info:

```bash
# 1. Version
./cconductor --version

# 2. System info
uname -a
bash --version
jq --version

# 3. Recent logs
tail -100 logs/research.log > problem-logs.txt

# 4. Session info (if relevant)
./cconductor sessions > sessions-info.txt

# 5. Config (remove sensitive data!)
jq 'del(.advanced.mcp_servers)' config/cconductor-config.json > config-sanitized.json

# 6. Error message (exact text)
```

### Where to Get Help

**1. Documentation**:

- [User Guide](USER_GUIDE.md) - Complete usage
- [Quick Reference](QUICK_REFERENCE.md) - Command cheat sheet
- [Configuration Reference](CONFIGURATION_REFERENCE.md) - All settings

**2. Guides**:

- [Quality Guide](QUALITY_GUIDE.md) - Quality troubleshooting
- [Citations Guide](CITATIONS_GUIDE.md) - Citation issues
- [Security Guide](SECURITY_GUIDE.md) - Security configuration
- [Custom Knowledge](CUSTOM_KNOWLEDGE.md) - Knowledge base issues

**3. Logs**:

```bash
# Research log
tail -100 logs/research.log

# System errors
dmesg | tail

# CConductor-specific errors
grep ERROR logs/*.log
```

**4. Community** (if available):

- GitHub Issues (if open source)
- Community forum
- Discord/Slack

---

## Quick Reference

### Essential Commands

```bash
# Start research
./cconductor "research question"

# Check status
./cconductor status

# List sessions
./cconductor sessions

# Get latest session
./cconductor latest

# Resume research
./cconductor resume session_name

# Check version
./cconductor --version

# Get help
./cconductor --help
```

### Essential File Locations

```bash
# Configuration
config/cconductor-config.json
config/security-config.json
config/cconductor-modes.json

# Session data
research-sessions/[session-name]/research-report.md

# Logs
logs/research.log

# Custom knowledge
knowledge-base-custom/

# PDFs for analysis
pdfs/
```

### Essential Checks

```bash
# API key set?
echo $ANTHROPIC_API_KEY

# Config valid?
jq empty config/cconductor-config.json

# Disk space?
df -h

# Any locks?
find research-sessions -name "*.lock"

# Research running?
ps aux | grep cconductor

# Recent errors?
grep ERROR logs/research.log | tail -10
```

---

**Last Updated**: October 2025  
**Version**: 0.1.0

**For more help**, see [User Guide](USER_GUIDE.md) or visit the documentation.

---

**CConductor Troubleshooting** - Get back on track 🔧
