---
name: requests-mock
description: |
  Mocks HTTP responses for unit testing without live Acumatica endpoints.
  Use when: writing or updating unit tests for get_access_token(), check_connection(),
  stream pagination, OAuth token requests, OData metadata fetches, or any code that
  calls requests.post/requests.get directly. Also use when a unit test is making real
  HTTP calls that should be mocked.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# requests-mock

Intercepts `requests` library HTTP calls in pytest and returns controlled responses. Essential for unit-testing `source.py` without a live Acumatica instance — every `get_access_token()`, OData metadata fetch, and stream page request can be stubbed deterministically.

## Quick Start

### Fixture-based (preferred)

```python
import pytest
import requests_mock as requests_mock_module

@pytest.fixture
def mock_token_response(requests_mock):
    requests_mock.post(
        "https://test.acumatica.com/identity/connect/token",
        json={"access_token": "test-token", "token_type": "Bearer"},
        status_code=200,
    )
```

### Inline context manager

```python
import requests_mock

def test_check_connection():
    with requests_mock.Mocker() as m:
        m.post("https://test.acumatica.com/identity/connect/token",
               json={"access_token": "abc123"})
        result, msg = source.check_connection(config, logger)
        assert result is True
```

## Key Concepts

| Concept | Usage | Example |
|---------|-------|---------|
| `requests_mock` fixture | Auto-injected by pytest plugin | `def test_foo(requests_mock):` |
| `Mocker()` | Context manager for non-fixture use | `with requests_mock.Mocker() as m:` |
| `register_uri` | Register URL with method | `m.register_uri("GET", url, json={...})` |
| Response list | Simulate pagination | `m.get(url, [{"json": page1}, {"json": page2}])` |
| `exc` parameter | Simulate network errors | `m.get(url, exc=ConnectionError)` |

## Common Patterns

### Mock OAuth token + stream data together

```python
def test_stream_read(requests_mock):
    requests_mock.post(".../token", json={"access_token": "tok"})
    requests_mock.get(".../SalesOrder", json={"value": [{"OrderNbr": "SO-001"}]})
    records = list(stream.read_records(sync_mode=SyncMode.full_refresh))
    assert len(records) == 1
```

### Simulate pagination termination

```python
requests_mock.get(
    url,
    [
        {"json": {"value": [{"id": i} for i in range(1000)]}},  # page 1
        {"json": {"value": []}},                                  # page 2 — empty = stop
    ],
)
```

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **pytest** skill for fixture setup and test organization
- See the **oauth** skill for token lifecycle patterns being mocked
- See the **airbyte-cdk** skill for stream classes under test