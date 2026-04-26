# Domain: Development and operations

## System

Tools, scripts, and configuration files to assist with development, testing, deployment, and operations.

## External actors

Roles:

- 👤Developer
  - Modifies codebase
- 👤Maintainer
  - Makes releases

Systems:

- ⚙️GitHub
  - A platform that allows to store, manage, share code and automate related workflows

---

## Contexts

### dev

Development, testing, and release automation.

Relationships:

```mermaid
graph
  dev["📦dev"]
  Developer["👤Developer"]
  Maintainer["👤Maintainer"]
  GitHub["⚙️GitHub"]
  dev -->|development tooling and workflows| Developer
  dev -->|test tooling and workflows| Developer
  dev -->|release management tooling and workflows| Maintainer
  GitHub -->|repository hosting| dev
  GitHub -->|CI/CD automation| dev
```

### ops

Production operations, monitoring, and incident response.

---

## Context map

```mermaid
graph LR
  dev["📦dev"]
  ops["📦ops"]
  dev -->|deployment automation and tooling| ops
```
