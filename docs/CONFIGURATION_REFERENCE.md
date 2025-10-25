# CConductor Configuration Reference

**Complete reference for all configuration options**

**Last Updated**: October 2025  
**For**: Advanced users and administrators

---

## Table of Contents

1. [Configuration Files Overview](#configuration-files-overview)
2. [Main Configuration (cconductor-config.json)](#main-configuration-cconductor-configjson)
3. [Research Modes (cconductor-modes.json)](#research-modes-cconductor-modesjson)
4. [Security Configuration (security-config.json)](#security-configuration-security-configjson)
5. [Adaptive Research (adaptive-config.json)](#adaptive-research-adaptive-configjson)
6. [Knowledge Base (knowledge-config.json)](#knowledge-base-knowledge-configjson)
7. [Paths Configuration (paths.json)](#paths-configuration-pathsjson)
8. [MCP Servers (mcp-servers.json)](#mcp-servers-mcp-serversjson)
9. [Configuration Patterns](#configuration-patterns)
10. [Advanced Topics](#advanced-topics)

---

## Configuration Files Overview

### Location

Configuration files are stored in OS-appropriate locations:

**User Configs (your customizations)**:

- **macOS**: `~/.config/cconductor/`
- **Linux**: `~/.config/cconductor/` (or `$XDG_CONFIG_HOME/cconductor/`)
- **Windows**: `%APPDATA%\CConductor\`

**Default Configs (git-tracked, don't edit)**:

- `PROJECT_ROOT/config/*.default.json`

```
# User configs (in your home directory)
~/.config/cconductor/
  cconductor-config.json              Main configuration
  cconductor-modes.json               Research mode definitions
  security-config.json           Security settings
  adaptive-config.json           Adaptive research settings
  knowledge-config.json          Knowledge base paths
  paths.json                     Directory paths
  mcp-servers.json              MCP server integrations
  
# Default configs (in project directory)  
PROJECT_ROOT/config/
  *.default.json                 Default versions (don't edit these!)
```

### The `.default` Pattern

**How configs work**:

1. **Default configs**: In `PROJECT_ROOT/config/*.default.json` (git-tracked, never edit)
2. **User configs**: In `~/.config/cconductor/*.json` (your customizations)
3. **Loading**: CConductor loads defaults, then overlays your customizations

**Benefits**:

- ✅ Your customizations stored in OS-standard location
- ✅ Survive project deletion/reinstallation
- ✅ Git updates never overwrite your settings
- ✅ Multi-user support (each user has own configs)
- ✅ You can always reset: delete your config to use defaults

**Upgrade safety**: Your customizations in `~/.config/cconductor/` persist across CConductor upgrades and reinstalls!

---

## Main Configuration (cconductor-config.json)

### Overview

**File**: `config/cconductor-config.json`  
**Purpose**: Primary configuration for research behavior  
**Affects**: All research sessions

### Full Structure

```json
{
  "version": "0.1.0",
  "research": { ... },
  "research_modes": { ... },
  "agents": { ... },
  "context_management": { ... },
  "output": { ... },
  "logging": { ... },
  "quality_gates": { ... },
  "advanced": { ... }
}
```

---

### Section: research

**Controls basic research parameters**

```json
"research": {
  "max_web_searches": 5,
  "sources_per_search": 7,
  "min_source_credibility": "medium",
  "require_cross_validation": true,
  "min_sources_per_claim": 3,
  "include_code_analysis": true,
  "search_timeout_seconds": 30
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_web_searches` | integer | `5` | Max web searches per research task |
| `sources_per_search` | integer | `7` | How many sources to analyze per search |
| `min_source_credibility` | string | `"medium"` | Minimum source quality: `"low"`, `"medium"`, `"high"` |
| `require_cross_validation` | boolean | `true` | Require multiple sources for claims |
| `min_sources_per_claim` | integer | `3` | Minimum sources to support each claim |
| `include_code_analysis` | boolean | `true` | Enable code repository analysis |
| `search_timeout_seconds` | integer | `30` | Timeout for web searches |

**When to adjust**:

- **Increase `max_web_searches`** for more comprehensive research (slower)
- **Decrease `sources_per_search`** for faster research (less thorough)
- **Set `min_source_credibility` to "high"** for academic work
- **Increase `min_sources_per_claim`** for higher reliability

---

### Section: research_modes

**Configure built-in research modes**

```json
"research_modes": {
  "scientific": {
    "enabled": true,
    "min_peer_reviewed_sources": 5,
    "require_methodology_assessment": true,
    "require_statistical_analysis": true,
    "check_retractions": true,
    "track_citation_network": true,
    "preferred_databases": ["arxiv", "google_scholar", "pubmed"]
  },
  "business_market": { ... },
  "technical": { ... },
  "general": { ... }
}
```

**Scientific Mode Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable this mode |
| `min_peer_reviewed_sources` | integer | `5` | Minimum peer-reviewed papers needed |
| `require_methodology_assessment` | boolean | `true` | Assess study methodology |
| `require_statistical_analysis` | boolean | `true` | Include statistical analysis |
| `check_retractions` | boolean | `true` | Check if papers were retracted |
| `track_citation_network` | boolean | `true` | Analyze citation relationships |
| `preferred_databases` | array | See config | Prioritize these academic databases |

**Business/Market Mode Options**:

```json
"business_market": {
  "enabled": true,
  "require_tam_sam_som": true,
  "min_competitors_analyzed": 5,
  "require_financial_metrics": true,
  "require_multiple_market_sources": true,
  "track_funding_rounds": true,
  "distinguish_disclosed_vs_estimated": true
}
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `require_tam_sam_som` | boolean | `true` | Calculate TAM/SAM/SOM |
| `min_competitors_analyzed` | integer | `5` | Minimum competitors to analyze |
| `require_financial_metrics` | boolean | `true` | Extract financial data |
| `require_multiple_market_sources` | boolean | `true` | Cross-validate market data |
| `track_funding_rounds` | boolean | `true` | Track company funding |
| `distinguish_disclosed_vs_estimated` | boolean | `true` | Separate disclosed from estimated data |

**Technical Mode Options**:

```json
"technical": {
  "enabled": true,
  "require_code_examples": true,
  "require_file_line_references": true,
  "include_architecture_analysis": true
}
```

**General Mode Options**:

```json
"general": {
  "enabled": true,
  "default_mode": true
}
```

---

### Section: agents

**Control AI agent behavior**

```json
"agents": {
  "parallel_execution": true,
  "max_parallel_agents": 4,
  "model": "claude-sonnet-4-5",
  "context_window_limit": 180000,
  "agent_timeout_minutes": 10,
  "available_agents": [
    "research-planner",
    "web-researcher",
    "code-analyzer",
    "academic-researcher",
    "market-analyzer",
    "competitor-analyzer",
    "financial-extractor",
    "synthesis-agent",
    "fact-checker"
  ]
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `parallel_execution` | boolean | `true` | Run agents in parallel |
| `max_parallel_agents` | integer | `4` | Max simultaneous agents |
| `model` | string | `"claude-sonnet-4-5"` | Claude model to use |
| `context_window_limit` | integer | `180000` | Max tokens per agent |
| `agent_timeout_minutes` | integer | `10` | Timeout for each agent |
| `available_agents` | array | See config | Which agents are enabled |

**When to adjust**:

- **Decrease `max_parallel_agents`** to reduce Claude Code usage (fewer simultaneous prompts)
- **Increase `agent_timeout_minutes`** for complex research
- **Disable agents** by removing from `available_agents`

**Note on Claude Code usage**: Each agent invocation uses Claude Code prompts. More parallel agents = faster research but higher prompt usage. Adjust `max_parallel_agents` to balance speed vs. cost based on your Claude subscription/API plan.

---

### Section: context_management

**Manage token usage and context**

```json
"context_management": {
  "enable_pruning": true,
  "enable_summarization": true,
  "max_facts_per_source": 10,
  "token_budget_per_agent": {
    "research-planner": 10000,
    "web-researcher": 40000,
    "code-analyzer": 30000,
    "academic-researcher": 40000,
    "market-analyzer": 40000,
    "competitor-analyzer": 40000,
    "financial-extractor": 30000,
    "synthesis-agent": 60000,
    "fact-checker": 40000
  }
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_pruning` | boolean | `true` | Remove low-relevance content |
| `enable_summarization` | boolean | `true` | Summarize long content |
| `max_facts_per_source` | integer | `10` | Max facts extracted per source |
| `token_budget_per_agent` | object | See config | Token limits per agent type |

**Token budgets**: Control how much context each agent type can use. Increase for deeper analysis, decrease to save costs.

---

### Section: output

**Control output format and content**

```json
"output": {
  "default_format": "markdown",
  "include_confidence_scores": true,
  "show_conflicting_info": true,
  "show_knowledge_gaps": true,
  "citation_style": "inline",
  "include_methodology_section": true
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `default_format` | string | `"markdown"` | Output format |
| `include_confidence_scores` | boolean | `true` | Show confidence in findings |
| `show_conflicting_info` | boolean | `true` | Highlight contradictions |
| `show_knowledge_gaps` | boolean | `true` | Note areas needing more research |
| `citation_style` | string | `"inline"` | Citation format |
| `include_methodology_section` | boolean | `true` | Add methodology description |

---

### Section: logging

**Control logging behavior**

```json
"logging": {
  "enabled": true,
  "log_level": "info",
  "log_queries": true,
  "log_sources": true,
  "audit_trail": true,
  "log_file": "../logs/research.log"
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable logging |
| `log_level` | string | `"info"` | Log level: `"debug"`, `"info"`, `"warn"`, `"error"` |
| `log_queries` | boolean | `true` | Log research questions |
| `log_sources` | boolean | `true` | Log accessed sources |
| `audit_trail` | boolean | `true` | Complete audit trail |
| `log_file` | string | `"../logs/research.log"` | Log file path |

---

### Section: quality_gates

**Set quality thresholds**

```json
"quality_gates": {
  "min_sources": 3,
  "min_verified_claims_percentage": 70,
  "fail_on_low_quality": false,
  "warn_on_conflicts": true
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `min_sources` | integer | `3` | Minimum sources required |
| `min_verified_claims_percentage` | integer | `70` | Minimum % of claims with citations |
| `fail_on_low_quality` | boolean | `false` | Stop if quality threshold not met |
| `warn_on_conflicts` | boolean | `true` | Warn about source conflicts |

---

### Section: advanced

**Advanced features**

```json
"advanced": {
  "enable_mcp": false,
  "mcp_servers": [],
  "custom_agents": [],
  "enable_hooks": true,
  "cache_search_results": true,
  "cache_ttl_hours": 24
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_mcp` | boolean | `false` | Enable MCP integrations |
| `mcp_servers` | array | `[]` | MCP servers to use |
| `custom_agents` | array | `[]` | Custom agent scripts |
| `enable_hooks` | boolean | `true` | Enable hooks system |
| `cache_search_results` | boolean | `true` | Enable WebSearch cache (overrides `config/web-search-cache.default.json`) |
| `cache_ttl_hours` | integer | `24` | Default TTL for WebSearch cache entries (hours) |

### File: `config/web-fetch-cache.default.json`

```json
{
  "enabled": true,
  "ttl_hours": 24,
  "max_body_size_mb": 5
}
```

---

### File: `config/web-search-cache.default.json`

```json
{
  "enabled": true,
  "ttl_hours": 12,
  "max_entries": 400,
  "materialize_per_session": 20,
  "fresh_query_markers": [
    "?fresh=1",
    "?refresh=1"
  ],
  "log_debug_samples": false
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Toggle WebSearch cache guard and storage |
| `ttl_hours` | integer | `12` | Time-to-live for cached search results (overridden by `advanced.cache_ttl_hours` if set) |
| `max_entries` | integer | `400` | Maximum number of query entries retained in the cache index |
| `materialize_per_session` | integer | `20` | Maximum cached searches materialized into each session’s context |
| `fresh_query_markers` | array | `["?fresh=1","?refresh=1"]` | Suffixes that force a live WebSearch instead of using cache |
| `log_debug_samples` | boolean | `false` | If true, post-tool hook logs raw search payloads for debugging |

---

## Research Modes (cconductor-modes.json)

### Overview

**File**: `config/cconductor-modes.json`  
**Purpose**: Define detailed research mode configurations  
**Affects**: Research behavior per mode

### Available Modes

CConductor has 5 built-in research modes:

1. **default** - General purpose research
2. **scientific** - Academic literature with PDF analysis
3. **market** - Market sizing and competitive analysis
4. **technical** - Technical architecture deep dives
5. **literature_review** - Systematic literature reviews

### Mode Structure

```json
"scientific": {
  "name": "Scientific Literature Review",
  "description": "Academic research with full PDF analysis...",
  "agents": ["research-planner", "academic-researcher", "pdf-analyzer", ...],
  "output_format": "markdown",
  "clarification_required": true,
  "pdf_centric": true,
  "special_instructions": { ... },
  "quality_requirements": { ... }
}
```

### Mode Selection

**Automatic detection** based on keywords:

```json
"mode_selection": {
  "auto_detect_keywords": {
    "scientific": ["paper", "study", "research", "peer-reviewed", ...],
    "market": ["market size", "TAM", "SAM", "competitors", ...],
    "technical": ["implementation", "architecture", "how does", ...],
    "literature_review": ["literature review", "systematic review", ...]
  },
  "default_mode": "default"
}
```

**How it works**:

- CConductor scans your question for keywords
- Matches to the most appropriate mode
- Falls back to `default_mode` if no match

**Example**:

```bash
./cconductor "peer-reviewed research on CRISPR"
# Auto-selects "scientific" mode

./cconductor "market size for AI-powered CRM"
# Auto-selects "market" mode

./cconductor "how does Docker containerization work"
# Auto-selects "technical" mode
```

### Literature Review Mode (Most Comprehensive)

**Special features**:

```json
"literature_review": {
  "name": "Comprehensive Literature Review",
  "description": "Academic literature review with citation network analysis...",
  "agents": [
    "research-planner",
    "academic-researcher",
    "pdf-analyzer",
    "synthesis-agent",
    "fact-checker"
  ],
  "output_format": "markdown",
  "pdf_centric": true,
  "special_instructions": {
    "academic_researcher": {
      "systematic_search": true,
      "always_fetch_pdfs": true,
      "min_papers": 20,
      "track_citation_network": true,
      "identify_seminal_papers": true,
      "identify_recent_advances": true,
      "extract_full_methodology": true,
      "categorize_by_approach": true
    },
    "synthesis_agent": {
      "format": "systematic_literature_review",
      "sections": [
        "Abstract",
        "Introduction and Background",
        "Search Methodology",
        "Inclusion/Exclusion Criteria",
        "Literature Overview",
        "Thematic Analysis",
        "Methodological Comparison",
        "Key Findings Synthesis",
        "Temporal Trends",
        "Citation Network Analysis",
        "Research Gaps",
        "Limitations of Current Literature",
        "Future Research Directions",
        "Conclusion",
        "References"
      ],
      "create_summary_tables": true,
      "create_timeline": true,
      "assess_consensus": true,
      "identify_controversies": true,
      "quantitative_synthesis": true
    }
  },
  "quality_requirements": {
    "min_peer_reviewed_sources": 15,
    "min_total_papers": 20,
    "max_preprint_reliance": 0.25,
    "require_seminal_papers": true,
    "require_recent_papers": true,
    "recent_cutoff_years": 2,
    "min_citation_tracking_depth": 2,
    "require_methodological_diversity": true
  }
}
```

**Output sections**: 15 structured sections including abstract, methodology, analysis, gaps, and references.

**Quality requirements**: Highest standards - minimum 20 papers, citation network analysis, temporal trends.

**Best for**: Academic papers, dissertation research, grant proposals.

---

## Security Configuration (security-config.json)

### Overview

**File**: `config/security-config.json`  
**Purpose**: Control which domains and content CConductor can access  
**See also**: [Security Guide](SECURITY_GUIDE.md) for complete documentation

### Security Profiles

Three built-in profiles:

1. **strict** (default) - Maximum safety, prompts for unknown domains
2. **permissive** - Trusted commercial sites auto-allowed
3. **max_automation** - Minimal prompts (for sandboxed environments only)

### Profile Selection

```json
{
  "security_profile": "strict"
}
```

**Change to**:

- `"strict"` - Production, academic, sensitive work
- `"permissive"` - Business research, trusted environment
- `"max_automation"` - VMs/containers/testing only

### Profile Definitions

```json
"profiles": {
  "strict": {
    "description": "Production: Academic auto-allowed, commercial prompt once, known-bad blocked",
    "auto_allow_academic": true,
    "auto_allow_commercial": false,
    "prompt_commercial_once_per_session": true,
    "block_url_shorteners": true,
    "block_free_domains": true,
    "enable_content_scanning": true,
    "max_fetch_size_mb": 10,
    "fetch_timeout_seconds": 30
  }
}
```

**Profile options**:

| Option | Type | Strict | Permissive | Max Auto |
|--------|------|--------|------------|----------|
| `auto_allow_academic` | boolean | ✅ | ✅ | ✅ |
| `auto_allow_commercial` | boolean | ❌ | ✅ | ✅ |
| `prompt_commercial_once_per_session` | boolean | ✅ | ❌ | ❌ |
| `block_url_shorteners` | boolean | ✅ | ✅ | ✅ |
| `block_free_domains` | boolean | ✅ | ✅ | ❌ |
| `enable_content_scanning` | boolean | ✅ | ✅ | ✅ |
| `max_fetch_size_mb` | integer | 10 | 50 | 100 |
| `fetch_timeout_seconds` | integer | 30 | 60 | 120 |

### Domain Lists

**Academic (always allowed)**:

```json
"academic": [
  "arxiv.org",
  "semanticscholar.org",
  "pubmed.ncbi.nlm.nih.gov",
  "*.edu",
  "*.gov",
  "nature.com",
  "science.org",
  ...
]
```

**Commercial (profile-dependent)**:

```json
"commercial": [
  "crunchbase.com",
  "bloomberg.com",
  "techcrunch.com",
  "reuters.com",
  "forbes.com",
  ...
]
```

**Blocked (always blocked)**:

```json
"blocked": [
  "bit.ly",
  "tinyurl.com",
  "t.co",
  "*.tk",
  "*.ml",
  "*.ga",
  ...
]
```

**Customizing lists**: Add your trusted/blocked domains directly to these arrays.

---

## Adaptive Research (adaptive-config.json)

### Overview

**File**: `config/adaptive-config.json`  
**Purpose**: Configure the adaptive research loop (advanced mode)  
**Note**: This is used by `./cconductor-adaptive` only, not standard research

### Key Settings

```json
{
  "max_iterations": 10,
  "termination_threshold": 0.9,
  "gap_exploration_probability": 0.7,
  "contradiction_resolution_priority": "high",
  "lead_evaluation_threshold": 0.6,
  "min_coverage_percentage": 80,
  "min_confidence_per_entity": 0.7,
  "parallel_task_limit": 3,
  "enable_knowledge_graph": true
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `max_iterations` | integer | `10` | Max research cycles |
| `termination_threshold` | float | `0.9` | Stop when confidence reaches this |
| `gap_exploration_probability` | float | `0.7` | Chance of exploring gaps |
| `contradiction_resolution_priority` | string | `"high"` | Priority for resolving conflicts |
| `lead_evaluation_threshold` | float | `0.6` | Min score to follow a lead |
| `min_coverage_percentage` | integer | `80` | Target topic coverage % |
| `min_confidence_per_entity` | float | `0.7` | Min confidence per entity |
| `parallel_task_limit` | integer | `3` | Max parallel tasks |
| `enable_knowledge_graph` | boolean | `true` | Use knowledge graph |

**When to adjust**:

- **Increase `max_iterations`** for more thorough research
- **Increase `termination_threshold`** for higher quality (slower)
- **Decrease `min_coverage_percentage`** for faster research

---

## Knowledge Base (knowledge-config.json)

### Overview

**File**: `config/knowledge-config.json`  
**Purpose**: Configure knowledge base directories  
**Affects**: Where CConductor looks for domain knowledge

### Structure

```json
{
  "knowledge_directories": [
    "../knowledge-base",
    "../knowledge-base-custom"
  ],
  "enable_custom_knowledge": true,
  "knowledge_cache_ttl_hours": 24
}
```

**Options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `knowledge_directories` | array | See config | Directories to search for knowledge |
| `enable_custom_knowledge` | boolean | `true` | Use custom knowledge files |
| `knowledge_cache_ttl_hours` | integer | `24` | Cache lifetime for knowledge |

**Adding knowledge directories**:

```json
"knowledge_directories": [
  "../knowledge-base",           // Built-in
  "../knowledge-base-custom",    // Your knowledge
  "/path/to/company-knowledge",  // Company-wide
  "../project-knowledge"         // Project-specific
]
```

**See**: [Custom Knowledge Guide](CUSTOM_KNOWLEDGE.md) for creating knowledge files.

---

## Web Fetch Cache (web-fetch-cache.json)

### Overview

**File**: `config/web-fetch-cache.json`  
**Purpose**: Configure persistence, TTL, and reuse behaviour for WebFetch results  
**Affects**: Pre-tool cache hits, orchestrator input context, hook guidance messages

### Structure

```json
{
  "enabled": true,
  "ttl_hours": 24,
  "max_entries": 500,
  "max_total_mb": 512,
  "materialize_per_session": 25,
  "fresh_url_parameters": ["fresh=1", "fresh=true", "refresh=1", "refresh=true"]
}
```

**Key options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Toggle cache storage globally |
| `ttl_hours` | integer | `24` | Cached objects older than this are marked stale and re-fetched |
| `max_entries` | integer | `500` | Upper bound on cached URL entries before pruning oldest |
| `max_total_mb` | integer | `512` | Soft disk budget; exceeded size triggers pruning |
| `materialize_per_session` | integer | `25` | Maximum cached sources surfaced in agent context per session |
| `fresh_url_parameters` | array | see above | URL substrings that force a fresh WebFetch when present |

**Behaviour**:

- Successful WebFetch calls write bodies and metadata to `$cache_dir/web-fetch/objects/` with a shared index (`index.json`).
- Pre-tool hooks consult the cache; cache hits materialize the content under `<session>/cache/web-fetch/` and instruct agents to `Read` the cached file instead of fetching. Agents can append `?fresh=1` (or variants listed above) to bypass the cache.
- The orchestrator includes a “Cached Sources Available” section built from the session manifest so downstream agents know which evidence is already on disk.

---

## Quality Gate (quality-gate.json)

### Overview

**File**: `config/quality-gate.json`  
**Purpose**: Define the enforcement thresholds for mission completion  
**Affects**: Whether a mission can produce reports/artifacts

### Structure

```json
{
  "mode": "advisory",
  "thresholds": {
    "min_sources_per_claim": 2,
    "min_independent_sources": 2,
    "min_trust_score": 0.6,
    "min_claim_confidence": 0.6,
    "max_low_confidence_claims": 0
  },
  "recency": {
    "enforce": true,
    "max_source_age_days": 540,
    "allow_unparsed_dates": true
  },
  "trust_weights": {
    "peer_reviewed": 0.4,
    "academic": 0.35,
    "official": 0.35,
    "high": 0.3,
    "medium": 0.2,
    "news": 0.18,
    "trade_publication": 0.15,
    "blog": 0.1,
    "low": 0.05,
    "unknown": 0.05
  },
  "default_trust_weight": 0.1,
  "reporting": {
    "output_filename": "artifacts/quality-gate.json",
    "summary_filename": "artifacts/quality-gate-summary.json",
    "banner_title": "Quality Issues Detected",
    "banner_severity": "warning"
  }
}
```

**Key options**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `mode` | string | `advisory` | `advisory` completes the mission with warnings; `enforce` blocks finalization |
| `thresholds.min_sources_per_claim` | integer | `2` | Minimum number of sources per claim |
| `thresholds.min_independent_sources` | integer | `2` | Minimum unique domains per claim |
| `thresholds.min_trust_score` | float | `0.6` | Minimum sum of trust weights for a claim |
| `thresholds.min_claim_confidence` | float | `0.6` | Lowest confidence allowed before flagging |
| `thresholds.max_low_confidence_claims` | integer | `0` | Permitted claims below confidence threshold |
| `recency.enforce` | boolean | `true` | Require at least one fresh source per claim |
| `recency.max_source_age_days` | integer | `540` | Maximum age (in days) for considered fresh |
| `recency.allow_unparsed_dates` | boolean | `true` | If `false`, missing/ambiguous dates fail the gate |
| `trust_weights` | object | see above | Weights applied per `sources[].credibility` label |
| `default_trust_weight` | float | `0.1` | Weight applied when credibility is missing |
| `reporting.output_filename` | string | `artifacts/quality-gate.json` | Full diagnostic report written after each run |
| `reporting.summary_filename` | string | `artifacts/quality-gate-summary.json` | Compact summary consumed by the orchestrator and dashboards |
| `reporting.banner_title` | string | `"Quality Issues Detected"` | Heading used when warnings are rendered in final reports |
| `reporting.banner_severity` | string | `"warning"` | Severity hint for consumers (e.g., dashboards) |

**Customizing**:

- Create `~/.config/cconductor/quality-gate.json` to override defaults.
- Lower `min_trust_score` for exploratory missions that rely on less authoritative sources.
- Increase `max_source_age_days` for historical research.
- Add new trust labels (e.g., `"regulatory": 0.4`) to match your source taxonomy.
- Switch `mode` to `enforce` when you want research runs to stop until every threshold passes.

**Failure handling**:

- In `advisory` mode the mission completes, the session status becomes `completed_with_advisory`, and the report includes a prominent warning banner plus remediation guidance.
- In `enforce` mode the orchestrator marks the mission `blocked_quality_gate` and stops finalization.
- Detailed findings live in `artifacts/quality-gate.json` (full report) and `artifacts/quality-gate-summary.json` (compact summary).
- Fix the flagged issues (add sources, resolve contradictions, refresh stale evidence) and rerun or resume the session to re-check quality.

### Quality Gate Output Schema (v0.4.0+)

The quality gate emits structured confidence surfaces for each claim in `artifacts/quality-gate.json`:

```json
{
  "status": "passed",
  "mode": "advisory",
  "evaluated_at": "2024-10-25T10:30:00Z",
  "summary": {
    "total_claims": 50,
    "failed_claims": 3,
    "low_confidence_claims": 2,
    "unresolved_contradictions": 0,
    "average_trust_score": 0.82
  },
  "claim_results": [
    {
      "id": "c0",
      "statement": "Market valued at $50B in 2024",
      "agent_confidence": 0.85,
      "confidence_surface": {
        "source_count": 3,
        "independent_source_count": 2,
        "trust_score": 0.72,
        "newest_source_age_days": 45,
        "oldest_source_age_days": 120,
        "parseable_dates": 3,
        "unparsed_dates": 0,
        "limitation_flags": [],
        "last_reviewed_at": "2024-10-25T10:30:00Z",
        "status": "passed"
      }
    },
    {
      "id": "c12",
      "statement": "Policy implemented in 2020",
      "agent_confidence": 0.90,
      "confidence_surface": {
        "source_count": 1,
        "independent_source_count": 1,
        "trust_score": 0.45,
        "newest_source_age_days": 410,
        "oldest_source_age_days": 410,
        "parseable_dates": 1,
        "unparsed_dates": 0,
        "limitation_flags": [
          "Insufficient sources: require at least 2, found 1",
          "Not enough independent sources: require 2 unique domains, found 1"
        ],
        "last_reviewed_at": "2024-10-25T10:30:00Z",
        "status": "flagged"
      }
    }
  ]
}
```

**Field Descriptions**:

| Field | Type | Description |
|-------|------|-------------|
| `agent_confidence` | float | Agent's subjective belief in claim validity (0-1) |
| `confidence_surface.source_count` | int | Total number of sources supporting claim |
| `confidence_surface.independent_source_count` | int | Number of unique domains (independence check) |
| `confidence_surface.trust_score` | float | Computed trust score from source credibility weights (0-1) |
| `confidence_surface.newest_source_age_days` | int/null | Age of most recent source in days |
| `confidence_surface.oldest_source_age_days` | int/null | Age of oldest source in days |
| `confidence_surface.parseable_dates` | int | Number of sources with valid publication dates |
| `confidence_surface.unparsed_dates` | int | Number of sources with missing/invalid dates |
| `confidence_surface.limitation_flags` | array | Human-readable issues found during assessment |
| `confidence_surface.last_reviewed_at` | string | ISO 8601 timestamp of assessment |
| `confidence_surface.status` | string | "passed" or "flagged" |

**Usage**:
- Synthesis agent reads this data to include "Confidence & Limitations" section in reports
- Render fallback uses summary to generate table if synthesis omits the section
- Optional KG integration can store `confidence_surface` as `quality_gate_assessment` field in claims

---

## Paths Configuration (paths.json)

### Overview

**File**: `config/paths.json`  
**Purpose**: Configure all directory paths  
**Affects**: Where CConductor stores data and looks for inputs

### Structure

```json
{
  "sessions": "../research-sessions",
  "logs": "../logs",
  "pdfs": "../pdfs",
  "knowledge_base": "../knowledge-base",
  "knowledge_base_custom": "../knowledge-base-custom",
  "agents_dir": "../src/claude-runtime/agents",
  "hooks_dir": "../src/claude-runtime/hooks"
}
```

**All paths are relative to the `config/` directory.**

**Options**:

| Path | Default | Purpose |
|------|---------|---------|
| `sessions` | `../research-sessions` | Research session output |
| `logs` | `../logs` | Log files |
| `pdfs` | `../pdfs` | PDFs for analysis |
| `knowledge_base` | `../knowledge-base` | Built-in knowledge |
| `knowledge_base_custom` | `../knowledge-base-custom` | Your knowledge |
| `agents_dir` | `../src/claude-runtime/agents` | Agent definition templates |
| `hooks_dir` | `../src/claude-runtime/hooks` | Hook script templates |

**When to customize**:

- Moving data to different drive
- Network storage
- Shared team directories
- Docker volume mappings

**Example custom paths**:

```json
{
  "sessions": "/mnt/research-data/sessions",
  "logs": "/var/log/cconductor",
  "pdfs": "/shared/papers",
  "knowledge_base": "../knowledge-base",
  "knowledge_base_custom": "/company/cconductor-knowledge",
  "agents_dir": "../src/claude-runtime/agents",
  "hooks_dir": "../src/claude-runtime/hooks"
}
```

---

## MCP Servers (mcp-servers.json)

### Overview

**File**: `config/mcp-servers.json`  
**Purpose**: Configure Model Context Protocol (MCP) server integrations  
**Affects**: External tool integrations (Zapier, Evernote, etc.)

### Structure

```json
{
  "mcpServers": {
    "zapier": {
      "command": "node",
      "args": [...],
      "env": {
        "ZAPIER_API_KEY": "your-key-here"
      }
    }
  }
}
```

**Typical integrations**:

- Zapier (automation)
- Evernote (note-taking)
- Slack (notifications)
- Affinity (CRM)

**Setup**: See individual MCP server documentation for configuration.

---

## Configuration Patterns

### The Git-Safe Customization Pattern

**Always use this pattern**:

1. **Never edit `.default.json` files** in `PROJECT_ROOT/config/` - these are tracked in git
2. **Create user configs** in `~/.config/cconductor/` using `./src/utils/config-loader.sh init <config-name>`
3. **Edit user configs** in `~/.config/cconductor/` - these are in your home directory, never touched by git
4. **Reset anytime**: Delete `~/.config/cconductor/config-name.json` to revert to defaults

**Result**:

- Zero merge conflicts on git pull
- Configs survive project deletion/reinstallation
- Each user can have their own settings
- Smooth upgrades every time

---

### Environment Variable Overrides

**Some configs support environment variables**:

```bash
# Override security profile
export CCONDUCTOR_SECURITY_PROFILE=permissive
./cconductor "research question"

# Override mode
export RESEARCH_MODE=scientific
./cconductor "research question"

# Override log level
export LOG_LEVEL=debug
./cconductor "research question"
```

**Supported variables**:

- `CCONDUCTOR_SECURITY_PROFILE` - Security profile
- `RESEARCH_MODE` - Research mode
- `LOG_LEVEL` - Logging level
- `MAX_PARALLEL_AGENTS` - Agent parallelism

---

### Per-Session Overrides

**Create session-specific config** (coming in v0.2):

```bash
# Will be: ./cconductor "question" --config custom-config.json
```

**Current workaround**: Modify main config before running, restore after.

---

## Advanced Topics

### Configuration Validation

**Check config syntax**:

```bash
jq empty config/cconductor-config.json
# No output = valid JSON
# Error message = fix syntax
```

**Validate all configs**:

```bash
for f in config/*.json; do 
  echo "Checking $f..."
  jq empty "$f" || echo "ERROR in $f"
done
```

---

### Configuration Backup

**Backup your customizations**:

```bash
# Backup all your configs
mkdir -p backups/$(date +%Y%m%d)
cp config/*.json backups/$(date +%Y%m%d)/

# Or just your customizations
cp config/cconductor-config.json config/cconductor-config.backup
cp config/security-config.json config/security-config.backup
```

**Recommended**: Keep backups before major upgrades.

---

### Version Tracking

**Config files include version**:

```json
{
  "version": "0.1.0",
  ...
}
```

**Check version**:

```bash
jq .version config/cconductor-config.json
```

**Version compatibility**: CConductor checks config versions and migrates if needed.

---

### Configuration Debugging

**See active configuration**:

```bash
./cconductor configure
# Shows current settings (planned for v0.2)
```

**Current workaround - check config manually**:

```bash
jq . config/cconductor-config.json
```

**See what security profile is active**:

```bash
jq .security_profile config/security-config.json
```

**See what research mode will be used**:

```bash
jq '.mode_selection.default_mode' config/cconductor-modes.json
```

---

### Configuration Templates

**For teams**: Create template configs for common scenarios:

**Academic template**:

```json
{
  "research": {
    "min_source_credibility": "high",
    "min_sources_per_claim": 5
  },
  "research_modes": {
    "scientific": {
      "min_peer_reviewed_sources": 10
    }
  }
}
```

**Business template**:

```json
{
  "research_modes": {
    "business_market": {
      "min_competitors_analyzed": 10
    }
  }
}
```

**Fast prototype template**:

```json
{
  "research": {
    "max_web_searches": 3,
    "sources_per_search": 5,
    "min_sources_per_claim": 2
  }
}
```

---

## See Also

- **[User Guide](USER_GUIDE.md)** - How to use CConductor
- **[Security Guide](SECURITY_GUIDE.md)** - Security configuration details
- **[Custom Knowledge](CUSTOM_KNOWLEDGE.md)** - Adding domain knowledge
- **[Quality Guide](QUALITY_GUIDE.md)** - Quality scoring configuration

---

**CConductor Configuration** - Fine-tune your research ⚙️
