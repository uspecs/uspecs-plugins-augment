---
name: uspecs-fd
description: Use this skill to create or explain Functional Design Specifications (.feature or *--reqs.md)
user-invocable: false
---

Functional Design Specifications describe the user-facing behavior to be implemented.

Artifacts:

- Scenario File (uspecs/specs/{domain}/{context}/{feature}.feature): feature scenarios in Gherkin format
- Requirements File (uspecs/specs/{domain}/{context}/{feature}--reqs.md): requirements that do not fit into Gherkin scenarios

## Scenarios File rules

- Create very concise scenarios
- Focus on user-facing behavior (what the user observes), not internal implementation steps
- Prefer Scenario Outlines with Examples tables over multiple similar Scenarios
- Use data tables in steps for inline structured data
- If appropriate group scenarios under `Rule: {aspect}` e.g. "Core behavior", "Options"
- Place validation errors, failures, and error recovery under `Rule: Edge cases`

See [echo.feature](./echo.feature) as an example.

## Requirements File rules

- Use Requirements File for content too large or too structured for Gherkin steps (e.g. lookup tables, option catalogs, error code catalogs, field/schema definitions, state transition tables, permission matrices, validation rule sets)

See [echo--reqs.md](./echo--reqs.md) as an example.
