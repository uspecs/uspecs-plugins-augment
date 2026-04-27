---
name: uspecs-sec-constr
description: Use this skill when authoring or reviewing the `## Construction` or `## Quick start` section in `change.md` or `impl.md` under a Change Folder.
user-invocable: false
---

## Construction section

Section contains to-do items for modifying source files, tests, scripts, documentation, or any non-specification, non-configuration files and optionally a Quick start section for user-facing changes.

Use when: the change involves source files, tests, scripts, documentation, or any non-specification, non-configuration files.

Do not use when: the change only involves specifications or provisioning/configuration.

## Rules

- For `create` action use multiple subitems explaining what the new file should contain:
  - Purpose of the file
  - Key functions, classes, or components to include
  - Test cases or scenarios to cover
- For `update` action use subitems describing each change
- Optional grouping: when items span 3+ distinct dependency categories, group under `###` headers ordered by dependency (foundational first, dependent after)
- Tests
  - If not specified otherwise (prompt, skills, etc.), include test file items when explicitly requested or implied by the codebase's established patterns
  - Tests first: always place test file items before all implementation items — when using `###` grouping headers, put tests in a leading `### Tests` group before all other groups
- Optionally add a `## Quick start` section after Construction when the change introduces new features, APIs, CLI commands, or configuration that users need to learn. Skip for internal refactoring, bug fixes, or changes with no user-facing impact.

## Example

````markdown
## Construction

- [ ] update: [run-tests.py](../../../tests/run-tests.py)
  - add: `--timeout` flag to limit per-test execution time
  - update: `run_single_test` to enforce timeout and return failure on expiry
- [ ] create: [auth/oauth_provider.go](../../../internal/auth/oauth_provider.go)
  - OAuth2 provider abstraction with token refresh
  - Interface: `OAuthProvider` with `Authenticate`, `Refresh`, `Revoke` methods
  - Default implementation for Google OAuth2
````
