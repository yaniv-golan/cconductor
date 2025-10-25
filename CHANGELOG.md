# Changelog

All notable changes to CConductor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2025-10-23

**⚠️ BREAKING CHANGES**: This release introduces a new session directory structure that is incompatible with previous versions. Old sessions cannot be resumed or viewed with v0.4.0.

### Added

- **Session README Generator**: new `src/utils/session-readme-generator.sh` produces the user-facing root `README.md` with direct links to the final report, research journal, dashboard, and supporting directories.
- **Structured Session Layout**: Replaced the flat session structure with an organized directory tree:
  - `meta/` - Session metadata, provenance, and configuration
  - `inputs/` - Original research question and input files
  - `cache/` - Live mission web/search caches for reuse
  - `work/` - Agent working directories (replaces `raw/`)
  - `knowledge/` - Knowledge graph and session knowledge files
  - `artifacts/` - Agent artifacts and manifest (replaces `artifacts/`)
  - `logs/` - Events, orchestration decisions, quality gate results
  - `report/` - Final mission report and research journal (replaces `final/`)
  - `viewer/` - Interactive dashboard (moved from root)
- **Session Manifest**: `INDEX.json` at session root provides quick navigation, file counts, and SHA-256 checksums for all deliverables
- **Provenance Tracking**: `meta/provenance.json` captures environment details (tool versions, git commit, system info, configuration checksums) for reproducibility
- **Session README**: `README.md` at the session root provides quick navigation, statistics, and usage examples for each session
- **Automated Release Pipeline**: GitHub Actions now build multi-arch Docker images, publish release artifacts, and update the Homebrew tap automatically (see `docs/RELEASE_AUTOMATION.md`)
- **Agent Watchdog & Cost Tracking**: Long-running agents are monitored by `agent-watchdog.sh`, cost data is extracted directly from Claude outputs, and a manual `tests/manual/cost-capture-validation` suite plus `tests/cost-extraction-test.sh` guard the budget tooling
- **Docker Distribution**: Official Docker images published to GitHub Container Registry (ghcr.io)
  - Multi-platform support (linux/amd64, linux/arm64)
  - Three authentication methods: volume mount, environment variable, Docker secrets
  - Comprehensive documentation in `docs/DOCKER.md`
  - Docker Compose example configuration
  - Automated builds via GitHub Actions on release
- **Homebrew Distribution**: Custom tap for macOS installation
  - Formula: `brew tap yaniv-golan/cconductor && brew install cconductor`
  - Automatic dependency management (bash, jq, curl, bc, ripgrep)
  - Proper library directory structure initialization
  - Installation guide in `docs/HOMEBREW.md`
  - Automated formula updates on release via GitHub Actions
- **Confidence Surface**: Quality gate results now visible in every report
  - Gate output includes structured `confidence_surface` with source counts, trust scores, limitation flags
  - Synthesis agent mandated to include "Confidence & Limitations" section in reports
  - Render fallback ensures visibility even if synthesis omits section
  - Optional KG integration stores `quality_gate_assessment` in claims
  - Session-level tracking records all gate runs in `meta/session-metadata.json`
  - Documented in `docs/RESEARCH_QUALITY_FRAMEWORK.md` and `docs/KNOWLEDGE_SYSTEM_TECHNICAL.md`
- **Quality Remediator Improvements**:
  - Increased timeout from 600s to 900s (15 minutes) to accommodate heavy remediation workloads
  - QA cycle now distinguishes timeout (124) from other failures, allowing retry on timeout instead of immediately failing
  - Better logging: "timed out" vs "failed (exit code: N)" for clearer diagnostics
  - Strengthened prompt to prevent planning loops: agent must complete with summary after writing JSON
  - Added explicit output format template to ensure consistent response structure

### Changed

- **Meta README Flow**: `manifest-generator.sh` has been renamed to `meta-manifest-generator.sh` and now targets the `meta/` directory exclusively.
- **Session File Paths** (breaking): All file references updated to use the new session directory structure

### Fixed

- **Session Resume Bug**: Fixed `cconductor sessions resume` command not passing session ID and arguments to handler, causing "Session ID required" error. The command now correctly forwards all arguments after the subcommand.
- **Resume UX**: Added helpful message when attempting to resume a session that has exhausted its iterations/time, with actionable suggestions including the new extension flags.
- **Session Extension**: Added `--extend-iterations N` and `--extend-time M` flags to `cconductor sessions resume` command:
  - `--extend-iterations N`: Add N additional iterations to completed sessions
  - `--extend-time M`: Add M additional minutes to the time budget
  - Preserves all accumulated knowledge, sources, and research context
  - Both flags can be used together for comprehensive session extension
  - **Budget Tracking**: Extension flags now properly update the persisted `meta/budget.json` file via new `budget_extend_limits` function, ensuring budget checks respect extended limits
  - Knowledge graph: `knowledge-graph.json` → `knowledge/knowledge-graph.json`
  - Final report: `final/mission-report.md` → `report/mission-report.md`
  - Events log: `events.jsonl` → `logs/events.jsonl`
  - Artifacts: `artifacts/<agent>/` → `artifacts/<agent>/`
  - Dashboard: `dashboard.html` → `viewer/index.html`
