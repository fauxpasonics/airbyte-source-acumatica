# Deployment Reference

## Contents
- Local Development Workflow
- Docker Deployment
- Airbyte Cloud Publishing
- Configuration Management
- Rollback

## Local Development Workflow

```bash
# 1. Install dependencies
poetry install --with dev

# 2. Validate credentials work
poetry run source-acumatica check --config secrets/config.json

# 3. Discover streams
poetry run source-acumatica discover --config secrets/config.json

# 4. Run sync
poetry run source-acumatica read \
  --config secrets/config.json \
  --catalog sample_files/configured_catalog.json
```

For dependency management, see the **poetry** skill.

## Docker Deployment

Build and validate locally before deploying:

```bash
# Build
airbyte-ci connectors --name=source-acumatica build

# Smoke test the image
docker run --rm airbyte/source-acumatica:dev spec

# Full check with credentials
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  airbyte/source-acumatica:dev check --config /secrets/config.json
```

## Airbyte Cloud Publishing

Publishing is fully automated after merge to `master`. The pipeline:

1. Builds the Docker image with the tag from `metadata.yaml`
2. Pushes to `airbyte/source-acumatica:<version>` on Docker Hub
3. Updates the Airbyte connector registry

**Manual trigger is not supported.** Only merge to `master` triggers publication.

Current published version is in `metadata.yaml`:
```yaml
dockerImageTag: "0.1.19"
```

## Configuration Management

All runtime config is passed via `--config` JSON file. No environment variables required.

```json
{
  "BASEURL": "https://your-instance.acumatica.com",
  "CLIENTID": "your-client-id",
  "CLIENTSECRET": "your-client-secret",
  "USERNAME": "your-username",
  "PASSWORD": "your-password",
  "PAGESIZE": 1000
}
```

The `secrets/` directory is gitignored. The `sample_files/sample_config.json` is the template — it contains no real credentials and IS committed.

```bash
cp sample_files/sample_config.json secrets/config.json
# Edit secrets/config.json with real values
```

## Rollback

Airbyte Cloud connectors can be pinned to a specific version in the UI. To roll back:

1. In Airbyte UI, navigate to the connector instance
2. Change the version to the previous `dockerImageTag` value
3. The previous image is still available on Docker Hub

To identify the last known-good version, check `metadata.yaml` git history:
```bash
git log --oneline -- metadata.yaml
```

## Anti-Patterns

### WARNING: Committing secrets/config.json

The `secrets/` directory is gitignored for security. If you accidentally stage it:

```bash
# Check what's staged
git diff --cached secrets/

# Unstage immediately
git restore --staged secrets/config.json
```

NEVER force this file into a commit. Rotate credentials immediately if it was pushed.