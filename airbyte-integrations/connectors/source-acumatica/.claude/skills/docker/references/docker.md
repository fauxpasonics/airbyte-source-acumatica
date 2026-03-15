# Docker Reference

## Contents
- Image Build
- Running Commands
- Volume Mounts
- Anti-Patterns
- Common Errors

## Image Build

The connector image is built exclusively via `airbyte-ci` — not `docker build` directly. `airbyte-ci` handles multi-platform builds, dependency installation, and Airbyte connector contract validation.

```bash
# Build
airbyte-ci connectors --name=source-acumatica build

# Verify the image exists
docker images | grep source-acumatica
# Expected: airbyte/source-acumatica   dev   <id>   <size>
```

The resulting tag is always `airbyte/source-acumatica:dev` for local builds.

## Running Commands

All five connector verbs work identically in Docker:

```bash
# spec — no mounts needed
docker run --rm airbyte/source-acumatica:dev spec

# check
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  airbyte/source-acumatica:dev check --config /secrets/config.json

# discover
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  airbyte/source-acumatica:dev discover --config /secrets/config.json

# read (full sync)
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  -v $(pwd)/sample_files:/sample_files \
  airbyte/source-acumatica:dev \
  read --config /secrets/config.json --catalog /sample_files/configured_catalog.json

# read (integration test catalog)
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  -v $(pwd)/integration_tests:/integration_tests \
  airbyte/source-acumatica:dev \
  read --config /secrets/config.json \
       --catalog /integration_tests/configured_catalog.json
```

## Volume Mounts

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `$(pwd)/secrets` | `/secrets` | OAuth credentials config |
| `$(pwd)/sample_files` | `/sample_files` | Sample catalog for reads |
| `$(pwd)/integration_tests` | `/integration_tests` | Integration test catalog |

The `secrets/` directory is gitignored. Never bake credentials into the image layer.

## Anti-Patterns

### WARNING: Copying secrets into the image

**The Problem:**
```dockerfile
# BAD — credentials baked into image layer
COPY secrets/config.json /app/secrets/config.json
```

**Why This Breaks:**
1. Credentials persist in every image layer and Docker history — `docker history` exposes them
2. Image pushed to any registry leaks credentials to all who pull it
3. Rotating credentials requires a full image rebuild

**The Fix:**
```bash
# GOOD — mount at runtime, never in image
docker run --rm -v $(pwd)/secrets:/secrets airbyte/source-acumatica:dev check --config /secrets/config.json
```

### WARNING: Using `docker build` instead of `airbyte-ci`

**The Problem:**
```bash
# BAD — bypasses Airbyte connector contract validation
docker build -t airbyte/source-acumatica:dev .
```

**Why This Breaks:**
1. Skips multi-platform build configuration required for Airbyte Cloud
2. Missing connector metadata labels that the registry expects
3. Acceptance tests (`airbyte-ci connectors test`) will fail against a manually built image

**The Fix:**
```bash
# GOOD
airbyte-ci connectors --name=source-acumatica build
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `No such file: /secrets/config.json` | Missing `-v` mount | Add `-v $(pwd)/secrets:/secrets` |
| `Image not found: airbyte/source-acumatica:dev` | Not built yet | Run `airbyte-ci connectors --name=source-acumatica build` |
| `ModuleNotFoundError` | Stale image with old deps | Rebuild after `poetry update` |
| OAuth 401 in container | Clock skew in container vs host | Ensure host time is synced (`timedatectl`) |