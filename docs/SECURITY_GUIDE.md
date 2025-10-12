# CConductor Security Configuration Guide

**Configure security to protect against malicious sites and unsafe content**

**Last Updated**: October 2025  
**For**: IT-conscious users and administrators

---

## Table of Contents

1. [Introduction](#introduction)
2. [Security Profiles Overview](#security-profiles-overview)
3. [Changing Your Security Profile](#changing-your-security-profile)
4. [Understanding Domain Categories](#understanding-domain-categories)
5. [Handling Security Prompts](#handling-security-prompts)
6. [Advanced Configuration](#advanced-configuration)
7. [For IT Administrators](#for-it-administrators)
8. [Troubleshooting](#troubleshooting)

---

## Introduction

CConductor includes configurable security to protect against:

- Malicious websites and content
- Data exfiltration attempts  
- Unsafe or suspicious domains
- Unauthorized access

This guide helps you choose the right security level for your use case.

**Who needs this**:

- Corporate users handling sensitive data
- Security-conscious researchers
- IT administrators deploying CConductor
- Users researching sensitive topics

---

## Security Profiles Overview

CConductor provides three security profiles with different trade-offs between safety and convenience.

### Strict Mode (Default) 🔒

**Best for**:

- Academic research
- Sensitive data handling
- Corporate environments
- Unknown or untrusted topics

**Configuration**:

```json
{
  "security_profile": "strict"
}
```

**What it does**:

- ✅ Auto-allows: `.edu`, `.gov`, `.ac.uk`, major academic sites
- ⚠️  Prompts for: Unknown or commercial domains  
- ❌ Blocks: Known malicious sites, URL shorteners
- ✅ Validates: All content before processing

**Example prompt**:

```
⚠️  Security Check: Unfamiliar Domain

Domain: example-research-site.com
Category: Unknown
Reason: First access to this domain
Context: Fetching research data

Your options:
  [A] Allow once - for this research only
  [S] Allow always - add to trusted list
  [D] Deny - skip this source

Choose: _
```

**Pros**:

- Maximum safety and control
- See every new domain before access
- No surprises

**Cons**:

- More prompts during research
- Slightly slower for new domains

---

### Permissive Mode ⚡

**Best for**:

- Business research
- Trusted network environments
- Experienced users
- Speed-prioritized research

**Configuration**:

```json
{
  "security_profile": "permissive"
}
```

**What it does**:

- ✅ Auto-allows: Major sites (Wikipedia, GitHub, Bloomberg, etc.)
- ✅ Auto-allows: `.edu`, `.gov`, trusted commercial domains
- ⚠️  Prompts for: Truly unknown or suspicious domains
- ❌ Blocks: Known malicious sites

**Fewer prompts**: You'll only see prompts for genuinely unusual domains.

**Pros**:

- Faster research (fewer interruptions)
- Still safe for most use cases
- Good balance of safety and speed

**Cons**:

- Less control over every domain
- Auto-allows more commercial sites

---

### Max Automation Mode 🚀

**Best for**:

- Testing and development
- Sandboxed environments (VMs, containers)
- Non-sensitive research **ONLY**

**Configuration**:

```json
{
  "security_profile": "max_automation"
}
```

**What it does**:

- ✅ Auto-allows: Almost all domains
- ⚠️  Prompts rarely: Only for truly suspicious patterns
- ❌ Blocks: Known malicious sites only
- ⚡ Minimal validation for speed

⚠️ **WARNING**: Only use in isolated environments!

**Pros**:

- Maximum speed
- Minimal prompts
- Best for automated testing

**Cons**:

- Less security protection
- Not suitable for sensitive work
- Should only be used in VMs or containers

**When to use**:

- Running CConductor in Docker container
- Testing in isolated VM
- Development environment only
- Never for production research with sensitive data

---

## Changing Your Security Profile

### Step-by-Step

**1. Open the config file**:

```bash
nano config/security-config.json
```

Or use your preferred editor:

```bash
vim config/security-config.json
# or
code config/security-config.json
```

**2. Find the setting** (should be near the top):

```json
{
  "security_profile": "strict",
  ...
}
```

**3. Change the value**:

```json
"strict"       → Maximum safety (default)
"permissive"   → Balanced approach  
"max_automation" → Minimum prompts (testing only)
```

**4. Save and close**:

- nano: `Ctrl+X`, then `Y`, then `Enter`
- vim: `ESC`, then `:wq`, then `Enter`
- VS Code: `Cmd+S` (Mac) or `Ctrl+S` (Windows/Linux)

**5. Verify the change**:

```bash
cat config/security-config.json | grep security_profile
# Should show your new setting
```

### Visual Guide

**Before** (strict mode):

```json
{
  "security_profile": "strict",
  "profiles": {
    "strict": {
      "description": "Production: Academic auto-allowed, commercial prompt once",
      ...
    }
  }
}
```

**After** (permissive mode):

```json
{
  "security_profile": "permissive",
  "profiles": {
    "strict": {
      "description": "Production: Academic auto-allowed, commercial prompt once",
      ...
    }
  }
}
```

**Important**: Only change the `"security_profile"` value at the top. Don't modify the profile definitions themselves.

---

## Understanding Domain Categories

CConductor categorizes all domains into groups with different handling rules.

### Auto-Allowed Domains (All Modes)

These domains are always allowed without prompts:

**Academic & Government**:

- `.edu` - Educational institutions
- `.gov` - U.S. Government  
- `.ac.uk` - UK academic institutions
- `arxiv.org` - Academic paper repository
- `semanticscholar.org` - Research papers
- `pubmed.ncbi.nlm.nih.gov` - Medical research
- Major publishers: `nature.com`, `science.org`, `springer.com`

**Major Platforms**:

- `wikipedia.org` - Wikipedia
- `github.com` - Code repositories

**Complete list** in: `config/security-config.json` → `domain_lists.academic`

---

### Trusted Commercial (Profile-Dependent)

Business and commercial sites with different handling by profile:

**Business News & Data**:

- `bloomberg.com`, `reuters.com`, `forbes.com`
- `wsj.com`, `economist.com`, `ft.com`
- `crunchbase.com`, `pitchbook.com`

**Technology News**:

- `techcrunch.com`, `wired.com`, `theverge.com`

**Handling**:

- **Strict mode**: Prompts on first access
- **Permissive mode**: Auto-allowed
- **Max automation**: Auto-allowed

**Complete list** in: `config/security-config.json` → `domain_lists.commercial`

---

### Unknown Domains

Any domain not in the above categories.

**Examples**:

- Company blogs
- Personal websites
- Regional news sites
- Specialized databases

**Handling**:

- **Strict mode**: Always prompts
- **Permissive mode**: Prompts
- **Max automation**: Auto-allowed (risky!)

**This is where profiles differ most**: Strict mode protects you by prompting for every unknown domain.

---

### Blocked Domains

Known malicious or problematic sites, always blocked in all modes:

**URL Shorteners** (can hide malicious links):

- `bit.ly`, `tinyurl.com`, `t.co`, `goo.gl`

**Free/suspicious TLDs**:

- `.tk`, `.ml`, `.ga`, `.cf`, `.gq`

**Complete list** in: `config/security-config.json` → `domain_lists.blocked`

---

## Handling Security Prompts

### Understanding the Prompt

When you see this prompt:

```
⚠️  Security Check: Unfamiliar Domain

Domain: research-example-site.com
Category: Unknown
Reason: First access to this domain
Context: Fetching market research data

Your options:
  [A] Allow once - for this research only
  [S] Allow always - add to trusted list
  [D] Deny - skip this source

Choose: _
```

**What each choice does**:

**[A] Allow once**:

- Domain is accessed this one time only
- Will prompt again in future research sessions
- Does NOT add to any permanent list
- Safe default when unsure

**[S] Allow always**:

- Domain is added to your personal trusted list
- Never prompts for this domain again (any session)
- Use for sites you trust and use often
- Effectively adds to your "commercial_trusted" list

**[D] Deny**:

- Skips this source entirely
- Research continues without it
- Use for suspicious or irrelevant domains
- No impact on future sessions

### Decision Guide

**Choose "Allow once" [A] when**:

- ✅ Domain looks legitimate and professional
- ✅ Relevant to your research topic
- ✅ First time seeing this domain
- ✅ Not sure if you'll use it again
- ✅ **When in doubt, choose this** - safest option

**Choose "Allow always" [S] when**:

- ✅ Well-known site in your field
- ✅ You'll use it regularly for research
- ✅ Company or industry standard source
- ✅ You've verified it's trustworthy
- ✅ Don't want to see this prompt again

**Choose "Deny" [D] when**:

- ❌ Suspicious or sketchy URL
- ❌ Not related to your research
- ❌ Looks like spam or malware
- ❌ Domain seems irrelevant
- ❌ Want to skip this source

### Is It Safe to Allow?

**Check these indicators**:

**1. Domain looks professional?**

- ✅ Good: `ibm.com/research`, `stanford.edu/papers`
- ❌ Bad: `research-free-download-now.tk`, `study-help123.ml`

**2. Uses HTTPS (secure)?**

- ✅ Good: `https://` - encrypted connection
- ❌ Bad: `http://` - not secure (though CConductor warns about this)

**3. Matches research context?**

- ✅ Good: Tech blog for tech research, medical journal for health research
- ❌ Bad: Random unrelated site appearing in results

**4. Known organization?**

- ✅ Good: Recognizable university, company, or publication
- ❌ Bad: Unknown site with generic name

**5. TLD (domain ending) reputable?**

- ✅ Good: `.com`, `.org`, `.edu`, `.gov`, `.io`, `.co`
- ⚠️  Neutral: Country codes (`.uk`, `.de`, `.jp`)
- ❌ Bad: `.tk`, `.ml`, `.ga` (often used for spam)

**When in doubt**: Choose "Allow once" [A]. It's the safe middle ground.

---

## Advanced Configuration

### Custom Domain Lists

You can customize which domains are trusted or blocked.

**Edit**: `config/security-config.json`

#### Adding Trusted Domains

Add domains you frequently use to your trusted list:

```json
{
  "domain_lists": {
    "commercial": [
      "example-research-site.com",
      "company-blog.com",
      "industry-database.org"
    ]
  }
}
```

**Effect**: These domains will be auto-allowed in permissive mode, and only prompt once in strict mode.

#### Blocking Specific Domains

Add domains you never want to access:

```json
{
  "domain_lists": {
    "blocked": [
      "suspicious-site.com",
      "known-malware.net"
    ]
  }
}
```

**Effect**: These domains are blocked in all security profiles.

### Profile-Specific Settings

Each security profile has detailed settings you can customize.

**Edit**: `config/security-config.json` → `profiles` → `[profile_name]`

**Available settings**:

```json
{
  "profiles": {
    "strict": {
      "auto_allow_academic": true,        // Auto-allow .edu/.gov?
      "auto_allow_commercial": false,     // Auto-allow commercial?
      "prompt_commercial_once_per_session": true,  // Prompt only once?
      "block_url_shorteners": true,       // Block bit.ly etc?
      "block_free_domains": true,         // Block .tk/.ml etc?
      "enable_content_scanning": true,    // Scan content for issues?
      "max_fetch_size_mb": 10,           // Max download size
      "fetch_timeout_seconds": 30         // Timeout for fetches
    }
  }
}
```

**Most users don't need to change these**. The defaults are well-tested.

---

## For IT Administrators

### Corporate Deployment

**Recommended setup for corporate environments**:

**1. Set default profile to strict**:

```json
{
  "security_profile": "strict"
}
```

**2. Add corporate resources to trusted list**:

```json
{
  "domain_lists": {
    "commercial": [
      "company-intranet.corp",
      "internal-wiki.corp",
      "research-database.corp"
    ]
  }
}
```

**3. Test in sandbox environment**:

```bash
# Run CConductor in container or VM first
docker run -v ./cconductor:/app cconductor-image ./cconductor "test query"
```

**4. Deploy configuration**:

- Distribute `security-config.json` to all users
- Optional: Make config file read-only to prevent changes
- Document internal policy

**5. Monitor usage**:

- Check logs in `logs/` directory
- Review security events
- Audit domain access patterns

### Network Considerations

**Firewall rules**:

- Allow outbound HTTPS (port 443) to Claude API endpoints
- Allow access to academic domains (`.edu`, `.gov`, arxiv.org, etc.)
- Block if needed: URL shorteners, suspicious TLDs

**Proxy settings**:

- CConductor respects system proxy settings
- Set `HTTP_PROXY` and `HTTPS_PROXY` environment variables if needed
- Test proxy compatibility before deployment

**VPN compatibility**:

- CConductor works through most VPNs
- Some VPNs may block certain research domains
- Test thoroughly in your VPN environment

### Audit & Compliance

**Logging**:

- All domain access logged to `logs/` directory
- Security events logged with timestamps
- Logs include: domain, action (allowed/denied), reason

**Log location**:

```
logs/
  research.log       # General research log
  security.log       # Security-specific events (if enabled)
```

**What's logged**:

```
[2025-10-02 18:45:23] SECURITY: Domain check: example-research-site.com
[2025-10-02 18:45:25] SECURITY: User action: ALLOW_ONCE
[2025-10-02 18:45:30] SECURITY: Fetch complete: 2.3MB in 4.2s
```

**Compliance considerations**:

- Logs contain domain names and timestamps
- Consider data retention policies
- May need to anonymize logs for GDPR
- Review your organization's logging requirements

### Sandboxed Deployment

For maximum security, run CConductor in isolated environment:

**Docker**:

```bash
# Build container
docker build -t cconductor-secure .

# Run with max_automation (safe in container)
docker run --rm \
  -v ./config:/app/config \
  -v ./research-sessions:/app/research-sessions \
  cconductor-secure ./cconductor "research question"
```

**VM**:

```bash
# Run CConductor in dedicated VM
# Use max_automation profile for speed
# VM isolation provides security
```

**Benefits**:

- Can use max_automation safely
- No risk to host system
- Easy to reset/rebuild
- Network isolation possible

---

## Troubleshooting

### Too Many Prompts

**Problem**: Constantly asked about domains during research.

**Cause**: Using strict mode with many unfamiliar domains.

**Solutions**:

1. **Switch to permissive mode** (if appropriate):

   ```bash
   nano config/security-config.json
   # Change: "security_profile": "permissive"
   ```

2. **Add frequently-used domains to trusted list**:

   ```json
   {
     "domain_lists": {
       "commercial": [
         "frequently-used-site.com"
       ]
     }
   }
   ```

3. **Use "Allow always" [S]** for domains you trust and use often.

---

### Research Blocked

**Problem**: Can't access needed sources.

**Symptoms**: Important sources are denied, research incomplete.

**Solutions**:

1. **Check if domain is in blocked list**:

   ```bash
   cat config/security-config.json | grep -A 20 '"blocked"'
   ```

2. **Remove from blocked list if needed**:
   Edit `config/security-config.json`, remove domain from `blocked` array.

3. **Temporarily use permissive mode**:
   Switch profile, run research, switch back.

4. **Add to trusted list**:
   Add domain to `commercial` list if frequently needed.

---

### Unknown Security Errors

**Problem**: Cryptic security-related error messages.

**Solutions**:

1. **Check logs**:

   ```bash
   tail -f logs/research.log
   grep ERROR logs/*.log
   ```

2. **Validate config JSON**:

   ```bash
   jq empty config/security-config.json
   # No output = valid
   # Error = fix JSON syntax
   ```

3. **Reset to default**:

   ```bash
   cp config/security-config.default.json config/security-config.json
   ```

4. **Check file permissions**:

   ```bash
   ls -l config/security-config.json
   # Should be readable
   ```

---

### Profile Not Applied

**Problem**: Security behavior doesn't match selected profile.

**Causes & Solutions**:

1. **Typo in profile name**:

   ```json
   ❌ "security_profile": "Strict"     // Wrong (capitalized)
   ❌ "security_profile": "stict"      // Wrong (typo)
   ✅ "security_profile": "strict"     // Correct
   ```

2. **Config file not saved**:
   - Make sure you saved the file after editing
   - Verify: `cat config/security-config.json | grep security_profile`

3. **Cached old config**:
   - Restart CConductor
   - Try: `./cconductor configure` to see active config

---

## Best Practices

### Choosing the Right Profile

**Use Strict when**:

- ✅ Researching sensitive topics
- ✅ Handling confidential data
- ✅ In corporate/academic environment
- ✅ Unfamiliar research domains
- ✅ Maximum control desired

**Use Permissive when**:

- ✅ Business research with known sources
- ✅ Trusted network environment
- ✅ Speed is important
- ✅ Familiar with research domains
- ✅ Experienced user

**Use Max Automation when**:

- ✅ Testing in VM or container **ONLY**
- ✅ Development environment
- ✅ Non-sensitive research
- ✅ Sandboxed execution

### Security Hygiene

**Regular maintenance**:

1. **Review trusted domains** quarterly - remove unused
2. **Update blocked list** - add newly discovered threats
3. **Check logs** periodically for unusual activity
4. **Keep config backed up** - especially custom lists

**When researching sensitive topics**:

1. Use strict mode
2. Review every prompt carefully
3. Check logs after research
4. Consider using VPN
5. Use sandboxed environment if very sensitive

---

## See Also

- **[User Guide](USER_GUIDE.md)** - Complete usage guide
- **[Configuration Reference](CONFIGURATION_REFERENCE.md)** - All config options
- **[Troubleshooting](TROUBLESHOOTING.md)** - Fix common issues

---

**CConductor Security** - Configurable protection for safe research 🔒
