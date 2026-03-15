# Poetry Patterns Reference

## Contents
- Dependency Group Management
- Lockfile Discipline
- CLI Entrypoint Pattern
- Version Constraints
- Anti-Patterns

---

## Dependency Group Management

This project separates runtime from dev dependencies. Runtime deps go in `[tool.poetry.dependencies]`; test tooling goes in `[tool.poetry.group.dev.dependencies]`.

```toml
# pyproject.toml — current structure
[tool.poetry.dependencies]
python = "^3.9,<3.12"
airbyte-cdk = "^0"

[tool.poetry.group.dev.dependencies]
requests-mock = "*"
pytest-mock = "*"
pytest = "*"
```

**Why this matters:** The Docker image runs `poetry install --without dev`, keeping the production image lean. If you add a test tool to `[tool.poetry.dependencies]`, it ships to production.

```bash
# Install everything locally
poetry install --with dev

# Install only runtime deps (mirrors Docker)
poetry install --without dev
```

---

## Lockfile Discipline

ALWAYS commit `poetry.lock`. It guarantees reproducible builds across developer machines and CI.

```bash
# After any dependency change, lock is auto-updated — commit both files
git add pyproject.toml poetry.lock
git commit -m "chore: add pytest-cov to dev dependencies"
```

### WARNING: Pinning with `"*"` in dev deps

```toml
# ACCEPTABLE for dev deps — versions don't affect production
pytest = "*"
requests-mock = "*"
```

```toml
# NEVER use "*" for runtime deps — breaks reproducibility
# BAD
airbyte-cdk = "*"

# GOOD — caret allows compatible updates, locks exact version in poetry.lock
airbyte-cdk = "^0"
```

**Why `"*"` breaks runtime deps:** On a fresh install without `poetry.lock`, Poetry resolves the latest version, which may introduce breaking changes. The lockfile mitigates this, but the constraint is your safety net when the lockfile is regenerated.

---

## CLI Entrypoint Pattern

The `source-acumatica` command is wired via `[tool.poetry.scripts]`:

```toml
[tool.poetry.scripts]
source-acumatica = "source_acumatica.run:run"
```

This means `poetry run source-acumatica` resolves to `source_acumatica/run.py:run()`. When adding a new entrypoint:

```toml
# Add alongside existing script
[tool.poetry.scripts]
source-acumatica = "source_acumatica.run:run"
source-acumatica-debug = "source_acumatica.run:debug_run"
```

Then reinstall to register it:

```bash
poetry install
poetry run source-acumatica-debug --config secrets/config.json
```

---

## Version Constraints

This project pins Python to `^3.9,<3.12` to match `airbyte-cdk` compatibility.

```toml
python = "^3.9,<3.12"
```

**DO NOT** widen this range without verifying airbyte-cdk supports the new version. The CDK has historically had issues on Python 3.12+ due to dependency transitive constraints.

| Constraint | Meaning | Use When |
|------------|---------|----------|
| `^0` | `>=0.0.0, <1.0.0` | Pre-1.0 libs (airbyte-cdk) |
| `^1.7` | `>=1.7.0, <2.0.0` | Stable libs (Poetry itself) |
| `"*"` | Any version | Dev-only tools where version doesn't matter |
| `>=2.0,<3` | Explicit range | When you need to exclude specific versions |

---

## Anti-Patterns

### WARNING: Editing poetry.lock manually

**The Problem:** Manually editing `poetry.lock` to change a version or remove a package.

**Why This Breaks:**
1. Lock file hashes become invalid — `poetry install` fails with integrity errors
2. Dependency graph consistency is violated — transitive deps won't match
3. CI will fail on a fresh clone with no explanation

**The Fix:**
```bash
# Remove a package properly
poetry remove package-name

# Force regenerate the lockfile
poetry lock --no-update
```

### WARNING: Running pip install inside Poetry project

```bash
# BAD — installs outside Poetry's virtualenv or pollutes it unpredictably
pip install some-package

# GOOD — always use Poetry to manage deps
poetry add some-package
```

**Why this breaks:** `pip install` bypasses `pyproject.toml`, so the dep is invisible to other developers and won't be present in CI or Docker builds.