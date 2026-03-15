# Development Workflows Reference

## Contents
- Adding a New Stream
- Debugging Pagination
- Fixing Incremental State
- Schema Discovery Issues
- Release Checklist

---

## Adding a New Stream

Copy this checklist and track progress:
- [ ] Step 1: Identify endpoint type (Contract / Inquiry / DAC)
- [ ] Step 2: Create JSON schema in `source_acumatica/schemas/` (or use metadata-driven discovery)
- [ ] Step 3: Define stream class in `source.py` inheriting correct base
- [ ] Step 4: Register in `SourceAcumatica.streams()`
- [ ] Step 5: Add unit test in `unit_tests/test_streams.py`
- [ ] Step 6: Validate with `poetry run source-acumatica discover --config secrets/config.json`

### Step 3 — Define Stream Class

```python
# Full-refresh DAC stream
class DAC__PurchaseOrders(AcumaticaStream):
    _entity = "PurchaseOrder"
    _endpoint_type = "DAC"
    primary_key = "OrderNbr"

    def get_json_schema(self):
        return process_schema(getodata4metadata(self._config, self._entity))
```

```python
# Incremental stream — only if entity has LastModified field
class IncrementalDAC__PurchaseOrders(IncrementalAcumaticaStream):
    _entity = "PurchaseOrder"
    cursor_field = "LastModifiedDateTime"
    primary_key = "OrderNbr"
```

### Step 4 — Register in streams()

```python
def streams(self, config):
    token = get_access_token(config)
    auth = TokenAuthenticator(token)
    existing = [...]
    existing.append(DAC__PurchaseOrders(config=config, authenticator=auth))
    return existing
```

---

## Debugging Pagination

When a sync returns fewer records than expected:

1. Check `$skip`/`$top` appear in request logs: `logger.info(f"Fetching skip={skip} top={page_size}")`
2. Verify the termination condition — if the API returns exactly `page_size` records on the last page, the loop fetches one extra empty page. This is expected and harmless.
3. Validate: `poetry run source-acumatica read --config secrets/config.json --catalog sample_files/configured_catalog.json 2>&1 | grep skip`
4. If validation fails (zero records), check that `response.json().get("value", [])` matches actual API response shape — some Contract endpoints return a list directly, not wrapped in `"value"`.

```python
# Contract endpoints — root is a list
records = response.json()  # list directly

# OData v3/v4 endpoints — wrapped
records = response.json().get("value", [])
```

---

## Fixing Incremental State

When incremental sync re-reads all records on every run:

1. Confirm `get_updated_state()` returns a dict with the correct cursor key
2. Confirm the cursor field name matches exactly (case-sensitive: `LastModifiedDateTime` ≠ `lastModifiedDateTime`)
3. Confirm the state is passed into `request_params()` as a filter

```python
# State must filter the API request, not just track locally
def request_params(self, stream_state=None, **kwargs):
    params = {"$top": self._config.get("PAGESIZE", 1000), "$skip": self._next_page}
    if stream_state and self.cursor_field in stream_state:
        cursor_val = stream_state[self.cursor_field]
        params["$filter"] = f"{self.cursor_field} gt datetimeoffset'{cursor_val}'"
    return params
```

Validate iterate-until-pass:
1. Run sync, capture state output
2. Modify a record in Acumatica
3. Re-run sync with captured state as input
4. Confirm only the modified record is returned
5. If all records returned, the `$filter` param is missing or malformed — fix and repeat step 1

---

## Schema Discovery Issues

When `discover` returns empty or malformed schemas:

```python
# Check raw metadata response before process_schema()
raw = getodata4metadata(config, "SalesOrder")
logger.info(f"Raw metadata: {json.dumps(raw, indent=2)}")
schema = process_schema(raw)
logger.info(f"Processed schema: {json.dumps(schema, indent=2)}")
```

Common failures:

| Symptom | Cause | Fix |
|---------|-------|-----|
| Empty `properties` dict | `allOf` not merged | Verify `process_schema()` handles all `allOf` levels |
| `None` type fields | Nullable OData fields missing type | Default to `["null", "string"]` in schema processing |
| Missing nested fields | Parent entity not expanded | Add `$expand` param to metadata request |

---

## Release Checklist

Copy this checklist before submitting a PR:
- [ ] Bump `dockerImageTag` in `metadata.yaml`
- [ ] Bump `version` in `pyproject.toml` (match semver)
- [ ] Run `poetry run pytest unit_tests/` — all pass
- [ ] Run `poetry run source-acumatica discover --config secrets/config.json` — streams listed
- [ ] Run `poetry run source-acumatica read --config secrets/config.json --catalog sample_files/configured_catalog.json` — records flow
- [ ] Update `docs/integrations/sources/acumatica.md` changelog entry

See the **poetry** skill for dependency updates before release. See the **docker** skill for building and testing the connector image locally.