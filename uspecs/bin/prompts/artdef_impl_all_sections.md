# Add implementation plan artifact

## data

- You must include only one of the following artifacts, the first one that matches the change request:
  - Domain specifications section (?specs_maybe)(?!domains_exists)
  - Functional design section (?specs_maybe)(?!fd_exists)
  - Provisioning and configuration section (?!prov_exists)
  - Technical design section (?specs_maybe)(?!td_exists)
  - Construction and Quick start sections (?!constr_exists)

Important: include exactly one implementation artifact from the list above. Use the first one from the list above that matches the change request. Do not combine multiple implementation artifacts.

Reinforcing rule: if the change requires changing project technology, installing software or adding dependencies, then Provisioning and configuration section matches -- even if the change also involves source file changes.
