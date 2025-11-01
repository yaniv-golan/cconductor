# Homebrew Installation Guide

Install CConductor using Homebrew package manager for macOS.

## Installation

```bash
# Add CConductor tap
brew tap yaniv-golan/cconductor

# Install CConductor
brew install cconductor

# Verify installation
cconductor --version
```

## Prerequisites

### Claude Code CLI (Required)

```bash
# Install Node.js (if not already installed)
brew install node

# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Set up authentication (choose one method):

# Method 1: config.json file
mkdir -p ~/.config/claude
cat > ~/.config/claude/config.json << 'EOF'
{
  "api_key": "your_anthropic_api_key_here"
}
EOF

# Method 2: Environment variable (add to ~/.zshrc or ~/.bashrc)
export ANTHROPIC_API_KEY="your_anthropic_api_key_here"
```

### Shell Dependencies (Required)

```bash
# CConductor relies on bash, jq, curl, bc, and ripgrep.
brew install bash jq curl bc ripgrep
```

> macOS ships with bash 3.2. Homebrew's `bash` formula installs the required 4.x+ runtime. We intentionally keep the runtime stack to portable shell tooling; introduce additional languages only with maintainer approval.

## Usage

```bash
# Start research
cconductor "What is quantum computing?"

# With specific mission
cconductor "Market analysis" --mission market-research

# Interactive mode
cconductor
```

## Updating

```bash
# Update tap
brew update

# Upgrade CConductor
brew upgrade cconductor

# Update Claude Code CLI
npm update -g @anthropic-ai/claude-code
```

## Uninstalling

```bash
# Remove CConductor
brew uninstall cconductor

# Remove tap (optional)
brew untap yaniv-golan/cconductor
```

## Troubleshooting

### Formula Not Found
```bash
# Ensure tap is added
brew tap yaniv-golan/cconductor

# Update brew
brew update
```

### Claude Code CLI Not Found
```bash
# Verify Node.js is installed
node --version

# Reinstall Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Verify installation
which claude
```

### Path Issues
```bash
# Ensure Homebrew is in PATH
echo $PATH | grep homebrew

# Add to ~/.zshrc (Apple Silicon)
export PATH="/opt/homebrew/bin:$PATH"

# Add to ~/.zshrc (Intel)
export PATH="/usr/local/bin:$PATH"
```

## Installation Locations

Homebrew installs CConductor to:

- **Apple Silicon**: `/opt/homebrew/bin/cconductor`
- **Intel**: `/usr/local/bin/cconductor`

Data directories follow standard paths:
- **Research sessions**: `~/Library/Application Support/CConductor/research-sessions/`
- **Cache**: `~/Library/Caches/CConductor/`
- **Config**: `~/.config/cconductor/`

## Related Documentation

- [Installation Guide](../README.md#installation)
- [User Guide](USER_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)
