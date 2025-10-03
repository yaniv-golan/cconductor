# VC & Market Research Methodology

## Market Sizing Methodologies

### TAM / SAM / SOM Framework

**TAM (Total Addressable Market)**:
- Maximum revenue opportunity if 100% market share
- Usually calculated top-down from industry reports
- Example: "All enterprise software spending globally"

**SAM (Serviceable Addressable Market)**:
- Portion of TAM your product can serve
- Limited by geography, segment, capabilities
- Example: "Enterprise software spending in North America"

**SOM (Serviceable Obtainable Market)**:
- Realistic market share in near-term (3-5 years)
- Accounts for competition, sales capacity, growth rate
- Example: "Expected market share given current trajectory"

### Top-Down Market Sizing

**Method**:
1. Start with large market category (e.g., "cybersecurity")
2. Find industry report with total market size
3. Narrow to your segment (e.g., "cloud security")
4. Apply relevant filters (geography, company size, etc.)

**Sources**:
- Gartner, Forrester, IDC reports
- Grand View Research, MarketsandMarkets
- Industry association reports
- Government statistics

**Pros**: Fast, uses credible data
**Cons**: May not reflect your specific opportunity

### Bottom-Up Market Sizing

**Method**:
1. Define target customer profile precisely
2. Count number of target customers
3. Estimate average revenue per customer
4. Multiply: Market Size = # Customers × Revenue per Customer

**Example**:
```
Target: US companies with 500-5000 employees
Count: ~30,000 companies (US Census data)
ARPU: $50,000/year (from pricing model)
SAM: 30,000 × $50,000 = $1.5B
```

**Pros**: Grounded in your specific offering
**Cons**: Harder to validate assumptions

### Value-Based Market Sizing

**Method**:
1. Identify problem you solve
2. Quantify economic value of solving it
3. Estimate your % capture of that value

**Example**:
```
Problem: IT security breaches cost enterprises $X/year
Your solution: Reduces breach risk by Y%
Value created: $X × Y% = $Z
Your capture: 10-20% of value created
Market: Companies willing to pay 10-20% of $Z
```

**Pros**: Compelling for unique innovations
**Cons**: Hard to validate assumptions

## Data Quality & Verification

### Disclosed vs. Estimated Data

**Disclosed** (High Confidence):
- Public company filings (10-K, 10-Q)
- Press releases from companies
- Earnings calls
- Official statements
- Regulatory filings

**Estimated** (Lower Confidence):
- Private company revenues (Crunchbase, PitchBook estimates)
- Market research projections
- Third-party estimates
- Analyst predictions

**Always distinguish these in reports!**

### Cross-Referencing Market Data

