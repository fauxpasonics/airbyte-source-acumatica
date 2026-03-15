---
name: poetry
description: |
  Manages project dependencies, lockfiles, and virtual environments for Python projects.
  Use when: adding/removing/updating dependencies, running the connector CLI, managing dev vs runtime deps, debugging version conflicts, or setting up the project for the first time.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Poetry

Python package manager for the source-acumatica connector. Handles dependency isolation, lockfile management, and the `source-acumatica` CLI entrypoint.

## Quick Start

```bash
# Install all deps including dev tools
poetry install --with dev

# Run the connector CLI
poetry run source-acumatica spec
poetry run source-acumatica check --config secrets/config.json
poetry run source-acumatica discover --config secrets/config.json
poetry run source-acumatica read --config secrets/config.json --catalog sample_files/configured_catalog.json

# Run tests
poetry run pytest unit_tests/
poetry run pytest integration_tests/
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| Runtime deps | `[tool.poetry.dependencies]` | `airbyte-cdk = "^0"` |
| Dev deps | `[tool.poetry.group.dev.dependencies]` | `pytest = "*"` |
| CLI entrypoint | `[tool.poetry.scripts]` | `source-acumatica = "source_acumatica.run:run"` |
| Lockfile | `poetry.lock` | Commit this — never edit manually |

## Common Patterns

### Add a dependency

```bash
# Runtime dependency
poetry add requests

# Dev-only dependency
poetry add --group dev pytest-cov
```

### Update a single package

```bash
poetry update airbyte-cdk
poetry run pytest unit_tests/  # verify nothing broke
```

### Debug environment issues

```bash
poetry env info          # show active virtualenv path
poetry env list          # list all envs for this project
poetry env remove 3.9    # remove and recreate if corrupted
poetry install --with dev
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **pytest** skill for test execution patterns
- See the **airbyte-cdk** skill for CDK dependency constraints
- See the **docker** skill for containerized builds using the Poetry-installed connector