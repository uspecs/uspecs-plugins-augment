---
name: uspecs-sec-td
description: Use this skill when authoring or reviewing the `## Technical design` section in `change.md` or `impl.md` under a Change Folder.
user-invocable: false
---

## Technical design section

Section contains to-do items for modifying technical specification files under `uspecs/specs/`:

- Domain Technology: `uspecs/specs/{domain}/tech.md`
- Domain Architecture: `uspecs/specs/{domain}/arch.md`
- Domain Subsystem Architecture: `uspecs/specs/{domain}/arch-{subsystem}.md`
- Context Technology: `uspecs/specs/{domain}/{context}/tech.md`
- Context Architecture: `uspecs/specs/{domain}/{context}/arch.md`
- Context Subsystem Architecture: `uspecs/specs/{domain}/{context}/arch-{subsystem}.md`
- Feature Technical Design: `uspecs/specs/{domain}/{context}/{feature}--td.md`

Use when:

- Change request modifies existing technical specifications (e.g. updating architecture or technology details)
- Change request explicitly requires creating new technical specifications or deriving technical specifications from codebase

Do not use when: the change affects only functional specifications, provisioning/configuration, or source code with no impact on architectural or technical design documentation.

## Rules

- Follow the to-do list format: relative paths from the change file to the target, specific action verbs (create, update, add, fix, remove, rename, move, etc.)
- For `update` action use subitems describing each change
- For `create` action use a single subitem with specification type and brief purpose

## Example

```markdown
## Technical design

- [ ] update: [softeng/arch.md](../../specs/prod/softeng/arch.md)
  - update: dispatch section to document uchange/uimpl action flow
  - add: new section on error handling and retry strategy
  
- [ ] create: [payments/checkout--td.md](../../specs/prod/payments/checkout--td.md)
  - Feature Technical Design: token handling, PSP integration, error recovery strategy
```
