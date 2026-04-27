---
name: uspecs-td
description: Use this skill when authoring or reviewing a Technical Design Specification - any `tech.md`, `arch.md`, `arch-{subsystem}.md`, or `*--td.md` file under `uspecs/specs/`. Covers Domain Technology, Domain Architecture, Domain Subsystem Architecture, Context Architecture, Context Subsystem Architecture, and Feature Technical Design.
user-invocable: false
---

Technical Design Specifications describe how functionality is to be implemented.

<!-- // TODO Same text as in artdef_impl_td.md -->

Artifact types:

- Domain Technology (`uspecs/specs/{domain}/tech.md`) - tech stack, architecture patterns, UI/UX guidelines
- Domain Architecture (`uspecs/specs/{domain}/arch.md`)
- Domain Subsystem Architecture (`uspecs/specs/{domain}/arch-{subsystem}.md`)
- Context Technology (`uspecs/specs/{domain}/{context}/tech.md`)
- Context Architecture (`uspecs/specs/{domain}/{context}/arch.md`)
- Context Subsystem Architecture (`uspecs/specs/{domain}/{context}/arch-{subsystem}.md`)
- Feature Technical Design (`uspecs/specs/{domain}/{context}/{feature}--td.md`)

## Structure

- Technology: [example-tech.md](./struct-tech.md) - tech stack, architecture patterns, UI/UX guidelines (same structure for domain and context levels)
- Architecture: [example-arch.md](./struct-arch.md) - key components, key flows, key data models (same structure for domain, context, or subsystem level)
- Feature TD: [example-td.md](./struct-td.md) - feature-scoped technical design with UI components