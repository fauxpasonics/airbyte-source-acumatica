# Stream Patterns Reference

## Contents
- Stream Inheritance Hierarchy
- Pagination Pattern
- Incremental Cursor Pattern
- Schema Flattening
- Anti-Patterns

---

## Stream Inheritance Hierarchy

All streams inherit from `AcumaticaStream`, never directly from `HttpStream`. The CDK's `HttpStream` assumes a single base URL and standard auth headers — Acumatica requires OAuth token management and OData query params that conflict with those assumptions.

```python
# GOOD — inherit from project base class
class DAC__Customers(AcumaticaStream):
    _entity = "Customers"
    _endpoint_type = "DAC"

# BAD — bypasses shared pagination, auth, and flattening logic
class DAC__Customers(HttpStream):
    ...
```

For incremental streams, extend `IncrementalAcumaticaStream`:

```python
class IncrementalDAC__SalesOrder(IncrementalAcumaticaStream):
    _entity = "SalesOrder"
    cursor_field = "LastModifiedDateTime"
```

---

## Pagination Pattern

Use `$skip` / `$top` OData params. The loop terminates when the response returns fewer records than `page_size` — this is the only reliable EOF signal from Acumatica.

```python
def read_records(self, sync_mode, cursor_field=None, stream_slice=None, stream_state=None):
    skip = 0
    page_size = self._config.get("PAGESIZE", 1000)
    while True:
        params = {"$skip": skip, "$top": page_size}
        response = requests.get(self._url, headers=self._headers(), params=params)
        records = response.json().get("value", [])
        yield from (self._flatten(r) for r in records)
        if len(records) < page_size:
            break
        skip += page_size
```

**WARNING:** Never use `response.json()` directly as a list — Acumatica OData responses wrap records under `"value"`. Accessing the root object as a list raises `TypeError` silently if the response shape changes.

---

## Incremental Cursor Pattern

`get_updated_state()` must compare strings, not parse dates, because Acumatica returns ISO 8601 strings that sort lexicographically. Parsing adds unnecessary complexity and can break on timezone variants.

```python
def get_updated_state(self, current_stream_state, latest_record):
    latest_val = latest_record.get(self.cursor_field, "")
    current_val = current_stream_state.get(self.cursor_field, "")
    return {self.cursor_field: max(latest_val, current_val)}
```

Cursor fields are hardcoded to `LastModified` or `LastModifiedDateTime`. When adding a new incremental stream, verify which field the entity exposes:

```python
# Check entity metadata before assuming cursor field name
class IncrementalDAC__Invoices(IncrementalAcumaticaStream):
    cursor_field = "LastModified"  # NOT LastModifiedDateTime for this entity
```

---

## Schema Flattening

`process_schema()` merges `allOf` references and `flatten_json_array()` converts nested navigation properties to top-level prefixed fields. This is required because Airbyte catalog schemas must be flat JSON Schema — nested `$ref` and `allOf` are not supported at the destination layer.

```python
# Input from OData metadata
{
  "Address": {
    "City": "Seattle",
    "State": "WA"
  }
}

# Output after flatten_json_array()
{
  "Address_City": "Seattle",
  "Address_State": "WA"
}
```

**WARNING:** Deep nesting (3+ levels) can produce field name collisions (`A_B_C` vs `A__B_C`). If two entities share a prefix pattern, verify flattened output before writing tests.

---

## Anti-Patterns

### WARNING: Hardcoding Page Size

**The Problem:**
```python
# BAD — ignores user config
params = {"$skip": skip, "$top": 500}
```

**Why This Breaks:** Large Acumatica instances time out on 1000-record pages; small instances waste roundtrips on 100-record pages. The `PAGESIZE` config exists precisely to tune this per-deployment.

**The Fix:**
```python
# GOOD
page_size = self._config.get("PAGESIZE", 1000)
params = {"$skip": skip, "$top": page_size}
```

---

### WARNING: Returning Raw Nested Records

**The Problem:**
```python
# BAD — returns nested objects Airbyte destinations cannot serialize
yield from response.json().get("value", [])
```

**Why This Breaks:** Destinations like BigQuery and Snowflake reject nested objects unless the schema explicitly declares them as `object` type. The OData metadata-driven schema declares flat fields — the records must match.

**The Fix:**
```python
# GOOD — always flatten before yielding
yield from (flatten_json_array(r) for r in response.json().get("value", []))