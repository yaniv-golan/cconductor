# Research Data Sources

This document describes the research data sources available to CConductor agents, including MCP servers and direct API endpoints.

## Academic Sources

### arXiv (MCP Server)

**Type**: MCP Server via Python uv  
**Command**: `uv tool install arxiv-mcp-server` (Python package)  
**Description**: Search arXiv preprints for scientific papers  
**Usage**: Physics, CS, math, and STEM papers  
**Returns**: PDF URLs for caching  
**Setup**: Install with uv: `uv tool install arxiv-mcp-server`
**Source**: https://github.com/blazickjp/arxiv-mcp-server

### Semantic Scholar (Direct API)

**Type**: REST API  
**Base URL**: <https://api.semanticscholar.org/graph/v1>  
**Description**: Academic papers with citations, influence scores, paper details  
**API Key**: Not required (rate limited)  
**Rate Limit**: 100 requests/5 minutes (unauthenticated)  
**Usage**: Cross-disciplinary search and citation analysis

**API Endpoints**:

```bash
# Search papers
GET /paper/search?query={query}&fields=title,authors,year,abstract,citationCount,openAccessPdf

# Get paper by ID
GET /paper/{paper_id}?fields=title,authors,year,abstract,citations,references,openAccessPdf

# Example
curl 'https://api.semanticscholar.org/graph/v1/paper/search?query=attention+is+all+you+need&fields=openAccessPdf'
```

### PubMed (Direct API)

**Type**: REST API (NCBI E-utilities)  
**Base URL**: <https://eutils.ncbi.nlm.nih.gov/entrez/eutils>  
**Description**: Biomedical literature from PubMed/PMC  
**API Key**: Optional (NCBI_API_KEY env var)  
**Rate Limit**: 3 req/s (no key), 10 req/s (with key)  
**Usage**: Medical, biology, health sciences research

**API Endpoints**:

```bash
# Search PubMed
GET /esearch.fcgi?db=pubmed&term={query}&retmax=20&retmode=json

# Fetch article details
GET /efetch.fcgi?db=pubmed&id={pmid}&retmode=xml

# Check for PMC full-text
GET /elink.fcgi?dbfrom=pubmed&id={pmid}&linkname=pubmed_pmc&retmode=json
```

**API Key Setup**: Register at <https://ncbiinsights.ncbi.nlm.nih.gov/2017/11/02/new-api-keys-for-the-e-utilities/>

### Crossref (Direct API)

**Type**: REST API  
**Base URL**: <https://api.crossref.org>  
**Description**: DOI resolution and citation metadata  
**API Key**: Not required  
**Etiquette**: Include email in User-Agent header for polite pool access  
**Usage**: Resolving DOIs, finding papers, checking citations

**API Endpoints**:

```bash
# Look up by DOI
GET /works/{doi}

# Search works
GET /works?query={query}&rows=20
```

## Market/Business Sources

### SEC EDGAR (Direct API)

**Type**: REST API  
**Base URL**: <https://data.sec.gov>  
**Description**: SEC filings and public company data  
**API Key**: Not required  
**Rate Limit**: 10 requests/second  
**Usage**: 10-K, 10-Q, 8-K filings  
**Requirement**: User-Agent header required

### Crunchbase (Direct API)

**Type**: REST API (Paid)  
**API Key**: Required (CRUNCHBASE_API_KEY)  
**Description**: Company and funding data  
**Usage**: Startup funding, acquisitions, people data  
**Setup**: Requires paid subscription at <https://www.crunchbase.com/products/api>

## Agent Integration Patterns

### For academic-researcher Agent

