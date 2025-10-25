# Deep Research Engine - Project Memory

## Purpose
This project implements a multi-agent research system that conducts comprehensive, validated research on any topic using Claude Code's agent architecture.

## Domain Knowledge
@../knowledge-base/verified-sources.md
@../knowledge-base/research-methodology.md
@../knowledge-base/scientific-methodology.md
@../knowledge-base/business-methodology.md

## Research Guidelines

### Source Credibility Hierarchy
1. **Academic** - Peer-reviewed journals, academic papers, .edu sites
2. **Official** - Official documentation, RFC specifications, standards bodies
3. **High Authority** - Reputable technical blogs, established experts, major tech companies
4. **Medium** - Stack Overflow, GitHub discussions, technical forums
5. **Low** - Personal blogs, unverified claims, outdated content

### Citation Standards
- **Always include full URLs** for web sources
- **Include access date** for all web content (format: YYYY-MM-DD)
- **Preserve original quotes** with quotation marks and exact wording
- **Note when paraphrasing** vs. directly quoting
- **Include file:line references** for code sources (e.g., `src/main.rs:123`)
- **Prefer primary sources** over secondary summaries

### Context Management Rules

#### Token Budgets per Agent
- Research Planner: 10,000 tokens (planning only)
- Web Researcher: 40,000 tokens per task
- Code Analyzer: 30,000 tokens per task
- Academic Researcher: 40,000 tokens per task
- Market Analyzer: 40,000 tokens per task
- Competitor Analyzer: 40,000 tokens per task
- Financial Extractor: 30,000 tokens per task
- Synthesis Agent: 60,000 tokens (receives summaries, not raw data)
- Fact Checker: 40,000 tokens

#### Progressive Summarization
- **Level 1 (Raw)**: Full findings from research agents
- **Level 2 (Intermediate)**: Summarized to top 10 facts per source
- **Level 3 (Synthesis)**: Consolidated narrative with citations
- **Level 4 (Final)**: Validated report with quality metrics

#### Context Pruning Strategy
- Remove duplicate information across sources
- Prioritize high-credibility sources over low-credibility
- Keep only top-priority findings (priority 4-5)
- Limit code snippets to 20 lines maximum
- Summarize lengthy explanations to key points

### Research Process Workflow

```
1. Understanding & Clarification (research-planner agent - interactive)
   ↓
2. Decompose Question (research-planner agent)
   ↓
3. Parallel Research Execution
   ├─ Web Research (web-researcher agent)
   ├─ Code Analysis (code-analyzer agent)
   ├─ Academic Research (academic-researcher agent)
   ├─ Market Analysis (market-analyzer agent)
   ├─ Competitor Analysis (competitor-analyzer agent)
   └─ Financial Analysis (financial-extractor agent)
   ↓
4. Context Pruning & Summarization
   ↓
5. Synthesis (synthesis-agent agent)
   ↓
6. Validation (fact-checker agent)
   ↓
7. Format Output
```

### Agent Communication Protocol

Agents communicate through structured JSON files in the session directory:
- Input: `$SESSION_DIR/work/<agent>/input.txt`
- Output: `$SESSION_DIR/work/<agent>/output.json`

Each agent is stateless and cannot communicate with other agents directly.

### Quality Standards

#### Minimum Requirements
- **Minimum 3 sources** per major claim
- **Cross-reference** all statistics and technical details
- **Flag uncertainty** when information is limited
- **Acknowledge conflicts** when sources disagree
- **Include confidence scores** for all major claims

#### Quality Metrics
- Source diversity (multiple independent sources)
- Recency (prefer recent information, note when old)
- Depth (comprehensive coverage of topic)
- Citation quality (proper attribution)

### Error Handling

- If a source is unavailable, note it and continue with available sources
- If findings conflict, present all perspectives
- If information is insufficient, clearly state knowledge gaps
- If validation fails, report concerns but still deliver the report

## Agent-Specific Instructions

### For Web Researcher Agent
- Prioritize official documentation and academic sources
- Always check publish/update dates
- Note geographical or temporal context (e.g., "As of 2024...")
- Be aware of bias in sources

### For Code Analyzer Agent
- Always provide file:line references
- Prefer recent commits over old code
- Note if code is experimental or deprecated
- Explain architecture before diving into details

### For Academic Researcher Agent
- Prioritize peer-reviewed sources over preprints
- Note journal impact factors
- Check for retractions
- Track citation networks

### For Market/Competitor/Financial Agents
- Distinguish disclosed vs. estimated data
- Note data recency and sources
- Use multiple methodologies for market sizing
- Verify funding data from multiple sources

### For Synthesis Agent
- Lead with executive summary
- Use clear section structure
- Acknowledge all perspectives on controversial topics
- Highlight confidence levels throughout
- Use domain-appropriate structure

### For Fact Checker Agent
- Cross-reference with 3+ independent sources for critical claims
- Check dates, numbers, and technical terms carefully
- Flag vague claims (e.g., "many experts say...")
- Verify that quotes are accurate
- Apply domain-specific validation rules

## Output Preferences

- Default format: Markdown
- Include table of contents for reports >2000 words
- Use code blocks for technical examples
- Include visual separators between major sections
- Always include a "Sources" or "References" section at the end
