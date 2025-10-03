# Installation and Configuration

## How Installation Works

### Installation Flow

```
install.sh
    ↓
    1. Clone/update repository to ~/.delve
    2. Set permissions
    3. Run: ./delve --init --yes
        ↓
        src/init.sh
            ↓
            1. Check dependencies (jq, curl, bash)
            2. Create ~/.config/delve/ directory
            3. Create OS-appropriate data directories
            4. Set up .gitignore
            5. Make scripts executable
            6. Validate configurations
```

### What Gets Created

#### On macOS

```
~/.delve/                                   # Application code
    ├── delve                               # Main entry point
    ├── src/                                # Source code
    ├── config/*.default.json               # Default configs (git-tracked)
    └── ...

~/.config/delve/                            # User configs (created, empty)
    # User creates configs as needed with:
    # ./src/utils/config-loader.sh init <config-name>

~/Library/Application Support/Delve/       # User data (created on first use)
    ├── research-sessions/
    ├── knowledge-base-custom/
    └── citations.json

~/Library/Caches/Delve/                     # Cache (created on first use)
    └── pdfs/

~/Library/Logs/Delve/                       # Logs (created on first use)
    └── audit.log
```

#### On Linux

```
~/.delve/                                   # Application code
~/.config/delve/                            # User configs
~/.local/share/delve/                       # User data
~/.cache/delve/                             # Cache
~/.local/state/delve/                       # Logs
```

### Configuration Creation

**Important**: User configs are **not** created automatically during installation!

Users create them when needed:

```bash
# List available configs
./src/utils/config-loader.sh list

# Create a custom config
./src/utils/config-loader.sh init delve-config

# This creates ~/.config/delve/delve-config.json
# User then edits it
vim ~/.config/delve/delve-config.json
```

**Why this approach?**

- Most users use defaults (no custom configs needed)
- Explicit opt-in for customization
- Clear separation of defaults vs user changes
- No unnecessary file creation

## Installation Methods

### Method 1: Quick Install (Recommended)

```bash
curl -fsSL https://github.com/yaniv-golan/delve/releases/latest/download/install.sh | bash
```

**What happens:**

1. Downloads `install.sh`
2. Clones repo to `~/.delve`
3. Runs `./delve --init --yes` (non-interactive)
4. Creates `~/.config/delve/` directory
5. Optionally adds to PATH

### Method 2: Manual Install (Development)

```bash
git clone https://github.com/yaniv-golan/delve.git
cd delve
./delve --init
```

**What happens:**

1. Clone repo to current directory
2. Run initialization (interactive)
3. Creates `~/.config/delve/` directory
4. User manually adds to PATH if desired

### Method 3: Custom Location

```bash
curl -fsSL https://raw.githubusercontent.com/yaniv-golan/delve/main/install.sh | bash -s /custom/path
```

**What happens:**

1. Installs to `/custom/path` instead of `~/.delve`
2. Still creates `~/.config/delve/` (OS-standard location)
3. User configs always in home directory regardless of install location

## First Run

```bash
./delve "What is quantum computing?"
```

**What happens:**

1. **Check initialization** (`check_initialization()`)
   - Checks if `~/.config/delve/` exists
   - If not, runs `init.sh` interactively

2. **Load configuration**
   - Loads defaults from `PROJECT_ROOT/config/*.default.json`
   - Overlays user configs from `~/.config/delve/*.json` (if they exist)
   - Uses merged configuration

3. **Run research**
   - Creates session in `~/Library/Application Support/Delve/research-sessions/` (macOS)
   - Or `~/.local/share/delve/research-sessions/` (Linux)

## Configuration Management

### Viewing Configurations

```bash
# Show config status
./delve configure

# Output:
🔧 Delve Configuration

═══════════════════════════════════════════════════════
User Config Directory: /Users/you/.config/delve/

Available configurations:

  • adaptive-config (using default)
  • delve-config (using default)
  • delve-modes (using default)
  • knowledge-config (using default)
  • mcp-servers (using default)
  • paths (using default)
  • research-config (using default)
  • research-modes (using default)
  • security-config (using default)

Config locations:
  Defaults:  /Users/you/.delve/config/*.default.json (git-tracked, don't edit)
  User:      /Users/you/.config/delve/*.json (customize these)

═══════════════════════════════════════════════════════

Create custom config:
  ./src/utils/config-loader.sh init <config-name>

Edit config:
  vim /Users/you/.config/delve/<config-name>.json

View differences:
  ./src/utils/config-loader.sh diff <config-name>

Get help:
  ./src/utils/config-loader.sh help
```

