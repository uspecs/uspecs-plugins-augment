---
description: Start a new change (uchange). User provides a description of the change request.
---

# uchange

Parse user input as `[options] {description}`:

- Determine `kebab-name` from {description}: kebab-case, max 40 chars (ideal 15-30), descriptive, safe to use as a git branch name
- If {description} contains a URL, add `--issue-url {URL}` option
- If the user asks to derive specifications from the codebase, add `--specs` option
- Identify the root directory of the plugin (PLUGIN_ROOT) and run `bash {PLUGIN_ROOT}/bin/softeng.sh action uchange --kebab-name <kebab-name> [options]` and follow the instructions in the output how to process {description}
  - Do not pass {description} verbatim to the command

Options: `--kebab-name <name>` (required), `--no-impl`, `--branch`, `--no-branch`, `--issue-url <url>`, `--specs`
