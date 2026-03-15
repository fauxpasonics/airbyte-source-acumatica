# Integration Test Reference

## Contents
- When to Use Integration Tests
- Acceptance Test Config
- Running Against Live Acumatica
- WARNING: Never Import Integration Tests in Unit Suites

## When to Use Integration Tests

Integration tests in `integration_tests/` hit a real Acumatica instance. Run them only when:
- Validating schema discovery against a live tenant
- Debugging OData metadata parsing failures
- Confirming pagination behavior with real record counts

For everything else, use unit tests with mocks. See the **requests-mock** skill.

## Acceptance Test Config

`acceptance-test-config.yml` drives the Airbyte CI/CD acceptance suite. Key sections:

```yaml
connection:
  tests:
    - config_path: "secrets/config.json"    # must succeed
      status: "succeed"
    - config_path: "integration_tests/invalid_config.json"  # must fail
      status: "failed"
basic_read:
  tests:
    - config_path: "secrets/config.json"
      configured_catalog_path: "integration_tests/configured_catalog.json"
      empty_streams: []
```

The `empty_streams` list must name any streams that legitimately return 0 records. Leaving it empty when a stream is actually empty causes acceptance test failures.

The incremental section is bypassed:
```yaml
incremental:
  bypass_reason: "This connector does not implement incremental sync"
```

Update this when `IncrementalAcumaticaStream` is wired into a real stream.

## Running Against Live Acumatica

Requires `secrets/config.json` — never commit this file.

```bash
# Run acceptance tests via airbyte-ci (requires Docker)
airbyte-ci connectors --name=source-acumatica test

# Run a specific integration test file directly
poetry run pytest integration_tests/testsalesorder.py -v

# Run the full sync to validate end-to-end
poetry run source-acumatica read \
  --config secrets/config.json \
  --catalog integration_tests/configured_catalog.json
```

Validate-then-iterate loop:
1. Make changes to stream logic
2. Run `poetry run pytest unit_tests/` — fix all failures
3. Run `poetry run source-acumatica check --config secrets/config.json` — confirm auth
4. Run `poetry run source-acumatica read --config secrets/config.json --catalog integration_tests/configured_catalog.json`
5. If records are missing or schema errors appear, inspect logs and repeat from step 1

## Configured Catalog

`integration_tests/configured_catalog.json` controls which streams are exercised in basic_read and full_refresh acceptance tests. Keep it in sync with streams returned by `discover`:

```json
{
  "streams": [
    {
      "stream": {
        "name": "contract__SalesOrder",
        "json_schema": {}
      },
      "sync_mode": "full_refresh",
      "destination_sync_mode": "overwrite"
    }
  ]
}
```

If a stream appears in the catalog but isn't returned by `streams()`, acceptance tests will fail with a "stream not found" error.

## WARNING: Never Import Integration Tests in Unit Suites

### The Problem

```python
# BAD — running pytest from root directory
poetry run pytest .
```

**Why This Breaks:**
1. `integration_tests/testsalesorder.py` hits live endpoints — it will fail with connection errors in CI.
2. `integration_tests/acceptance.py` may attempt fixture setup that requires credentials.
3. Mixing test types inflates test time and creates flaky CI builds.

**The Fix:**
```bash
# GOOD — target directories explicitly
poetry run pytest unit_tests/        # fast, always safe
poetry run pytest integration_tests/ # only when credentials are available
```

See the **poetry** skill for the full test command reference.
