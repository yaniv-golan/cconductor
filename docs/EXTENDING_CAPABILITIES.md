# Extending the Capabilities Taxonomy

## Overview

CConductor's capability taxonomy enables the mission orchestrator to discover and select agents based on what they can do, not just their names. As you build custom agents or need new research types, you can extend the taxonomy.

## Current Taxonomy

**24 capabilities defined in `config/capabilities.json`**:

### Research Types (8)
- `academic_research` - Academic papers and scholarly sources
- `web_research` - General web content research
- `market_sizing` - TAM/SAM/SOM calculations
- `competitive_analysis` - Competitor and landscape analysis
- `legal_research` - Legal documents, regulations, case law
- `customer_research` - Customer needs, behavior, segmentation
- `trend_analysis` - Patterns, forecasting, time-series
- `benchmarking` - Performance comparisons

### Analysis Types (8)
- `fact_checking` - Claim verification and validation
- `tam_validation` - Market size claim validation
- `financial_analysis` - Financial data and business metrics
- `investment_analysis` - Deal analysis, due diligence
- `code_analysis` - Source code and architecture
- `regulatory_analysis` - Compliance, policy impacts
- `risk_assessment` - Risk modeling and scenarios
- `scenario_planning` - Future scenarios, what-if analysis

### Data Processing (3)
- `pdf_analysis` - PDF extraction and analysis
- `data_extraction` - Scraping, parsing structured data
- `synthesis` - Combining findings into reports

### Orchestration (5)
- `mission_planning` - Multi-agent mission planning
- `agent_selection` - Selecting appropriate agents
- `dynamic_orchestration` - Adaptive workflow management
- `decision_logging` - Decision tracking
- `budget_management` - Budget and resource tracking

## When to Add New Capabilities

### Good Reasons ✅
- **Domain expertise**: You're building agents for specialized domains (e.g., biotech, aerospace)
- **Unique analysis type**: New analysis method not covered (e.g., sentiment_analysis, network_analysis)
- **Tool-specific**: Capability tied to specific tools/APIs (e.g., sql_analysis, api_integration)
- **Orchestrator selection**: The orchestrator needs to distinguish between agents for proper selection

### Poor Reasons ❌
- **Implementation detail**: Don't add capabilities for how agents work internally
- **Tool inventory**: Capabilities aren't a list of tools (that's the `tools` field)
- **Over-specification**: Don't create 50 micro-capabilities that overlap
- **Temporary need**: One-off research tasks don't warrant new capabilities

## How to Extend

### 1. Built-in Level (Shared)

Edit `config/capabilities.json`:

```json
{
  "capabilities": [
    {
      "id": "sentiment_analysis",
      "label": "Sentiment Analysis",
      "description": "Analyze sentiment, opinion, and emotional tone in text",
      "synonyms": ["opinion_mining", "emotion_detection", "sentiment_mining"]
    }
  ]
}
```

**Guidelines**:
- Use snake_case for IDs
- Keep descriptions concise and clear
- Add 2-4 synonyms for matching flexibility
- Commit to version control for team sharing

### 2. User-Level (Private)

Currently not supported - capabilities are shared across all users. If you need private capabilities:

**Workaround**: Use existing generic capabilities and specify in agent metadata's `best_used_for` field.

## Capability Design Best Practices

### Good Capability Definition ✅

```json
{
  "id": "patent_research",
  "label": "Patent Research",
  "description": "Search and analyze patents, patent applications, and IP filings",
  "synonyms": ["ip_research", "patent_analysis", "intellectual_property"]
}
```

**Why good**:
- Clear, specific domain
- Actionable description
- Useful synonyms
- Orchestrator can understand when to use it

### Poor Capability Definition ❌

```json
{
  "id": "smart_analysis",
  "label": "Smart Analysis",
  "description": "Does analysis intelligently",
  "synonyms": ["good_research", "quality_work"]
}
```

