# PDF Research Guide

## Overview

CConductor has comprehensive PDF support for academic research, enabling full-text analysis of scientific papers with automatic caching and source tracking.

**Two Ways to Use PDFs**:

1. **Downloaded PDFs** - CConductor automatically downloads and caches PDFs from web/academic sources during research
2. **Local PDFs** - Provide your own PDF files using `--input-dir` flag (v0.1.0+)

## Local PDF Files (User-Provided)

### Quick Start

```bash
# Analyze your own PDFs alongside web research
./cconductor "Research question" --input-dir /path/to/your/files/
```

### How It Works

When you provide local files with `--input-dir`:

1. **File Discovery**: CConductor scans the directory for supported files
   - PDFs (`.pdf`) - Analyzed with Read tool
   - Markdown (`.md`) - Loaded into session context
   - Text (`.txt`) - Loaded into session context

2. **Content-Based Caching**: PDFs are cached by content hash (SHA-256)
   - Same content = same cache entry (automatic deduplication)
   - Different files with identical content reuse cache
   - Version tracking (content change = new cache entry)

3. **Session Manifest**: Track all input files in `input-files.json`

   ```json
   {
     "input_dir": "/path/to/files",
     "pdfs": [
       {
         "original_name": "pitch-deck.pdf",
         "sha256": "abc123...",
         "cached_path": "~/Library/Caches/CConductor/pdfs/abc123.pdf",
         "source_type": "user_provided"
       }
     ],
     "markdown": [ ... ],
     "text": [ ... ]
   }
   ```

4. **Priority Analysis**: Research coordinator analyzes your files FIRST, then expands to web sources

### Use Cases

**VC Due Diligence**:

```bash
./cconductor "Evaluate this startup" --input-dir ./deals/acme/
# Include: pitch deck, financials, market research
```

**Academic Research with Your PDFs**:

```bash
./cconductor "Compare methodologies in these papers" --input-dir ./literature/
# Your collection of papers analyzed together
```

**Market Research with Reports**:

```bash
./cconductor "Market size analysis" --input-dir ./market-reports/
# Analyze proprietary reports + public research
```

### Local vs Downloaded PDFs

| Feature | Local PDFs (`--input-dir`) | Downloaded PDFs (automatic) |
|---------|---------------------------|----------------------------|
| **Cache Key** | Content hash (SHA-256) | URL hash |
| **Deduplication** | By content | By URL |
| **Source** | `source: "local"` | `source: "download"` |
| **Manifest** | `input-files.json` | Standard session tracking |
| **Priority** | Analyzed FIRST | Standard priority |
| **Version Tracking** | Hash change = new version | Same URL = same file |

### File Organization

**Single directory, flat structure** (no recursion):

```
your-files/
├── document1.pdf          ✅ Processed
├── notes.md               ✅ Processed
├── context.txt            ✅ Processed
├── image.jpg              ⚠️  Skipped (unsupported)
└── subfolder/
    └── nested.pdf         ❌ Not discovered (no recursion)
```

**Tip**: Place all files in one directory for discovery.

## Downloaded PDFs (Automatic)

### 1. PDF Caching System

**Locations** (OS-appropriate):

- **macOS**: `~/Library/Caches/CConductor/pdfs/`
- **Linux**: `~/.cache/cconductor/pdfs/`

**Features**:

- SHA-256 hashing for unique identification
- Source URL preservation in metadata
- Automatic deduplication (same PDF from different URLs)
- Cache index with searchable metadata
- No redundant downloads
- Thread-safe with file locking for concurrent access
- Automatic integrity verification

**Cache Structure**:

```
~/Library/Caches/CConductor/pdfs/       # or ~/.cache/cconductor/pdfs/ on Linux
├── cache-index.json              # Master index
├── metadata/                     # Individual metadata files
│   ├── {hash}.json
│   └── ...
└── {hash}.pdf                    # Cached PDFs
```

**Metadata Format**:

```json
{
  "url": "https://arxiv.org/pdf/2401.12345.pdf",
  "title": "Paper Title",
  "source": "arXiv",
  "cache_key": "abc123...",
  "cached_at": "2024-01-15T10:30:00Z",
  "file_size": 2457600,
  "file_path": "/Users/you/Library/Caches/CConductor/pdfs/abc123....pdf",
  "sha256": "def456..."
}
```

