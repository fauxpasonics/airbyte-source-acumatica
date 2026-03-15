---
name: airbyte-cdk
description: |
  Develops Airbyte connector streams and handles incremental sync with cursors using the airbyte-cdk Python framework.
  Use when: implementing or modifying AcumaticaStream / IncrementalAcumaticaStream classes, adding new streams in source.py, debugging pagination or cursor state, writing stream unit tests, or resolving CDK API mismatches.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Airbyte CDK Skill

This connector uses `airbyte-cdk ^0` with a custom base stream (`AcumaticaStream`) rather than `HttpStream`, because Acumatica requires OAuth token injection and OData-style pagination (`$skip/$top`) that don't fit the CDK's default HTTP stream model. All three endpoint types (Contract, OData v3 Inquiry, OData v4 DAC) inherit from the same base.

## Quick Start

### Full-Refresh Stream

```python
from airbyte_cdk.sources.streams import Stream

class AcumaticaStream(Stream):
    primary_key = None

    def __init__(self, config, authenticator):
        self._config = config
        self._authenticator = authenticator

    @property
    def name(self) -> str:
        return f"DAC__{self._entity}"

    def read_records(self, sync_mode, cursor_field=None, stream_slice=None, stream_state=None):
        skip = 0
        page_size = self._config.get("PAGESIZE", 1000)
        while True:
            records = self._fetch_page(skip, page_size)
            yield from records
            if len(records) < page_size:
                break
            skip += page_size
```

### Incremental Stream

```python
from airbyte_cdk.sources.streams import IncrementalMixin

class IncrementalAcumaticaStream(AcumaticaStream):
    cursor_field = "LastModifiedDateTime"

    def get_updated_state(self, current_stream_state, latest_record):
        latest = latest_record.get(self.cursor_field, "")
        current = current_stream_state.get(self.cursor_field, "")
        return {self.cursor_field: max(latest, current)}
```

## Key Concepts

| Concept | Location | Notes |
|---------|----------|-------|
| Base stream | `source.py:31` | Custom `Stream` subclass, not `HttpStream` |
| Incremental | `source.py:151` | Cursor: `LastModified` or `LastModifiedDateTime` |
| Stream naming | `source.py` | `{ENDPOINTTYPE}__{ENTITY}` convention |
| Schema discovery | `source.py:224` | `process_schema()` flattens `allOf` + nested objects |
| Pagination | `request_params()` | `$skip` / `$top` OData params |

## Common Patterns

### Registering a New Stream

```python
# In SourceAcumatica.streams()
def streams(self, config):
    token = get_access_token(config)
    auth = TokenAuthenticator(token)
    return [
        MyNewStream(config=config, authenticator=auth),
        # ...existing streams
    ]
```

### Schema from OData Metadata

```python
def get_json_schema(self):
    raw = getodata4metadata(self._config, self._entity)
    return process_schema(raw)
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **pytest** skill for writing mocked stream tests
- See the **poetry** skill for dependency and environment management
- See the **docker** skill for building and running the connector image