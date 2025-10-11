# Scientific Research Methodology

## Study Design Hierarchy

### Evidence Strength (Strongest to Weakest)

1. **Systematic Reviews & Meta-Analyses**
   - Synthesize multiple studies
   - Statistical aggregation of results
   - Highest level of evidence
   - Look for Cochrane reviews

2. **Randomized Controlled Trials (RCTs)**
   - Gold standard for causation
   - Random assignment to treatment/control
   - Blinded when possible
   - Check sample size adequacy

3. **Cohort Studies**
   - Follow groups over time
   - Can show temporal relationships
   - Watch for confounding variables
   - Useful when RCTs unethical

4. **Case-Control Studies**
   - Compare groups with/without outcome
   - Retrospective analysis
   - Useful for rare conditions
   - Prone to recall bias

5. **Cross-Sectional Studies**
   - Snapshot at one point in time
   - Cannot establish causation
   - Good for prevalence data
   - Limited inferential power

6. **Case Reports & Case Series**
   - Individual or small group observations
   - Hypothesis-generating
   - Cannot generalize
   - Lowest evidence level

## Defining Leading Studies

A "**leading study**" is one that provides the strongest, most reliable evidence for a specific claim. When citing evidence, prioritize studies that satisfy most of these criteria:

### Core Criteria

**1. High Level of Evidence**
- **Preferred**: Systematic reviews/meta-analyses (≥5 studies aggregated)
- **Strong**: Large RCTs with pre-registration, or large prospective cohorts
- **Domain-Specific**: 
  - Computer Science: Top-tier conference/journal papers with reproducibility artifacts
  - Economics: RCTs or strong quasi-experimental designs
  - Clinical: Phase III trials registered on ClinicalTrials.gov

**2. Methodological Rigor**
- Pre-registered analysis plans (when applicable)
- Appropriate controls and blinding
- Validated measurement instruments
- Confounders identified and addressed
- Statistical methods clearly justified
- Limitations transparently discussed
- Low risk of bias assessment

**3. Scale & Statistical Power**
- Adequate sample size for field (typically n≥100, or multicenter/population-based)
- Meta-analyses: Include heterogeneity analysis and publication bias assessment
- Effect sizes reported with confidence intervals
- Sufficient power to detect meaningful effects

**4. Publication Quality & Recognition**
- Published in high-impact journals (IF >10) or premier field-specific venues
- Peer-reviewed (not just preprints, unless explicitly noted)
- Highly cited relative to age (>100 citations for papers >2 years old)
- Referenced in subsequent systematic reviews or clinical guidelines
- Indexed in major databases (PubMed, Web of Science, Scopus)

**5. Replication & Convergence**
- Findings independently replicated by other research groups
- Consistent with multiple high-quality studies
- Aligns with established mechanisms or theoretical frameworks
- Part of a converging body of evidence

**6. Recency & Relevance**
- Current for fast-moving fields (within 2-5 years)
- Directly addresses the specific population, outcome, timing, and context of the claim
- Not superseded by more recent, higher-quality research

**7. Transparency & Low Bias Risk**
- Conflicts of interest disclosed
- Data and/or code available (or strong reproducibility signals)
- Funding sources transparent
- Results don't obviously favor funders
- No retractions or major corrections

### Domain-Specific Considerations

**Emerging Topics**:
- Recent preprints from top research groups may be "provisional leading studies"
- Must be explicitly flagged as "not yet peer-reviewed"
- Prefer those with multiple independent replications

**Rare Diseases / Low-Data Domains**:
- Best-available evidence may be high-quality case series or multicenter registries
- Judge relative to field norms, not absolute criteria
- Explicitly note limited evidence base

**Definitive Null Results**:
- High-quality studies showing no effect or small effects are also "leading studies"
- Important for establishing boundaries and preventing overstatement
- Must be adequately powered to detect meaningful effects

### Practical Selection Guide

When identifying leading studies for research reports:

