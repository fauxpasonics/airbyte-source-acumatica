---
name: docker
description: |
  Builds and deploys containerized Airbyte connector images using airbyte-ci.
  Use when: building the connector image, running connector commands in Docker, debugging container issues, or deploying connector versions.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Docker Skill

Builds and runs the `airbyte/source-acumatica:dev` connector image via `airbyte-ci`. All connector commands (`spec`, `check`, `discover`, `read`) run identically inside Docker — secrets and catalog files are volume-mounted, never baked into the image.

## Quick Start

### Build the image

```bash
airbyte-ci connectors --name=source-acumatica build
```

### Run connector commands in Docker

```bash
# Validate credentials
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  airbyte/source-acumatica:dev check --config /secrets/config.json

# Discover streams
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  airbyte/source-acumatica:dev discover --config /secrets/config.json

# Full sync
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  -v $(pwd)/sample_files:/sample_files \
  airbyte/source-acumatica:dev \
  read --config /secrets/config.json --catalog /sample_files/configured_catalog.json
```

### Run full CI test suite

```bash
airbyte-ci connectors --name=source-acumatica test
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| Image tag | Always use `:dev` for local builds | `airbyte/source-acumatica:dev` |
| Secrets mount | Mount at `/secrets`, never copy | `-v $(pwd)/secrets:/secrets` |
| Catalog mount | Mount integration_tests or sample_files | `-v $(pwd)/sample_files:/sample_files` |
| airbyte-ci | Airbyte's build/test orchestrator | `airbyte-ci connectors --name=source-acumatica build` |

## Common Patterns

### Validate image after build

**When:** After any code change before pushing

```bash
airbyte-ci connectors --name=source-acumatica build
docker run --rm airbyte/source-acumatica:dev spec
```

### Debug a failing read inside Docker

**When:** Sync works locally but fails in container

```bash
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  -v $(pwd)/integration_tests:/integration_tests \
  airbyte/source-acumatica:dev \
  read --config /secrets/config.json \
       --catalog /integration_tests/configured_catalog.json
```

## See Also

- [docker](references/docker.md)
- [ci-cd](references/ci-cd.md)
- [deployment](references/deployment.md)
- [monitoring](references/monitoring.md)

## Related Skills

- See the **poetry** skill for dependency management before building
- See the **pytest** skill for running unit tests outside Docker
- See the **airbyte-cdk** skill for stream implementation patterns