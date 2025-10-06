#!/usr/bin/env bash
# CConductor First-Run Initialization
# Sets up directories, configs, and verifies dependencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================"
echo "CConductor Setup"
echo "========================================"
echo ""

# Show version
if [ -f "$PROJECT_ROOT/VERSION" ]; then
    VERSION=$(cat "$PROJECT_ROOT/VERSION")
    echo "Version: $VERSION"
else
    echo "Version: unknown"
fi
echo ""

# Step 1: Check dependencies
echo "1. Checking dependencies..."
echo "   (claude, jq, curl, bash, bc)"
echo ""

missing_deps=()

# Check for CRITICAL dependency: Claude Code CLI
if ! command -v claude &> /dev/null; then
    echo "   ✗ CRITICAL: Claude Code CLI not found"
    echo ""
    echo "   CConductor requires Claude Code CLI to function."
    echo "   This is the AI agent runtime that powers the multi-agent system."
    echo ""
    
    # Check if npm is available
    if ! command -v npm &> /dev/null; then
        echo "   First, install Node.js (includes npm):"
        echo ""
        echo "     macOS:"
        if ! command -v brew &> /dev/null; then
            echo "       1. Install Homebrew:"
            echo "          /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo "       2. Install Node.js:"
            echo "          brew install node"
        else
            echo "       brew install node"
        fi
        echo ""
        echo "     Ubuntu:"
        echo "       curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
        echo "       sudo apt-get install -y nodejs"
        echo ""
        echo "   Then install Claude Code CLI:"
    else
        echo "   Install with:"
    fi
    echo "     npm install -g @anthropic-ai/claude-code"
    echo ""
    echo "   Requirements:"
    echo "     • Node.js 18 or newer (provides npm)"
    echo "     • Claude.ai or Console account (Pro/Max subscription or API credits)"
    echo ""
    echo "   After installation, you must login:"
    echo "     claude login"
    echo ""
    echo "   See: https://docs.anthropic.com/en/docs/claude-code/overview"
    echo ""
    exit 1
fi

# Check for required utility commands
if ! command -v jq &> /dev/null; then
    missing_deps+=("jq")
fi

if ! command -v curl &> /dev/null; then
    missing_deps+=("curl")
fi

if ! command -v bash &> /dev/null; then
    missing_deps+=("bash")
fi

if ! command -v bc &> /dev/null; then
    missing_deps+=("bc")
fi

# Function to auto-install dependencies
auto_install_dependencies() {
    local deps=("$@")
    
    # Detect OS and package manager
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            echo "   → Installing with Homebrew..."
            brew install "${deps[@]}"
            return $?
        else
            echo "   ✗ Homebrew not found. Install from: https://brew.sh"
            return 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - try common package managers
        if command -v apt-get &> /dev/null; then
            echo "   → Installing with apt-get..."
            sudo apt-get update && sudo apt-get install -y "${deps[@]}"
            return $?
        elif command -v dnf &> /dev/null; then
            echo "   → Installing with dnf..."
            sudo dnf install -y "${deps[@]}"
            return $?
        elif command -v yum &> /dev/null; then
            echo "   → Installing with yum..."
            sudo yum install -y "${deps[@]}"
            return $?
        elif command -v pacman &> /dev/null; then
            echo "   → Installing with pacman..."
            sudo pacman -S --noconfirm "${deps[@]}"
            return $?
        else
            echo "   ✗ No supported package manager found"
            return 1
        fi
    else
        echo "   ✗ Unsupported OS: $OSTYPE"
        return 1
    fi
}

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "   ✗ Missing dependencies:"
    for dep in "${missing_deps[@]}"; do
        echo "      - $dep"
    done
    echo ""
    
    # Check if we should offer auto-install
    # Skip auto-install if --no-auto-install flag is set
    if [ "${AUTO_INSTALL:-true}" = "true" ]; then
        echo "Would you like to install missing dependencies automatically? [Y/n]"
        read -r response
        
        case "${response:-y}" in
            [Yy]|[Yy][Ee][Ss]|"")
                echo ""
                if auto_install_dependencies "${missing_deps[@]}"; then
                    echo ""
                    echo "   ✓ Dependencies installed successfully!"
                    echo ""
                else
                    echo ""
                    echo "   ✗ Auto-install failed. Please install manually:"
                    echo "     macOS:   brew install ${missing_deps[*]}"
                    echo "     Ubuntu:  sudo apt-get install ${missing_deps[*]}"
                    echo "     Fedora:  sudo dnf install ${missing_deps[*]}"
                    echo ""
                    exit 1
                fi
                ;;
            *)
                echo ""
                echo "Please install dependencies manually:"
                echo "  macOS:   brew install ${missing_deps[*]}"
                echo "  Ubuntu:  sudo apt-get install ${missing_deps[*]}"
                echo "  Fedora:  sudo dnf install ${missing_deps[*]}"
                echo ""
                exit 1
                ;;
        esac
    else
        echo "Installation:"
        echo "  macOS:   brew install ${missing_deps[*]}"
        echo "  Ubuntu:  sudo apt-get install ${missing_deps[*]}"
        echo "  Fedora:  sudo dnf install ${missing_deps[*]}"
        echo ""
        exit 1
    fi
fi

