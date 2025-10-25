# Research Quality Framework

CConductor systematically assesses and communicates research quality across all domains using universal dimensions.

## Universal Quality Dimensions

Every research finding has boundaries. When analyzing sources, systematically assess:

### Source Constraints
- **What was examined?** What data, documents, code, or populations were studied?
- **What was excluded?** What sources were unavailable, out of scope, or filtered?
- **Access limitations:** Paywalls, restricted data, missing documentation?

### Temporal Boundaries  
- **When current?** Publication date, data collection period, version/release?
- **Snapshot vs trend?** Single point in time or longitudinal tracking?
- **Time sensitivity:** Does this change rapidly or remain stable?

### Scope Limitations
- **Population/sample:** Who/what was studied? Who/what was excluded?
- **Context specificity:** Domain, geography, environment, conditions?
- **Breadth vs depth:** Comprehensive survey or deep dive on subset?

### Magnitude vs Existence
- **Effect exists?** Is there a relationship, difference, or pattern?
- **Effect size:** How large is it? (percentages, coefficients, fold-changes)
- **Practical importance:** Large enough to matter in real-world decisions?

### Alternative Explanations
- **Confounders:** What other factors could produce the same pattern?
- **Correlation vs causation:** Established mechanism or just association?
- **Competing hypotheses:** What alternative explanations exist?

### Measurement Quality
- **How measured?** Instruments, methods, proxies, self-report?
- **Measurement sensitivity:** Can it detect the phenomenon adequately?
- **Distribution issues:** Range restriction, ceiling/floor effects, clustering?

### Generalizability Boundaries
- **Where applies:** Contexts where findings clearly transfer?
- **Where uncertain:** Extrapolations beyond the data?
- **Where doesn't apply:** Known exceptions or contradictions?

### Subgroup & Heterogeneity
- **Participant heterogeneity:** Are different types pooled together?
- **Subgroups analyzed:** Were key subgroups examined separately?
- **Sample sizes per subgroup:** Adequate power for subgroup comparisons?
- **Effect heterogeneity:** Do effects differ meaningfully across subgroups?
- **Generalizability by subgroup:** Which subgroups were/weren't examined?

## Why This Matters

Findings without context can mislead:

- **Scientific Research:**
  - **Without context:** "35-45% of autistic mothers have bonding difficulties"
  - **With context:** "Most autistic mothers had low bonding difficulty scores in one cross-sectional study at 1 month postpartum (N=2,692, general population with trait measures, not clinical diagnosis)"

- **Market Research:**
  - **Without context:** "Market is $50B"
  - **With context:** "North American SMB segment estimated at $50B by analysts (Q4 2024); enterprise excluded; disclosed data not available"

- **Technical Research:**
  - **Without context:** "V2.0 is faster"
  - **With context:** "V2.0 shows 15% improvement on synthetic benchmarks in cloud environment; real-world usage not tested; on-premise deployments excluded"

## How Agents Use This

Every research agent extracts:

1. **Source constraints** - what was/wasn't examined
2. **Temporal scope** - when current, time period
3. **Population/sample boundaries** - who/what included/excluded
4. **Magnitude** - effect sizes, not just significance
5. **Alternative explanations** - confounders, other factors
6. **Measurement quality** - how assessed, limitations
7. **Subgroup analyses** - which subgroups examined, effect heterogeneity
8. **Generalizability** - where applies vs uncertain

Synthesis agent integrates these into final reports using domain-appropriate language.

## Domain-Specific Application

### Scientific Research

Context elements to emphasize:
- Study design (cross-sectional, longitudinal, RCT, meta-analysis)
- Time points when measurements were taken
- Population type (clinical diagnosis vs trait measures, general vs clinical sample)
- Effect sizes with interpretation (small/medium/large, clinical relevance)
- Confounders and alternative explanations
- Subgroup analyses and effect heterogeneity
- Generalizability limits

### Market Research

Context elements to emphasize:
- Data provenance (disclosed, estimated, or projected)
- Temporal scope (historical, current, or forecasted)
- Geographic and segment boundaries
- Data collection methodology
- Alternative explanations for trends

### Technical Research

Context elements to emphasize:
- Version/release information
- Deployment context and environment
- Completeness (production vs examples vs tests)
- Known limitations and constraints
- Performance characteristics and applicability

## Benefits

1. **Prevents Misinterpretation:** Users understand the boundaries of findings
2. **Enables Critical Evaluation:** Clear context allows users to assess applicability
3. **Supports Decision-Making:** Magnitude and scope information inform real-world decisions
4. **Maintains Transparency:** Limitations are visible, not hidden
5. **Improves Reproducibility:** Clear documentation of constraints aids replication

## Implementation

This framework is implemented through:

1. **Knowledge Base:** Universal dimensions defined in `knowledge-base/research-methodology.md`
2. **Agent Prompts:** All research agents instructed to extract context systematically
3. **Output Schemas:** `source_context` field in agent output captures dimensions
4. **Synthesis Integration:** Synthesis agent uses context to write nuanced reports

## Best Practices

When using CConductor for research:

1. **Review limitations sections** in reports carefully
2. **Pay attention to scope qualifiers** (time periods, populations, contexts)
3. **Consider magnitude** alongside statistical significance
4. **Note alternative explanations** when evaluating causality
5. **Check generalizability boundaries** before applying findings to new contexts

## Confidence Metric Precedence

CConductor maintains two confidence indicators for claims:

### Agent Confidence (Research Phase)
- **Field**: `.confidence` (0-1 scale)
- **Source**: Research agents during discovery
- **Represents**: Agent's subjective belief in claim validity
- **Available**: Immediately when claim is added

### Gate Trust Score (Audit Phase)
- **Field**: `confidence_surface.trust_score` (0-1 scale) in quality gate reports
- **Field**: `quality_gate_assessment.trust_score` (0-1 scale) when stored in knowledge graph
- **Source**: Quality gate hook after research completes
- **Represents**: Objective computation from source quality, independence, recency
- **Available**: After quality gate runs

### For End Users (Reports)
**Precedence**:
1. **Primary**: Use `confidence_surface.trust_score` (from quality gate) if present
2. **Fallback**: Use `.confidence` (from agent) if gate assessment unavailable
3. **Discrepancies**: Note when agent confidence and gate trust differ significantly (>0.2)

**Example**: "This claim has high agent confidence (0.95) but was flagged by quality gate (trust score 0.42) due to single-source limitation."

### For Agents (Research/Synthesis)
- **During research**: Use `.confidence` (gate hasn't run yet)
- **During synthesis**: Prefer `confidence_surface.trust_score` from quality gate reports
- **Highlight conflicts**: When high agent confidence meets low gate trust, investigate why

### Implementation
- Synthesis agent system prompt enforces precedence (v0.4.0+)
- Render fallback ensures visibility in reports (v0.4.0+)
- Gate trust score is objective, agent confidence is subjective—both have value
- Quality gate results stored in `artifacts/quality-gate.json`
- Optional KG integration stores as `quality_gate_assessment` field

## Future Enhancements

Planned improvements to the framework:

- Automated detection of missing context information
- Quality scoring based on completeness of contextual information
- Visual indicators for scope boundaries in reports
- Cross-domain consistency validation
- Machine-readable metadata for automated analysis

