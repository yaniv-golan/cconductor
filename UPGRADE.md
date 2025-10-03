# Upgrade Guide

This guide explains how to upgrade Delve safely, preserving your configurations and data.

---

## Quick Upgrade

**For most users** (installed via `install.sh`):

```bash
delve --update
```

That's it! Your customizations are preserved automatically. 🎉

---

## Choosing Your Update Method

Delve supports two installation methods with different update procedures:

### Installed via install.sh (Recommended)

If you installed with:

```bash
curl -fsSL https://github.com/yaniv-golan/delve/releases/latest/download/install.sh | bash
```

**Update with:**

```bash
delve --update
```

See: [Installer-Based Updates](#installer-based-updates) below.

### Installed via git clone (Development)

If you cloned the repository:

```bash
git clone https://github.com/yaniv-golan/delve.git
```

**Update with:**

```bash
cd /path/to/delve
git pull origin main
./delve --init --yes
```

See: [Git-Based Updates](#git-based-updates) below.

---

## Installer-Based Updates

**For users who installed with the installer script** (most users).

### Automatic Update

Simply run:

```bash
delve --update
```

**What this does**:

- Detects your installation location automatically
- Downloads the latest release from GitHub
- Verifies checksums for security
- Updates Delve in place
- Preserves all your configurations
- Preserves your research sessions
- Preserves your custom knowledge base

**Example**:

```bash
$ delve --update
🔄 Updating Delve...

→ Detected installer-based installation
→ Downloading latest installer...
→ Running installer...
→ Verifying checksums...
→ Installing to /Users/you/.delve...

✅ Updated successfully
New version: 0.2.0
```

### Automatic Update Checks

Delve automatically checks for updates **once per day** and notifies you when a new version is available.

**When an update is available**, you'll see:

```
┌───────────────────────────────────────────────┐
│ 🔔 Update Available                           │
│                                               │
│ Current version: 0.1.0                        │
│ Latest version:  0.2.0                        │
│                                               │
│ Run 'delve --update' to upgrade              │
│                                               │
│ Release notes:                                │
│ https://github.com/yaniv-golan/delve/releases │
└───────────────────────────────────────────────┘
```

**The notification appears**:

- After you finish a research session
- Before you start a new session
- Only once per day (not on every command)

### Check for Updates Manually

```bash
delve --check-update
```

This immediately checks GitHub for new versions (bypasses the daily cache).

### Disable Update Checks

**Temporarily** (for one command):

```bash
delve --no-update-check "your research question"
```

**Permanently** - Edit your configuration:

```bash
# macOS/Linux
nano ~/.delve/config/delve-config.json
```

Add or modify:

```json
{
  "update_settings": {
    "check_for_updates": false
  }
}
```

Save and exit. Delve will no longer check for updates automatically.

**Re-enable later** by setting `"check_for_updates": true` or removing the setting.

### What Gets Updated

When you run `delve --update`:

✅ **Updated**:

- All core scripts and programs
- Built-in knowledge base
- Default configurations (`config/*.default.json` files in project)
- Documentation

✅ **Preserved** (never touched):

- Your custom configurations (`~/.config/delve/*.json`)
- Your data (`~/Library/Application Support/Delve/` or `~/.local/share/delve/`):
  - Research sessions
  - Custom knowledge
  - Citations database
- Your settings

### Version Compatibility

**Same major version** (e.g., 0.1.0 → 0.2.0):

- ✅ All sessions remain compatible
- ✅ Configurations work unchanged
- ✅ Resume old sessions works

**Major version change** (e.g., 0.x → 1.x):

- ⚠️ Old sessions may not be compatible
- ⚠️ Check CHANGELOG.md for breaking changes
- ⚠️ May need to update configurations

### After Updating

**1. Verify version**:

```bash
delve --version
```

**2. Test basic functionality**:

```bash
delve "What is Docker?"
```

**3. Check configuration** (optional):

```bash
# List your configs
./src/utils/config-loader.sh list

# Check a specific config
cat ~/.config/delve/delve-config.json | jq .
```

### Troubleshooting Updates

#### Update Fails to Download

**Problem**: Network error or GitHub unavailable.

**Solution**:

```bash
# Try again later, or
# Manual update:
curl -fsSL https://github.com/yaniv-golan/delve/releases/latest/download/install.sh | bash
```

#### Update Breaks Configuration

**Problem**: New version has incompatible config format.

**Solution**:

```bash
# Check default configs
cat PROJECT_ROOT/config/*.default.json

# Reset to defaults if needed
rm ~/.config/delve/delve-config.json

# Or recreate from defaults
./src/utils/config-loader.sh init delve-config
```

Your research sessions and custom knowledge are always safe in `~/Library/Application Support/Delve/` (macOS) or `~/.local/share/delve/` (Linux)!

---

## Git-Based Updates

**For developers who cloned the repository**.

### Standard Update

For updates within the same major version (e.g., 0.1.0 → 0.2.0):

```bash
# 1. Navigate to your delve directory
cd /path/to/delve

# 2. Pull latest changes
git pull origin main

# 3. Check new version
cat VERSION

# 4. Review recent changes (optional)
git log --oneline --since="1 week ago"

# 5. Re-run initialization (applies updates, validates configs)
./delve --init --yes
```

**What happens**:

- Default configs updated with new features
- Your customizations preserved (in non-tracked `.json` files)
- New config files created if added
- Dependencies validated

### Major Version Update

For major version changes (e.g., 0.x → 1.x):

```bash
# 1. Pull updates
cd /path/to/delve
git pull origin main

# 2. Check changelog for breaking changes
cat CHANGELOG.md  # Read carefully!

# 3. Check version
NEW_VERSION=$(cat VERSION)
echo "Upgrading to: $NEW_VERSION"

# 4. Check session compatibility
./src/utils/version-check.sh report research-sessions/session_XXXXX

# 5. Re-run init
./delve --init --yes
```

**Important**: Old sessions may not be compatible with major version changes. Use `version-check.sh` to verify before resuming.

### How Config Safety Works

Delve uses an **overlay pattern** to prevent merge conflicts:

```
config/adaptive-config.default.json  ← Git-tracked (updated on pull)
~/.config/delve/adaptive-config.json ← Your customizations (in home dir)
                                     ↓
                           Final config (merged at runtime)
```

When you upgrade:

- `git pull` updates `.default.json` files in project (new features, bug fixes)
- Your configs in `~/.config/delve/` are **never touched** (not in project)
- At runtime, Delve loads defaults then overlays your customizations

**Result**:

- Zero merge conflicts
- Automatic feature updates
- Configs survive project deletion!

### Merging New Config Options

After upgrading, default configs may have new fields you want to use.

**View what changed**:

```bash
cd /path/to/delve
./src/utils/config-loader.sh diff adaptive-config
./src/utils/config-loader.sh diff security-config
./src/utils/config-loader.sh diff paths
```

**Add new fields to your config**:

```bash
# Example: New field "enable_caching" added to adaptive-config.default.json
jq '.enable_caching = true' ~/.config/delve/adaptive-config.json > ~/.config/delve/adaptive-config.json.tmp
mv ~/.config/delve/adaptive-config.json.tmp ~/.config/delve/adaptive-config.json

# Verify
./src/utils/config-loader.sh load adaptive-config | jq '.enable_caching'
```

**Reset config to defaults**:

```bash
# Backup first (optional)
cp ~/.config/delve/adaptive-config.json ~/.config/delve/adaptive-config.json.backup

# Reset to defaults (just delete it)
rm ~/.config/delve/adaptive-config.json

# Or recreate and edit
./src/utils/config-loader.sh init adaptive-config
vim ~/.config/delve/adaptive-config.json
```

### After Upgrading (Git)

**1. Validate installation**:

```bash
cd /path/to/delve

# Validate all configurations
./src/utils/config-loader.sh validate

# Check all paths resolve correctly
./src/utils/path-resolver.sh list

# Verify version
./src/utils/version-check.sh engine
```

**2. Test basic functionality**:

```bash
cd /path/to/delve

# Test with simple query (2-3 minutes)
./delve "What is Docker?"

# Verify session created
ls -lt research-sessions/ | head -1

# Check session metadata
SESSION_DIR=$(ls -td research-sessions/session_* | head -1)
cat "$SESSION_DIR/session.json" | jq '.'
```

**3. Resume old sessions (if compatible)**:

```bash
cd /path/to/delve

# Find your old session
ls -lt research-sessions/

# Check compatibility
./src/utils/version-check.sh validate research-sessions/session_XXXXX

# If compatible, resume
./delve resume session_XXXXX
```

### Git Troubleshooting

#### "Session incompatible with current engine"

**Problem**: Session created with different major version.

**Solution**:

```bash
cd /path/to/delve

# Check versions
./src/utils/version-check.sh report research-sessions/session_XXXXX

# Option 1: Use matching engine version (downgrade)
# Option 2: Start new session
# Option 3: Wait for migration tool (not yet available)
```

#### "Config file contains invalid JSON"

**Problem**: Your custom config has syntax errors.

**Solution**:

```bash
cd /path/to/delve

# Validate JSON
jq '.' config/adaptive-config.json

# If errors, reset to defaults:
rm config/adaptive-config.json
./src/utils/config-loader.sh init adaptive-config
```

#### Git Merge Conflicts in Config Files

**This should never happen!** User config files are gitignored.

If it happens, you accidentally committed user configs:

```bash
cd /path/to/delve

# Remove from git (keep local file)
git rm --cached config/*.json
git commit -m "Remove user configs from git"

# Verify gitignore
grep "config/\*.json" .gitignore

# If missing, re-run init
./delve --init
```

---

## Configuration Reference

### Files You Can Customize

**User Configs** (OS-appropriate location):

```
macOS/Linux:
  ~/.config/delve/delve-config.json       ← Main settings
  ~/.config/delve/security-config.json    ← Security policies
  ~/.config/delve/paths.json              ← File paths

Windows:
  %APPDATA%\Delve\delve-config.json       ← Main settings
  %APPDATA%\Delve\security-config.json    ← Security policies
  %APPDATA%\Delve\paths.json              ← File paths
```

**User Data** (OS-appropriate location):

```
macOS:
  ~/Library/Application Support/Delve/research-sessions/
  ~/Library/Application Support/Delve/knowledge-base-custom/
  ~/Library/Application Support/Delve/citations.json

Linux:
  ~/.local/share/delve/research-sessions/
  ~/.local/share/delve/knowledge-base-custom/
  ~/.local/share/delve/citations.json
```

### Files You Should NOT Edit

```
PROJECT_ROOT/config/*.default.json  ← Defaults (git-tracked, updated on pull)
PROJECT_ROOT/src/**/*.sh            ← Core engine (edit with caution)
PROJECT_ROOT/.claude/agents/*.json  ← Agent definitions (core functionality)
PROJECT_ROOT/VERSION                ← Version tracking (auto-generated)
```

---

## Version Compatibility Matrix

| Your Session | Engine Version | Compatible? | Action |
|--------------|----------------|-------------|--------|
| 0.1.x        | 0.1.x          | ✓ Yes       | Resume works |
| 0.1.x        | 0.5.x          | ✓ Yes       | Resume works (minor version up) |
| 0.1.x        | 1.0.x          | ✗ No        | Start new session |
| 1.0.x        | 0.1.x          | ✗ No        | Upgrade engine |

**Rule**: Same major version = compatible. Different major version = incompatible.

---

## Before Upgrading (Optional)

### Check Current Version

```bash
# Installed version
delve --version

# Git version
cd /path/to/delve
cat VERSION
```

### Backup Your Customizations (Optional)

**Backup user configs and data**:

```bash
# macOS
tar -czf delve-backup-$(date +%Y%m%d).tar.gz \
    ~/.config/delve/ \
    ~/Library/Application\ Support/Delve/ \
    2>/dev/null

# Linux
tar -czf delve-backup-$(date +%Y%m%d).tar.gz \
    ~/.config/delve/ \
    ~/.local/share/delve/ \
    2>/dev/null

ls -lh delve-backup-*.tar.gz
```

**Or backup just configs**:

```bash
tar -czf delve-configs-$(date +%Y%m%d).tar.gz ~/.config/delve/
```

### Review Active Sessions

```bash
# macOS
ls -lt ~/Library/Application\ Support/Delve/research-sessions/ | head -10

# Linux
ls -lt ~/.local/share/delve/research-sessions/ | head -10

# Or use path resolver to find location
cd /path/to/delve
./src/utils/path-resolver.sh resolve session_dir
```

---

## Best Practices

### 1. Stay Up to Date

**Keep automatic checks enabled** to be notified of important updates:

```json
{
  "update_settings": {
    "check_for_updates": true
  }
}
```

### 2. Update Regularly

Run updates periodically:

```bash
# Check for updates weekly
delve --check-update

# Update when available
delve --update
```

### 3. Read Release Notes

Before major updates, review changes:

```bash
# View latest release notes
cat CHANGELOG.md | less

# Or visit:
# https://github.com/yaniv-golan/delve/releases
```

### 4. Test After Updates

Always test with a simple query after updating:

```bash
delve "What is Docker?"
```

### 5. Keep Backups of Important Sessions

```bash
# macOS
tar -czf my-research-backup.tar.gz ~/Library/Application\ Support/Delve/research-sessions/session_XXXXX

# Linux  
tar -czf my-research-backup.tar.gz ~/.local/share/delve/research-sessions/session_XXXXX

# Or find and backup by name
SESSION_DIR=$(./src/utils/path-resolver.sh resolve session_dir)
tar -czf my-research-backup.tar.gz "$SESSION_DIR/session_XXXXX"
```

---

## Getting Help

- **Configuration**: `delve configure` or see [Configuration Reference](docs/CONFIGURATION_REFERENCE.md)
- **Troubleshooting**: See [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- **Full Documentation**: [User Guide](docs/USER_GUIDE.md)
- **Issues**: [GitHub Issues](https://github.com/yaniv-golan/delve/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yaniv-golan/delve/discussions)

---

**Questions?** Check the documentation or open an issue on GitHub.
