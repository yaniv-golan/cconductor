#!/bin/bash
# Delve Installer
# Installs Delve and optionally adds it to PATH

set -euo pipefail

VERSION="0.1.0"
REPO_URL="https://github.com/yaniv-golan/delve.git"
DEFAULT_INSTALL_DIR="$HOME/.delve"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

# Detect shell
detect_shell() {
    if [ -n "${BASH_VERSION:-}" ]; then
        echo "bash"
    elif [ -n "${ZSH_VERSION:-}" ]; then
        echo "zsh"
    else
        basename "$SHELL"
    fi
}

# Get shell config file
get_shell_config() {
    local shell_type=$(detect_shell)
    
    case "$shell_type" in
        bash)
            if [ -f "$HOME/.bashrc" ]; then
                echo "$HOME/.bashrc"
            elif [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        zsh)
            echo "$HOME/.zshrc"
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            echo "$HOME/.profile"
            ;;
    esac
}

# Add to PATH
add_to_path() {
    local install_dir="$1"
    local shell_config=$(get_shell_config)
    local shell_type=$(detect_shell)
    
    # Check if already in PATH
    if echo "$PATH" | grep -q "$install_dir"; then
        success "Already in PATH"
        return 0
    fi
    
    # Create config file if it doesn't exist
    touch "$shell_config"
    
    # Add PATH entry
    info "Adding Delve to PATH in $shell_config"
    
    case "$shell_type" in
        fish)
            echo "" >> "$shell_config"
            echo "# Delve Research Engine" >> "$shell_config"
            echo "set -gx PATH $install_dir \$PATH" >> "$shell_config"
            ;;
        *)
            echo "" >> "$shell_config"
            echo "# Delve Research Engine" >> "$shell_config"
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$shell_config"
            ;;
    esac
    
    success "Added to PATH in $shell_config"
    info "Restart your shell or run: source $shell_config"
}

# Main installation
main() {
    echo "══════════════════════════════════════════════"
    echo "  Delve Installer v$VERSION"
    echo "══════════════════════════════════════════════"
    echo ""
    
    # Parse arguments
    INSTALL_DIR="${1:-$DEFAULT_INSTALL_DIR}"
    ADD_TO_PATH="${ADD_TO_PATH:-ask}"
    
    # Check if git is installed
    if ! command -v git &> /dev/null; then
        error "git is required but not installed"
        info "Install git first:"
        info "  macOS:   brew install git"
        info "  Ubuntu:  sudo apt-get install git"
        info "  Fedora:  sudo dnf install git"
        exit 1
    fi
    
    # Create install directory parent
    mkdir -p "$(dirname "$INSTALL_DIR")"
    
    # Clone or update repository
    if [ -d "$INSTALL_DIR/.git" ]; then
        info "Delve already installed at $INSTALL_DIR"
        echo "Updating to latest version..."
        cd "$INSTALL_DIR"
        git pull origin main
        success "Updated to latest version"
    else
        info "Installing Delve to $INSTALL_DIR"
        git clone "$REPO_URL" "$INSTALL_DIR"
        success "Cloned repository"
    fi
    
    cd "$INSTALL_DIR"
    
    # Make scripts executable
    info "Setting permissions..."
    chmod +x delve
    chmod +x src/init.sh
    chmod +x src/*.sh 2>/dev/null || true
    chmod +x src/utils/*.sh 2>/dev/null || true
    success "Permissions set"
    
    # Run initialization
    echo ""
    info "Running first-time setup..."
    ./delve --init --yes
    
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  Installation Complete!"
    echo "══════════════════════════════════════════════"
    echo ""
    
    # Ask about PATH
    if [ "$ADD_TO_PATH" = "ask" ]; then
        echo "Would you like to add Delve to your PATH?"
        echo "This allows you to run 'delve' from anywhere."
        echo ""
        read -p "Add to PATH? [Y/n] " -r response
        
        case "${response:-y}" in
            [Yy]|[Yy][Ee][Ss]|"")
                add_to_path "$INSTALL_DIR"
                ;;
            *)
                info "Skipped adding to PATH"
                info "To use Delve, either:"
                info "  1. Run: $INSTALL_DIR/delve \"your question\""
                info "  2. Add manually to PATH: export PATH=\"$INSTALL_DIR:\$PATH\""
                ;;
        esac
    elif [ "$ADD_TO_PATH" = "true" ]; then
        add_to_path "$INSTALL_DIR"
    fi
    
    echo ""
    info "Next steps:"
    echo ""
    
    if echo "$PATH" | grep -q "$INSTALL_DIR"; then
        echo "  • Reload your shell: source $(get_shell_config)"
        echo "  • Start researching: delve \"your research question\""
    else
        echo "  • Start researching: $INSTALL_DIR/delve \"your research question\""
    fi
    
    echo "  • View latest results: delve latest"
    echo "  • Show help: delve --help"
    echo ""
    
    success "Happy researching! 🔬"
}

# Run installer
main "$@"