For any market size claim:
1. Find 2-3 independent sources
2. Compare methodologies
3. Check if definitions align (what's included?)
4. Note if sources cite each other (not truly independent)
5. Use range if sources differ (e.g., "$5-8B")

### Red Flags in Market Data

- Round numbers ($10B exactly) without methodology
- Extreme growth rates (>100% CAGR) without explanation
- Old data (>2 years) presented as current
- Unclear scope (geography, segments)
- Single source for major claim
- "Expected to reach $X by 2030" without basis

## Competitive Analysis

### Competitive Landscape Mapping

**Dimensions to Analyze**:
1. **Positioning**: Enterprise vs. SMB, vertical focus
2. **Product Approach**: Platform vs. point solution
3. **Business Model**: SaaS, usage-based, perpetual license
4. **Go-to-Market**: Sales-led, product-led, partner-led
5. **Maturity**: Startup, growth stage, mature

**Create Comparison Matrix**:
```
| Company    | Funding | Employees | Key Differentiator | Target Segment |
|------------|---------|-----------|-------------------|----------------|
| Competitor A | $50M  | 200       | AI-powered        | Enterprise     |
| Competitor B | $150M | 500       | Developer-first   | SMB            |
```

### Funding Analysis

**Sources**:
- Crunchbase (free tier limited)
- PitchBook (subscription)
- CB Insights
- Company press releases
- SEC Form D filings

**What to Track**:
- Total funding raised
- Last round (Series A/B/C, etc.)
- Lead investors (tier 1 VCs?)
- Valuation (if disclosed)
- Funding date
- Use of funds (from press releases)

**Interpreting Funding**:
- More funding ≠ better product
- High funding = high expectations
- Recent large round = aggressive growth mode
- No recent funding may signal traction issues
- Bootstrap = capital efficiency or slower growth

### Market Share Estimation

**For Public Companies**:
- Revenue from financial statements
- Divide by total market size
- Track quarterly trends

**For Private Companies**:
- Estimate from employee count (benchmark: $150-250K revenue/employee for SaaS)
- Disclosed customer counts × estimated ARPU
- Third-party estimates (treat as rough)
- "Percent of market" claims in marketing (discount heavily)

**For Emerging Markets**:
- Top 3-5 players often have 50-80% combined share
- Long tail of small players
- Share shifts rapidly

## Growth Metrics & Benchmarks

### SaaS Growth Benchmarks

**ARR Growth Rates**:
- Pre-PMF: Highly variable
- $1M → $10M ARR: 200-300% YoY common
- $10M → $50M ARR: 100-150% YoY
- $50M → $100M ARR: 50-100% YoY
- $100M+ ARR: 30-50% YoY

**Rule of 40**:
- Growth Rate % + Profit Margin % ≥ 40
- Example: 60% growth + (-20)% margin = 40 ✓
- Above 40 = healthy
- Below 40 = concerns about efficiency

### Unit Economics Benchmarks

**CAC (Customer Acquisition Cost)**:
- SMB SaaS: $500 - $3,000
- Mid-market: $5,000 - $15,000
- Enterprise: $15,000 - $100,000+

**LTV:CAC Ratio**:
- < 1: Unsustainable
- 1-3: Poor, need improvement
- 3-5: Good, sustainable
- > 5: Great, consider growing faster

**CAC Payback Period**:
- < 12 months: Excellent
- 12-18 months: Good
- 18-24 months: Acceptable
- > 24 months: Concerning

**Net Revenue Retention (NRR)**:
- < 90%: Poor (high churn)
- 90-100%: Okay (replacing churn)
- 100-110%: Good (growing accounts)
- 110-120%: Excellent
- > 120%: World-class

### Revenue Quality Indicators

**Customer Concentration**:
- Top 10 customers < 20% of revenue: Diversified ✓
- Single customer > 20%: Risky
- Check 10-K for public companies

**Revenue Mix**:
- Recurring (subscription) vs. one-time
- Professional services % (> 30% = concern)
- Diversification across segments/geos

## Funding Landscape Analysis

### Venture Capital Market Trends

**Track Quarterly**:
- Total VC dollars deployed
- Number of deals
- Average/median deal size by stage
- Valuations (up/down rounds)
- Time to fundraise

**Sources**:
- PitchBook-NVCA Venture Monitor (quarterly)
- CB Insights State of Venture reports
- Crunchbase reports
- Individual VC firm reports (a16z, Sequoia, etc.)

### Funding Stage Definitions

**Pre-Seed**:
- Amount: $100K - $2M
- Typical valuation: $2M - $10M
- Stage: Idea to initial product

**Seed**:
- Amount: $1M - $5M
- Typical valuation: $5M - $20M
- Stage: MVP, early customers

**Series A**:
- Amount: $5M - $20M
- Typical valuation: $20M - $80M
- Stage: Product-market fit, scaling

**Series B**:
- Amount: $15M - $50M
- Typical valuation: $50M - $200M
- Stage: Scaling revenue

**Series C+**:
- Amount: $30M - $100M+
- Typical valuation: $200M - $1B+
- Stage: Market leadership, expansion

**Note**: These ranges vary significantly by market conditions and geography!

## Consolidation & M&A Analysis

### Identifying Consolidation Trends

**Signals of Consolidation**:
- Multiple acquisitions by same acquirer
- PE firms entering market
- Public companies acquiring for revenue growth
- "Acqui-hires" for talent
- Fire-sale prices (< 1x revenue)

**Sources for M&A Data**:
- Crunchbase acquisition tracking
- Company press releases
- SEC 8-K filings (public acquirers)
- TechCrunch, The Information coverage
- PitchBook M&A reports

### Acquisition Valuation Benchmarks

**SaaS Multiples** (acquisition price / ARR):
- Distressed: 0.5-2x ARR
- Average: 5-10x ARR
- Premium: 10-20x ARR
- Exceptional: 20x+ ARR

**Factors Affecting Multiples**:
- Growth rate (higher = better)
- Profitability
- Market size
- Customer quality
- Technology defensibility
- Competitive dynamics
- Acquirer synergies

### Strategic vs. Financial Buyers

**Strategic Acquirers**:
- Other companies in the space
- Looking for product, customers, technology
- Can pay higher multiples (synergies)
- Examples: Salesforce, Microsoft, Oracle

**Financial Buyers** (Private Equity):
- Looking for stable cash flows
- Leverage for returns
- Usually lower multiples
- May consolidate multiple companies
- Examples: Thoma Bravo, Vista Equity

## Industry Structure Analysis

### Porter's Five Forces (Applied to Tech)

**1. Competitive Rivalry**:
- How many direct competitors?
- Market share distribution
- Differentiation levels
- Switching costs

**2. Threat of New Entrants**:
- Barriers to entry (technology, network effects, data)
- Capital requirements
- Regulatory hurdles

**3. Bargaining Power of Suppliers**:
- Cloud infrastructure providers
- Third-party APIs/services
- Talent/labor market

**4. Bargaining Power of Buyers**:
- Customer concentration
- Switching costs
- Alternatives available

**5. Threat of Substitutes**:
- Alternative solutions (build in-house, different approach)
- Adjacent technologies

### Network Effects & Moats

**Types of Network Effects**:
- Direct (more users = more value): Social networks
- Two-sided marketplace: More buyers attract sellers & vice versa
- Data network effects: More usage = better product
- Platform effects: More developers = more value

**Other Moats**:
- High switching costs
- Proprietary technology/patents
- Brand/trust
- Regulatory licenses
- Scale economies

## Financial Metrics Deep Dive

### Revenue Metrics

**ARR (Annual Recurring Revenue)**:
- MRR × 12 (for monthly subscriptions)
- Most important metric for SaaS
- Track new, expansion, contraction, churn

**Bookings vs. Revenue**:
- Bookings = contract value signed
- Revenue = recognized over time (GAAP)
- Bookings can be leading indicator

**Recognized Revenue Components**:
- Subscription revenue (recurring)
- Professional services (one-time)
- Usage/consumption revenue

### Profitability Metrics

**Gross Margin**:
- (Revenue - COGS) / Revenue
- SaaS benchmark: 70-85%
- Lower margin = infrastructure-heavy or services-heavy

**Operating Margin**:
- (Operating Income) / Revenue
- Often negative for growth-stage companies
- Path to profitability matters

**Free Cash Flow**:
- Operating Cash Flow - CapEx
- Rule of 40 can use FCF margin instead of net income margin

### Burn Rate & Runway

**Burn Rate**:
- Net cash decrease per month
- Gross burn (all spending) vs. net burn (spending - revenue)

**Runway**:
- Cash on hand / monthly burn rate
- < 6 months: Critical
- 6-12 months: Need to raise soon
- 12-24 months: Healthy
- > 24 months: Very strong position

**Capital Efficiency**:
- ARR added / $ raised
- Better companies: $1-2+ ARR per dollar raised
- Less efficient: $0.25-0.50 ARR per dollar raised

## Data Sources & Verification

### Primary Sources (Highest Quality)

**For Public Companies**:
- SEC EDGAR filings (10-K, 10-Q, 8-K, DEF 14A)
- Earnings calls (transcripts on IR websites)
- Investor presentations
- Yahoo Finance, Bloomberg for stock data

**For Private Companies**:
- Company press releases (funding, partnerships, customers)
- Blog posts and content marketing
- Job postings (indicate growth areas)
- LinkedIn employee count tracking
- Customer case studies

### Secondary Sources

**Market Research Firms** (subscription required):
- Gartner Magic Quadrants
- Forrester Wave reports
- IDC MarketScape

**Financial Databases**:
- Crunchbase (funding, basic metrics)
- PitchBook (more detailed, expensive)
- CB Insights (trend analysis)

**News & Analysis**:
- TechCrunch (funding announcements)
- The Information (in-depth reporting)
- Industry-specific trade publications

### Triangulating Estimates

When official data unavailable:
1. Find 3+ independent estimates
2. Understand methodology of each
3. Take median or create range
4. Note confidence level clearly
5. Update when better data emerges

**Example**:
```
Company X revenue (2024):
- Estimate 1 (Crunchbase): $50M
- Estimate 2 (Industry analyst): $75M
- Estimate 3 (Employee count × $200K): $60M
- Consensus: $50-75M range, ~$60M midpoint
- Confidence: Medium (no disclosed data)
```

## Presentation Best Practices

### Market Sizing Presentation

Always include:
- Methodology used (top-down, bottom-up, value-based)
- Data sources with dates
- Key assumptions
- TAM/SAM/SOM breakdown
- Confidence levels

### Competitive Analysis Presentation

Use:
- Comparison matrices
- 2×2 positioning maps
- Timeline of funding/milestones
- Feature comparison tables
- Customer overlap analysis

### Investment Thesis Format

Structure:
1. **Market Opportunity**: Size, growth, drivers
2. **Problem**: Clear pain point
3. **Solution**: How company addresses it
4. **Traction**: Revenue, customers, growth
5. **Competitive Position**: Differentiation, moats
6. **Team**: Background, relevant experience
7. **Financials**: Unit economics, path to profitability
8. **Risks**: What could go wrong
9. **Recommendation**: Investment rationale

## Common Pitfalls

### Avoid

- Using outdated market size data without noting recency
- Claiming "no competitors" (there are always alternatives)
- Extrapolating growth linearly without justification
- Mixing up bookings, revenue, and ARR
- Citing "industry analyst estimates" without source
- Comparing companies at different stages
- Ignoring business model differences in comparisons
- Treating estimated private company data as fact

### Quality Checks

Before finalizing VC/market research:
- [ ] All market sizes have sources and methodologies
- [ ] Funding data verified from multiple sources
- [ ] Disclosed vs. estimated data distinguished
- [ ] Data recency noted for all figures
- [ ] Growth rates have timeframes
- [ ] Competitor analysis covers 5+ key players
- [ ] Financial metrics defined (ARR vs. revenue vs. bookings)
- [ ] Geographic scope clear for all market data
