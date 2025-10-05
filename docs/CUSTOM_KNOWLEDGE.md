# Adding Custom Knowledge to CConductor

**Teach CConductor about your domain without coding**

**Version**: 0.1.0  
**Last Updated**: October 2025  
**For**: Everyone - no coding required!

---

## Table of Contents

1. [Introduction](#introduction)
2. [Quick Start](#quick-start)
3. [Complete Examples](#complete-examples)
4. [File Structure Template](#file-structure-template)
5. [Where to Put Files](#where-to-put-files)
6. [Best Practices](#best-practices)
7. [Testing Your Knowledge](#testing-your-knowledge)
8. [Advanced Topics](#advanced-topics)
9. [Troubleshooting](#troubleshooting)

---

## Introduction

CConductor can use your own domain expertise to improve research results. No coding required - just create simple text files!

**What is custom knowledge?**

- Domain expertise you add to CConductor
- Information CConductor wouldn't know otherwise
- Company-specific information
- Regional or specialized knowledge
- Internal terminology and frameworks

**Use cases**:

- Your company's products and services
- Regional market information
- Specialized industry knowledge
- Internal terminology and processes
- Proprietary frameworks or methods
- Domain-specific best practices

**How it works**:

1. Create markdown files (`.md`) in your knowledge directory
   - **macOS**: `~/Library/Application Support/CConductor/knowledge-base-custom/`
   - **Linux**: `~/.local/share/cconductor/knowledge-base-custom/`
2. Write your knowledge in simple structured format
3. CConductor automatically discovers and uses it
4. No configuration or code changes needed!

---

## Quick Start

Get started in 5 minutes:

### 1. Create Your File

**Find your knowledge directory first**:

```bash
# Get the path to your knowledge directory
KNOWLEDGE_DIR=$(./src/utils/path-resolver.sh resolve knowledge_base_custom_dir)
echo $KNOWLEDGE_DIR
```

**Then create your file**:

```bash
# macOS
nano ~/Library/Application\ Support/CConductor/knowledge-base-custom/my-company.md
# or
open -a TextEdit ~/Library/Application\ Support/CConductor/knowledge-base-custom/my-company.md

# Linux
nano ~/.local/share/cconductor/knowledge-base-custom/my-company.md
# or
gedit ~/.local/share/cconductor/knowledge-base-custom/my-company.md
```

### 2. Add Your Knowledge

Use this simple template:

```markdown
## Overview
Brief description of what this knowledge covers.

## Key Concepts
- Term 1: Clear definition
- Term 2: Clear definition
- Term 3: Clear definition

## Important Facts
- Specific fact with numbers/dates
- Another important fact
- Key information CConductor should know

## Sources
- Where to find authoritative information
- Links to documentation
```

### 3. Save and Use

Save the file, then run research:

```bash
./cconductor "question related to your domain"
```

**That's it!** CConductor automatically finds and uses your knowledge.

---

## Complete Examples

### Example 1: Company Products

**File**: `knowledge-base-custom/acme-products.md`

```markdown
## Overview
ACME Corp product line, market positioning, and competitive landscape
for business and market research.

## Product Portfolio

### ACME Widget Pro
- **Type**: Enterprise SaaS solution
- **Pricing**: $999/month (annual contract)
- **Target**: Companies with 500+ employees
- **Customers**: 500+ enterprise clients
- **Key Features**: AI-powered automation, 99.9% uptime SLA, 24/7 support
- **Launched**: March 2018

### ACME Widget Lite
- **Type**: SMB solution
- **Pricing**: $99/month (monthly or annual)
- **Target**: Small to medium businesses (10-500 employees)
- **Customers**: 2,000+ SMB clients
- **Key Features**: Essential features, 99.5% uptime, email support
- **Launched**: September 2019

### ACME API Platform
- **Type**: Developer platform
- **Pricing**: Usage-based ($0.01 per API call, first 10,000 free)
- **Target**: Developers and technical teams
- **Customers**: 5,000+ developers
- **Key Features**: RESTful API, webhooks, extensive documentation
- **Launched**: June 2022

## Market Position

### Target Market
- **Primary**: Mid-market B2B SaaS (50-5000 employees)
- **Industries**: Technology, Finance, Healthcare, E-commerce
- **Geography**: North America (primary), expanding to EMEA in 2024
- **Market Segment**: Widget automation and management

### Competitive Landscape
- **Main Competitors**: WidgetCo, FastWidget, EnterpriseWidgets
- **Market Position**: #3 in market share (12%), #1 in customer satisfaction
- **Differentiation**: Only provider with native AI integration

## Key Differentiators

1. **AI Integration**: Machine learning-powered automation (patent pending)
2. **Uptime**: 99.9% SLA for Enterprise (industry avg: 99.5%)
3. **Support**: 24/7 support included in all plans (competitors charge extra)
4. **Integrations**: 50+ native integrations (competitors: 20-30)
5. **Security**: SOC 2 Type II, GDPR compliant, ISO 27001

## Customer Profile

### Typical Enterprise Customer
- **Company Size**: 500-5000 employees
- **Industry**: Tech, Finance, Healthcare
- **Pain Point**: Manual widget management costing 20+ hours/week
- **Decision Makers**: CTO, VP Engineering, Director of Operations
- **Sales Cycle**: 60-90 days average
- **Annual Contract Value**: $12,000-$50,000

### Typical SMB Customer
- **Company Size**: 10-200 employees
- **Industry**: Any, especially tech startups
- **Pain Point**: Need affordable widget solution
- **Decision Makers**: Founder, Operations Manager
- **Sales Cycle**: 7-14 days average
- **Annual Contract Value**: $1,200-$5,000

## Company Information

### Basic Facts
- **Founded**: January 2015
- **Headquarters**: San Francisco, California
- **Employees**: 250+ (as of 2024)
- **Funding**: Series C, $50M raised (May 2023)
- **Investors**: Sequoia Capital, Andreessen Horowitz, FirstMark Capital

### Financial Metrics (Public Information)
- **Revenue (2023)**: $25M (announced in press release)
- **Growth Rate**: 150% YoY (2022-2023)
- **Customers**: 2,500+ total
- **Retention Rate**: 95% (industry-leading)

### Key Milestones
- **2015**: Company founded, seed funding ($2M)
- **2016**: Product launched, first 100 customers
- **2018**: Series A ($10M), Enterprise tier launched
- **2020**: Series B ($20M), reached profitability
- **2022**: API platform launched, 1,000+ customers
- **2023**: Series C ($50M), expansion to EMEA announced
- **2024**: 2,500+ customers, SOC 2 Type II certified

## Sources

### Official Sources
- **Company Website**: https://acmecorp.com
- **Product Documentation**: https://docs.acmecorp.com
- **Blog**: https://blog.acmecorp.com
- **Status Page**: https://status.acmecorp.com

### Press & News
- **Press Releases**: https://acmecorp.com/press
- **TechCrunch Coverage**: Search "ACME Corp TechCrunch"
- **Funding Announcements**: Crunchbase.com/organization/acme-corp

### Contact
- **Sales**: sales@acmecorp.com
- **Support**: support@acmecorp.com
- **Press**: press@acmecorp.com

## Research Tips

### When Researching ACME
- Always specify which product (Pro, Lite, or API)
- Distinguish between SMB and Enterprise features
- Check dates - features and pricing have evolved
- For competitive analysis, compare with WidgetCo, FastWidget, EnterpriseWidgets
- For market research, focus on mid-market B2B SaaS segment

### Common Misconceptions
- ACME Widget is NOT a consumer product (it's B2B only)
- Enterprise tier is different from Pro tier (don't confuse)
- ACME does NOT offer on-premise deployment (cloud only)
- API platform is separate product, not included in Widget tiers
```

**Now when you research**:

```bash
./cconductor "ACME Widget competitive analysis"
./cconductor "ACME Corp market position in widget automation"
./cconductor "Compare ACME Widget Pro vs FastWidget Enterprise"
```

CConductor knows all about ACME products, pricing, customers, and competitive positioning!

---

### Example 2: Healthcare Domain

**File**: `knowledge-base-custom/healthcare-us.md`

```markdown
## Overview
Healthcare policy and regulatory knowledge for US market research,
focusing on Medicare, Medicaid, ACA, and HIPAA regulations.

## Key Concepts

### Medicare
- **Type**: Federal health insurance program
- **Eligibility**: Age 65+ OR certain disabilities OR End-Stage Renal Disease
- **Parts**: A (Hospital), B (Medical), C (Medicare Advantage), D (Prescription)
- **Enrollment**: Initial enrollment period around 65th birthday
- **Coverage**: ~64 million Americans (2024)

### Medicaid
- **Type**: Federal-state health program
- **Eligibility**: Low-income individuals and families
- **Variation**: Each state sets own eligibility and benefits
- **Expansion**: Under ACA, 40 states have expanded Medicaid (as of 2024)
- **Coverage**: ~85 million Americans (2024)

### ACA (Affordable Care Act)
- **Also Known As**: "Obamacare" (same thing, different names)
- **Enacted**: March 23, 2010
- **Key Provisions**: Individual mandate (ended 2019), Medicaid expansion, insurance marketplaces
- **Marketplaces**: HealthCare.gov (federal) and state exchanges
- **Open Enrollment**: November 1 - January 15 annually

### HIPAA
- **Full Name**: Health Insurance Portability and Accountability Act
- **Purpose**: Protect patient health information privacy
- **Applies To**: Covered entities (healthcare providers, insurers, clearinghouses)
- **Key Rules**: Privacy Rule, Security Rule, Breach Notification Rule
- **Penalties**: Up to $1.5M per violation category per year

## Important Facts

### Medicare Facts
- Medicare Part A is premium-free for most (if worked 10+ years)
- Medicare Part B has monthly premium (standard $174.70 in 2024)
- Medicare Part D covers prescription drugs (added in 2006)
- Medicare Advantage (Part C) is private insurance alternative
- Open enrollment: October 15 - December 7 annually

### Medicaid Facts  
- Medicaid is funded jointly by federal and state governments
- Eligibility varies by state (no national standard)
- Some states have work requirements (controversial)
- Medicaid expansion raised income threshold to 138% of poverty level
- 10 states have not expanded Medicaid (as of 2024)

### Healthcare Costs
- Average health insurance premium (2024): $8,000/year individual, $23,000/year family
- Average deductible (2024): $1,700 individual, $3,500 family
- Out-of-pocket maximum (ACA): $9,450 individual, $18,900 family (2024)
- Prescription drug costs: Significant concern, varies widely

## Data Sources

### Official Government
- **CMS.gov**: Centers for Medicare & Medicaid Services (authoritative data)
- **HealthCare.gov**: ACA marketplace and information
- **HHS.gov**: Department of Health and Human Services
- **Medicare.gov**: Official Medicare information

### Research & Analysis
- **KFF.org**: Kaiser Family Foundation (excellent healthcare policy analysis)
- **HealthAffairs.org**: Peer-reviewed health policy journal
- **NEJM.org**: New England Journal of Medicine (clinical and policy)

### Data & Statistics
- **CMS Data Navigator**: Medicare/Medicaid enrollment and spending data
- **Census Bureau**: Health insurance coverage statistics
- **NCHS**: National Center for Health Statistics

## Common Misconceptions

### Medicare Misconceptions
- ❌ "Medicare is free" → Correct: Part A is often free, but B/D have premiums
- ❌ "Medicare covers everything" → Correct: Has gaps (dental, vision, long-term care)
- ❌ "Medicare and Medicaid are the same" → Correct: Completely different programs

### ACA Misconceptions
- ❌ "ACA and Obamacare are different" → Correct: Same thing, different names
- ❌ "ACA is just for poor people" → Correct: Available to anyone, subsidies based on income
- ❌ "Individual mandate still exists" → Correct: Federal penalty ended in 2019 (some states have own)

### Medicaid Misconceptions
- ❌ "Medicaid is same in all states" → Correct: Varies significantly by state
- ❌ "Medicaid is only for unemployed" → Correct: Many working people qualify
- ❌ "All states expanded Medicaid" → Correct: 10 states have not (as of 2024)

## Research Tips

### For Medicaid Research
- **Always specify state** - Medicaid varies dramatically by state
- Check expansion status - 40 expanded, 10 have not
- Distinguish between traditional and expanded Medicaid
- Income thresholds differ by state

### For Medicare Research
- Specify which Part (A, B, C, or D)
- Check the year - rules and premiums change annually
- Distinguish between Original Medicare and Medicare Advantage
- Note open enrollment periods

### For ACA Research
- Use "ACA" or "Affordable Care Act" (not "Obamacare" for professional research)
- Check if discussing federal or state marketplace
- Note year - ACA has been modified since 2010
- Distinguish between exchange plans and Medicaid expansion

### For Cost Research
- Always specify year (healthcare costs change rapidly)
- Note whether discussing premiums, deductibles, or out-of-pocket
- Distinguish between individual and family coverage
- Check if employer-sponsored or individual market

## Regional Variations

### States Without Medicaid Expansion (as of 2024)
- Alabama, Florida, Georgia, Kansas, Mississippi, South Carolina, Tennessee, Texas, Wisconsin, Wyoming
- These states have more restrictive Medicaid eligibility
- Low-income gap: too much income for traditional Medicaid, not enough for ACA subsidies

### State Marketplaces vs Federal
- **State-run**: California (Covered CA), New York, Massachusetts, etc.
- **Federal (HealthCare.gov)**: Most states
- **State-Federal Partnership**: Some states
- Enrollment periods and plans may vary

## Updates & Changes

### Recent Changes (2023-2024)
- Inflation Reduction Act (2022): Extended ACA subsidies through 2025
- Medicaid continuous enrollment ended (post-COVID)
- Medicare negotiating drug prices (first time, limited)
- No surprises Act: Protects against surprise medical bills

### Pending Changes
- ACA subsidy extension beyond 2025 uncertain (requires legislation)
- Medicaid work requirements being debated
- Drug price negotiations expanding
- Medicare coverage gaps being discussed
```

---

### Example 3: Regional Market Knowledge

**File**: `knowledge-base-custom/pacific-northwest-market.md`

```markdown
## Overview
Pacific Northwest regional market knowledge for business research
and market analysis (Washington, Oregon, British Columbia).

## Major Cities & Markets

### Seattle, Washington
- **Population**: 750,000 city / 4 million metro (2024)
- **Economy**: Tech hub, aerospace, maritime, healthcare
- **Key Companies**: Amazon HQ, Microsoft (nearby), Boeing, Starbucks, Costco
- **Tech Scene**: 2nd largest tech hub in US (after SF Bay Area)
- **Median Income**: $105,000 household (2024)
- **Cost of Living**: High (20% above national average)

### Portland, Oregon
- **Population**: 650,000 city / 2.5 million metro (2024)
- **Economy**: Tech, creative industries, outdoor recreation, manufacturing
- **Key Companies**: Nike, Intel, Columbia Sportswear, Adidas North America
- **Tech Scene**: Silicon Forest, strong startup ecosystem
- **Median Income**: $85,000 household (2024)
- **Cost of Living**: Moderate-high (10% above national average)
- **Notable**: No sales tax in Oregon

### Vancouver, BC
- **Population**: 670,000 city / 2.6 million metro (2024)
- **Economy**: International gateway, film production, tech, natural resources
- **Key Companies**: Lululemon, EA Vancouver, Microsoft Vancouver
- **Tech Scene**: Growing tech hub, strong gaming industry
- **Notable**: Different country (Canada), different regulations
- **Cost of Living**: Very high (among most expensive in North America)

## Key Industries

### Technology
- **Major Players**: Amazon, Microsoft, Google, Meta (all have large presences)
- **Startups**: Thriving startup ecosystem, strong VC presence
- **Focus Areas**: Cloud computing, AI/ML, e-commerce, enterprise software
- **Employment**: 350,000+ tech workers across region
- **Salaries**: Competitive with SF Bay Area, lower cost of living

### Aerospace
- **Dominant**: Boeing (Seattle area)
- **Supply Chain**: Extensive aerospace supplier ecosystem
- **Space**: Blue Origin, SpaceX, numerous space startups
- **Employment**: 100,000+ aerospace workers

### Outdoor Recreation Industry
- **Major Brands**: REI (Seattle), Columbia (Portland), Nike (Portland), Arc'teryx (Vancouver)
- **Market**: $10B+ regional industry
- **Culture**: Region's outdoor lifestyle drives innovation
- **Growing**: E-bikes, sustainable gear, tech-enabled equipment

### Maritime & Logistics
- **Port of Seattle**: Major container port, cruise terminal
- **Port of Portland**: River port, shipping
- **Port of Vancouver**: Largest port in Canada
- **Industry**: Shipping, logistics, marine technology

## Economic Characteristics

### Regional Economy
- **GDP**: ~$500B combined (2024)
- **Growth**: Above national average (3-4% annually)
- **Unemployment**: Generally below national average
- **Income Inequality**: High, especially in Seattle

### Tax Environment
- **Washington**: No state income tax, sales tax ~10%
- **Oregon**: No sales tax, state income tax up to 9.9%
- **British Columbia**: Provincial income tax + GST/PST
- **Notable**: Tax differences drive cross-border shopping and employment decisions

### Cost of Living
- **Housing**: Expensive, especially Seattle and Vancouver
- **Median Home Price (2024)**: Seattle $850K, Portland $550K, Vancouver $1.2M
- **Rent**: High in urban cores, more affordable in suburbs
- **Overall**: 10-30% above US national average (except Vancouver, higher)

## Demographics

### Population Characteristics
- **Education**: Highly educated (40%+ with bachelor's degrees)
- **Age**: Younger than national average, median age 35-38
- **Diversity**: Increasing, especially Asian and Hispanic populations
- **Migration**: Positive migration until 2022, slowing in 2023-2024

### Culture & Lifestyle
- **Environmentally Conscious**: Strong green/sustainability culture
- **Outdoor Recreation**: Hiking, skiing, cycling extremely popular
- **Coffee Culture**: Birthplace of Starbucks, strong coffee scene
- **Tech-Savvy**: Early adopters, high technology penetration
- **Political**: Generally progressive (especially urban areas)

## Business Environment

### Startup Ecosystem
- **VC Availability**: Strong VC presence, but smaller than SF/NYC
- **Accelerators**: Techstars, Y Combinator presence, local accelerators
- **Success Stories**: Amazon, Microsoft, Costco, Starbucks (historical), many recent unicorns
- **Focus**: Enterprise SaaS, AI/ML, clean tech, outdoor tech

### Corporate Environment
- **Headquarters**: Many Fortune 500 and major tech companies based here
- **Satellite Offices**: Most major tech companies have significant presence
- **Remote Work**: Very high adoption (post-COVID shift)
- **Recruiting**: Competitive talent market

### Regulatory Environment
- **Business-Friendly**: Generally supportive of business (especially WA)
- **Labor**: Strong labor protections, $15+ minimum wage
- **Environmental**: Strict environmental regulations (especially OR, BC)
- **Privacy**: Washington has strong privacy law (WPA)

## Market Opportunities

### Growing Sectors
- **Clean Tech**: Strong government support, cultural fit
- **AI/ML**: Major research institutions, tech talent
- **Healthcare Tech**: Major healthcare systems, aging population
- **Outdoor Tech**: Perfect market for testing/adoption
- **Remote Work Tools**: High remote work adoption

### Challenges
- **Housing Costs**: Limiting growth and talent attraction
- **Homelessness**: Significant issue, especially Seattle/Portland
- **Income Inequality**: Growing concern
- **Traffic/Transit**: Infrastructure challenges
- **Weather**: Rain 6-8 months impacts some sectors

## Research Tips

### For Market Research
- Distinguish WA vs OR (different tax structures significant for retail)
- Include or exclude BC depending on question (different country)
- Consider weather impact (seasonal patterns differ from national)
- Note tech industry dominance in economic data
- Account for high cost of living in consumer spending analysis

### For Competitive Analysis
- Strong local brand loyalty (support local businesses)
- Environmental credentials important
- Tech-savvy early adopters (good test market)
- Income levels support premium pricing
- Outdoor lifestyle influences product design

### For Talent/HR Research
- Very competitive tech talent market
- High salaries necessary (especially Seattle)
- Strong preference for remote/flexible work
- Environmental/social responsibility important to talent
- Quality of life (outdoor access) major draw

## Data Sources
- **Puget Sound Business Journal**: Local business news
- **Portland Business Journal**: Oregon business news
- **Seattle Times, Oregonian**: Regional news
- **WA Employment Security Dept**: Employment data
- **OR Employment Dept**: Oregon employment data
- **Statistics Canada**: BC data
```

---

## File Structure Template

Use this template for any domain:

```markdown
## Overview
[2-3 sentences: What this knowledge covers and when to use it]

## Key Concepts
[Define important terms and concepts]
- **Term 1**: Clear, specific definition
- **Term 2**: Clear, specific definition
- **Term 3**: Clear, specific definition
[5-20 terms recommended]

## Important Facts
[Facts that are often needed in research]
- Specific fact with numbers/dates
- Another important fact
- Key data points
[10-30 facts recommended]

## Data Sources
[Where to find authoritative information]
- **Source 1**: Description and URL
- **Source 2**: Description and URL
- **Source 3**: Description and URL
[3-10 sources recommended]

## Common Misconceptions
[Things often misunderstood]
- ❌ Misconception → ✅ Correct information
- ❌ Misconception → ✅ Correct information
[3-10 misconceptions if applicable]

## Research Tips
[How to research this domain effectively]
- Tip for accurate research
- What to specify or clarify
- What to watch out for
[3-10 tips recommended]

## Regional/Contextual Variations
[If applicable: how things differ by region, time, or context]
[Optional section]

## Updates & Changes
[Recent or upcoming changes to be aware of]
[Optional section, especially for rapidly changing fields]

## Related Topics
[Connected areas to explore]
- Related topic 1
- Related topic 2
[Optional section]
```

**Tips for writing**:

- Be concise (1-3 sentences per point)
- Use plain language (avoid jargon unless defining it)
- Include dates for time-sensitive info
- Link to authoritative sources
- Use specific numbers and data
- Update regularly (add date in overview)

---

## Where to Put Files

### For Permanent Knowledge

**Locations** (OS-appropriate):

- **macOS**: `~/Library/Application Support/CConductor/knowledge-base-custom/`
- **Linux**: `~/.local/share/cconductor/knowledge-base-custom/`

**Find your exact path**:

```bash
./src/utils/path-resolver.sh resolve knowledge_base_custom_dir
```

**Structure**:

```bash
knowledge-base-custom/
  my-company.md
  my-industry.md
  regional-info.md
  technical-domain.md
```

**Automatic discovery**: CConductor finds all `.md` files in this directory

### Organizing Your Knowledge

**By domain**:

```bash
# In your knowledge-base-custom directory:
knowledge-base-custom/
  healthcare/
    medicare.md
    medicaid.md
    hipaa.md
  finance/
    regulations.md
    markets.md
  technology/
    cloud-platforms.md
    security-standards.md
```

**By project**:

```bash
knowledge-base-custom/
  project-alpha.md
  q4-analysis.md
  competitor-research.md
```

**By region**:

```bash
knowledge-base-custom/
  regions/
    north-america.md
    emea.md
    apac.md
```

**Any organization works** - CConductor searches all subdirectories automatically!

**Tip**: Use the full path when creating directories:

```bash
# macOS
mkdir -p ~/Library/Application\ Support/CConductor/knowledge-base-custom/healthcare/

# Linux
mkdir -p ~/.local/share/cconductor/knowledge-base-custom/healthcare/
```

---

## Best Practices

### Writing Effective Knowledge

#### Do's ✅

**Be specific with facts**:

- ✅ "Founded in January 2015, raised $50M Series C in May 2023"
- ❌ "Recently founded, well-funded"

**Include real numbers**:

- ✅ "99.9% uptime SLA, $999/month, 500+ enterprise customers"
- ❌ "Very reliable, premium pricing, many customers"

**Cite your sources**:

- ✅ "According to Q3 2024 earnings call, revenue was $25M"
- ❌ "Revenue is high"

**Add dates to everything**:

- ✅ "As of 2024, market size is $10B growing at 15% CAGR"
- ❌ "Current market size is $10B"

**Define your terms**:

- ✅ "TAM (Total Addressable Market): The total market demand for a product"
- ❌ Using "TAM" without explanation

**Use clear structure**:

```markdown
## Section Title
### Subsection
- **Bold Term**: Definition or value
- Specific fact with context
```

#### Don'ts ❌

**Too vague**:

- ❌ "Popular product in the industry"
- ✅ "#3 in market share (12%), 2,500+ customers"

**Too broad**:

- ❌ Single file covering "Everything about technology"
- ✅ Focused files on specific topics

**Out of date**:

- ❌ Statistics from 2019 without noting the year
- ✅ "As of 2024..." or "(2024 data)" for everything

**No sources**:

- ❌ Unverifiable claims with no attribution
- ✅ Links to official sources, documentation, press releases

**Too long**:

- ❌ Novel-length files (>1000 lines)
- ✅ Focused, scannable files (100-500 lines)

**Full of opinions**:

- ❌ "Best product ever" or "Terrible competitor"
- ✅ "Market leader with 30% share" or "#1 in customer satisfaction (G2 rating 4.8/5)"

### Quality Checklist

Before saving your knowledge file:

- [ ] Overview clearly states what and when
- [ ] Terms are defined, not just listed
- [ ] Facts are specific with numbers
- [ ] Dates included for time-sensitive info
- [ ] Sources cited with URLs
- [ ] Language is simple and clear
- [ ] Sections are organized logically
- [ ] File name is descriptive
- [ ] Updated date noted (if time-sensitive)

---

## Testing Your Knowledge

### Quick Test

After creating your knowledge file:

```bash
# 1. Create the file (use your OS-specific path)
# macOS:
nano ~/Library/Application\ Support/CConductor/knowledge-base-custom/test-domain.md
# Linux:
# nano ~/.local/share/cconductor/knowledge-base-custom/test-domain.md

# 2. Run test research
./cconductor "question about your domain"

# 3. Check if knowledge was used
./cconductor latest
```

### What to Look For

In your research report:

✅ **Good signs**:

- Terms from your file are used correctly
- Facts from your file appear in findings
- Numbers and dates match what you provided
- Sources you listed are referenced
- Context is accurate

❌ **Problems**:

- Your knowledge doesn't appear
- Information is incorrect or outdated
- Terms are misused
- Context is wrong

### Troubleshooting Knowledge Not Appearing

**Problem**: Your knowledge doesn't show up in research.

**Check**:

1. **File is in right place**:

   ```bash
   # macOS
   ls ~/Library/Application\ Support/CConductor/knowledge-base-custom/
   # Should show your-file.md
   
   # Linux
   ls ~/.local/share/cconductor/knowledge-base-custom/
   ```

2. **File ends in .md**:

   ```bash
   # Use your OS-specific path
   # macOS: ls ~/Library/Application\ Support/CConductor/knowledge-base-custom/*.md
   # Linux: ls ~/.local/share/cconductor/knowledge-base-custom/*.md
   ```

3. **Markdown is valid**:
   - Check for syntax errors
   - Ensure headers use `##` format
   - Lists use `-` or `*`

4. **Question relates to your domain**:
   - Must actually ask about topics in your knowledge
   - Try more specific question
   - Mention key terms from your file

5. **File isn't empty**:

   ```bash
   # Use your OS-specific path
   # macOS: wc -l ~/Library/Application\ Support/CConductor/knowledge-base-custom/your-file.md
   # Linux: wc -l ~/.local/share/cconductor/knowledge-base-custom/your-file.md
   # Should show line count > 0
   ```

---

## Advanced Topics

### Multiple Knowledge Files

CConductor uses **all** files in `knowledge-base-custom/`:

- They work together harmoniously
- No conflicts if domains are separate
- Related knowledge reinforces itself
- Organize by topic for clarity

**Example** (in your OS-specific knowledge directory):

```bash
knowledge-base-custom/
  company-products.md     # Your products
  competitors.md          # Competitor info
  market-data.md          # Market statistics
  industry-terms.md       # Terminology
```

All four files are used together during research!

**Full paths**:

- **macOS**: `~/Library/Application Support/CConductor/knowledge-base-custom/*.md`
- **Linux**: `~/.local/share/cconductor/knowledge-base-custom/*.md`

### Knowledge Prioritization

When multiple files have information, CConductor prioritizes:

1. **More specific** over more general
2. **More recent** over older (if dates provided)
3. **Better sourced** over unsourced
4. **More detailed** over vague

**Tip**: Include dates to help CConductor prefer newer information.

### Updating Knowledge

Just edit and save - that's it!

```bash
# Edit existing knowledge (use your OS-specific path)
# macOS:
nano ~/Library/Application\ Support/CConductor/knowledge-base-custom/my-file.md
# Linux:
# nano ~/.local/share/cconductor/knowledge-base-custom/my-file.md

# Make changes, add new facts, update dates
# Save

# Next research automatically uses updated version
./cconductor "question"
```

**Best practice**: Add an "Last Updated" date in your overview.

### Removing Knowledge

Simply delete or move the file (use your OS-specific path):

```bash
# macOS - Remove knowledge
rm ~/Library/Application\ Support/CConductor/knowledge-base-custom/old-knowledge.md

# Or move to archive
mkdir -p ~/cconductor-knowledge-archive/
mv ~/Library/Application\ Support/CConductor/knowledge-base-custom/old-knowledge.md ~/cconductor-knowledge-archive/

# Linux - Remove knowledge
# rm ~/.local/share/cconductor/knowledge-base-custom/old-knowledge.md
```

### Version Controlling Knowledge

You can use git to track changes in your knowledge directory:

```bash
# macOS
cd ~/Library/Application\ Support/CConductor/knowledge-base-custom/
# Linux
# cd ~/.local/share/cconductor/knowledge-base-custom/

git init
git add *.md
git commit -m "Initial knowledge base"

# After updates
git add -u
git commit -m "Updated company information"
```

**Note**: Your knowledge directory is separate from the CConductor project, so you can version control it independently.

---

## Troubleshooting

### Knowledge Seems Wrong

**Problem**: CConductor uses your knowledge incorrectly.

**Solutions**:

1. **Review your definitions**:
   - Are they clear and specific?
   - Any ambiguous terms?
   - Check for typos

2. **Check for contradictions**:
   - Do different sections conflict?
   - Are numbers consistent?
   - Dates match up?

3. **Verify facts are current**:
   - Add "(as of 2024)" to time-sensitive info
   - Update old statistics
   - Remove outdated information

4. **Make relationships clear**:
   - Explicitly state connections
   - Don't assume CConductor will infer
   - Be direct

### Multiple Files Conflict

**Problem**: Two knowledge files have conflicting information.

**CConductor's behavior**:

- Uses more specific information
- Prefers more recent (if dates provided)
- May note contradiction in report

**Solutions**:

1. **Add dates** to help CConductor prefer newer:

   ```markdown
   ## Product Pricing (Updated October 2024)
   - Enterprise: $999/month (increased from $899 in January 2024)
   ```

2. **Remove outdated file**:

   ```bash
   mv knowledge-base-custom/old-info.md knowledge-base-custom-archive/
   ```

3. **Consolidate related files**:
   - Merge into single authoritative file
   - Remove contradictions
   - Keep most current

### Knowledge Not Specific Enough

**Problem**: CConductor doesn't use your knowledge when you expect.

**Solution**: Make your knowledge more specific and detailed.

**Before** (too vague):

```markdown
## Products
- Widget Pro: Enterprise product
- Widget Lite: Small business product
```

**After** (specific):

```markdown
## Products

### Widget Pro
- **Target**: Enterprises with 500+ employees
- **Pricing**: $999/month annual contract
- **Use Case**: Large-scale widget automation across departments
- **Key Features**: Advanced analytics, API access, dedicated support
- **Customers**: 500+ including Fortune 500 companies

### Widget Lite  
- **Target**: Small businesses 10-200 employees
- **Pricing**: $99/month monthly or annual
- **Use Case**: Basic widget management for single team
- **Key Features**: Core features, email support
- **Customers**: 2,000+ SMBs
```

The specific version gives CConductor much more to work with!

---

## Examples Library

### Built-in Examples

See CConductor's built-in knowledge for examples:

```bash
ls knowledge-base/

# Files include:
# - research-methodology.md
# - scientific-methodology.md
# - vc-methodology.md
# - verified-sources.md
```

These are great templates to learn from!

### Community Examples

(Future: Link to community knowledge repository)

---

## See Also

- **[User Guide](USER_GUIDE.md)** - Complete CConductor usage
- **[Quick Reference](QUICK_REFERENCE.md)** - Command cheat sheet
- **[Security Guide](SECURITY_GUIDE.md)** - Keeping research secure

---

**Happy knowledge building!** 📖
