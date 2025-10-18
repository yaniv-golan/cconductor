# CConductor Quality Scoring Guide

**Understanding and improving research quality**

**Last Updated**: October 2025  
**For**: All users who want to understand and improve research quality

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quality Score Overview](#quality-score-overview)
3. [Understanding the Metrics](#understanding-the-metrics)
4. [Quality Score Ranges](#quality-score-ranges)
5. [Improving Research Quality](#improving-research-quality)
6. [Examples](#examples)
7. [Troubleshooting](#troubleshooting)

---

## Introduction

Every CConductor research session receives a quality score based on multiple factors. This guide helps you understand what the score means and how to achieve better results.

**Who needs this**:

- Anyone using CConductor for important research
- Academic users who need high-quality sources
- Business users who need reliable data
- Users troubleshooting research issues

**What quality scores measure**:

- Source credibility and authority
- Citation coverage (how many claims are cited)
- Information completeness
- Evidence quality
- Research depth

---

## Quality Score Overview

### The Quality Report

Every research session generates a quality report at the end. Find it in:

```
research-sessions/[session-name]/
  output/mission-report.md          ← Main report with findings
  intermediate/
    validation.json           ← Quality metrics here
```

### What You See

The quality report appears at the **end of your research report**:

```markdown
---
## Research Quality Assessment

**Overall Score**: 87/100 (VERY GOOD)

### Quality Metrics

Source Quality: 42/45 (93%)
  ✓ 35 high-authority sources
  ✓ 7 medium-authority sources
  ✓ 0 low-authority sources

Citation Coverage: 45/50 (90%)
  ✓ 45 claims with citations
  ⚠ 5 claims without citations

Completeness: 38/40 (95%)
  ✓ All major aspects covered
  ✓ Sufficient detail
  ✓ No critical gaps

Evidence Quality: 40/45 (89%)
  ✓ Multiple sources per claim
  ✓ Primary sources used
  ✓ Recent data (2023-2024)

Confidence: 85/100 (HIGH)
  ✓ Strong evidence for main findings
  ⚠ Some areas need more research

### Quality Band: VERY GOOD
Research is thorough and well-sourced. Suitable for professional use.
Minor improvements possible with continued research.
```

### Score Ranges

- **90-100** (EXCELLENT): Publication-ready, comprehensive coverage
- **80-89** (VERY GOOD): Professional quality, minor gaps only
- **70-79** (GOOD): Solid research, suitable for most uses
- **60-69** (ACCEPTABLE): Usable but has notable limitations
- **Below 60** (NEEDS WORK): Significant gaps or quality issues

---

## Understanding the Metrics

### Source Quality (Weighted 30%)

**What it measures**: Authority and credibility of sources used.

**Score factors**:

- **High-authority sources** (best):
  - Peer-reviewed academic journals
  - Government agencies (.gov)
  - Major research institutions (.edu)
  - Established industry sources
  
- **Medium-authority sources** (good):
  - Reputable news organizations
  - Well-known industry publications
  - Established company sources
  - Professional associations

- **Low-authority sources** (problematic):
  - Personal blogs without credentials
  - Unverified sources
  - Sites with poor reputation
  - Outdated or deprecated sources

**Example breakdown**:

```
Source Quality: 42/45 (93%)
  ✓ 35 high-authority sources    ← Excellent!
  ✓ 7 medium-authority sources    ← Good
  ✓ 0 low-authority sources       ← Perfect!
```

**What good looks like**:

- 90%+ score = Excellent source selection
- 80-89% = Very good, mostly high-authority
- 70-79% = Good, mix of authority levels
- Below 70% = Too many low-authority sources

---

### Citation Coverage (Weighted 25%)

**What it measures**: Percentage of claims that have source citations.

**Score calculation**:

```
Citation Coverage = (Claims with citations / Total claims) × 100
```

**Example**:

```
Citation Coverage: 45/50 (90%)
  ✓ 45 claims with citations     ← 45 claims backed by sources
  ⚠ 5 claims without citations   ← 5 unsupported claims
```

**What good looks like**:

- **Academic research**: Need 85-100% coverage
- **Business research**: 70-85% is acceptable
- **General research**: 60-75% is acceptable

**Why claims go unsourced**:

- Common knowledge statements
- Logical inferences from data
- Synthetic conclusions from multiple sources
- Technical explanations
- Transitional statements

**What matters**: Major factual claims should always be cited. Transitional or explanatory text doesn't always need citations.

---

### Completeness (Weighted 20%)

**What it measures**: How thoroughly the research question was answered.

**Score factors**:

- All major aspects of question addressed
- Sufficient depth and detail
- No critical gaps in coverage
- Context and background provided
- Relevant adjacent topics explored

**Example**:

```
Completeness: 38/40 (95%)
  ✓ All major aspects covered
  ✓ Sufficient detail
  ✓ No critical gaps
```

**What good looks like**:

- 90%+ = Comprehensive, thorough coverage
- 80-89% = Very complete, minor gaps only
- 70-79% = Adequate coverage, some gaps
- Below 70% = Significant gaps or missing areas

**Common gaps**:

- Missing regional perspectives
- Lacking historical context
- No competitive comparison
- Insufficient market data
- Missing technical details

---

### Evidence Quality (Weighted 15%)

**What it measures**: Strength and reliability of evidence.

**Score factors**:

- Multiple sources support key claims
- Primary sources vs. secondary
- Recency of data
- Source agreement vs. contradiction
- Methodology quality (for studies)

**Example**:

```
Evidence Quality: 40/45 (89%)
  ✓ Multiple sources per claim
  ✓ Primary sources used
  ✓ Recent data (2023-2024)
```

**What good looks like**:

- **Excellent (90%+)**: Multiple recent primary sources
- **Very Good (80-89%)**: Mix of primary and quality secondary
- **Good (70-79%)**: Adequate sourcing, some secondary
- **Needs work (<70%)**: Over-reliant on weak sources

**Strong evidence**:

- Original research papers
- Official government data
- Company financial reports
- Industry studies with methodology
- Multiple corroborating sources

**Weak evidence**:

- Single uncorroborated claim
- Outdated data (5+ years old)
- Sources that contradict each other
- Unknown methodology
- Secondary or tertiary sources only

---

### Confidence (Weighted 10%)

**What it measures**: How confident CConductor is in the findings.

**Score factors**:

- Agreement across sources
- Quality of sources
- Depth of research
- Absence of contradictions
- Coverage of the topic

**Example**:

```
Confidence: 85/100 (HIGH)
  ✓ Strong evidence for main findings
  ⚠ Some areas need more research
```

**Confidence levels**:

- **90-100** (VERY HIGH): Strong agreement, excellent sources
- **80-89** (HIGH): Good evidence, minor uncertainties
- **70-79** (MODERATE): Adequate but some gaps
- **60-69** (LOW-MODERATE): Notable uncertainties
- **Below 60** (LOW): Significant uncertainties

**What affects confidence**:

- Source agreement: Do sources agree or contradict?
- Evidence depth: Single source vs. many sources
- Source quality: Authoritative vs. weak
- Topic coverage: Complete vs. partial

---

## Quality Score Ranges

### Excellent (90-100)

**Characteristics**:

- Publication-ready quality
- Comprehensive source coverage
- High citation coverage (90%+)
- All high-authority sources
- No significant gaps
- Strong evidence for all claims

**Suitable for**:

- Academic papers
- Executive presentations
- Published reports
- Critical decision-making
- Regulatory submissions

**Example use cases**:

- PhD dissertation research
- Board-level strategy documents
- Grant proposals
- Industry white papers

---

### Very Good (80-89)

**Characteristics**:

- Professional quality
- Very good source selection
- Good citation coverage (80-90%)
- Mostly high-authority sources
- Minor gaps only
- Strong supporting evidence

**Suitable for**:

- Business reports
- Professional presentations
- Team decisions
- Client deliverables
- Internal research reports

**Example use cases**:

- Market analysis reports
- Competitive intelligence
- Product research
- Strategic planning

---

### Good (70-79)

**Characteristics**:

- Solid research
- Good mix of sources
- Adequate citations (70-80%)
- Some medium-authority sources
- Some gaps present
- Generally reliable

**Suitable for**:

- Internal use
- Preliminary research
- Background information
- General learning
- Early-stage exploration

**Example use cases**:

- Exploratory research
- Background briefings
- Initial market scans
- Personal learning

---

### Acceptable (60-69)

**Characteristics**:

- Usable but limited
- Mixed source quality
- Lower citation coverage (60-70%)
- Notable gaps in coverage
- Some reliability concerns
- May need verification

**Suitable for**:

- Very early exploration
- Brainstorming
- General awareness
- **Not suitable for important decisions**

**Recommendation**: Resume research to improve quality before using for important purposes.

---

### Needs Work (Below 60)

**Characteristics**:

- Significant quality issues
- Weak or limited sources
- Low citation coverage (<60%)
- Major gaps in information
- Reliability concerns
- Incomplete research

**Not suitable for**:

- Professional use
- Decision-making
- Publication
- Client deliverables

**Action needed**: Resume research or restart with more specific question.

---

## Improving Research Quality

### Method 1: Resume Research (Most Effective)

The most effective way to improve quality is to continue researching:

```bash
# Find your session
./cconductor sessions

# Resume it
./cconductor resume session_name
```

**What happens**:

- CConductor identifies gaps in the research
- Finds additional authoritative sources
- Adds citations to unsupported claims
- Explores undercover areas
- Improves confidence scores

**Expected improvement**:

- Typically +10 to +15 points
- Citation coverage usually improves most
- Source quality increases
- Gaps get filled

**How long**: 10-30 minutes additional research depending on topic complexity.

---

### Method 2: More Specific Questions

Quality improves with more specific, focused questions.

**Instead of vague**:

```bash
❌ ./cconductor "AI trends"
```

**Be specific**:

```bash
✅ ./cconductor "peer-reviewed research on large language model safety alignment techniques 2023-2024"
```

**Why this helps**:

- Triggers appropriate research mode
- Finds more relevant sources
- Enables deeper exploration
- Improves source authority

**Specificity tips**:

- Include time frame (2023-2024)
- Specify domain (academic, market, technical)
- Use precise terminology
- Name specific entities/topics
- Request specific types of sources

---

### Method 3: Provide Context via PDFs

For academic or specialized topics, provide known papers:

```bash
# Add PDFs to the pdfs directory
mkdir -p pdfs/
cp your-papers/*.pdf pdfs/

# Run research
./cconductor "question related to the papers"
```

**Why this helps**:

- CConductor can analyze papers directly
- Extracts high-quality citations
- Builds on known research
- Links related work

**Best for**:

- Academic research
- Literature reviews
- Technical deep dives
- Building on known work

---

### Method 4: Configure Research Mode

For consistent quality needs, configure default research mode.

**Edit**: `config/cconductor-config.json`

```json
{
  "research": {
    "default_mode": "scientific"
  }
}
```

**Available modes**:

- `scientific`: Highest quality, academic focus
- `market`: Business data, industry focus
- `technical`: Technical documentation focus
- `default`: Balanced approach

**Effect**:

- Sets source preferences
- Adjusts quality thresholds
- Changes citation requirements
- Affects research depth

---

### Method 5: Let Research Complete Fully

**Don't interrupt research**:

- Let adaptive research run to completion
- Wait for "Research Complete!" message
- Don't stop early for speed

**Why**:

- Adaptive mode improves over time
- Later iterations find better sources
- Citations get added progressively
- Gaps get filled automatically

**Patience pays off**:

- First 10 minutes: Basic coverage (quality ~65)
- 20 minutes: Good coverage (quality ~75)
- 30+ minutes: Very good coverage (quality ~85+)

---

### Method 6: Add Custom Domain Knowledge

For specialized domains, add your expertise:

**Create**: `knowledge-base-custom/my-domain.md`

```markdown
## Overview
Domain expertise for [topic]

## Authoritative Sources
- Source 1: https://...
- Source 2: https://...

## Key Concepts
- Term: Definition with authoritative citation
```

**Why this helps**:

- Directs CConductor to best sources
- Provides domain-specific terminology
- Adds context for evaluation
- Improves relevance

**See**: [Custom Knowledge Guide](CUSTOM_KNOWLEDGE.md) for details.

---

## Examples

### Example 1: Excellent Quality (94/100)

**Question**:

```bash
./cconductor "What are the therapeutic mechanisms and clinical efficacy of CAR-T cell therapy for B-cell lymphomas based on peer-reviewed research?"
```

**Quality Report**:

```
Overall Score: 94/100 (EXCELLENT)

Source Quality: 44/45 (98%)
  ✓ 42 high-authority sources (all peer-reviewed journals)
  ✓ 2 medium-authority sources (clinical trial registries)
  ✓ 0 low-authority sources

Citation Coverage: 67/68 (99%)
  ✓ 67 claims with citations
  ⚠ 1 claim without citation (background context)

Completeness: 39/40 (98%)
  ✓ All major aspects covered
  ✓ Excellent depth
  ✓ No critical gaps

Evidence Quality: 44/45 (98%)
  ✓ Multiple primary sources per claim
  ✓ Recent clinical trials (2022-2024)
  ✓ Consistent findings across studies

Confidence: 95/100 (VERY HIGH)
  ✓ Strong consensus across sources
  ✓ High-quality evidence base
```

**Why excellent**:

- Highly specific question
- Academic focus triggered
- Peer-reviewed sources only
- Complete coverage
- Very high citation rate

**Suitable for**: Academic paper, grant proposal, clinical review

---

### Example 2: Very Good Quality (83/100)

**Question**:

```bash
./cconductor "Global market size and competitive landscape for enterprise CRM software 2024"
```

**Quality Report**:

```
Overall Score: 83/100 (VERY GOOD)

Source Quality: 38/45 (84%)
  ✓ 18 high-authority sources (Gartner, Forrester, official data)
  ✓ 12 medium-authority sources (industry publications)
  ✓ 2 low-authority sources (excluded from main findings)

Citation Coverage: 41/50 (82%)
  ✓ 41 claims with citations
  ⚠ 9 claims without citations

Completeness: 35/40 (88%)
  ✓ Major market segments covered
  ✓ Competitive landscape included
  ⚠ Limited APAC data

Evidence Quality: 38/45 (84%)
  ✓ Multiple sources for market size
  ✓ Official company data used
  ⚠ Some projections vary across sources

Confidence: 80/100 (HIGH)
  ✓ Good consensus on market size
  ⚠ Some regional data is estimated
```

**Why very good**:

- Good mix of authoritative business sources
- Strong citation coverage for key claims
- Minor gaps in less-critical areas
- Suitable for business decisions

**Suitable for**: Business presentation, strategic planning, client report

---

### Example 3: Good Quality (74/100)

**Question**:

```bash
./cconductor "Docker containerization and Kubernetes orchestration"
```

**Quality Report**:

```
Overall Score: 74/100 (GOOD)

Source Quality: 32/45 (71%)
  ✓ 10 high-authority sources (Docker/K8s docs, tech journals)
  ✓ 18 medium-authority sources (tech blogs, tutorials)
  ✓ 4 low-authority sources (personal blogs)

Citation Coverage: 35/50 (70%)
  ✓ 35 claims with citations
  ⚠ 15 claims without citations (mostly technical explanations)

Completeness: 30/40 (75%)
  ✓ Core concepts covered
  ⚠ Limited real-world deployment examples
  ⚠ Performance comparisons thin

Evidence Quality: 30/45 (67%)
  ✓ Official documentation used
  ⚠ Some single-source claims
  ⚠ Mix of technical depths

Confidence: 70/100 (MODERATE)
  ✓ Core technical facts solid
  ⚠ Best practices vary across sources
```

**Why good**:

- Broad technical question
- Mix of authoritative and community sources
- Technical explanations don't always need citations
- Suitable for learning and internal use

**Suitable for**: Internal documentation, team learning, technical exploration

**To improve**: Resume research for more deployment examples and performance data

---

### Example 4: Needs Work (58/100)

**Question**:

```bash
./cconductor "tech trends"
```

**Quality Report**:

```
Overall Score: 58/100 (NEEDS WORK)

Source Quality: 22/45 (49%)
  ✓ 5 high-authority sources
  ✓ 10 medium-authority sources
  ✗ 12 low-authority sources (too many!)

Citation Coverage: 25/50 (50%)
  ✓ 25 claims with citations
  ✗ 25 claims without citations

Completeness: 20/40 (50%)
  ⚠ Very broad coverage, shallow depth
  ✗ Many important sub-topics barely touched
  ✗ Critical gaps in analysis

Evidence Quality: 18/45 (40%)
  ⚠ Many single-source claims
  ✗ Conflicting information not resolved
  ✗ Sources vary widely in quality

Confidence: 45/100 (LOW)
  ✗ Significant uncertainties
  ✗ Limited consensus
```

**Why poor**:

- Question too vague and broad
- Triggered general mode (lowest quality threshold)
- Many unreliable sources
- Shallow coverage of everything

**Action needed**:

- Ask more specific question
- Resume research OR restart with focused question
- **Don't use for important purposes**

---

## Troubleshooting

### Quality Score Lower Than Expected

**Problem**: You expected higher quality but got a lower score.

**Common causes**:

1. **Question was too broad**:
   - Broad questions get shallow coverage
   - Lack of focus reduces authority
   - Hard to find consensus

   **Fix**: Ask more specific question

2. **Research didn't complete**:
   - Interrupted early
   - Technical error
   - Insufficient time

   **Fix**: Let research run fully or resume

3. **Limited sources available**:
   - Very new topic (2024 only)
   - Niche specialized domain
   - Regional/language limitations

   **Fix**: Provide PDFs or custom knowledge

4. **Wrong research mode**:
   - Academic question but general mode used
   - Market question but scientific mode triggered

   **Fix**: Configure mode or use specific keywords

---

### Low Citation Coverage

**Problem**: Many claims without citations, low coverage percentage.

**Causes**:

- Fast research (breadth over depth)
- Topic has limited published sources
- Too broad question

**Solutions**:

1. **Resume research**:

   ```bash
   ./cconductor resume session_name
   ```

2. **More specific question**:
   Use precise terminology, mention specific papers/sources

3. **Provide known sources**:
   Add PDFs to help CConductor find citations

4. **Let adaptive mode run longer**:
   Don't interrupt, citations improve over time

---

### Low Source Quality

**Problem**: Too many low-authority sources, few high-authority.

**Causes**:

- Limited authoritative sources available for topic
- Question didn't trigger academic mode
- Very recent topic (not yet in journals)

**Solutions**:

1. **Use academic keywords**:

   ```bash
   ./cconductor "peer-reviewed research on [topic]"
   ./cconductor "published studies on [topic]"
   ```

2. **Configure for scientific mode**:
   Edit `config/cconductor-config.json` to default to scientific

3. **Resume research**:
   Additional time finds better sources

4. **Accept limitation**:
   Some topics genuinely lack authoritative sources yet

---

### Completeness Issues

**Problem**: Research has gaps, important aspects missing.

**Causes**:

- Question too broad (can't cover everything)
- Research stopped early
- Topic aspect not discoverable

**Solutions**:

1. **Resume research**:

   ```bash
   ./cconductor resume session_name
   ```

   Adaptive mode identifies and fills gaps

2. **Ask follow-up**:

   ```bash
   # First research
   ./cconductor "CAR-T cell therapy overview"
   
   # Follow-up for gap
   ./cconductor "CAR-T cell therapy side effects and management"
   ```

3. **More specific question**:
   Break broad question into focused sub-questions

---

## See Also

- **[User Guide](USER_GUIDE.md)** - Complete CConductor usage
- **[Citations Guide](CITATIONS_GUIDE.md)** - Understanding citations
- **[Configuration Reference](CONFIGURATION_REFERENCE.md)** - All config options
- **[Custom Knowledge](CUSTOM_KNOWLEDGE.md)** - Adding domain expertise

---

**CConductor Quality** - Research you can trust 🎯
