# CConductor Citations & Bibliography Guide

**Understanding and using CConductor's automatic citation system**

**Last Updated**: October 2025  
**For**: Academic users, students, researchers

---

## Table of Contents

1. [Introduction](#introduction)
2. [How Citations Work](#how-citations-work)
3. [Citations by Research Mode](#citations-by-research-mode)
4. [For Academic Use](#for-academic-use)
5. [Understanding Citation Coverage](#understanding-citation-coverage)
6. [Troubleshooting](#troubleshooting)
7. [Examples](#examples)

---

## Introduction

CConductor automatically tracks and cites all sources used during research. This guide explains how the citation system works and how to use it effectively.

**Who needs this**:

- Academic researchers writing papers
- Students working on assignments  
- Professionals who need to cite sources
- Anyone requiring traceable references

**What CConductor provides**:

- Automatic source tracking during research
- In-text citations with numbered references
- Complete bibliography at end of reports
- Source URLs and metadata
- Citation coverage metrics in quality scores

---

## How Citations Work

### Automatic Source Tracking

CConductor tracks every source accessed during research:

**What's tracked**:

- Web pages visited and analyzed
- Academic papers found and read
- PDF documents processed
- Code repositories examined
- Market data sources consulted

**How it's tracked**:

- Each source gets a unique reference number
- Claims are linked to their sources
- Multiple sources can support one claim
- All sources appear in bibliography

### In-Text Citations

Citations appear as numbered references in square brackets:

**Example in report**:

```markdown
Docker uses containerization to isolate applications [1]. The technology
was first released in 2013 [2] and quickly gained adoption due to its
efficiency and portability [3][4].
```

**What the numbers mean**:

- `[1]` = Reference #1 in bibliography
- `[2]` = Reference #2 in bibliography
- `[3][4]` = Multiple sources support this claim

### Bibliography

Every report ends with a complete bibliography:

**Example bibliography**:

```markdown
## References

[1] Docker Inc. (2024). "What is Docker? An overview of containerization."
    Docker Documentation. Retrieved from https://docs.docker.com/get-started/

[2] Merkel, D. (2014). "Docker: lightweight Linux containers for consistent
    development and deployment." Linux Journal, 2014(239), 2.

[3] Turnbull, J. (2014). "The Docker Book: Containerization is the new
    virtualization." James Turnbull.

[4] Stack Overflow. (2023). "Developer Survey Results: Container Usage."
    Retrieved from https://survey.stackoverflow.co/2023/
```

**Bibliography includes**:

- Author (when available)
- Date/Year
- Title
- Publication/Source
- URL (for web sources)
- DOI (for academic papers, when available)

---

## Citations by Research Mode

CConductor automatically adjusts citation style and density based on the research mode detected from your question or configured in settings.

### Scientific/Academic Research

**When used**: Questions about peer-reviewed research, academic topics, scientific studies.

**Citation characteristics**:

- ✅ Every major claim is cited
- ✅ Full academic-style citations
- ✅ Emphasis on peer-reviewed sources
- ✅ Author-date format
- ✅ Complete bibliography

**Example output**:

```markdown
## Quantum Error Correction

Quantum error correction is essential for practical quantum computing [1].
The surface code is currently the most promising approach, requiring a
physical error rate below 1% for effective error correction [2][3].

Recent advances have demonstrated error rates of 0.6% in superconducting
qubits [4], approaching the threshold needed for fault-tolerant quantum
computation [5].

## References

[1] Nielsen, M. A., & Chuang, I. L. (2010). Quantum Computation and Quantum
    Information. Cambridge University Press.

[2] Fowler, A. G., et al. (2012). "Surface codes: Towards practical
    large-scale quantum computation." Physical Review A, 86(3), 032324.

[3] Dennis, E., et al. (2002). "Topological quantum memory." Journal of
    Mathematical Physics, 43(9), 4452-4505.

[4] Google AI Quantum. (2023). "Suppressing quantum errors by scaling a
    surface code logical qubit." Nature, 614(7949), 676-681.

[5] Preskill, J. (2018). "Quantum Computing in the NISQ era and beyond."
    Quantum, 2, 79.
```

**Quality requirements**:

- Citation coverage typically 85-95%
- Peer-reviewed sources prioritized
- Full attribution for all major claims

### Market/Business Research

**When used**: Questions about markets, companies, business data, competitive analysis.

**Citation characteristics**:

- ✅ Major claims and data cited
- ✅ URL-based references
- ✅ Emphasis on business sources
- ✅ Source attribution for numbers

**Example output**:

```markdown
## SaaS CRM Market Analysis

The global SaaS CRM market reached $52.3B in 2023 and is projected to
grow at 13.7% CAGR through 2028 [1]. North America represents the largest
regional market at 42% share [2].

### Competitive Landscape

The top 5 vendors control 67% of the market [3]:
- Salesforce: 23.8% share, $12.4B revenue [4]
- Microsoft Dynamics: 16.2% share, $8.5B revenue [5]
- Oracle: 10.1% share, $5.3B revenue [6]

## References

[1] Grand View Research. (2024). "SaaS CRM Market Size, Share & Trends
    Analysis Report." Retrieved from https://www.grandviewresearch.com/

[2] Gartner. (2024). "Market Share Analysis: CRM Software, Worldwide, 2023."
    Retrieved from https://www.gartner.com/

[3] Forrester Research. (2024). "The Forrester Wave: CRM Suites, Q1 2024."
    Retrieved from https://www.forrester.com/

[4] Salesforce. (2024). Q2 FY2024 Earnings Release. Retrieved from
    https://investor.salesforce.com/

[5] Microsoft. (2024). "Microsoft Cloud strength drives second quarter
    results." Retrieved from https://www.microsoft.com/investor/

[6] Oracle. (2024). Oracle Announces Fiscal 2024 Second Quarter Financial
    Results. Retrieved from https://www.oracle.com/investor/
```

**Quality requirements**:

- Citation coverage typically 70-85%
- Business and industry sources
- URLs and access dates provided

### General/Technical Research

**When used**: Mixed topics, technical questions, general research.

**Citation characteristics**:

- ✅ Key claims cited
- ✅ Mix of source types
- ✅ Basic references with URLs

**Example output**:

```markdown
## Docker Containerization

Docker uses OS-level virtualization to deliver software in containers [1].
Containers package an application with all its dependencies, ensuring it
runs consistently across different environments [2].

The technology has been widely adopted, with over 13 million developers
using Docker as of 2023 [3].

## References

[1] Docker Inc. (2024). "What is a container?" Docker Documentation.
    https://docs.docker.com/get-started/

[2] Ward, B., & Seltzer, M. (2014). "Containers vs. Virtual Machines."
    ACM Queue, 12(5).

[3] Docker Inc. (2023). "Docker State of Application Development Report."
    https://www.docker.com/resources/
```

**Quality requirements**:

- Citation coverage typically 60-75%
- Mixed source types accepted
- Focus on verifiable claims

---

## For Academic Use

### Meeting Academic Standards

**What CConductor provides**:

- ✅ All major claims are cited
- ✅ Bibliography is complete and formatted
- ✅ Sources are traceable via URLs/DOIs
- ✅ Multiple sources for key claims

**What you may need to add**:

- ⚠️  Format adjustments for specific journal styles (APA, MLA, Chicago)
- ⚠️  DOIs for papers (if not automatically included)
- ⚠️  Institutional requirements (e.g., annotated bibliography)
- ⚠️  Page numbers for direct quotes

### Configuring for Academic Research

To get the most academic-focused citations, configure CConductor for scientific research:

**Edit**: `config/cconductor-modes.json`

The `scientific` mode is configured to:

- Prioritize peer-reviewed sources
- Fetch full PDFs of papers
- Track citation networks
- Extract methodology details
- Provide comprehensive citations

**Alternatively**, use keywords in your question to trigger academic mode automatically:

```bash
./cconductor "peer-reviewed research on quantum error correction"
./cconductor "systematic review of CRISPR therapeutic applications"
./cconductor "meta-analysis of mindfulness interventions for anxiety"
```

Keywords like "peer-reviewed", "systematic review", "meta-analysis", "published research" automatically trigger academic source preferences.

### Export Formats

**Current Features**:

- Markdown with inline citations
- Plain text bibliography
- Copy-paste into your paper

**Coming in v0.2**:

- BibTeX export for LaTeX papers
- RIS export for reference managers (Zotero, Mendeley, EndNote)
- Direct formatting in APA, MLA, Chicago styles

**Current workflow**:

1. Run research with academic keywords
2. Copy bibliography from report
3. Manually format for journal requirements
4. Add any missing DOIs or page numbers

### Citation Styles

**Current style**: URL-based with dates and authors when available

**Example**:

```
[1] Smith, J., & Jones, M. (2023). "Title of Paper." Journal Name,
    Volume(Issue), Pages. https://doi.org/10.1234/example
```

**For your paper**: You may need to reformat to match journal requirements:

**APA 7th**:

```
Smith, J., & Jones, M. (2023). Title of paper. Journal Name, Volume(Issue),
Pages. https://doi.org/10.1234/example
```

**MLA 9th**:

```
Smith, John, and Mary Jones. "Title of Paper." Journal Name, vol. Volume,
no. Issue, 2023, pp. Pages, doi:10.1234/example.
```

**Chicago 17th**:

```
Smith, John, and Mary Jones. "Title of Paper." Journal Name Volume, no.
Issue (2023): Pages. https://doi.org/10.1234/example.
```

---

## Understanding Citation Coverage

### What is Citation Coverage?

**Citation coverage** = percentage of claims that have source citations

**Shown in quality report**:

```
Citation Coverage: 45/50 (90%)
```

**What this means**:

- 45 claims have citations
- 50 total claims made
- 90% of claims are sourced

### Good Citation Coverage

**For academic work**:

- Excellent: 90-100% coverage
- Good: 80-89% coverage
- Acceptable: 70-79% coverage
- Needs work: <70% coverage

**For business work**:

- Excellent: 80-90% coverage
- Good: 70-79% coverage
- Acceptable: 60-69% coverage

**For general research**:

- Good: 60-70% coverage
- Acceptable: 50-59% coverage

### Improving Citation Coverage

If citation coverage is lower than you need:

**Method 1: Resume research** (most effective):

```bash
./cconductor resume session_123
```

Continuing research typically:

- Finds more authoritative sources
- Links existing claims to sources
- Improves overall coverage by 10-15%

**Method 2: Configure for academic sources**:

Edit `config/cconductor-config.json` to emphasize academic sources:

```json
{
  "research_modes": {
    "scientific": {
      "min_peer_reviewed_sources": 10,
      "prioritize_peer_reviewed": true,
      "track_citations": true
    }
  }
}
```

Then research questions with academic keywords.

**Method 3: Provide PDF sources**:

Add academic PDFs to help CConductor find papers:

```bash
mkdir pdfs/
# Add your PDF files
cp important-papers/*.pdf pdfs/

./cconductor "your question based on these papers"
```

**Method 4: Be more specific in questions**:

More specific questions get better-sourced results:

❌ "Tell me about CRISPR"  
✅ "What does peer-reviewed research say about CRISPR therapeutic applications?"

---

## Troubleshooting

### Low Citation Count

**Problem**: Report has few citations, lower quality score.

**Causes**:

- Topic is very new (limited sources available)
- Question is too broad
- Fast research (traded depth for speed)
- Non-academic topic (fewer citable sources)

**Solutions**:

1. **Resume research**:

   ```bash
   ./cconductor resume session_123
   ```

2. **Use more specific question**:

   ```bash
   # Instead of:
   ./cconductor "AI trends"
   
   # Try:
   ./cconductor "peer-reviewed research on large language model advances 2023-2024"
   ```

3. **Add time to research**:
   - Let research complete fully
   - Don't interrupt
   - Adaptive mode will find more sources

4. **Provide known sources**:
   - Add relevant PDFs to pdfs/ directory
   - Mention specific databases or journals in question

### Missing Bibliography

**Problem**: Report doesn't have bibliography section.

**Causes**:

- Report generation error
- Research didn't complete
- Very short/incomplete research

**Solutions**:

1. **Check report completion**:

   ```bash
   ./cconductor sessions latest
   # Look for "Research Complete!" message
   ```

2. **Check for errors**:

   ```bash
   tail -20 logs/research.log
   ```

3. **Resume research**:

   ```bash
   ./cconductor resume session_123
   ```

4. **Check report file**:

   ```bash
   # Should end with ## References section
   tail -50 research-sessions/$(cat research-sessions/.latest)/final/mission-report.md
   ```

### Citations Are URLs Not Papers

**Problem**: Bibliography has web URLs instead of academic papers.

**Causes**:

- Question didn't trigger academic mode
- Topic has limited academic research
- Web sources were more relevant

**Solutions**:

1. **Use academic keywords in question**:

   ```bash
   ./cconductor "peer-reviewed studies on [topic]"
   ./cconductor "published research on [topic]"
   ./cconductor "academic literature on [topic]"
   ```

2. **Configure default mode to scientific**:
   Edit `config/cconductor-config.json`:

   ```json
   {
     "research": {
       "default_mode": "scientific"
     }
   }
   ```

3. **Add PDF sources**:

   ```bash
   mkdir pdfs/
   # Add academic PDFs
   ./cconductor "question about papers in pdfs/"
   ```

4. **Resume for more academic sources**:

   ```bash
   ./cconductor resume session_123
   ```

---

## Examples

### Example 1: Academic Research Report

**Question**:

```bash
./cconductor "What are the mechanisms of action for mRNA vaccines and their efficacy data from clinical trials?"
```

**Result excerpt**:

```markdown
## mRNA Vaccine Mechanisms

mRNA vaccines work by introducing messenger RNA encoding a viral protein
into cells, which then produce the protein to trigger an immune response [1].
Unlike traditional vaccines, mRNA vaccines do not contain live virus and
cannot cause infection [2].

### Efficacy Data

Clinical trials demonstrated high efficacy for COVID-19 mRNA vaccines:
- Pfizer-BioNTech (BNT162b2): 95% efficacy in preventing symptomatic
  COVID-19 [3]
- Moderna (mRNA-1273): 94.1% efficacy in phase 3 trials [4]

Both vaccines showed strong efficacy against severe disease and
hospitalization, with over 95% protection [5][6].

## References

[1] Pardi, N., Hogan, M. J., Porter, F. W., & Weissman, D. (2018). mRNA
    vaccines—a new era in vaccinology. Nature Reviews Drug Discovery,
    17(4), 261-279. https://doi.org/10.1038/nrd.2017.243

[2] Polack, F. P., et al. (2020). Safety and Efficacy of the BNT162b2
    mRNA Covid-19 Vaccine. New England Journal of Medicine, 383(27),
    2603-2615. https://doi.org/10.1056/NEJMoa2034577

[3] Baden, L. R., et al. (2021). Efficacy and Safety of the mRNA-1273
    SARS-CoV-2 Vaccine. New England Journal of Medicine, 384(5), 403-416.
    https://doi.org/10.1056/NEJMoa2035389

[continues...]
```

**Quality metrics**:

- Citation coverage: 92% (47/51 claims)
- Sources: 28 academic papers
- Quality score: 89/100 (EXCELLENT)

### Example 2: Market Research Report

**Question**:

```bash
./cconductor "What is the total addressable market for AI-powered customer service platforms in 2024?"
```

**Result excerpt**:

```markdown
## Market Size Analysis

The global AI-powered customer service market reached $8.9B in 2023 and
is projected to grow to $47.1B by 2030, representing a CAGR of 26.8% [1].

### Market Segments

- **Chatbots & Virtual Assistants**: $3.2B (36% of market) [2]
- **AI-Powered Email Response**: $2.1B (24%) [2]
- **Voice AI**: $1.8B (20%) [3]
- **Analytics & Insights**: $1.8B (20%) [3]

## References

[1] Grand View Research. (2024). "AI in Customer Service Market Size,
    Share & Trends Analysis Report." Retrieved January 15, 2024, from
    https://www.grandviewresearch.com/industry-analysis/

[2] Gartner. (2024). "Market Guide for Conversational AI Platforms."
    Retrieved January 10, 2024, from https://www.gartner.com/

[3] MarketsandMarkets. (2024). "Conversational AI Market by Component,
    Type, Deployment Mode." Retrieved from
    https://www.marketsandmarkets.com/
```

**Quality metrics**:

- Citation coverage: 78% (28/36 claims)
- Sources: 15 industry reports, 8 company data
- Quality score: 82/100 (VERY GOOD)

---

## See Also

- **[User Guide](USER_GUIDE.md)** - Complete usage guide
- **[Quality Guide](QUALITY_GUIDE.md)** - Understanding quality scores
- **[Security Guide](SECURITY_GUIDE.md)** - Configuring security
- **[Configuration Reference](CONFIGURATION_REFERENCE.md)** - All settings

---

**CConductor Citations** - Automatic source tracking for credible research 📚
