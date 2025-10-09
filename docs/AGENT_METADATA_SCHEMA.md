# Agent Metadata Schema

## Overview

Agent metadata defines an agent's capabilities, tools, inputs/outputs, and other characteristics. This metadata is used by the mission orchestrator for capability-based agent selection.

## Schema

```json
{
  "name": "string (required)",
  "description": "string (required)",
  "capabilities": ["capability_id", ...] (optional),
  "expertise_domains": ["domain", ...] (optional),
  "input_types": ["input_type_id", ...] (optional),
  "output_types": ["output_type_id", ...] (optional),
  "output_schema": {
    "field_name": "required|optional"
  } (optional),
  "can_validate": ["validation_type", ...] (optional),
  "best_used_for": "string" (optional),
  "typical_invocation_pattern": "string" (optional),
  "tools": ["Tool", ...] (required),
  "model": "claude-sonnet-4-5" (required)
}
```

## Required Fields

### name
- **Type**: string
- **Description**: Unique identifier for the agent (must match directory name)
- **Example**: `"market-sizing-expert"`

### description
- **Type**: string
- **Description**: Brief description of what the agent does
- **Example**: `"TAM/SAM/SOM calculation and validation specialist"`

### tools
- **Type**: array of strings
- **Description**: Claude Code tools the agent can use
- **Valid values**: `WebSearch`, `WebFetch`, `Read`, `Write`, `Code`, `Task`
- **Example**: `["WebSearch", "WebFetch", "Read", "Code"]`

### model
- **Type**: string
- **Description**: Claude model to use for this agent
- **Valid values**: `claude-sonnet-4-5`, `claude-opus-4`
- **Example**: `"claude-sonnet-4-5"`

## Optional Fields

### capabilities
- **Type**: array of strings
- **Description**: Capability IDs from `config/capabilities.json`
- **Purpose**: Used by orchestrator for capability-based agent selection
- **Example**: `["market_sizing", "tam_validation", "financial_analysis"]`

### expertise_domains
- **Type**: array of strings
- **Description**: Domains or industries where agent has expertise
- **Example**: `["b2b_saas", "marketplaces", "hardware", "biotech"]`

### input_types
- **Type**: array of strings
- **Description**: Types of inputs the agent can process (from `config/input_types.json`)
- **Example**: `["pitch_deck", "market_claims", "financial_data"]`

### output_types
- **Type**: array of strings
- **Description**: Types of outputs the agent produces (from `config/output_types.json`)
- **Example**: `["market_sizing_table", "validation_report"]`

### output_schema
- **Type**: object
- **Description**: Expected fields in agent's output with required/optional status
- **Example**:
```json
{
  "market_sizing_table": "required",
  "assumptions_list": "required",
  "validation_notes": "optional"
}
```

### can_validate
- **Type**: array of strings
- **Description**: Types of claims or data this agent can validate
- **Example**: `["market_sizing_claims", "growth_projections", "financial_metrics"]`

### best_used_for
- **Type**: string
- **Description**: Natural language description of ideal use cases
- **Example**: `"Independent verification of market size claims before investment analysis"`

### typical_invocation_pattern
- **Type**: string
- **Description**: Typical task description for invoking this agent
- **Example**: `"Validate the TAM/SAM/SOM claims in this startup's pitch deck"`

## Capability Taxonomy

Capabilities should reference IDs from `config/capabilities.json`. Common capabilities include:

- `market_sizing` - Calculate and validate TAM/SAM/SOM
- `academic_research` - Find and analyze academic papers
- `web_research` - General web content research
- `competitive_analysis` - Analyze competitors and landscape
- `fact_checking` - Verify and validate claims
- `synthesis` - Synthesize findings into reports
- `financial_analysis` - Analyze financial data and metrics
- `investment_analysis` - Evaluate investment opportunities

See `config/capabilities.json` for the complete list.

## Input/Output Type Taxonomy

### Input Types (from `config/input_types.json`)
- `pitch_deck` - Startup pitch presentations
- `market_claims` - Claims about market size
- `academic_paper` - Scholarly papers
- `financial_data` - Financial statements/metrics
- `meeting_notes` - Notes from meetings
- `research_question` - Research query/topic

### Output Types (from `config/output_types.json`)
- `market_sizing_table` - TAM/SAM/SOM calculations
- `investment_brief` - Investment analysis with recommendation
- `literature_review` - Academic literature review
- `competitive_analysis` - Competitive landscape analysis
- `validation_report` - Claim validation report
- `research_report` - General research findings

See respective JSON files for complete lists.

## Location

### Project Agents
- **Path**: `src/claude-runtime/agents/<agent-name>/metadata.json`
- **Tracked**: Yes (git)
- **Scope**: Available to all users

### User Agents
- **Path**: `~/.config/cconductor/agents/<agent-name>/metadata.json`
- **Tracked**: No (private)
- **Scope**: User-specific
- **Priority**: Overrides project agents with same name

## Validation

Agent metadata is validated on registry initialization:

1. **JSON validity**: Must be valid JSON
2. **Required fields**: All required fields must be present
3. **Name matching**: `name` field must match directory name
4. **Capability validation**: Capabilities must exist in taxonomy
5. **Input/output validation**: Types should exist in taxonomies (warnings if missing)

Invalid agents are skipped with warnings logged.

## Example: Market Sizing Expert

```json
{
  "name": "market-sizing-expert",
  "description": "TAM/SAM/SOM calculation and validation specialist with code-based calculations",
  "capabilities": [
    "market_sizing",
    "tam_validation",
    "financial_analysis"
  ],
  "expertise_domains": [
    "b2b_saas",
    "marketplaces",
    "hardware",
    "biotech"
  ],
  "input_types": [
    "pitch_deck",
    "market_claims",
    "preliminary_research"
  ],
  "output_types": [
    "market_sizing_table",
    "validation_report"
  ],
  "output_schema": {
    "market_sizing_table": "required",
    "assumptions_list": "required",
    "validation_notes": "optional",
    "methodology_description": "required"
  },
  "can_validate": [
    "market_sizing_claims",
    "growth_projections"
  ],
  "best_used_for": "Independent validation of market size claims before investment analysis",
  "typical_invocation_pattern": "Validate TAM/SAM/SOM claims in pitch deck and provide independent bottom-up calculations",
  "tools": [
    "WebSearch",
    "WebFetch",
    "Read",
    "Code"
  ],
  "model": "claude-sonnet-4-5"
}
```

## Best Practices

1. **Be Specific**: Use precise capability IDs, not vague descriptions
2. **Complete Metadata**: Fill in optional fields for better orchestrator matching
3. **Validate Taxonomies**: Ensure capabilities/types exist in taxonomy files
4. **Update When Changing**: Keep metadata in sync with agent prompt changes
5. **Document Use Cases**: `best_used_for` helps orchestrator make good choices
6. **Test Selection**: Verify orchestrator selects your agent for intended use cases

## Testing

```bash
# List all agents (validates metadata)
cconductor agents list

# Describe specific agent
cconductor agents describe market-sizing-expert

# Query by capability
# (Internal: agent_registry_query_capabilities "market_sizing")
```

## Migration from Old Format

If you have existing agents without extended metadata:

1. Add `capabilities` array based on agent's purpose
2. Add `input_types` and `output_types` arrays
3. Optionally add `output_schema`, `can_validate`, `best_used_for`
4. Agents continue working; orchestrator just won't select them optimally

Minimal working metadata only needs: `name`, `description`, `tools`, `model`.

