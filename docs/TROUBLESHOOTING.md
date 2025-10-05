# Delve Troubleshooting Guide

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
# 1. Check Delve is installed correctly
./delve --version

# 2. Check for running research
ps aux | grep delve

# 3. Check disk space
df -h

# 4. Check recent sessions
./delve sessions

# 5. Check latest session status
./delve latest

# 6. Check for errors in logs (use your OS-appropriate log path)
# macOS: tail -50 ~/Library/Logs/Delve/research.log
# Linux: tail -50 ~/.local/state/delve/research.log

# 7. Check for lock files in your sessions directory
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
find "$SESSION_DIR" -name "*.lock"
```

**If any of these fail**, proceed to relevant section below.

---

## Installation & Setup Issues

### Delve Command Not Found

**Symptoms**:

```bash
$ ./delve "question"
-bash: ./delve: No such file or directory
```

**Causes**:

- Not in the Delve directory
- File was deleted or moved
- Wrong working directory

**Solutions**:

**1. Verify you're in the right directory**:

```bash
pwd
# Should show: /path/to/delve or /path/to/research-engine

ls -la delve
# Should show executable file
```

**2. If not in directory, navigate to it**:

```bash
cd /path/to/delve
./delve --version
```

**3. If file doesn't exist, check installation**:

```bash
# Check if git repository
git status

# If it's a git repo, check if delve exists
ls -la | grep delve

# If missing, restore from git
git checkout delve
chmod +x delve
```

**4. Set up path (optional)**:

```bash
# Add to ~/.bashrc or ~/.zshrc:
export PATH="/path/to/delve:$PATH"
alias delve="/path/to/delve/delve"

# Then:
source ~/.bashrc  # or ~/.zshrc
delve --version   # Should work from anywhere
```

---

### Permission Denied

**Symptoms**:

```bash
$ ./delve "question"
-bash: ./delve: Permission denied
```

**Cause**: File is not executable.

**Solution**:

```bash
chmod +x delve
chmod +x src/*.sh
chmod +x src/utils/*.sh
./delve --version  # Should work now
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
# Mac
brew install jq

# Linux (Ubuntu/Debian)
sudo apt-get install jq

# Linux (Fedora/RHEL)
sudo dnf install jq

# Verify
jq --version
```

**Install curl** (usually pre-installed):

```bash
# Mac
brew install curl

# Linux
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
./delve ""  # ❌ Will fail

# Solution: Provide meaningful question
./delve "What is CRISPR and how does it work?"  # ✅
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
ps aux | grep delve
# Should show running process

# Check CPU usage
top -p $(pgrep -f delve)
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
ps aux | grep delve

# Interrupt gracefully
kill -INT <PID>

# Wait 30 seconds, then force if needed
kill -9 <PID>

# Resume research
./delve sessions
./delve resume session_name
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
ps aux | grep delve-wrapper
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
./delve resume session_name
```

**Prevention**:

- Don't Ctrl+C during research
- Let research complete naturally
- Use `./delve status` before starting new research

---

### Can't Resume Session

**Symptoms**:

```bash
$ ./delve resume my-session
Error: Session not found
```

**Solutions**:

**1. List available sessions**:

```bash
./delve sessions
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
./delve "original question again"
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
./delve resume session_name
# Adds 10-15 points typically
```

**2. Ask more specific question**:

```bash
# Instead of:
./delve "AI trends"  # Too vague

# Try:
./delve "peer-reviewed research on large language model safety techniques 2023-2024"
```

**3. Provide PDF sources**:

```bash
mkdir -p pdfs/
cp your-papers/*.pdf pdfs/
./delve "question related to papers"
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
./delve resume session_name
# Citations improve significantly
```

**2. Use academic keywords**:

```bash
./delve "peer-reviewed studies on [topic]"
./delve "published research on [topic]"
./delve "academic literature on [topic]"
```

**3. Configure for academic mode**:
Edit `config/delve-config.json`:

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
./delve "question about these papers"
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
./delve "market size for CRM software"

# Try:
./delve "market size for CRM software in 2024 based on recent reports"
```

**3. Resume research for more sources**:

```bash
./delve resume session_name
# Gets additional verification
```

**4. Check quality score**:

```bash
./delve latest
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
./delve "What are the therapeutic mechanisms of action for CAR-T cell therapy in treating B-cell lymphomas?"

# Not:
./delve "CAR-T therapy"
```

**2. Check what mode was used**:

```bash
# Look in research-sessions/[session]/raw/research-plan.json
jq '.mode' research-sessions/[session]/raw/research-plan.json
```

**3. Specify domain in question**:

```bash
# For academic:
./delve "peer-reviewed research on [topic]"

# For market:
./delve "market size and competitive landscape for [product]"

# For technical:
./delve "technical architecture and implementation of [technology]"
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
Edit `config/delve-config.json`:

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
Edit `config/delve-config.json`:

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
jq empty config/delve-config.json
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
cp config/delve-config.default.json config/delve-config.json
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
jq . config/delve-config.json | grep "your-setting"
```

**2. Check for syntax errors**:

```bash
jq empty config/delve-config.json
```

**3. Restart any running research**:

```bash
# Changes only apply to new sessions
# Not to already-running research
```

**4. Check file permissions**:

```bash
ls -la config/delve-config.json
# Should be readable (-rw-r--r--)
```

**5. Check environment variable overrides**:

```bash
# These override config files
echo $DELVE_SECURITY_PROFILE
echo $RESEARCH_MODE
echo $LOG_LEVEL

# Unset if needed
unset DELVE_SECURITY_PROFILE
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
./delve latest
# Shows info about most recent research
```

**2. List all sessions**:

```bash
./delve sessions
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
./delve sessions

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
./delve --version

# 2. System info
uname -a
bash --version
jq --version

# 3. Recent logs
tail -100 logs/research.log > problem-logs.txt

# 4. Session info (if relevant)
./delve sessions > sessions-info.txt

# 5. Config (remove sensitive data!)
jq 'del(.advanced.mcp_servers)' config/delve-config.json > config-sanitized.json

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

# Delve-specific errors
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
./delve "research question"

# Check status
./delve status

# List sessions
./delve sessions

# Get latest session
./delve latest

# Resume research
./delve resume session_name

# Check version
./delve --version

# Get help
./delve --help
```

### Essential File Locations

```bash
# Configuration
config/delve-config.json
config/security-config.json
config/delve-modes.json

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
jq empty config/delve-config.json

# Disk space?
df -h

# Any locks?
find research-sessions -name "*.lock"

# Research running?
ps aux | grep delve

# Recent errors?
grep ERROR logs/research.log | tail -10
```

---

**Last Updated**: October 2025  
**Version**: 0.1.0

**For more help**, see [User Guide](USER_GUIDE.md) or visit the documentation.

---

**Delve Troubleshooting** - Get back on track 🔧
