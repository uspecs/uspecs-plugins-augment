---
name: uspecs-sec-domains
description: Use this skill when authoring or reviewing the `## Domain specifications` section in `change.md` or `impl.md` under a Change Folder.
user-invocable: false
---

## Domain specifications section

Section contains to-do items for modifying Domain Specifications under `uspecs/specs/`:

- Domain Specification: `uspecs/specs/{domain}/domain.md`

Use when:

- Change request modifies an existing domain (actors, concepts, contexts)
- Change request explicitly requires creating new domain specifications or deriving domain specifications from codebase

Do not use when: the change only adds features, scenarios, or implementation details within an already-defined domain.

## Rules

- Follow the to-do list format: relative paths from the change file to the target, specific action verbs (create, update, add, fix, remove, rename, move, etc.)
- For `update` action use subitems describing each change
- For `create` action use a single subitem with specification type and brief domain purpose

## Example

```markdown
## Domain specifications

- [ ] create: [softeng/domain.md](../../specs/prod/softeng/domain.md)
  - Domain Specification for software engineering workflow: actors, core concepts, contexts
- [ ] update: [payments/domain.md](../../specs/prod/payments/domain.md)
  - add: "Refund" concept with lifecycle and authorization rules
  - update: "Checkout" context to reference the new Refund concept
```