- **Session Metadata Files**: `budget.json`, `mission-metrics.json`, and `orchestrator-*.json` now live under `meta/`, and per-session error logs write to `logs/system-errors.log`.
- **MCP Configuration**: `.mcp.json` remains at session root (Claude Code requirement) with organizational symlink in `meta/`
- **Agent Prompts**: Updated synthesis-agent, mission-orchestrator, and quality-remediator system prompts with new file paths
- **Dashboard**: Moved to `viewer/` directory, updated file references to use relative paths to parent directories
- **Budget Tracking**: `invoke-agent.sh` now records real Claude spend per agent invocation, and mission logs/events moved under `logs/` for consistent auditing
- **Documentation**: Every guide (README, USAGE, TROUBLESHOOTING, SESSION_RESUME, etc.) now reflects the new directory layout and agent workflow paths

### Migration

**No automatic migration is provided.** To work with v0.4.0:
- Old sessions remain readable but cannot be resumed or viewed with the new dashboard
- New missions automatically use the v0.4.0 structure
- Manual migration: copy files from old structure to the corresponding new directories if needed

### Documentation

- Added dedicated guides for Docker (`docs/DOCKER.md`), Homebrew (`docs/HOMEBREW.md`), and release automation (`docs/RELEASE_AUTOMATION.md`)
- Updated `USAGE.md`, `README.md`, `TROUBLESHOOTING.md`, and session continuity/resume guides with the new session structure
- Added `memory-bank/systemPatterns.md` documentation for new architecture

### Removed

- Retired the legacy `docs/KG_ARTIFACT_PATTERN.md` guide; its schema details now live inside the new session knowledge tooling

## [0.3.3] - 2025-10-23

### Added

- **Coverage Gap Remediation**: Missions now verify quality standards before generating final reports. Quality gate automatically triggers remediation when research doesn't meet configured thresholds for sources, domains, trust scores, or recency.
- **Agent Timeout Protection**: Agents that become unresponsive are automatically terminated after configurable timeouts (10-20 minutes depending on agent type), allowing missions to adapt and continue.
- **Quality Gate Modes**: Choose between "advisory" mode (flags issues but allows synthesis) or "enforce" mode (blocks synthesis until standards met) via `config/quality-gate.default.json`.

### Fixed

- Mission orchestration log parsing errors when starting new sessions
- Path displays now consistently show relative paths in terminal output
- Agents hanging indefinitely without timeout protection

### Changed

- **Streamlined Cache Messages**: Verbose mode now shows single-line cache notifications instead of multi-line status updates. Cache hits display as `♻️ Cache hit: <url> (from date)` and misses as `🌐 <url> (reason)`.
- **Clearer Quality Gate Messaging**: Changed "failed" to "flagged" and "blocked" to "postponed" for more accurate, constructive terminology.
- **Improved Cache Guidance**: Updated documentation to clarify when agents should bypass cache (only when search landscape changes, not for finding recent content).

## [0.3.2] - 2025-10-22

### Fixed

- Orchestrator agent I/O model understanding: Updated system prompt to clarify that research agents return JSON in responses rather than writing to files directly. Prevents confusing refinement instructions on agent reinvocation.
- Knowledge graph integration now uses `json-parser.sh` utilities to properly handle markdown-wrapped JSON from agents. Fixes issue where agent findings weren't integrated when wrapped in markdown code fences.

### Changed

- Consolidated JSON parsing across `knowledge-graph.sh` and `export-journal.sh` to use shared `json-parser.sh` utilities for consistent markdown fence handling.

## [0.3.1] - 2025-10-22

### Changed

- **Code Consolidation** - Centralized helper functions across 38 files, reducing code duplication by ~500 lines and improving maintainability
- **Cross-Platform Improvements** - Enhanced macOS compatibility with atomic locking using `mkdir` instead of `flock`
- **Error Handling** - Consistent error messages and logging across all utilities and hooks

### Fixed

- Fixed path error in `kg-integrate.sh` that prevented knowledge graph integration
- Fixed bash syntax error in `orchestration-logger.sh` when logging JSON with parentheses
- Fixed variable collision in `shared-state.sh` that broke digital librarian functionality
- Fixed missing input validation in `citation-tracker.sh` and `research-logger.sh` hooks

### Added

- New helper modules: `core-helpers.sh`, `json-helpers.sh`, `file-helpers.sh`, `hash-file.sh`, `hash-string.sh`
- Cross-platform hashing utilities supporting sha256sum/shasum/openssl
- Graceful degradation for hooks when helper functions unavailable

