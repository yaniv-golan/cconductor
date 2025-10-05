# Research Data Sources

This document describes the research data sources available to CConductor agents, including MCP servers and direct API endpoints.

## Academic Sources

### arXiv (MCP Server)

**Type**: MCP Server via npx  
**Command**: `npx -y @modelcontextprotocol/server-arxiv`  
**Description**: Search arXiv preprints for scientific papers  
**Usage**: Physics, CS, math, and STEM papers  
**Returns**: PDF URLs for caching  
**Setup**: No setup required (auto-installs via npx)

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

## Adding New MCP Servers to Sessions

To add MCP servers to a research session, edit `.mcp.json` in the session directory:

```json
{
  "mcpServers": {
    "arxiv": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-arxiv"],
      "type": "stdio"
    },
    "your-mcp-server": {
      "type": "http",
      "url": "https://your-server.com/mcp"
    }
  }
}
```

See [Claude Code MCP documentation](https://docs.claude.com/en/docs/claude-code/mcp) for available MCP servers.

## Adding User-Wide MCP Servers

To add MCP servers available to ALL sessions, create `~/.claude/mcp.json`:

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

These will be available in all Claude Code sessions, including CConductor research sessions.