# Verify all dependencies are now available
if command -v jq &> /dev/null && command -v curl &> /dev/null && command -v bash &> /dev/null && command -v bc &> /dev/null; then
    echo "   ✓ claude (Claude Code CLI) - REQUIRED"
    echo "   ✓ jq (JSON processor)"
    echo "   ✓ curl (HTTP client)"
    echo "   ✓ bash (shell)"
    echo "   ✓ bc (calculator for math operations)"
else
    echo "   ✗ Dependencies still missing after installation attempt"
    exit 1
fi
echo ""

# Step 2: Create directories
echo "2. Creating directories..."

# Source path resolver to use configured paths
if [ -f "$SCRIPT_DIR/utils/path-resolver.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/utils/path-resolver.sh"

    # Initialize all configured paths
    init_all_paths > /dev/null 2>&1
    echo "   ✓ All configured directories created"
else
    # Fallback to basic directories if path-resolver not available
    mkdir -p "$PROJECT_ROOT/knowledge-base-custom"
    mkdir -p "$PROJECT_ROOT/research-sessions"
    mkdir -p "$PROJECT_ROOT/logs"
    echo "   ✓ knowledge-base-custom/"
    echo "   ✓ research-sessions/"
    echo "   ✓ logs/"
fi
echo ""

# Step 3: Set up user configuration directory
echo "3. Setting up user configuration directory..."

# Get user config directory (OS-appropriate location)
if [ -f "$SCRIPT_DIR/utils/platform-paths.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/utils/platform-paths.sh"
    USER_CONFIG_DIR=$(get_config_dir)
else
    USER_CONFIG_DIR="$HOME/.config/cconductor"
fi

# Create user config directory
if [ ! -d "$USER_CONFIG_DIR" ]; then
    mkdir -p "$USER_CONFIG_DIR"
    echo "   ✓ Created $USER_CONFIG_DIR"
else
    echo "   ✓ User config directory exists: $USER_CONFIG_DIR"
fi

# Note: We don't copy default configs automatically
# Users create them with: ./src/utils/config-loader.sh init <config_name>
echo "   Default configs available in: $PROJECT_ROOT/config/*.default.json"
echo "   To customize: ./src/utils/config-loader.sh init <config_name>"
echo ""

# Step 4: Verify .gitignore
echo "4. Checking .gitignore..."
GITIGNORE="$PROJECT_ROOT/.gitignore"

if [ ! -f "$GITIGNORE" ]; then
    echo "   Creating .gitignore"
    cat > "$GITIGNORE" << 'EOF'
# User customizations
knowledge-base-custom/

# Session data (includes per-session .claude/ and .mcp.json)
research-sessions/
research-sessions/*/.claude/settings.local.json
research-sessions/*/.mcp.json

# Logs
logs/
*.log

# Cache
.cache/

# Temp files
*.tmp
*.lock

# OS files
.DS_Store
EOF
else
    # Check if key entries exist
    missing_entries=()

    if ! grep -q "knowledge-base-custom/" "$GITIGNORE" 2>/dev/null; then
        missing_entries+=("knowledge-base-custom/")
    fi

    if ! grep -q "research-sessions/" "$GITIGNORE" 2>/dev/null; then
        missing_entries+=("research-sessions/")
    fi

    if [ ${#missing_entries[@]} -gt 0 ]; then
        echo "   ⚠️  .gitignore may be missing entries:"
        for entry in "${missing_entries[@]}"; do
            echo "      - $entry"
        done
        echo "   Consider adding these entries manually."
    else
        echo "   ✓ .gitignore looks good"
    fi
fi
echo ""

# Step 5: Make scripts executable
echo "5. Setting script permissions..."
chmod +x "$SCRIPT_DIR/adaptive-research.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/research.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/research-wrapper.sh" 2>/dev/null || true
chmod +x "$SCRIPT_DIR/utils/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/claude-runtime/hooks/"*.sh 2>/dev/null || true
echo "   ✓ Scripts are executable"
echo "   (Note: Session hooks are set executable during session creation)"
echo ""

# Step 6: Validate configurations
echo "6. Validating configurations..."
if [ -f "$SCRIPT_DIR/utils/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/utils/config-loader.sh"
    if validate_configs > /dev/null 2>&1; then
        echo "   ✓ All configurations valid"
    else
        echo "   ⚠️  Some configurations may have issues"
        echo "   Run: ./src/utils/config-loader.sh validate"
    fi
else
    echo "   ⚠️  Config loader not found, skipping validation"
fi
echo ""

# Step 7: Summary
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""

echo "Configuration:"
echo "  • Default configs:  $PROJECT_ROOT/config/*.default.json"
echo "  • User configs:     $USER_CONFIG_DIR/"
echo "  • To customize:     ./src/utils/config-loader.sh init <config_name>"
echo ""

echo "Next steps:"
echo ""
echo "  1. List available configurations:"
echo "     ./src/utils/config-loader.sh list"
echo ""
echo "  2. Create custom config (optional):"
echo "     ./src/utils/config-loader.sh init paths"
echo "     vim $USER_CONFIG_DIR/paths.json"
echo ""
echo "  3. Start researching:"
echo "     ./src/adaptive-research.sh \"Your research question\""
echo ""
echo "  4. View help:"
echo "     ./src/adaptive-research.sh --help"
echo ""

echo "Documentation:"
echo "  • Configuration: ./src/utils/config-loader.sh help"
echo "  • Paths: ./src/utils/path-resolver.sh help"
echo "  • Versions: ./src/utils/version-check.sh help"
echo ""

echo "Happy researching! 🔬"
echo ""
