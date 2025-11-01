# Changelog

All notable changes to CConductor will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - Unreleased

### Added

- Stakeholder classification pipeline with a dedicated Claude agent, deterministic classifier, gate evaluator, and defaults so every mission automatically maintains stakeholder coverage; includes a `cconductor stakeholders refresh <session_id>` helper for reruns.
- Mission-scoped stakeholder policies and resolvers for all built-in missions, plus global defaults you can override in your own config.
- Quality gate regression coverage that seeds classification artifacts and keeps the new stakeholder checks stable.
- Research Journal Viewer now launches a preflight dashboard with domain heuristics, prompt parsing, and stakeholder summaries, and streams text artifacts through session-aware tabs.
- Argument Event Graph (AEG) pipeline that captures the claims and evidence each agent produces, lets you review relationships inside the dashboard, and can export to Argument Interchange Format (AIF)—a standard JSON-LD model used by argument-mapping tools—for outside analysis.
- Argument Contract Claude skill that standardizes how agents stream `argument_event` payloads, giving you consistent IDs and envelopes across academic, market, fact-checking, and quality roles.
- Session manifest pipeline that regenerates a curated `session-manifest.json` before every orchestrator turn so prompts and dashboards share the same source of truth.
- Write-tool artifact contract system that defines expected outputs per agent, validates them against shared schemas, and ships fixtures plus tests to prevent regressions.
- Optional independent source enforcement toggle (`CCONDUCTOR_REQUIRE_INDEPENDENT_SOURCES`) that blocks synthesis until claims cite enough distinct domains and logs missing coverage to `meta/independent-source-issues.json`.

### Changed

- Non-interactive installs now auto-provision required dependencies (including ripgrep) when you pass `--yes` and fail fast if tooling can’t be installed.
- Quality gate hook delegates stakeholder coverage decisions to the new reports, improving uncategorized tracking and failure messaging.
- Mission profiles are organized as discoverable bundles so mission loader updates happen transparently.
- Quality Guide and agent directory explain how the stakeholder classifier, policies, and gate cooperate.
- Dashboard viewer URLs are now session-prefixed, keeping links stable across concurrent viewers while the server serves the mission root.
- User Guide and Troubleshooting guide cover the new viewer URL pattern, preflight card, and recovery tips for blank tabs or 404s.
- Public docs are streamlined by moving maintainer references to the contributor section, with refreshed internal links.
- Mission state builder emits knowledge-graph and orchestration log paths relative to the session root, keeping prompts and agent reads sandbox-friendly.
- Streaming handler tolerates missing terminal `result` events by assembling partial deltas and warning instead of stalling.
- Agent invocation enforces artifact contracts, reports failures clearly in events/dashboards, and documents validation/bypass workflows in the Quick Start, Troubleshooting, and Quality guides.

### Fixed

- Trimmed noisy update notifications in `version-manager.sh` so resume/startup logs only display the latest available version tag.
- Fixed non-interactive installs hanging on the ripgrep prompt by teaching `src/init.sh` to honor `--yes` and wiring installers/updates to pass the flag through.
- When the provider reports "Session limit reached", `invoke-agent.sh` now logs the failure, emits a friendly CLI warning, and the mission halts immediately instead of falling back to defaults or continuing with a broken run.

## [0.4.1] - 2025-10-29

### Changed

- Expanded `./cconductor --help` coverage so debug and watchdog/timeout controls (including their aliases) are surfaced directly in the CLI output.
- Documented environment toggles for watchdog/timeouts, cache bypassing, and streaming diagnostics across the User Guide, Troubleshooting guide, Quality Guide, and Configuration Reference to clarify automation workflows.
- Aligned installation guidance in the README and User Guide: clarified Claude Code authentication via `claude` + `/login` + `/status`, listed required dependencies (bash ≥4, jq, curl, bc, git, ripgrep, Python 3, dialog), and highlighted Homebrew vs. curl installer paths for macOS and Linux users.
- Surfaced authoritative budget telemetry everywhere: mission state now records elapsed minutes and limit thresholds, orchestrator context prints the derived usage, and the journal appends a ledger-backed “Budget Snapshot” after strategic decisions.
- `export-journal.sh` now re-execs under Homebrew Bash when available so Bash 4+ features (parameter case transforms, arrays) always work during ad-hoc exports.

### Removed

- Dropped the unused `CCONDUCTOR_SEED` metadata field from generated `provenance.json` files to keep session artifacts lean.

### Fixed

- Hardened journal cleanup: the export script only removes temp files when paths exist, eliminating the lingering `rm -f '' ''` warning during regeneration.
- Fixed journal export exit codes by replacing brittle jq quoting, preventing macOS exports from aborting with status 1 despite generating output.

## [0.4.0] - 2025-10-29

**⚠️ BREAKING CHANGES**: Mission state now lives under `research-sessions/mission_<id>/` with a structured layout (manifest, README, dedicated subdirectories). Sessions created on v0.3.x or earlier cannot be resumed or viewed after upgrading.

### Added

- **Structured mission navigation**: Missions now emit `INDEX.json`, a mission README, and an expanded directory tree (`artifacts/`, `cache/`, `evidence/`, `inputs/`, `knowledge/`, `library/`, `logs/`, `meta/`, `report/`, `viewer/`, `work/`) so key assets are discoverable without spelunking.
- **Session README generator**: `src/utils/session-readme-generator.sh` keeps the mission README current with progress stats, quick links, and surfaced artifacts for reviewers.
- **Streaming runtime & watchdog controls**: Research now runs through a streaming orchestrator backed by `agent-watchdog.sh`, configurable heartbeats, and CLI/config toggles (`--enable/disable-watchdog`, `--enable/disable-agent-timeouts`) to tune mission safety budgets.
- **Quality surface & domain-aware guardrails**: Reports embed the new `confidence_surface`, domain heuristics, and remediation guidance; supporting scripts (`src/utils/domain-compliance-check.sh`, `src/utils/quality-surface-sync.sh`) keep evidence, gate data, and dashboards aligned.
- **Distribution & release automation**: Official Docker images, a Homebrew tap, and release automation docs (`docs/DOCKER.md`, `docs/HOMEBREW.md`, `docs/contributers/RELEASE_AUTOMATION.md`) ship with CI workflows that publish artifacts and refresh the tap automatically.
- **Tooling guardrails**: Safe `jq` helpers plus lint scripts (`scripts/audit-jq-usage.sh`, `scripts/lint-jq-patterns.sh`) and the tracked `scripts/pre-commit.sh` enforce consistent parsing, ShellCheck coverage, and runtime hygiene.

### Changed

- **Mission orchestration & resume flow**: Resume supports refinement prompts, iteration/time extensions, richer mission metrics, and hardened orchestration loops for multi-iteration runs.
- **CLI & prompts**: The launcher prefers Homebrew Bash when present, `./cconductor sessions` surfaces mission-centric identifiers, and agent prompts reinforce temporal and reporting checkpoints.
- **Logging & dashboards**: Consolidated logging wrappers, refreshed dashboards, and enhanced budget tracking keep watchdog timing, costs, and provenance visible inside each mission.

### Fixed

- **Mission completion edge cases**: Resolved premature completion and budget rollback bugs that previously blocked multi-iteration missions from finishing cleanly.
- **Agent reliability improvements**: Raised default timeouts for long-running agents, stabilized watchdog heartbeats, and removed stray stdout from the final banner.
- **Quality gate regressions**: Hardened malformed-sample handling and ensured remediation timeouts trigger retries instead of failing an entire QA pass.

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