1. Use WebSearch to find papers and identify PDF URLs
2. For arXiv papers: Extract arXiv ID → construct PDF URL (<https://arxiv.org/pdf/XXXX.XXXXX.pdf>)
3. For PMIDs: Use PubMed API to check for free full-text via PMC
4. For DOIs: Use Crossref API to get metadata → search for open access PDFs
5. Pass all PDF URLs to pdf-reader.sh prepare command for caching
6. Use Read tool on cached PDFs for full-text analysis

### For pdf-analyzer Agent

- Receives already-cached PDF paths from academic-researcher
- Focuses on structure extraction and content analysis
- Does not handle fetching or caching

### For synthesis-agent

- Receives structured analysis from pdf-analyzer and academic-researcher
- Synthesizes findings across multiple papers
- Can request additional PDF analysis if needed

## How Agents Use MCP Servers

**Automatic Discovery**: MCP server tools are automatically available to agents when configured via `.mcp.json`. Agents will discover and use them based on task requirements without needing explicit instructions.

**Tool Selection**: Agents autonomously decide when to use MCP tools vs. other methods (WebSearch, WebFetch). MCP tools are typically preferred for their specific domains due to:
- More reliable access (no rate limits/Cloudflare blocking)
- Structured data extraction
- Better error handling
- Direct API access vs. web scraping

**No Explicit Instructions Needed**: You don't need to mention MCP servers in your research queries - agents will use them when appropriate for the task at hand.

**Example**: With `arxiv-mcp-server` configured, the academic-researcher agent will automatically use `mcp__arxiv__search_papers` when searching for academic papers, while also using WebSearch for broader discovery across multiple platforms.

## Adding MCP Servers (Easy Method - Recommended)

The easiest way to add MCP servers is with the `claude mcp` CLI:

### Quick Add to All Sessions (User Scope)

```bash
# Add popular servers for all research sessions
claude mcp add --scope user --transport http github https://api.githubcopilot.com/mcp/
claude mcp add --scope user --transport http notion https://mcp.notion.com/mcp
claude mcp add --scope user --transport sse linear https://mcp.linear.app/sse
```

### Add to Current Session Only

```bash
# Navigate to your research session first
cd research-sessions/your-session-dir/

# Add servers just for this session
claude mcp add --transport stdio arxiv -- npx -y arxiv-mcp-server
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
```

### Manage Your Servers

```bash
# List all configured servers
claude mcp list

# Remove a server
claude mcp remove arxiv

# Get server details
claude mcp get github
```

### Popular MCP Servers

See the [Claude Code MCP Catalog](https://docs.claude.com/en/docs/claude-code/mcp#popular-mcp-servers) for dozens of pre-built servers:

**Development & Testing**:
- `sentry` - Error monitoring and debugging
- `socket` - Dependency security analysis
- `jam` - Debug recordings with console logs

**Project Management**:
- `github` - Issues, PRs, code reviews
- `linear` - Issue tracking
- `atlassian` - Jira tickets and Confluence docs
- `notion` - Documentation and notes

**Databases**:
- `postgres` - Database queries
- `airtable` - Spreadsheet database
- `hubspot` - CRM data

**Design & Media**:
- `figma` - Design context for code generation
- `canva` - Design generation

**Payments**:
- `stripe` - Payment processing
- `paypal` - Commerce capabilities

## Adding MCP Servers (Manual JSON Method)

If you prefer manual configuration or need advanced options, you can edit JSON files directly.

### Session-Specific Servers

Edit `.mcp.json` in the session directory:

```json
{
  "mcpServers": {
    "arxiv": {
      "command": "npx",
      "args": ["-y", "arxiv-mcp-server"],
      "type": "stdio"
    },
    "your-mcp-server": {
      "type": "http",
      "url": "https://your-server.com/mcp"
    }
  }
}
```

### User-Wide Servers

Create or edit `~/.claude/mcp.json`:

```json
{
  "mcpServers": {
    "github": {
      "type": "sse",
      "url": "https://api.githubcopilot.com/mcp/sse"
    },
    "notion": {
      "type": "http",
      "url": "https://mcp.notion.com/mcp"
    }
  }
}
```

### Secure API Keys with Environment Variables

Use `${VAR}` syntax to keep secrets out of config files:

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": {
        "Authorization": "Bearer ${GITHUB_TOKEN}"
      }
    },
    "custom-tool": {
      "type": "stdio",
      "command": "${HOME}/bin/my-tool",
      "args": ["--api-key", "${MY_TOOL_API_KEY}"],
      "env": {
        "CACHE_DIR": "${XDG_CACHE_HOME}/cache"
      }
    }
  }
}
```

Set environment variables in your shell:

```bash
export GITHUB_TOKEN="ghp_your_token_here"
export MY_TOOL_API_KEY="key_xyz..."
```

This approach keeps sensitive data secure and allows different values per environment.

## Advanced MCP Features

### Using MCP Resources (@mentions)

If your MCP servers expose resources, reference them with @ mentions:

```bash
# Analyze a GitHub issue
./cconductor "Analyze @github:issue://123 and suggest an implementation approach"

# Compare database schema with documentation
./cconductor "Compare @postgres:schema://users with our data model docs"

# Reference design files
./cconductor "Generate code from @figma:file://abc123"
```

Type `@` in Claude Code to see available resources from all configured servers.

### Using MCP Prompts (Slash Commands)

MCP servers can provide custom slash commands. When using CConductor in interactive mode, you can use these commands:

```bash
# List issues from Jira
/mcp__jira__list_issues

# Create GitHub PR
/mcp__github__create_pr "Fix authentication bug"

# Query database
/mcp__postgres__run_query "SELECT * FROM users LIMIT 10"
```

Type `/` in Claude Code to see available MCP commands from your configured servers.

---

## Claude Code Plugins Compatibility

CConductor is **fully compatible** with [Claude Code plugins](https://docs.claude.com/en/docs/claude-code/plugins). Any plugins you install via `/plugin install` will automatically be available in CConductor research sessions.

### Why Use Plugins with CConductor?

Plugins extend Claude Code with additional tools, commands, and integrations that enhance research capabilities:

- **Data Sources**: GitHub, Notion, PostgreSQL, Airtable
- **Development Tools**: Sentry, Socket, Jam
- **Documentation**: Confluence, Notion, Box
- **Business Tools**: HubSpot, Stripe, Plaid

### How to Use Plugins

**Install plugins globally** (available to all sessions):

```bash
# Add a marketplace
/plugin marketplace add your-org/plugins

# Install specific plugins
/plugin install github@your-org
/plugin install notion@your-org

# Browse available plugins
/plugin
```

**Use in CConductor** (plugins work automatically):

```bash
# Plugins are available in research sessions
./cconductor "Analyze GitHub issues for Claude Code bugs"
./cconductor "Summarize our Notion docs about product strategy"
```

### Recommended Plugins for Research

**Development & Code Analysis**:
- `github` - Access issues, PRs, and code
- `sentry` - Error monitoring and debugging
- `socket` - Dependency security analysis

**Documentation & Knowledge**:
- `notion` - Company documentation
- `atlassian` - Jira tickets and Confluence
- `box` - Enterprise content

**Data & Business**:
- `stripe` - Payment and transaction data
- `hubspot` - CRM data
- `airtable` - Structured data

See the [Claude Code Plugin Catalog](https://docs.claude.com/en/docs/claude-code/mcp#popular-mcp-servers) for dozens more.

### Architecture Note

CConductor and plugins serve different purposes:
- **CConductor**: Orchestrates multi-agent research workflows
- **Plugins**: Provide tools and data sources

They work together: CConductor orchestrates research, plugins provide the data sources and tools that agents use during research.

