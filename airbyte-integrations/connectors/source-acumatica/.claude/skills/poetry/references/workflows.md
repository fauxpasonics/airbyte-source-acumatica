# Poetry Workflows Reference

## Contents
- Project Setup
- Adding/Removing Dependencies
- Running the Connector
- Updating the CDK
- Troubleshooting Environments

---

## Project Setup

Copy this checklist for first-time setup:

```
- [ ] Step 1: Verify Python version (3.9–3.11)
- [ ] Step 2: poetry install --with dev
- [ ] Step 3: cp sample_files/sample_config.json secrets/config.json
- [ ] Step 4: Edit secrets/config.json with real credentials
- [ ] Step 5: poetry run source-acumatica check --config secrets/config.json
- [ ] Step 6: poetry run pytest unit_tests/
```

```bash
# Step 1 — confirm Python version
python --version   # must be 3.9.x, 3.10.x, or 3.11.x

# Step 2
poetry install --with dev

# Step 5 — validates OAuth and connectivity
poetry run source-acumatica check --config secrets/config.json
```

---

## Adding / Removing Dependencies

### Add runtime dependency

```bash
poetry add requests

# Verify tests still pass
poetry run pytest unit_tests/
```

### Add dev-only dependency

```bash
poetry add --group dev pytest-cov

# Confirm it landed in dev group, not runtime
grep -A5 "group.dev" pyproject.toml
```

### Remove a dependency

```bash
poetry remove some-package

# Always commit both files
git add pyproject.toml poetry.lock
```

---

## Running the Connector

All connector commands run via `poetry run`. Never call `python -m source_acumatica` directly — the entrypoint in `run.py` sets up logging and exception handling.

```bash
# Print JSON schema of connection spec
poetry run source-acumatica spec

# Validate credentials
poetry run source-acumatica check --config secrets/config.json

# Discover available streams dynamically from Acumatica metadata
poetry run source-acumatica discover --config secrets/config.json

# Execute a sync
poetry run source-acumatica read \
  --config secrets/config.json \
  --catalog sample_files/configured_catalog.json
```

For test execution, see the **pytest** skill.

---

## Updating the CDK

`airbyte-cdk` is the most impactful dependency. Updates can change stream base class APIs.

```
- [ ] Step 1: poetry update airbyte-cdk
- [ ] Step 2: poetry run pytest unit_tests/
- [ ] Step 3: poetry run source-acumatica discover --config secrets/config.json
- [ ] Step 4: Review any AcumaticaStream / IncrementalAcumaticaStream method signature changes
- [ ] Step 5: git add pyproject.toml poetry.lock && git commit
```

```bash
# Check what version you're moving to before updating
poetry show airbyte-cdk

# Update
poetry update airbyte-cdk

# Validate — iterate until pass
poetry run pytest unit_tests/
```

If tests fail after a CDK update, check `source.py:31` (`AcumaticaStream`) and `source.py:151` (`IncrementalAcumaticaStream`) for broken base class method signatures. See the **airbyte-cdk** skill for CDK-specific patterns.

---

## Troubleshooting Environments

### Corrupted virtualenv

```bash
# Identify the env
poetry env list

# Remove it
poetry env remove python3.9   # or the version shown

# Recreate
poetry install --with dev
```

### Wrong Python version picked up

```bash
# Pin Poetry to use a specific Python binary
poetry env use /usr/bin/python3.10
poetry install --with dev
```

### Lock file out of sync with pyproject.toml

```bash
# Regenerate without upgrading packages
poetry lock --no-update

# Or upgrade everything to latest allowed versions
poetry lock
```

This surfaces when someone edits `pyproject.toml` directly without running `poetry lock`, causing `poetry install` to fail with a lock file mismatch error.