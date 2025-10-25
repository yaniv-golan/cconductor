FROM ubuntu:22.04

LABEL org.opencontainers.image.source="https://github.com/yaniv-golan/cconductor"
LABEL org.opencontainers.image.description="CConductor - AI Research, Orchestrated"
LABEL org.opencontainers.image.licenses="MIT"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    bash \
    jq \
    curl \
    bc \
    python3 \
    ripgrep \
    nodejs \
    npm \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Create application directory
WORKDIR /opt/cconductor

# Copy application files
COPY cconductor ./cconductor
COPY src/ ./src/
COPY config/ ./config/
COPY knowledge-base/ ./knowledge-base/
COPY library/ ./library/
COPY docs/ ./docs/
COPY VERSION ./VERSION
COPY LICENSE ./LICENSE
COPY README.md ./README.md

# Set executable permissions
RUN chmod +x cconductor && \
    find src/ -name "*.sh" -type f -exec chmod +x {} \;

# Create data directories and library structure
RUN mkdir -p /data/research-sessions /data/cache /data/config /data/logs && \
    mkdir -p /opt/cconductor/library/sources /opt/cconductor/library/digests

# Add to PATH
ENV PATH="/opt/cconductor:${PATH}"

# Volume mount points for persistent data
VOLUME ["/data/research-sessions", "/data/cache", "/root/.config/claude"]

# Set working directory for user operations
WORKDIR /data

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["--help"]