**Why bad**:
- Vague and meaningless
- Doesn't help orchestrator decide
- Overlaps with everything
- No clear use case

## Updating Agent Metadata

After adding a capability, update relevant agents:

```json
{
  "name": "patent-researcher",
  "capabilities": [
    "patent_research",
    "legal_research",
    "competitive_analysis"
  ]
}
```

The orchestrator can now query: "Which agents can do patent research?"

## Validation

Capabilities are validated on agent registry init:

```bash
# Test validation
export CCONDUCTOR_USER_CONFIG_DIR="$PWD/user-test-config"
./src/cconductor-mission.sh agents list
```

**Warnings indicate**:
- Agent references unknown capability
- Capability not in taxonomy
- Agent should update metadata

## Common Extension Patterns

### Domain-Specific Research

```json
{
  "id": "medical_research",
  "label": "Medical Research",
  "description": "Research clinical trials, medical literature, and healthcare data",
  "synonyms": ["clinical_research", "healthcare_research", "biomedical_research"]
}
```

### Specialized Analysis

```json
{
  "id": "network_analysis",
  "label": "Network Analysis",
  "description": "Analyze networks, relationships, and graph structures",
  "synonyms": ["graph_analysis", "relationship_mapping", "social_network_analysis"]
}
```

### Data Source Integration

```json
{
  "id": "database_research",
  "label": "Database Research",
  "description": "Query and analyze data from databases and structured sources",
  "synonyms": ["sql_research", "database_analysis", "structured_query"]
}
```

### Creative/Generative

```json
{
  "id": "content_generation",
  "label": "Content Generation",
  "description": "Generate reports, summaries, and written content",
  "synonyms": ["report_writing", "content_creation", "documentation"]
}
```

## Migration Strategy

When adding capabilities to the built-in taxonomy:

1. **Add to taxonomy** - Update `config/capabilities.json`
2. **Document in CHANGELOG** - Note new capabilities
3. **Update relevant agents** - Add to built-in agent metadata
4. **Update missions** - Reference in built-in mission profiles
5. **Test discovery** - Verify orchestrator can query

## Versioning

Capabilities follow semantic versioning in `capabilities.json`:

```json
{
  "version": "1.0.0",
  "capabilities": [...]
}
```

- **Major**: Breaking changes (removing capabilities)
- **Minor**: New capabilities added
- **Patch**: Description/synonym improvements

## Future: User Capability Extensions

Planned for future release:

```bash
~/.config/cconductor/capabilities.json  # User extensions
```

Will merge with built-in capabilities, enabling private domain-specific capabilities without forking.

## Questions?

- **"Should I add a capability for X?"** - Ask: Would the orchestrator need to distinguish agents based on X?
- **"My capability overlaps with Y"** - That's okay if they serve different purposes. Use synonyms to link them.
- **"I need 20 new capabilities"** - Consider if you're over-specifying. Start with 3-5 high-level ones.

## Examples in Practice

### Before: Agent selection unclear
```
Orchestrator: "I need to research regulations"
Registry: Returns all agents (unhelpful)
```

### After: Clear capability-based selection
```
Orchestrator: "I need regulatory_analysis capability"
Registry: Returns [legal-researcher, compliance-analyst]
Orchestrator: Selects best fit based on context
```

## Capability vs. Tool

**Common confusion**: Capabilities ≠ Tools

- **Capability**: What the agent can achieve (outcome)
  - Example: `competitive_analysis`
- **Tool**: How the agent works (mechanism)
  - Example: `WebSearch`, `Code`

An agent doing `competitive_analysis` might use `WebSearch` + `Read` + `Code` tools.

## Summary

- **Current**: 24 capabilities cover common research needs
- **Extensible**: Add to `config/capabilities.json` as needed
- **Validated**: Registry warns about unknown capabilities
- **Versioned**: Track changes with semantic versioning
- **Purpose**: Enable orchestrator to match agents to needs

Start with existing capabilities. Extend when orchestrator selection requires it.

