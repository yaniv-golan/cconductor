# Docker Usage Guide

Complete guide for running CConductor in Docker containers.

## Quick Start

### Prerequisites
- Docker installed
- Claude Code credentials (see [Authentication](#authentication))

### Basic Usage

```bash
docker run -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest \
  "What is quantum computing?"
```

## Authentication Methods

CConductor Docker supports three authentication methods:

### 1. Volume Mount (Recommended for Development)

Mount your existing Claude credentials:

```bash
# macOS/Linux
docker run -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest "your question"

# Windows (WSL2)
docker run -v /mnt/c/Users/YourName/.claude:/root/.claude \
  -v /mnt/c/Users/YourName/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest "your question"
```

**Pros**: Most secure, uses existing credentials (stored in macOS Keychain on Mac)  
**Cons**: Requires Claude Code CLI authentication on host first

**To authenticate Claude Code CLI**:
```bash
# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Authenticate (opens Claude.ai in browser, or prompts for API key)
# Credentials stored in ~/.claude/ and macOS Keychain
claude

# Then Docker volume mount will work
```

### 2. Environment Variable (Recommended for CI/CD)

Use API key via environment variable:

```bash
# Create .env file (more secure than -e)
echo "ANTHROPIC_API_KEY=sk-ant-xxx" > .env

# Run with env file
docker run --env-file .env \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest "your question"
```

**Pros**: Works in automated environments, no host dependencies  
**Cons**: Requires API key (not Claude Pro/Max subscription)

### 3. Docker Secrets (Recommended for Production)

Use Docker Swarm secrets:

```bash
# Initialize swarm
docker swarm init

# Create secret
echo "sk-ant-xxx" | docker secret create anthropic_api_key -

# Deploy service
docker service create \
  --name cconductor \
  --secret anthropic_api_key \
  --mount type=volume,source=research-data,target=/data \
  ghcr.io/yaniv-golan/cconductor:latest
```

**Pros**: Encrypted at rest and in transit, production-grade  
**Cons**: Requires Docker Swarm mode

## Common Use Cases

### Interactive Research
```bash
docker run -it --rm \
  -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest \
  "What are the latest advances in quantum computing?"
```

### CI/CD Pipeline
```yaml
# .github/workflows/research.yml
- name: Run Research
  run: |
    docker run --env-file .env \
      -v ${{ github.workspace }}/output:/data/research-sessions \
      ghcr.io/yaniv-golan/cconductor:latest \
      "${{ inputs.research_question }}"
```

### Docker Compose
```yaml
# docker-compose.yml
version: '3.8'
services:
  cconductor:
    image: ghcr.io/yaniv-golan/cconductor:latest
    volumes:
      - ~/.claude:/root/.claude:ro
      - ./research-sessions:/data/research-sessions
    environment:
      CCONDUCTOR_VERBOSE: "1"
```

Run with: `docker-compose run cconductor "your question"`

## Advanced Configuration

### Custom Missions
```bash
docker run -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest \
  "Market analysis question" --mission market-research
```

### With Local Files
```bash
docker run -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  -v ~/documents:/input:ro \
  ghcr.io/yaniv-golan/cconductor:latest \
  "Analyze these documents" --input-dir /input
```

### Verbose Mode
```bash
docker run -e CCONDUCTOR_VERBOSE=1 \
  -v ~/.claude:/root/.claude \
  -v ~/research:/data/research-sessions \
  ghcr.io/yaniv-golan/cconductor:latest "your question"
```

## Security Best Practices

1. **Never build credentials into images**
2. **Use .env files, not -e flags** (avoids shell history)
3. **Mount credentials read-only** (`:ro`)
4. **Use Docker secrets in production**
5. **Regularly rotate API keys**
6. **Review .dockerignore** to prevent credential leaks

## Troubleshooting

### Authentication Errors
```bash
# Verify credentials are mounted
docker run -it ghcr.io/yaniv-golan/cconductor:latest bash
ls -la /root/.claude/

# Check environment variable
echo $ANTHROPIC_API_KEY
```

### Permission Issues
```bash
# Research sessions owned by root
sudo chown -R $USER:$USER ~/research

# Or run with user mapping (Linux only)
docker run --user $(id -u):$(id -g) ...
```

### Volume Mount Not Working
```bash
# Verify path exists on host
ls -la ~/.claude/

# Use absolute paths
docker run -v /home/user/.claude:/root/.claude ...
```

## Building Locally

```bash
# Clone repository
git clone https://github.com/yaniv-golan/cconductor.git
cd cconductor

# Build image
docker build -t cconductor:local .

# Run local image
docker run -v ~/.claude:/root/.claude \
  cconductor:local "your question"
```

## Related Documentation

- [Installation Guide](../README.md#installation)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Security Guide](SECURITY_GUIDE.md)

