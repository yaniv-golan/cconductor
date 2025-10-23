#!/bin/bash
set -euo pipefail

echo "🔍 CConductor Docker Container"
echo "Version: $(cat /opt/cconductor/VERSION)"
echo ""

# Priority 1: Docker secrets (production/swarm)
if [ -f /run/secrets/anthropic_api_key ]; then
    ANTHROPIC_API_KEY=$(cat /run/secrets/anthropic_api_key)
    export ANTHROPIC_API_KEY
    echo "✓ Using Docker secret for authentication"
fi

# Priority 2: Environment variable (CI/CD)
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "✓ Using ANTHROPIC_API_KEY environment variable"
fi

# Priority 3: Volume-mounted credentials (development)
if [ -d "/root/.claude" ] && [ -f "/root/.claude/.credentials.json" ]; then
    echo "✓ Using mounted Claude credentials from ~/.claude"
elif [ -d "/root/.claude" ] && [ -f "/root/.claude/credentials.json" ]; then
    echo "✓ Using mounted Claude credentials from ~/.claude"
fi

# Allow certain commands without authentication
SKIP_AUTH_CHECK=0
for arg in "$@"; do
    case "$arg" in
        --help|-h|--version|-v|--init)
            SKIP_AUTH_CHECK=1
            break
            ;;
    esac
done

# Check if any authentication method is available (unless skipped)
if [ "$SKIP_AUTH_CHECK" = "0" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ ! -f "/root/.claude/.credentials.json" ] && [ ! -f "/root/.claude/credentials.json" ] && [ ! -f "/run/secrets/anthropic_api_key" ]; then
    cat >&2 <<'EOF'
❌ No Claude Code credentials found

Provide credentials using ONE of these methods:

1. Volume mount (recommended for development):
   docker run -v ~/.claude:/root/.claude \
     -v ~/research:/data/research-sessions \
     ghcr.io/yaniv-golan/cconductor:latest "your question"

2. Environment variable with env file (recommended for CI/CD):
   echo "ANTHROPIC_API_KEY=sk-ant-xxx" > .env
   docker run --env-file .env \
     -v ~/research:/data/research-sessions \
     ghcr.io/yaniv-golan/cconductor:latest "your question"

3. Docker secrets (recommended for production):
   echo "sk-ant-xxx" | docker secret create anthropic_api_key -
   docker service create --secret anthropic_api_key \
     --mount type=volume,source=research-data,target=/data \
     ghcr.io/yaniv-golan/cconductor:latest

Documentation: https://github.com/yaniv-golan/cconductor#docker-usage
EOF
    exit 1
fi

# Set PROJECT_ROOT for path resolution (critical for CConductor architecture)
export PROJECT_ROOT=/opt/cconductor

# Docker uses Linux paths, so set platform paths explicitly
# This overrides platform-paths.sh detection for containerized environment
export PLATFORM_DATA=/data
export PLATFORM_CACHE=/data/cache
export PLATFORM_LOGS=/data/logs
export PLATFORM_CONFIG=/root/.config/cconductor

# Initialize if first run (creates default configs and directory structure)
if [ ! -d "$PLATFORM_CONFIG" ]; then
    echo "📦 First run - initializing configuration..."
    /opt/cconductor/cconductor --init --yes > /dev/null 2>&1 || true
fi

echo ""

# Execute CConductor with all arguments
exec /opt/cconductor/cconductor "$@"

