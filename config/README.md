# Configuration Directory

This directory contains **default configuration files** for Delve. These files are git-tracked and should **never be edited directly**.

## File Structure

```
config/
├── README.md                    ← You are here
├── adaptive-config.default.json ← Default configs (git-tracked)
├── delve-config.default.json
├── delve-modes.default.json
├── knowledge-config.default.json
├── mcp-servers.default.json
├── paths.default.json
├── research-config.default.json
├── research-modes.default.json
├── security-config.default.json
└── ...
```

## User Configuration

**User configurations are stored in your home directory**, not here!

### Location by Operating System

- **macOS**: `~/.config/delve/`
- **Linux**: `~/.config/delve/` (or `$XDG_CONFIG_HOME/delve/`)
- **Windows**: `%APPDATA%\Delve\`

### Creating Custom Configurations

To customize any configuration:

```bash
# Create a user config from defaults
./src/utils/config-loader.sh init adaptive-config

# This creates ~/.config/delve/adaptive-config.json
# Now edit it:
vim ~/.config/delve/adaptive-config.json
```

### How It Works

1. **Default configs** (this directory): Git-tracked, updated on `git pull`
2. **User configs** (`~/.config/delve/`): Your customizations, never touched by git

When Delve loads a config:

1. Starts with default config from this directory
2. Overlays your user config from `~/.config/delve/` (if it exists)
3. Your values override defaults

## Benefits of This Approach

✅ **Zero merge conflicts**: Git updates never conflict with your settings  
✅ **Survives reinstalls**: Delete the project, configs stay safe in your home directory  
✅ **Multi-user support**: Each user has their own configs  
✅ **OS conventions**: Follows platform standards (XDG on Linux, etc.)  
✅ **Clean separation**: Code and user data properly separated

## Available Commands

```bash
# List all configs
./src/utils/config-loader.sh list

# Create user config
./src/utils/config-loader.sh init <config_name>

# Show where your config is
./src/utils/config-loader.sh where <config_name>

# View your customizations
./src/utils/config-loader.sh diff <config_name>

# Validate all configs
./src/utils/config-loader.sh validate

# Get help
./src/utils/config-loader.sh help
```

## Environment Variables

Override config directory location:

```bash
export DELVE_CONFIG_DIR="/custom/path"
```

## See Also

- [Configuration Reference](../docs/CONFIGURATION_REFERENCE.md) - Detailed config options
- [User Guide](../docs/USER_GUIDE.md) - Getting started
- [Upgrade Guide](../UPGRADE.md) - Upgrade instructions
