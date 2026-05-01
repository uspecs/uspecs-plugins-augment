---
name: uspecs-sec-fd
description: Use this skill when authoring or reviewing the `## Functional design` section in `change.md` or `impl.md` under a Change Folder.
user-invocable: false
---

## Functional design section

Section contains to-do items for modifying functional specification files under `uspecs/specs/`:

- Feature Specification: `uspecs/specs/{domain}/{context}/{feature}.feature`
- Requirements Specification: `uspecs/specs/{domain}/{context}/{feature}--reqs.md`

Use when:

- Change request modifies existing functional specifications (e.g. adding/removing scenarios)
- Change request explicitly requires creating new functional specifications or deriving functional specifications from codebase

Do not use when: the change affects only internal system behavior with no impact on what external actors observe.

## Rules

- Follow the to-do list format: relative paths from the change file to the target, specific action verbs (create, update, add, fix, remove, rename, move, etc.)
- For `update` action use subitems describing each change
- For `create` action use a single subitem with specification type and brief purpose

## Example

```markdown
## Functional design

- [ ] update: [softeng/upr.feature](../../specs/prod/softeng/upr.feature)
  - update: "PR creation is opened in the browser" scenario -> PR is created programmatically via gh CLI
  - add: scenario for PR URL displayed after successful merge
  
- [ ] create: [payments/checkout.feature](../../specs/prod/payments/checkout.feature)
  - Feature specification with scenarios for card and wallet payments
```  