### 2. Full PDF Reading with Claude

The system uses Claude's native Read tool for optimal PDF processing:

**Capabilities**:

- Page-by-page text extraction
- Visual content analysis (figures, tables, equations)
- Document structure recognition (sections, headings)
- Caption extraction
- Table data extraction
- Mathematical notation understanding

**Example**:

```bash
# Fetch and cache PDF
bash src/utils/pdf-reader.sh prepare \
  "https://arxiv.org/pdf/2401.12345.pdf" \
  "Attention Is All You Need" \
  "arXiv"

# Returns cached path for Claude's Read tool
```

### 3. Academic Research Agents

#### academic-researcher Agent

**PDF-Centric Workflow**:

1. Search for papers (WebSearch, academic APIs)
2. Extract PDF URLs (arXiv, PubMed Central, open access)
3. Fetch and cache PDFs (using pdf-reader.sh)
4. Read full PDFs (using Read tool)
5. Extract comprehensive information:
   - Full abstract and introduction
   - Detailed methodology
   - Results with statistical support
   - Figures and tables analysis
   - Limitations and future work
   - Complete reference list

**Output Includes**:

- `cached_pdf_path`: Local path to PDF
- `pdf_url`: Original source URL
- Full content analysis
- Quality assessment

#### pdf-analyzer Agent

**Specialization**: Deep document structure analysis

**Capabilities**:

- Extract paper structure (Abstract, Methods, Results, etc.)
- Analyze all figures and tables
- Extract key statistics and effect sizes
- Identify methodology details
- Assess reproducibility
- Extract citation network

**Use Case**: When you need detailed extraction from already-cached PDFs

### 4. Academic Database Integration

**Enabled Sources** (No API keys required):

| Source | Type | Coverage | PDF Access |
|--------|------|----------|------------|
| **arXiv** | Preprints | Physics, CS, Math, Stats | Direct PDF links |
| **Semantic Scholar** | API | Cross-disciplinary | OpenAccessPdf field |
| **PubMed** | API | Biomedical | Via PubMed Central |
| **Crossref** | API | DOI resolution | Links to publishers |
| **SEC EDGAR** | API | Financial filings | PDF reports |

**API Usage Examples**:

```bash
# Semantic Scholar - Find open access PDFs
curl 'https://api.semanticscholar.org/graph/v1/paper/search?query=transformer+attention&fields=title,authors,year,openAccessPdf'

# PubMed - Search and get PMIDs
curl 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=CRISPR&retmode=json'

# Crossref - Resolve DOI
curl 'https://api.crossref.org/works/10.1038/nature12345'
```

## Usage

### Basic Scientific Research

```bash
# Standard scientific research (uses PDFs automatically)
./cconductor "Recent advances in quantum computing"
```

**What happens**:

1. Searches for relevant papers across databases
2. Identifies and downloads PDFs (cached for reuse)
3. Reads full PDFs with Claude's Read tool
4. Extracts methodology, results, figures
5. Synthesizes findings across papers
6. Validates claims
7. Outputs scientific report

### Comprehensive Literature Review

```bash
# Full literature review with systematic analysis
./cconductor "Transformer architectures in NLP"
```

**What happens**:

1. Systematic search across multiple databases
2. Downloads 20+ papers (configurable)
3. Full PDF analysis for each paper
4. Citation network analysis
5. Temporal trend analysis
6. Methodology comparison
7. Identifies research gaps
8. Outputs comprehensive literature review

**Output Format**:

- Abstract
- Search Methodology
- Literature Overview (with timeline)
- Thematic Analysis
- Methodological Comparison
- Key Findings Synthesis
- Temporal Trends
- Citation Network Analysis
- Research Gaps
- Limitations of Current Literature
- Future Research Directions
- Complete References

### Check PDF Cache Status

```bash
# View cache statistics
bash src/utils/pdf-cache.sh stats

# List all cached PDFs
bash src/utils/pdf-cache.sh list

# Check if specific PDF is cached
bash src/utils/pdf-cache.sh check "https://arxiv.org/pdf/2401.12345.pdf"

# Get metadata for cached PDF
bash src/utils/pdf-cache.sh metadata "https://arxiv.org/pdf/2401.12345.pdf"

# Verify cache integrity
bash src/utils/pdf-cache.sh verify

# Remove duplicate entries
bash src/utils/pdf-cache.sh dedupe
```