## [0.3.0] - 2025-10-22

This release focuses on production-ready research outputs and smoother day-to-day workflows: configurable quality gates (with automated remediation), a fully integrated paragraph-level evidence pipeline, hardened fact-checking prompts, and a revamped caching + TUI experience that makes repeated missions faster and easier to manage.

### Added

- Configurable quality gate diagnostics (`config/quality-gate.default.json`) with granular thresholds, expanded documentation, and automated tests so teams can dial rigor up or down per mission.
- A dedicated quality remediator agent that can automatically address issues flagged by the gate before a report ships.
- Cache-aware web research tooling: shared Library Memory guardrails, new `cache-aware web research` skill, and supporting scripts/hooks that safely reuse previously sourced material.
- Bash-first evidence tooling that captures paragraph-level citations, source deep links, fallback bundles, and journal exports without relying on external scripts—complete with parity tests.
- Updated documentation covering the new evidence workflow, cache controls, and release planning guidance.

### Changed

- Mission outputs (mission report, research journal, evidence artifacts) now live in each session's `report/` directory, with dashboards, CLI helpers, and docs updated accordingly.
- Evidence generation is integrated across the orchestration pipeline; mission orchestration, hooks, and prompts were refreshed to automatically collect, merge, and render citations, and `cconductor` now defaults to `--evidence-mode render` with paragraph-level footnotes.
- Web caching received a full overhaul: richer verbose narration, stronger library guardrails, a smarter web-search cache, and new CLI flags (`--no-cache`, `--no-web-fetch-cache`, `--no-web-search-cache`) for fine-grained control.
- Sessions now persist the project root (`.cconductor-root`) so relocated session directories continue to resolve tools and agents correctly.
- Interactive tooling took a big leap—session browser entries are more compact, show emoji status indicators, surface process health, and the Configure action now displays live settings output in both CLI and dialog TUIs. Run ./cconductor with no args to go into Interactive mode.
- Launcher, test runner, and related scripts now explicitly run under Bash 4 to guarantee consistent behavior across macOS and Linux.
- Documentation was refreshed to remove hard-coded versions and to highlight the new caching and evidence flows.

### Fixed

- Mission synthesis instructions now escape literal Markdown characters (e.g., `~`) so financial figures and other symbols render correctly in exported reports.
- Adjacent footnote citations are separated with commas (`[^1], [^2]`), preventing markdown engines from collapsing superscripts.

### Removed

- **Session Layout Migrator Utility**: deleted `session-layout-migrator.sh`; the codebase now assumes the current session layout everywhere.
- Deleted `RELEASE_NOTES_v0.2.0.md`; ongoing release notes will live exclusively alongside GitHub Releases.
- Removed the unused `cache_snapshots/` placeholder; future reproducibility snapshots will be reconsidered when the feature is implemented.

## [0.2.3] - 2025-10-13

### Added

- **Security Enhancements**: Comprehensive security fixes for shell scripting vulnerabilities (see `docs/SECURITY_FIXES_2025-10-13.md`)
  - Fixed command injection vulnerability in `with_lock` function (replaced `eval` with safe `"$@"`)
  - Added trap handlers to prevent stale locks on error conditions
  - Implemented checksum verification for self-update downloads (prevents RCE)
  - Separated curl stderr from status output to prevent corruption
  - Changed to safer `rmdir` for lock directory removal
  - Made `debug.sh` and `error-messages.sh` safe for sourcing (conditional `set -e`)
  - Improved `setup-hooks.sh` idempotency with deep merge
  - Enhanced error handling in `kg-integrate.sh` with optional dependencies
  - Added semver validation to `verify-version.sh`
  - Fixed JSON array initialization in `artifact-manager.sh`
  - Broadened function search in `code-health.sh`
  - Fixed `max_length` parameter usage in `summarizer.sh`

- **Configurable Security Policies**: Safe-fetch security restrictions now configurable
  - New configuration file: `config/safe-fetch-policy.default.json`
  - Control URL restrictions (localhost, IP addresses)
  - Control content restrictions (executables, archives, compressed files)
  - All policies default to secure settings (blocking enabled)

### Changed

- **Timestamp Refactoring**: Standardized timestamp generation across all modules
  - All modules now use centralized `get_timestamp()` function from `src/shared-state.sh`
  - Ensures consistent UTC ISO 8601 format throughout the system
  - Updated 6 files: `cconductor-mission.sh`, `mission-orchestration.sh`, `mission-session-init.sh`, `kg-artifact-processor.sh`, and two hook scripts

### Removed

- Deleted one-time migration script `scripts/refactor-timestamps.sh` after manual verification and application
- Updated `scripts/README.md` to reflect script cleanup

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
- **Decision Logging**: Structured orchestration decisions in `logs/orchestration.jsonl`

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
