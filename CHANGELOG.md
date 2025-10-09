# Changelog

All notable changes to CConductor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-10-09 (In Development)

### 🚀 Major Changes - Mission-Based Orchestration

**Breaking Changes**: v0.2.0 introduces mission-based orchestration, replacing the task-queue system with autonomous, agentic research coordination.

### Added

#### Mission System
- **Mission Profiles**: JSON-based mission definitions with objectives, success criteria, and constraints
- **Mission Orchestrator Agent**: Autonomous orchestrator with plan/reflect/act cycle
- **4 Generic Mission Templates**: academic-research, market-research, competitive-analysis, technical-analysis
- **Mission CLI**: New `cconductor-mission.sh` entry point with run/missions/agents/dry-run commands

#### Agent Registry & Metadata
- **Agent Registry**: Capability-based agent discovery and selection
- **Extended Agent Metadata**: Capabilities, input/output types, expertise domains, output schemas
- **Capability Taxonomy**: 16 standardized capabilities (market_sizing, academic_research, etc.)
- **Input/Output Type Taxonomies**: Standardized type systems for agent I/O
- **User Agent Override**: User-defined agents override project agents by name

#### Orchestration Infrastructure
- **Budget Tracking**: Multi-dimensional tracking (USD, time, invocations) with soft/hard limits
- **Decision Logging**: Structured orchestration decisions in `orchestration-log.jsonl`
- **Artifact Management**: Content-addressed artifacts with provenance tracking
- **Handoff Protocol**: Agent-to-agent handoff tracking in knowledge graph

#### Event System
- **Mission Events**: 7 new event types (mission_started, mission_completed, orchestrator_*, agent_handoff, etc.)
- **Event Contract**: Documented event schema with backward compatibility guarantees
- **Orchestration Observability**: Comprehensive logging of orchestrator reasoning

### Changed

- **Orchestration Model**: Replaced rigid task-queue with autonomous mission orchestration
- **Agent Selection**: Dynamic capability-based selection vs. hardcoded coordinator
- **Knowledge Graph**: Extended to track handoffs and agent invocations

### Removed

- **Task Queue System**: `task-queue.sh` functionality replaced by mission orchestrator

### Documentation

- **AGENT_METADATA_SCHEMA.md**: Comprehensive agent metadata documentation
- **EVENTS_CONTRACT.md**: Event schema contract and backward compatibility guide
- **Mission README**: Mission profile structure and best practices
- **IMPLEMENTATION_SUMMARY.md**: Complete implementation status and architecture

### Migration Notes

v0.2.0 intentionally breaks backward compatibility with v0.1.x for a clean, agentic design:
- Mission-based research now requires `--mission` flag
- Old sessions remain readable but new workflow required for new research
- User agents/missions in `~/.config/cconductor/` override project defaults
- See `IMPLEMENTATION_SUMMARY.md` for complete migration guide

### Known Limitations

- Orchestrator agent invocation integration pending (placeholder implementation)
- TUI support deferred to post-MVP
- Dashboard mission view pending
- Comprehensive testing in progress

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