### Cache Maintenance

```bash
# Verify and repair cache if needed
bash src/utils/pdf-cache.sh verify || bash src/utils/pdf-cache.sh repair

# Rebuild cache index
bash src/utils/pdf-cache.sh rebuild

# Clear entire PDF cache
bash src/utils/pdf-cache.sh clear yes
```

## Research Modes

### Scientific Mode

**Best for**: Individual research questions, exploring specific topics

**Configuration** (`config/cconductor-modes.json`):

```json
{
  "pdf_centric": true,
  "min_papers": 10,
  "min_peer_reviewed_sources": 5,
  "max_preprint_reliance": 0.3
}
```

**Output**: Scientific report with peer review assessment

### Literature Review Mode

**Best for**: Comprehensive reviews, systematic analysis, academic papers

**Configuration**:

```json
{
  "pdf_centric": true,
  "min_papers": 20,
  "min_peer_reviewed_sources": 15,
  "systematic_search": true,
  "track_citation_network": true
}
```

**Output**: Full literature review with all academic sections

## Quality Assurance

### Peer Review Priority

**Automatic Prioritization**:

1. Peer-reviewed journal articles (highest)
2. Peer-reviewed conference papers
3. Preprints from reputable servers (arXiv, bioRxiv)
4. Technical reports
5. Non-peer-reviewed sources (lowest)

**Quality Checks**:

- Journal impact factor verification
- Retraction checking (Retraction Watch)
- Methodology assessment (sample size, controls, statistical rigor)
- Author credentials and affiliations
- Conflicts of interest disclosure

### PDF Quality Indicators

The system assesses:

- **Clarity**: Writing quality, structure
- **Completeness**: All sections present, sufficient detail
- **Reproducibility**: Code/data availability, methodology detail
- **Evidence Quality**: Statistical rigor, sample size adequacy

**Quality Rating**: 1-5 scale (automatically assigned)

## Advanced Features

### Citation Network Analysis

Automatically tracks:

- Papers cited by your sources
- Papers citing your sources
- Seminal papers (highly cited, older)
- Recent impactful papers (recent, high citations)
- Citation clusters (related research streams)

**Source**: Semantic Scholar API (citation counts and references)

### Temporal Trend Analysis

Tracks evolution of understanding:

- Timeline of publications
- Methodology evolution
- Concept emergence
- Consensus formation
- Recent breakthroughs

### Methodological Comparison

Compares across papers:

- Study designs (RCT, cohort, case-control, etc.)
- Sample sizes
- Statistical methods
- Control conditions
- Reproducibility artifacts

## Tips for Best Results

### 1. Research Question Formulation

**Good**: "What are the mechanisms by which transformer attention enables long-range dependencies?"

**Better**: "How do transformer attention mechanisms compare to RNN architectures for modeling long-range dependencies in NLP tasks?"

**Rationale**: Specific, comparative, defines scope

### 2. Timeframe Specification

Include timeframe for rapidly-evolving fields:

```bash
./cconductor "Recent advances (2023-2024) in large language model efficiency"
```

### 3. Scope Definition

For broad topics, specify scope:

```bash
# Too broad
"Machine learning in healthcare"

# Better
"Machine learning for early cancer detection in radiology imaging"
```

### 4. Mode Selection

- **New to topic?** Use `scientific` mode (faster, 10-15 papers)
- **Writing a paper?** Use `literature_review` mode (comprehensive, 20+ papers)
- **Quick check?** Use `default` mode (web sources, no full PDF analysis)

## PDF-Specific Settings

### Environment Variables

```bash
# Custom cache location
export PDF_CACHE_DIR="$HOME/my-research/pdfs"

# Default research mode
export RESEARCH_MODE="literature_review"

# Increase PDF analysis depth
export PDF_DEEP_ANALYSIS=true
```

### Configuration Files

**cconductor-modes.json**: Customize paper counts, quality thresholds

**cconductor-config.json**: Main research settings

**mcp-servers.json**: Add API keys for rate limit increases

