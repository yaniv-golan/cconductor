# Changelog

All notable changes to CConductor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2025-10-09

### Added

- **Enhanced Agent Prompts**: XML tags for improved Claude parsing and response quality
- **arXiv MCP Server Integration**: Automatic tool discovery for enhanced academic research capabilities
- **Research Journal Enhancements**: Improved agent reasoning extraction and markdown formatting in research outputs
- **Journal Export Improvements**: Enhanced export functionality with better formatting and auto-refresh capabilities

### Fixed

- **Research Journal Viewer**: Fixed link visibility and auto-refresh functionality
- **HTTP Server Management**: Improved server lifecycle management for dashboard
- **Code Quality**: Added shellcheck compliance fixes and cleanup

### Changed

- **Business Terminology**: Generalized market/business research terminology for broader applicability

### Documentation

- **Technical Documentation**: Added comprehensive Knowledge System Technical Deep Dive
- **Visual Documentation**: Added Mermaid diagrams for user experience and core functionality flows
- **Cross-references**: Enhanced documentation with better internal linking
- **README Updates**: Updated README and removed outdated configuration references

## [0.1.0] - 2025-10-05

### Added

- Multi-agent AI research system with 10+ specialized agents
- Real-time Research Journal Viewer with live progress tracking
- Journal export to comprehensive markdown timeline
- Adaptive research with automatic gap detection and follow-up
- Quality scoring and validation (0-100 scale)
- Automatic citations and bibliography generation
- Complex research queries from markdown files (`--question-file`)
- Local file analysis (`--input-dir`) with PDFs, markdown, and text
- Content-addressed PDF caching with deduplication
- Platform-aware file locations (macOS, Linux, Windows)
- Auto-initialization on first run
- Auto-dependency installation (jq, curl)
- One-line installer with PATH management
- Update detection and notification system
- Self-update capability (`cconductor --update`)
- GitHub Releases with checksum verification
- CI/CD automation with GitHub Actions
- Configurable security profiles (strict/permissive/max_automation)
- Custom knowledge base support
- Academic database integration (arXiv, Semantic Scholar, PubMed)
- Parallel task execution
- Session management and resumption
- Cross-platform support (macOS, Linux, Windows/WSL)

### Security

- SHA256 checksums for all release artifacts
- Verified installation option
- No telemetry or tracking
- Offline-capable operation
- Configurable domain permissions