1. **First Choice**: Recent systematic review or meta-analysis from Cochrane or comparable source
2. **Second Choice**: Multiple (≥2) independent high-quality primary studies showing consistent results
3. **Third Choice**: Single landmark study if it's large, rigorous, and widely cited
4. **Context-Dependent**: Best available evidence with explicit caveats about limitations

**Red Flags** (studies that are NOT leading):
- Single small pilot studies
- Industry-funded studies without independent replication
- High risk of bias on quality assessments
- Cannot access full methodology
- Contradicted by subsequent higher-quality research

## Statistical Significance vs. Practical Significance

### Understanding P-Values

**P-value < 0.05**:
- Conventionally "statistically significant"
- Does NOT mean result is large or important
- Can be significant with tiny effects if sample size is huge
- Can miss real effects if sample size is small

**What to check**:
- Effect size (Cohen's d, odds ratio, etc.)
- Confidence intervals
- Clinical/practical significance
- Multiple comparison corrections

### Common Statistical Pitfalls

1. **P-Hacking**
   - Testing multiple hypotheses until finding p<0.05
   - Check if analysis plan was pre-registered
   - Look for suspiciously perfect p-values (p=0.049)

2. **HARKing** (Hypothesizing After Results Known)
   - Presenting post-hoc findings as planned
   - Red flag: no pre-registration
   - Reduces replicability

3. **Correlation ≠ Causation**
   - Always distinguish these clearly
   - Consider confounders
   - Look for mechanistic explanation

## Peer Review Assessment

### Publication Types

**Peer-Reviewed Journals**:
- Multiple expert reviewers
- Editorial oversight
- Higher credibility
- Check journal impact factor

**Preprint Servers** (arXiv, bioRxiv, medRxiv):
- NOT peer-reviewed
- Faster dissemination
- Useful for cutting-edge work
- Lower credibility
- May have errors
- Flag clearly as preprint

**Conference Proceedings**:
- Variable peer review rigor
- Check conference reputation
- Often preliminary work
- May be superseded by journal version

### Journal Quality Indicators

**High Quality**:
- Impact Factor > 10 (in most fields)
- Published by major societies (Nature, Science, Cell, NEJM)
- Rigorous peer review process
- High rejection rates

**Predatory Journals** (Avoid):
- Pay-to-publish with no real peer review
- Suspicious email solicitations
- Poor English on journal website
- Not indexed in PubMed/Web of Science
- Check Beall's List

## Evaluating Research Quality

### Methodology Checklist

**For Experiments**:
- [ ] Clear hypothesis stated?
- [ ] Adequate sample size (power analysis)?
- [ ] Appropriate control groups?
- [ ] Randomization used?
- [ ] Blinding (single/double)?
- [ ] Statistical methods appropriate?
- [ ] Confounders addressed?

**For Surveys**:
- [ ] Representative sample?
- [ ] Response rate adequate (>60%)?
- [ ] Validated questionnaires?
- [ ] Bias assessment (selection, response)?
- [ ] Appropriate statistical analysis?

**For Meta-Analyses**:
- [ ] Comprehensive literature search?
- [ ] Clear inclusion/exclusion criteria?
- [ ] Publication bias assessed?
- [ ] Heterogeneity examined?
- [ ] Quality assessment of included studies?

### Red Flags in Papers

- Small sample sizes (n<30 without justification)
- Missing standard deviations or confidence intervals
- Cherry-picked data presentation
- Conflicts of interest not disclosed
- No discussion of limitations
- Results too good to be true
- Figures that don't match text
- Data unavailable upon request

## Understanding Research Findings

### Sample Size Matters

**Underpowered Studies** (too small):
- May miss real effects (Type II error)
- Estimates will be imprecise
- Wide confidence intervals
- Less reproducible

**Overpowered Studies** (huge sample):
- May find statistically significant but tiny effects
- Check effect size, not just p-value
- Consider practical significance

### Effect Sizes

**Small Effects**:
- Cohen's d ≈ 0.2
- Odds ratio ≈ 1.5
- r² ≈ 0.01
- May not be practically meaningful

**Medium Effects**:
- Cohen's d ≈ 0.5
- Odds ratio ≈ 2.5
- r² ≈ 0.06
- Moderately important

**Large Effects**:
- Cohen's d ≈ 0.8
- Odds ratio ≈ 4.0
- r² ≈ 0.14
- Highly important if real

## Reproducibility & Replication

### Replication Crisis

Many published findings don't replicate, especially in:
- Psychology
- Social sciences
- Preclinical biomedical research

**What increases confidence**:
- Pre-registered studies
- Open data and code
- Independent replications
- Large sample sizes
- Simple, robust designs

### Checking for Replication

When evaluating a finding:
1. Has it been replicated independently?
2. Is the effect consistent across studies?
3. Is there a mechanistic explanation?
4. Are there null results that aren't published?

## Citation Network Analysis

### Following Citations

**Forward Citations** (who cites this paper):
- Check Google Scholar "Cited by"
- Shows impact and reception
- Look for critiques or rebuttals

**Backward Citations** (what this paper cites):
- Review original sources
- Check if citations support claims
- Follow trail to seminal papers

### Citation Red Flags

- Self-citations dominate
- Cited by predatory journals only
- Citation count manipulated
- Misrepresented cited papers

## Field-Specific Considerations

### Biomedical Research

**Animal Studies**:
- Don't directly translate to humans
- Check species used
- Note ethical approval

**Clinical Trials**:
- Check ClinicalTrials.gov registration
- Phase I/II/III/IV have different purposes
- Industry-sponsored: watch for bias

**Genetic Studies**:
- Genome-wide significance: p < 5×10⁻⁸
- Replication essential
- Functional validation needed

### Physics & Mathematics

**Theoretical Papers**:
- Proofs should be verifiable
- Check for experimental validation
- Note if purely theoretical

**Experimental Physics**:
- Sigma levels (3σ = evidence, 5σ = discovery)
- Independent experiment confirmation
- Check detector calibration

### Computer Science

**Machine Learning Papers**:
- Check if baselines are strong
- Code availability
- Multiple datasets tested
- Ablation studies performed

**Systems Papers**:
- Reproducibility artifacts
- Open-source implementation
- Real-world evaluation vs. synthetic

## Conflicts of Interest

### Types of Conflicts

**Financial**:
- Industry funding
- Stock ownership
- Consulting fees
- Patents

**Non-Financial**:
- Personal relationships
- Academic competition
- Career advancement

### How to Handle

- Disclosed conflicts: note but don't automatically dismiss
- Undisclosed conflicts: major red flag
- Look for independent confirmation
- Check if results favor funder

## Retractions & Corrections

### Checking for Retractions

Use:
- Retraction Watch database
- PubMed links
- Journal websites

**Why papers get retracted**:
- Fraud/fabrication
- Honest errors
- Plagiarism
- Ethical violations

**Important**: Retracted papers still get cited!

## Assessing Consensus

### Finding Scientific Consensus

1. **Look for Review Papers**
   - Summarize field state
   - Written by experts
   - Note areas of agreement/disagreement

2. **Check Multiple Sources**
   - Don't rely on single study
   - Look for consistent patterns
   - Note sample size of literature

3. **Assess Controversy Level**
   - Settled science vs. active debate
   - Mainstream vs. fringe views
   - Evolution of understanding over time

### Presenting Uncertainty

Be clear about:
- What's established vs. speculative
- Where experts disagree
- What's unknown
- Confidence levels in claims

## Research Ethics Considerations

### What to Note

- IRB/Ethics board approval
- Informed consent procedures
- Data privacy protections
- Ethical treatment (animals, humans)
- Conflicts disclosed
- Data sharing policies

### Problematic Research

Flag or avoid research that:
- Lacks ethical approval
- Uses unethical methods
- Violates privacy
- Has undisclosed conflicts
- Data fabrication suspected
