# Mission Profiles

Mission profiles define research objectives, success criteria, and constraints for CConductor's mission-based orchestration system.

## Mission Profile Structure

Each mission profile is a JSON file with the following structure:

```json
{
  "name": "mission-id",
  "description": "Human-readable description",
  "version": "1.0",
  "objective": "Natural language goal statement",
  "success_criteria": {
    "required_outputs": ["output_type", ...],
    "required_validations": ["validation_type", ...],
    "confidence_threshold": 0.85,
    "all_claims_cited": true
  },
  "constraints": {
    "max_iterations": 8,
    "max_time_minutes": 90,
    "max_agent_invocations": 20,
    "budget_usd": 10.0
  },
  "preferred_agents": [
    {"agent": "agent-name", "for": "use case description"}
  ],
  "orchestration_guidance": "Strategic hints for the orchestrator",
  "output_specification": {
    "format": "markdown",
    "structure": "template reference",
    "required_sections": ["section_name", ...]
  },
  "domain_context": {
    "industry": "string",
    "custom_knowledge": ["knowledge-file.md"]
  }
}
```

## Required Fields

- `name`: Unique identifier for the mission
- `description`: Brief description of what this mission does
- `objective`: Clear statement of the mission goal
- `success_criteria.required_outputs`: List of required output types (from `config/output_types.json`)
- `constraints.max_iterations`: Maximum orchestration iterations

## Output Types

Output types should reference IDs from `config/output_types.json`:
- `market_sizing_table`
- `investment_brief`
- `literature_review`
- `competitive_analysis`
- `research_report`
- etc.

## Creating Custom Missions

### Built-in Missions (Shared)
Place in: `config/missions/`
- Generic missions for common research types
- Checked into version control
- Available to all users

### User Missions (Custom)
Place in: `~/.config/cconductor/missions/`
- User-specific or proprietary missions
- Not tracked by git
- Override built-in missions with same name

## Examples

### Academic Research
```json
{
  "name": "academic-research",
  "objective": "Conduct systematic literature review with peer-reviewed sources",
  "success_criteria": {
    "required_outputs": ["literature_review", "citation_network"],
    "confidence_threshold": 0.88,
    "min_peer_reviewed_sources": 10
  }
}
```

### Market Research
```json
{
  "name": "market-research",
  "objective": "Calculate TAM/SAM/SOM and analyze competitive landscape",
  "success_criteria": {
    "required_outputs": ["market_sizing_table", "competitive_analysis"],
    "required_validations": ["tam_validation"]
  }
}
```

## Usage

```bash
# List available missions
cconductor missions list

# Describe a mission
cconductor missions describe academic-research

# Run a mission
cconductor run --mission academic-research --input-dir ~/research/

# Dry-run to validate
cconductor run --mission academic-research --input-dir ~/research/ --dry-run
```

## Best Practices

1. **Clear Objectives**: State what success looks like in natural language
2. **Specific Outputs**: List concrete deliverables, not vague goals
3. **Reasonable Constraints**: Set realistic time/budget limits
4. **Orchestration Guidance**: Provide strategic hints without micromanaging
5. **Domain Context**: Include relevant industry or domain information

## Mission Composition

Missions can reference other missions or build on generic templates. The orchestrator can adapt generic missions based on the specific research context.