### Creating Custom Configs

```bash
# Create security config
./src/utils/config-loader.sh init security-config

# This creates ~/.config/delve/security-config.json
# Edit it
vim ~/.config/delve/security-config.json

# View your changes
./src/utils/config-loader.sh diff security-config
```

### Finding Data Locations

```bash
# Find session directory
./src/utils/path-resolver.sh resolve session_dir

# Find all paths
./src/utils/path-resolver.sh list

# Output:
Path Key                 Configured Value                        Resolved Path
─────────────────────────────────────────────────────────────────────────────────
cache_dir                ${PLATFORM_CACHE}                       /Users/you/Library/Caches/Delve
log_dir                  ${PLATFORM_LOGS}                        /Users/you/Library/Logs/Delve
session_dir              ${PLATFORM_DATA}/research-sessions      /Users/you/Library/Application Support/Delve/research-sessions
...
```

## Upgrades

### Installer-Based Installation

```bash
./delve --update
```

**What happens:**

1. Downloads latest `install.sh`
2. Runs installer to update `~/.delve/`
3. Runs `init.sh` to update directories
4. **Preserves** `~/.config/delve/` (never touched)
5. **Preserves** `~/Library/Application Support/Delve/` (never touched)

### Git-Based Installation

```bash
cd ~/.delve
git pull origin main
./delve --init --yes
```

**What happens:**

1. `git pull` updates code and `.default.json` files
2. `init.sh` validates/creates directories
3. **Preserves** `~/.config/delve/` (not in git)
4. **Preserves** `~/Library/Application Support/Delve/` (not in project)

## Uninstallation

### Remove Application

```bash
# Installer-based
rm -rf ~/.delve

# Git-based
rm -rf /path/to/delve
```

### Keep or Remove User Data

**Keep data** (recommended):

```bash
# User configs and data are safe in home directory
# ~/.config/delve/
# ~/Library/Application Support/Delve/
# Just delete application code above
```

**Remove everything** (clean slate):

```bash
# macOS
rm -rf ~/.delve
rm -rf ~/.config/delve
rm -rf ~/Library/Application\ Support/Delve
rm -rf ~/Library/Caches/Delve
rm -rf ~/Library/Logs/Delve

# Linux
rm -rf ~/.delve  # or your install location
rm -rf ~/.config/delve
rm -rf ~/.local/share/delve
rm -rf ~/.cache/delve
rm -rf ~/.local/state/delve
```

## Multi-User Systems

Each user has their own:

- Configs: `~/.config/delve/`
- Data: `~/Library/Application Support/Delve/` (or Linux equivalent)

Shared application:

- `/opt/delve/` or similar (system-wide install)
- All users can run it
- Each user gets their own data and configs

Example:

```bash
# Install system-wide
sudo curl -fsSL ... | bash -s /opt/delve

# User 1
/opt/delve/delve "research question"
# → Config: /home/user1/.config/delve/
# → Data: /home/user1/.local/share/delve/

# User 2
/opt/delve/delve "research question"
# → Config: /home/user2/.config/delve/
# → Data: /home/user2/.local/share/delve/
```

## Troubleshooting

### "Config directory not found"

```bash
# Run initialization
./delve --init
```

### "Can't find research sessions"

```bash
# Check configured path
./src/utils/path-resolver.sh resolve session_dir

# Verify directory exists
ls -la ~/Library/Application\ Support/Delve/research-sessions/
```

### "No configs found"

This is **normal**! Configs are created on demand:

```bash
# Create the config you need
./src/utils/config-loader.sh init delve-config
```

### "Configs in wrong location"

If you have old configs in project directory:

```bash
# Check what's where
./src/utils/config-loader.sh list

# User configs should be in ~/.config/delve/
# NOT in PROJECT_ROOT/config/
```

## See Also

- [User Guide](USER_GUIDE.md) - Complete usage guide
- [Configuration Reference](CONFIGURATION_REFERENCE.md) - All config options
- [Upgrade Guide](../UPGRADE.md) - Update instructions
- [Troubleshooting](TROUBLESHOOTING.md) - Common issues
