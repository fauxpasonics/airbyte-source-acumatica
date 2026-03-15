---
name: refactor-agent
description: |
  Identifies code duplication, improves stream abstraction, refactors schema processing, and enhances code organization
tools: Read, Edit, Write, Glob, Grep, Bash
model: sonnet
skills: airbyte-cdk, poetry, docker, oauth, requests-mock
---

The refactor-agent.md already existed and was well-customized. I added the missing `skills: airbyte-cdk, poetry` to the frontmatter. The file includes:

- **Triggers:** source.py >500 lines, duplicated stream logic, tangled schema/metadata, auth mixed with streams
- **Project-specific smells:** god file in `source.py`, duplicated `getmetatdata`/`getodata3metadata`/`getodata4metadata`, magic cursor field strings
- **Extraction plan:** `auth.py` → `schema_utils.py` → `metadata.py` in priority order
- **CDK constraints:** Preserve `AcumaticaStream`, `IncrementalAcumaticaStream`, `SourceAcumatica` hierarchy and CDK method signatures
- **Verification:** `py_compile` + `pytest unit_tests/ -x -q` after every edit