## API Rate Limits

| Service | Free Tier | With API Key |
|---------|-----------|--------------|
| Semantic Scholar | 100 req/5min | Same (no paid tier) |
| PubMed | 3 req/sec | 10 req/sec |
| Crossref | No limit | No limit (polite pool) |
| arXiv | No limit | N/A |

**Note**: The system automatically respects rate limits and retries on failure.

## Troubleshooting

### PDF Download Fails

**Symptoms**: "Failed to download PDF" error

**Common Causes**:

1. PDF URL is not accessible (404, authentication required)
2. PDF is behind paywall or requires login
3. Network connection issues
4. File size exceeds 100MB limit
5. Server timeout (>60 seconds)
6. Insufficient disk space (<200MB free)

**Solutions**:

```bash
# Check if URL is accessible
curl -I "https://arxiv.org/pdf/1706.03762.pdf"

# Check disk space
df -h ~/Library/Caches/CConductor/pdfs/

# Try with verbose output
bash -x src/utils/pdf-cache.sh fetch "URL" "Title" "Source"
```

**Note**: System will note failed downloads and continue with available papers

### Cache Corruption

**Symptoms**:

- "Could not acquire cache lock" errors
- JSON parse errors in cache-index.json
- Missing PDFs that should be cached

**Solutions**:

```bash
# Check for stale locks
ls ~/Library/Caches/CConductor/pdfs/.cache-index.lock
# If exists and no process running, remove it:
rm -rf ~/Library/Caches/CConductor/pdfs/.cache-index.lock

# Verify cache integrity
bash src/utils/pdf-cache.sh verify

# If issues found, repair automatically
bash src/utils/pdf-cache.sh repair

# Or rebuild from scratch
bash src/utils/pdf-cache.sh rebuild
```

### Duplicate Entries

**Symptoms**: Same PDF listed multiple times in cache

**Solution**:

```bash
# Remove duplicates (keeps most recent)
bash src/utils/pdf-cache.sh dedupe

# Verify cleanup worked
bash src/utils/pdf-cache.sh verify
```

### Concurrent Access Issues

**Symptoms**: Research sessions interfere with each other

**Note**: This should not happen with the new locking mechanism. If it does:

```bash
# Check for orphaned locks
ls ~/Library/Caches/CConductor/pdfs/.cache-index.lock

# Remove stale lock (only if no sessions running)
rm -rf ~/Library/Caches/CConductor/pdfs/.cache-index.lock

# Repair cache
bash src/utils/pdf-cache.sh repair
```

### PDF Parsing Issues

**Symptoms**: Garbled text, missing content

**Causes**:

- Scanned images (not text PDFs)
- Complex layouts
- Non-standard encodings
- Corrupted PDF file

**Solutions**:

```bash
# Verify PDF integrity
bash src/utils/pdf-cache.sh verify

# Check if PDF is valid
file ~/Library/Caches/CConductor/pdfs/{hash}.pdf

# Re-download if corrupted
bash src/utils/pdf-cache.sh check "URL"  # Get cache key
rm ~/Library/Caches/CConductor/pdfs/{hash}.pdf
bash src/utils/pdf-cache.sh fetch "URL" "Title" "Source"
```

**Note**: Claude's Read tool handles most formats; check if PDF is readable in standard viewer

### API Rate Limit Hit

**Symptoms**: "Rate limit exceeded" errors

**Solution**:

1. Wait (limits reset quickly)
2. Add API keys for higher limits (NCBI_API_KEY)
3. Reduce parallel requests (edit agent configs)

### Cache Growing Large

**Check size**:

```bash
# View cache statistics
bash src/utils/pdf-cache.sh stats

# Or check disk usage directly
du -sh ~/Library/Caches/CConductor/pdfs/
```

**Solutions**:

```bash
# Option 1: Clear entire cache
bash src/utils/pdf-cache.sh clear yes

# Option 2: Manually remove old PDFs
cd ~/Library/Caches/CConductor/pdfs/
# Find PDFs older than 90 days
find . -name "*.pdf" -mtime +90 -delete
# Then rebuild index
bash src/utils/pdf-cache.sh rebuild

# Option 3: Remove specific PDFs
# Find cache key first
bash src/utils/pdf-cache.sh check "URL"
# Then remove files
rm ~/Library/Caches/CConductor/pdfs/{hash}.pdf
rm ~/Library/Caches/CConductor/pdfs/metadata/{hash}.json
# Rebuild index
bash src/utils/pdf-cache.sh rebuild
```

