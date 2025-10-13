#!/usr/bin/env bash
# Init and Update - Initialization and update management
# Handles first-run setup and version updates

set -euo pipefail

# Guard against direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Error: This script should be sourced, not executed" >&2
    exit 1
fi

check_initialization() {
    # Check if user config directory exists (created by init.sh)
    # Platform-aware check
    if [ -f "$CCONDUCTOR_ROOT/src/utils/platform-paths.sh" ]; then
        # shellcheck disable=SC1091
        source "$CCONDUCTOR_ROOT/src/utils/platform-paths.sh"
        local config_dir
        config_dir=$(get_config_dir)
        
        # Check if config directory exists
        # We don't require configs to exist, just the directory
        if [ -d "$config_dir" ]; then
            return 0
        fi
    fi
    
    return 1
}

show_init_prompt() {
    cat <<EOF
┌─────────────────────────────────────────────────────┐
│ Welcome to CConductor! First-time setup required.        │
└─────────────────────────────────────────────────────┘

I will now:
  1. Check for dependencies (claude, jq, curl, bash, python3)
  2. Create user config directory (~/.config/cconductor/)
  3. Create OS-appropriate data directories
  4. Configure .gitignore to protect your data
  5. Make scripts executable
  6. Validate all configurations

This takes ~5 seconds. Run initialization? [Y/n] 
EOF
}

run_initialization() {
    local interactive="${1:-true}"
    
    if [ "$interactive" = "true" ]; then
        show_init_prompt
        read -r response
        
        case "${response:-y}" in
            [Yy]|[Yy][Ee][Ss]|"")
                echo ""
                "$CCONDUCTOR_ROOT/src/init.sh"
                ;;
            *)
                echo ""
                echo "Initialization cancelled. Run './cconductor --init' when ready."
                exit 0
                ;;
        esac
    else
        # Non-interactive mode
        "$CCONDUCTOR_ROOT/src/init.sh"
    fi
}

# Self-update functionality
perform_update() {
    echo "🔄 Updating CConductor..."
    echo ""
    
    # Detect installation method
    if [ -d "$CCONDUCTOR_ROOT/.git" ]; then
        # Git installation
        echo "→ Detected git installation"
        echo "→ Pulling latest changes..."
        cd "$CCONDUCTOR_ROOT"
        git fetch origin
        git pull origin main
        
        echo "→ Running initialization..."
        "$CCONDUCTOR_ROOT/src/init.sh"
        
        local new_version
        new_version=$(cat "$CCONDUCTOR_ROOT/VERSION" 2>/dev/null || echo "unknown")
        echo ""
        echo "✅ Updated to v$new_version"
    else
        # Installed via install.sh
        echo "→ Detected installer-based installation"
        echo "→ Downloading latest installer..."
        
        local temp_installer="/tmp/cconductor-install-$$.sh"
        local temp_checksum="/tmp/cconductor-install-$$.sh.sha256"
        
        # Download installer
        if ! curl -fsSL "https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh" \
            -o "$temp_installer" 2>/dev/null; then
            echo "✗ Failed to download installer"
            echo ""
            echo "Manual update:"
            echo "  curl -fsSL https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh | bash"
            exit 1
        fi
        
        # Download and verify checksum
        if ! curl -fsSL "https://github.com/yaniv-golan/cconductor/releases/latest/download/install.sh.sha256" \
            -o "$temp_checksum" 2>/dev/null; then
            echo "⚠ Warning: Could not download checksum, skipping verification"
            echo "This is a security risk. Continue anyway? [y/N]"
            read -r response
            if [[ "${response,,}" != "y" ]]; then
                rm -f "$temp_installer"
                exit 1
            fi
        else
            # Verify checksum
            echo "→ Verifying checksum..."
            if ! (cd /tmp && sha256sum -c "$temp_checksum" 2>/dev/null || shasum -a 256 -c "$temp_checksum" 2>/dev/null); then
                echo "✗ Checksum verification failed!"
                echo "This could indicate a compromised download."
                rm -f "$temp_installer" "$temp_checksum"
                exit 1
            fi
            echo "✓ Checksum verified"
        fi
        
        chmod +x "$temp_installer"
        echo "→ Running installer..."
        bash "$temp_installer" "$CCONDUCTOR_ROOT"
        rm -f "$temp_installer" "$temp_checksum"
        echo ""
        echo "✅ Updated successfully"
    fi
}

