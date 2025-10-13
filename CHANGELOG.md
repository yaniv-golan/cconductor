# Changelog

All notable changes to CConductor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2025-10-13

### Removed

- Non-functional output formatter scripts that were never integrated with the system

## [0.2.1] - 2025-10-12

### Fixed

- Documentation: Fixed 24 issues across README and docs/ (invalid commands, outdated versions, wrong file references)
- Export: Converted journal export to Obsidian foldable callout syntax for better compatibility

## [0.2.0] - 2025-10-12

### Mission-Based Orchestration

**Breaking Changes**: v0.2.0 introduces mission-based orchestration, replacing the task-queue system with autonomous research coordination.

- **Mission Types**: Use `--mission` flag to specify research type (academic-research, market-research, competitive-analysis, technical-analysis)
- **Autonomous Agent Selection**: System dynamically selects best agents based on research needs
- **Budget Tracking**: Monitor and control research costs with soft warnings and hard limits
- **Decision Logging**: Structured orchestration decisions in `orchestration-log.jsonl`

### Interactive Mode

- **Guided Setup**: Run `./cconductor` without arguments for interactive research wizard
- **Session Browser**: Interactive session listing and management
- **Resume with Refinement**: Continue research with specific guidance (`--refine` flag)

### Enhanced Research Journal

- **Agent Reasoning**: Dashboard and exports now show agent reasoning and decision-making
- **Verbose Mode**: Real-time progress updates (enabled by default, use `--quiet` to disable)
- **Better Truncation**: Improved display of long content in dashboard
- **Export Improvements**: Markdown exports include full agent reasoning

### Session Management

- **Unified Commands**: New `sessions` subcommand with list/latest/viewer/resume actions
- **Session Viewer**: View research journal with `cconductor sessions viewer`
- **Better Organization**: Improved session listing and status display

### Prompt Parser & Output Formatting 

- **Automatic Prompt Separation**: New prompt-parser agent separates research objectives from formatting instructions
- **Custom Output Formats**: Specify how results should be formatted without confusing research agents
- **Clean Knowledge Graph**: Research objectives stored without format pollution or JSON corruption
- **Flexible Presentation**: Same research can be reformatted without re-running
- **Action Verbs**: Agents now have configurable action verbs for better verbose output (e.g., "Researching", "Parsing", "Synthesizing")

### Knowledge Graph Integration

- **Reliable KG Integration**: Resolved silent sourcing failures that prevented KG integration
  - Created standalone `kg-integrate.sh` wrapper with subprocess isolation
  - Eliminated complex dependency chain issues
  - Added resilient 4-path extraction for findings files (Tier 1)
  - Enhanced Tier 0 extraction for structured JSON output
  - Production validated: 100% success rate across multiple agents
- **Agent JSON Output**: Strengthened JSON output requirements for research agents
  - Agent-specific instructions to prevent markdown fallback
  - Enhanced web-researcher manifest validation
  - Added JSON parser integration for Tier 0 validation
- All research agent findings now reliably integrate into knowledge graph
- Fast execution: 3-5 seconds per integration
- Defensive error handling: warnings don't break sessions

### Technical Improvements

- **Error Logging**: Centralized error tracking system for better observability
- **Platform Compatibility**: Improved macOS and Linux compatibility
- **Display Names**: Agents now have user-friendly display names in UI
- **Code Quality**: Comprehensive shellcheck validation
- **Path Resolution**: Fixed double `src/src` path issues in orchestrator
- **Agent Security**: Read-only tool restrictions for prompt-parser agent
- **Export Journal**: Fixed unbound variable error in trap handler

### Migration from v0.1.x

- Mission-based workflow is now the primary interface
- Use `--mission` flag for specific research types (optional, auto-detected if not specified)
- Session IDs now use `mission_` prefix instead of `session_`
- Old v0.1.x sessions remain readable

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