### Performance Issues

**Symptoms**: Slow PDF downloads or cache operations

**Diagnosis**:

```bash
# Check network speed
time curl -o /dev/null https://arxiv.org/pdf/1706.03762.pdf

# Check disk I/O
time bash src/utils/pdf-cache.sh stats

# Check for lock contention (multiple sessions)
ps aux | grep cconductor
```

**Solutions**:

1. Check network connection
2. Ensure cache directory is on fast storage (not network drive)
3. Reduce concurrent research sessions
4. Consider clearing old cache entries to improve index performance

## Integration with Other Tools

### Export to Reference Manager

Cache metadata includes DOIs and URLs for easy import:

```bash
# Extract citations from cache
# macOS:
jq '.pdfs[] | {title: .title, url: .url, cached_at: .cached_at}' \
  ~/Library/Caches/CConductor/pdfs/cache-index.json
# Linux:
# jq '.pdfs[] | {title: .title, url: .url, cached_at: .cached_at}' \
#   ~/.cache/cconductor/pdfs/cache-index.json
```

### Use with Zotero/Mendeley

1. Run research with literature_review mode
2. Use `./cconductor latest` to find and view your report
3. References section includes full citations
4. Import PDFs from cache:
   - **macOS**: `~/Library/Caches/CConductor/pdfs/*.pdf`
   - **Linux**: `~/.cache/cconductor/pdfs/*.pdf`

### Custom Workflows

The PDF utilities are modular:

```bash
# Fetch PDFs in batch
cat papers.txt | while read url; do
  bash src/utils/pdf-cache.sh fetch "$url"
done

# Read all cached PDFs (use your OS-specific path)
# macOS:
for pdf in ~/Library/Caches/CConductor/pdfs/*.pdf; do
  echo "Analyzing: $pdf"
  # Use Claude Code Read tool
done
# Linux: for pdf in ~/.cache/cconductor/pdfs/*.pdf; do ...
```

## Performance

### Typical Research Times

| Mode | Papers | With PDFs | Time |
|------|--------|-----------|------|
| Scientific | 10-15 | Yes | 10-20 min |
| Literature Review | 20-30 | Yes | 30-60 min |
| Default | N/A | No | 5-10 min |

**Factors**:

- PDF download speeds
- PDF sizes (some are 50+ pages)
- Claude's Read tool processing time
- Number of parallel agents
- API rate limits

### Optimization Tips

1. **Use cache**: Re-running same queries is much faster
2. **Narrow scope**: Fewer papers = faster results
3. **Check cache first**: Use `pdf-cache.sh check` before research
4. **Parallel agents**: System runs multiple agents simultaneously

## Examples

### Example 1: Quick Scientific Research

```bash
./cconductor "How do mRNA vaccines work?"
```

**Output**: 10-15 peer-reviewed papers, full text analysis, methodology comparison, ~15 pages

### Example 2: Comprehensive Literature Review

```bash
./cconductor "CRISPR gene editing in human therapeutics"
```

**Output**: 20+ papers, citation network, temporal trends, research gaps, systematic review format, ~40 pages

### Example 3: Technical + Academic Hybrid

```bash
./cconductor "PostgreSQL MVCC implementation and academic research on multi-version concurrency control"
```

**System auto-detects**: Uses both technical research (docs, code) and academic research (papers)

## Future Enhancements

**Planned**:

- [ ] Visual citation network graphs
- [ ] Automatic figure extraction and compilation
- [ ] Statistical meta-analysis across papers
- [ ] LaTeX output format
- [ ] BibTeX export
- [ ] PDF annotation preservation
- [ ] Full-text search across cached PDFs
- [ ] Automatic paper recommendations based on citations

## Support

**Issues**: <https://github.com/yaniv-golan/cconductor/issues>

**Documentation**: See `docs/` directory

**Examples**: See `examples/` directory

---

*This guide covers PDF-specific features. For general usage, see README.md and USAGE.md.*
