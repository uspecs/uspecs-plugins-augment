---
name: uspecs-sec-prov
description: Use this skill to create or explain Provisioning and configuration section items in implementation plans (impl.md, change.md)
user-invocable: false
---

## Provisioning and configuration section

Section contains to-do items for modifying infrastructure, dependencies, and configuration files.

Use when: the change involves installing software, adding dependencies, setting up infrastructure, or modifying configuration files (package.json, tsconfig.json, .env, CI configs, etc.)

Do not use when: the change only involves code changes (new/modified source files, tests, specs) with no provisioning or configuration.

## Rules

- Always prefer CLI commands over manual edits
- Make sure required components are not already installed
- Specify latest possible stable version, always use web search to find it
- Detect current OS - provide OS-specific instructions only
- Group by category
- Prefer vendor-independent alternatives when available

## Example

```markdown
## Provisioning and configuration

- [ ] install: Go 1.23+
  - `winget install GoLang.Go` or https://go.dev/dl/
- [ ] install: golangci-lint 1.61+
  - `go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.61.0`
- [ ] update: [package.json](../../../package.json): add TypeScript 5.6+ as dev dependency
  - `npm install --save-dev typescript@^5.6`
- [ ] update: [.github/workflows/ci.yml](../../../.github/workflows/ci.yml): add `golangci-lint` step after existing `go test` step (manual edit - no CLI available)
```
