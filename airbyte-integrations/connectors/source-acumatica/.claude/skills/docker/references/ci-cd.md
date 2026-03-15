# CI/CD Reference

## Contents
- Pipeline Overview
- airbyte-ci Commands
- Acceptance Tests
- Version Bumping Checklist
- Anti-Patterns

## Pipeline Overview

The CI/CD pipeline uses `airbyte-ci` to build, test, and publish the connector. Merging to `master` triggers automatic publication to Docker Hub and the Airbyte connector registry.

```
PR → airbyte-ci test → merge to master → auto-publish to Docker Hub + registry
```

## airbyte-ci Commands

```bash
# Build only
airbyte-ci connectors --name=source-acumatica build

# Run full test suite (build + unit + integration + acceptance)
airbyte-ci connectors --name=source-acumatica test

# Run a specific test type
airbyte-ci connectors --name=source-acumatica test --only-step=unit_tests
```

`airbyte-ci test` runs in this order:
1. Build Docker image
2. Unit tests (`unit_tests/`)
3. Integration tests (`integration_tests/`)
4. Acceptance tests (defined in `acceptance-test-config.yml`)

## Acceptance Tests

Acceptance tests validate the connector against the Airbyte connector contract. Config lives in `acceptance-test-config.yml`:

```yaml
connector_image: airbyte/source-acumatica:dev
acceptance_tests:
  spec:
    tests:
      - spec_path: "source_acumatica/spec.yaml"
  connection:
    tests:
      - config_path: "secrets/config.json"
        status: "succeed"
      - config_path: "integration_tests/invalid_config.json"
        status: "failed"
  full_refresh:
    tests:
      - config_path: "secrets/config.json"
        configured_catalog_path: "integration_tests/configured_catalog.json"
```

Incremental sync acceptance tests are currently bypassed:
```yaml
incremental:
  bypass_reason: "This connector does not implement incremental sync"
```

Remove `bypass_reason` and add test config when incremental sync is implemented. See the **airbyte-cdk** skill for incremental stream patterns.

## Version Bumping Checklist

Copy this checklist before every release:

- [ ] Step 1: Bump `dockerImageTag` in `metadata.yaml`
- [ ] Step 2: Bump `version` in `pyproject.toml` to match
- [ ] Step 3: Update changelog in `docs/integrations/sources/acumatica.md`
- [ ] Step 4: Run `airbyte-ci connectors --name=source-acumatica test` — all green
- [ ] Step 5: Open PR with title following Airbyte PR naming conventions
- [ ] Step 6: Merge → auto-publish triggered

Version format follows semantic versioning: `MAJOR.MINOR.PATCH`
- PATCH: bug fixes, no schema changes
- MINOR: new streams, backward-compatible schema additions
- MAJOR: breaking schema changes, auth method changes

## Anti-Patterns

### WARNING: Mismatched versions between metadata.yaml and pyproject.toml

**The Problem:**
```yaml
# metadata.yaml
dockerImageTag: "0.1.20"
```
```toml
# pyproject.toml
version = "0.1.19"   # BAD — out of sync
```

**Why This Breaks:**
The registry uses `metadata.yaml` for the published tag, but the Python package version is embedded in the image. Mismatch causes confusing version reporting in Airbyte UI diagnostics.

**The Fix:** Always update both files atomically in the same commit.

### WARNING: Skipping acceptance tests before merge

Running only unit tests locally before merging misses contract violations that acceptance tests catch — wrong `spec.yaml` types, missing required fields in records, broken `check` response format. Always run `airbyte-ci connectors --name=source-acumatica test` before opening a PR.