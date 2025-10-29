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
8. [Domain-Aware Quality & Stakeholder Patterns](#domain-aware-quality--stakeholder-patterns)

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
  report/mission-report.md      ← Main report with findings
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
./cconductor resume mission_id
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
   ./cconductor resume mission_id
   ```

2. **More specific question**:
   Use precise terminology, mention specific papers/sources

3. **Provide known sources**:
   Add PDFs to help CConductor find citations

4. **Let adaptive mode run longer**:
   Don't interrupt, citations improve over time

---

### Watchdog or Timeout Overrides

**Problem**: Agents run indefinitely or finish without quality gates triggering.

**What changed**: CConductor now supports toggles for the agent watchdog and timeout enforcement. Disabling these safeguards can be useful for deep dives, but it also removes automatic recovery when agents stall.

**Guidelines**:

- Prefer disabling only timeouts (`--disable-agent-timeouts`) if you need longer runs; the watchdog still enforces heartbeat freshness.
- If you disable the watchdog (`--disable-watchdog`), plan to supervise the mission manually—quality checks will not terminate stalled agents.
- Re-enable protections per run with `--enable-watchdog` / `--enable-agent-timeouts` or by updating `agent-timeouts.json`.
- Environment aliases (`CCONDUCTOR_ENABLE_WATCHDOG`, `CCONDUCTOR_DISABLE_WATCHDOG`, `CCONDUCTOR_ENABLE_AGENT_TIMEOUTS`, `CCONDUCTOR_DISABLE_AGENT_TIMEOUTS`) map to the same behaviors; document their use in review notes if you rely on them for automated workflows.
- Document watchdog/timeout overrides in post-mission reviews so stakeholders understand the risk posture.

**Quality impact**: Lower automation can reduce the consistency of quality metrics (agents may exceed budgets or return stale evidence). Use manual validation before sharing results.

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
   ./cconductor resume mission_id
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

## Domain-Aware Quality & Stakeholder Patterns

### What is Domain-Aware Quality?

CConductor includes **domain-aware quality checking** that adapts quality standards to your research domain.

**How it works**:

1. At mission start, CConductor analyzes your research objective
2. Identifies domain (e.g., aviation safety, healthcare policy, tech markets)
3. Generates domain-specific requirements:
   - **Stakeholder categories**: Which perspectives must be represented (regulators, manufacturers, critics, etc.)
   - **Freshness requirements**: How recent data must be per topic (regulatory decisions: 6 months, technical specs: 12 months)
   - **Mandatory watch items**: Critical facts that must be researched (e.g., "FAA certification status", "clinical trial results")

4. Quality gate enforces these requirements:
   - Checks that all critical stakeholder perspectives are included
   - Verifies mandatory watch items were researched
   - Applies topic-specific recency thresholds

**Benefits**:

- Reports automatically include balanced stakeholder representation
- No more defensive or biased reporting
- Ensures critical facts aren't omitted
- Domain-appropriate freshness (regulatory domains get stricter thresholds than historical research)

### Understanding Stakeholder Categories

CConductor automatically identifies stakeholder perspectives from source URLs and titles:

**Example - Aviation Safety Domain**:

- **Regulators**: faa.gov, easa.europa.eu, sources with "FAA", "certification"
- **Manufacturers**: boeing.com, airbus.com, sources with "manufacturer statement"
- **Operators**: airline websites, pilot unions, sources with "fleet operations"
- **Safety Advocates**: independent safety groups, sources with "investigation", "advocacy"
- **Independent Analysts**: think tanks, academic researchers, sources with "analysis", "study"

**How CConductor categorizes sources**:

1. **Domain matching**: Checks if source URL contains known patterns (e.g., ".gov" for regulators)
2. **Keyword matching**: Checks if source title contains category keywords (e.g., "FAA" → regulators)
3. **Auto-learning**: Domain Heuristics Agent performs web research to discover stakeholder patterns per mission

### When You Need Manual Stakeholder Patterns

Sometimes CConductor encounters sources it can't automatically categorize. You'll see warnings like:

```
⚠ Note: 8 uncategorized sources detected (18%)
   Review: artifacts/quality-gate-summary.json
   Action: Add patterns to ~/.config/cconductor/stakeholder-patterns.json if needed
```

**When to add manual patterns**:

- **Niche stakeholders**: Regional regulators (Transport Canada, CASA Australia)
- **Specialized groups**: Patient advocacy organizations, open-source maintainers
- **Domain-specific sources**: Industry newsletters, specialized journals
- **International sources**: Non-English domains that don't match US/EU patterns

**When NOT to add patterns**:

- Generic news sites (these are usually correctly categorized or intentionally not stakeholders)
- One-off sources (not worth maintaining patterns for)
- Sources that shouldn't be stakeholders (personal blogs, forums)

### How to Add Manual Stakeholder Patterns

**Step 1: Create your patterns file**

```bash
# Create config directory if it doesn't exist
mkdir -p ~/.config/cconductor

# Copy template
cp config/stakeholder-patterns.default.json ~/.config/cconductor/stakeholder-patterns.json
```

**Step 2: Edit the file**

Open `~/.config/cconductor/stakeholder-patterns.json` in your editor.

**Example - Adding regional aviation regulators**:

```json
{
  "additional_patterns": {
    "regional_regulators": {
      "domain_patterns": [
        "tc.gc.ca",
        "casa.gov.au",
        "dgca.gov.in"
      ],
      "keyword_patterns": [
        "Transport Canada",
        "CASA",
        "DGCA",
        "civil aviation authority"
      ]
    }
  }
}
```

**Pattern types explained**:

- **domain_patterns**: URL fragments that identify sources
  - Example: `"tc.gc.ca"` matches `https://tc.gc.ca/eng/civilaviation/`
  - Use specific fragments: `"tc.gc.ca"` not just `".ca"`
  
- **keyword_patterns**: Terms that appear in source titles/snippets
  - Example: `"Transport Canada"` matches title "Transport Canada Issues New Directive"
  - Case-insensitive matching
  - Include variations: `["safety advocate", "advocacy group", "safety coalition"]`

**Matching logic**: A source matches a stakeholder category if it matches **ANY** domain pattern **OR ANY** keyword pattern.

**Step 3: Add multiple categories**

You can add as many stakeholder categories as needed:

```json
{
  "additional_patterns": {
    "regional_regulators": {
      "domain_patterns": ["tc.gc.ca", "casa.gov.au"],
      "keyword_patterns": ["Transport Canada", "CASA"]
    },
    "safety_advocates": {
      "domain_patterns": ["familiesof737max.org", "airsafe.org"],
      "keyword_patterns": ["victim families", "safety advocate", "crash investigation"]
    },
    "pilot_unions": {
      "domain_patterns": ["alpa.org", "swapa.org"],
      "keyword_patterns": ["pilot union", "ALPA", "SWAPA", "pilot association"]
    }
  }
}
```

**Step 4: Run a test mission**

```bash
# Run research on your domain
./cconductor "Your research question about the domain"

# After mission completes, check uncategorized count
cat research-sessions/mission_*/artifacts/quality-gate-summary.json | jq '.uncategorized_sources'
```

**What to look for**:

```json
{
  "count": 2,           ← Should be lower than before
  "total": 45,
  "percentage": 4.4,    ← Should be <15%
  "samples": [          ← Review these to see what's still uncategorized
    {
      "url": "https://example.com/article",
      "title": "Example Title"
    }
  ]
}
```

**If count is still high**:

1. Review `samples` array to see what sources are missed
2. Add more domain/keyword patterns for those sources
3. Run another mission to verify

### Pattern Merging Behavior

Your manual patterns are **merged with auto-detected patterns**, not replaced:

- ✅ Auto-detected patterns still work
- ✅ Your patterns supplement them
- ✅ No conflict: your patterns take priority if there's overlap
- ✅ Different missions can use different auto-detected patterns

**Example**:

- Mission 1 (aviation): Auto-detects FAA, EASA + your manual patterns for Transport Canada
- Mission 2 (healthcare): Auto-detects FDA, CDC + your manual patterns for patient advocates
- Each mission gets relevant stakeholder categories

### Template File Reference

CConductor provides a comprehensive template with examples:

**Location**: `config/stakeholder-patterns.default.json`

**Includes examples for**:

- **Aviation**: Regional regulators, safety advocates
- **Healthcare**: Medical researchers, patient advocates
- **Technology**: Security researchers, open-source maintainers

**View template**:

```bash
cat config/stakeholder-patterns.default.json
```

The template includes detailed comments explaining each field and best practices.

### Best Practices

**1. Start small**

Don't try to add every possible stakeholder upfront. Start with the uncategorized sources you actually encounter.

**2. Use specific patterns**

❌ Bad: `".gov"` (too broad, matches everything)  
✅ Good: `"tc.gc.ca"` (specific to Transport Canada)

❌ Bad: `"research"` (too generic)  
✅ Good: `"clinical trial"` (specific to medical research)

**3. Include variations**

```json
"keyword_patterns": [
  "Transport Canada",
  "Transports Canada",
  "TC Civil Aviation",
  "TCCA"
]
```

**4. Document your additions**

Add comments (using `"_note"` fields) explaining why you added each category:

```json
{
  "additional_patterns": {
    "regional_regulators": {
      "_note": "Added June 2025 for international aviation compliance research",
      "domain_patterns": ["tc.gc.ca"],
      "keyword_patterns": ["Transport Canada"]
    }
  }
}
```

**5. Test incrementally**

Add 1-2 categories, run a test mission, verify they work, then add more.

**6. Share with your team**

If multiple people research the same domains, share your `stakeholder-patterns.json` file:

```bash
# Commit to team's shared config repository
cp ~/.config/cconductor/stakeholder-patterns.json team-configs/aviation-stakeholders.json
```

### Troubleshooting

**Problem: Patterns not matching**

**Symptoms**:
- Added patterns but uncategorized count didn't decrease
- Expected sources still show up in `samples` array

**Solutions**:

1. **Check pattern syntax**:
   ```bash
   # Validate JSON
   jq empty ~/.config/cconductor/stakeholder-patterns.json
   # Should print nothing if valid, error if invalid
   ```

2. **Check domain pattern specificity**:
   ```bash
   # View source URL from quality gate summary
   cat research-sessions/mission_*/artifacts/quality-gate-summary.json | \
     jq '.uncategorized_sources.samples[0].url'
   
   # Extract domain part manually
   # URL: https://www.example.com/path/to/article
   # Domain to match: "example.com" (without www, protocol, path)
   ```

3. **Check keyword case sensitivity**:
   - Keywords are case-insensitive
   - `"Transport Canada"` matches "transport canada", "TRANSPORT CANADA", etc.

4. **Verify file location**:
   ```bash
   # Check if file exists
   ls -la ~/.config/cconductor/stakeholder-patterns.json
   
   # If missing, copy template again
   cp config/stakeholder-patterns.default.json ~/.config/cconductor/stakeholder-patterns.json
   ```

**Problem: Too many categories**

**Symptoms**:
- Quality gate always fails with "missing critical stakeholder"
- You don't need all these perspectives for your research

**Solution**:

Domain-aware quality only flags **critical** stakeholders as missing. If you're seeing failures, it means the auto-detected heuristics deemed those perspectives critical for your domain.

Options:

1. **Let the orchestrator address gaps**: CConductor will automatically research missing perspectives
2. **Review domain heuristics**: Check `meta/domain-heuristics.json` to see why perspectives were marked critical
3. **Adjust research question**: If your question is too broad, CConductor will require more stakeholder perspectives

**Problem: Patterns work for one mission but not another**

**Cause**: Domain heuristics are mission-specific. Your manual patterns apply to ALL missions, but auto-detected stakeholder categories vary by mission.

**Example**:

- **Mission 1** (aviation safety): Auto-detects "regulators", "manufacturers", "safety_advocates"
  - Your pattern for "regional_regulators" supplements "regulators" category
  
- **Mission 2** (tech security): Auto-detects "vendors", "security_researchers", "users"
  - Your "regional_regulators" pattern doesn't match any category in this mission (correctly ignored)

**This is correct behavior**: Patterns only apply when relevant stakeholder categories exist.

### Advanced: Category Naming

**Important**: Your manual pattern category names should be semantic and clear, but they're merged based on similarity matching.

**Naming tips**:

- Use singular or plural consistently: `"regulators"` not mixing with `"regulator"`
- Use underscores for multi-word: `"safety_advocates"` not `"safety advocates"` or `"SafetyAdvocates"`
- Match auto-detected patterns when possible: Check `meta/domain-heuristics.json` to see what CConductor named the categories

**Example from heuristics**:

```json
{
  "stakeholder_categories": {
    "regulators": { ... },
    "safety_advocates": { ... }
  }
}
```

Your patterns should use same names:

```json
{
  "additional_patterns": {
    "regulators": { ... },        ← Merges with auto-detected "regulators"
    "safety_advocates": { ... }   ← Merges with auto-detected "safety_advocates"
  }
}
```

---

## See Also

- **[User Guide](USER_GUIDE.md)** - Complete CConductor usage
- **[Citations Guide](CITATIONS_GUIDE.md)** - Understanding citations
- **[Configuration Reference](CONFIGURATION_REFERENCE.md)** - All config options
- **[Custom Knowledge](CUSTOM_KNOWLEDGE.md)** - Adding domain expertise

---

**CConductor Quality** - Research you can trust 🎯
