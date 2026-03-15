---
# Testing Workflows Reference

## Contents
- New Unit Test Workflow
- Testing check_connection
- Testing Incremental Streams
- Debugging Mock Mismatches
- Test Checklist
---

## New Unit Test Workflow

Copy this checklist for each new unit test:

```
- [ ] Identify all HTTP calls the code path makes (token, metadata, data, logout)
- [ ] Register mocks in call order using requests_mock fixture
- [ ] Assert on records or state — not on mock call counts unless required
- [ ] Run: poetry run pytest unit_tests/ -v
- [ ] Confirm no real HTTP calls escape (requests_mock raises if unregistered URL hit)
```

## Testing check_connection

`check_connection()` only calls `get_access_token()`. One mock is sufficient:

```python
from source_acumatica.source import SourceAcumatica
import logging

logger = logging.getLogger("test")

def test_check_connection_success(requests_mock):
    requests_mock.post(
        "https://test.acumatica.com/identity/connect/token",
        json={"access_token": "valid-token"},
    )
    source = SourceAcumatica()
    ok, msg = source.check_connection(logger, CONFIG)
    assert ok is True

def test_check_connection_bad_credentials(requests_mock):
    requests_mock.post(
        "https://test.acumatica.com/identity/connect/token",
        status_code=400,
        json={"error": "invalid_grant"},
    )
    source = SourceAcumatica()
    ok, msg = source.check_connection(logger, CONFIG)
    assert ok is False
```

## Testing Incremental Streams

`IncrementalAcumaticaStream` tracks state via `get_updated_state()`. Verify cursor advances:

```python
from airbyte_cdk.models import SyncMode

def test_incremental_state_advances(requests_mock):
    requests_mock.post(".../token", json={"access_token": "tok"})
    requests_mock.get(
        ".../odata/Default/SalesOrder",
        json={"value": [
            {"OrderNbr": "SO-001", "LastModifiedDateTime": "2024-03-01T00:00:00"},
            {"OrderNbr": "SO-002", "LastModifiedDateTime": "2024-03-15T00:00:00"},
        ]},
    )
    requests_mock.get(".../odata/Default/SalesOrder", json={"value": []})  # empty = done

    initial_state = {"LastModifiedDateTime": "2024-01-01T00:00:00"}
    records = []
    new_state = initial_state.copy()

    for record in stream.read_records(
        sync_mode=SyncMode.incremental,
        stream_state=initial_state,
    ):
        records.append(record)
        new_state = stream.get_updated_state(new_state, record)

    assert new_state["LastModifiedDateTime"] == "2024-03-15T00:00:00"
```

## Debugging Mock Mismatches

When tests fail with `NoMockAddress` or `ConnectionError`:

**Step 1** — Print the actual URL being called:

```python
def test_debug_url(requests_mock):
    requests_mock.register_uri(requests_mock_module.ANY, requests_mock_module.ANY,
                                json={})
    stream.read_records(...)
    for req in requests_mock.request_history:
        print(req.method, req.url)  # reveals exact URL being constructed
```

**Step 2** — Compare printed URL to your mock registration. Common mismatches:
- Missing tenant prefix: `/odata/` vs `/{TENANTNAME}/odata/`
- Token URL: `/identity/connect/token` vs `/connect/token`
- Trailing slash differences

**Step 3** — Fix mock URL to match exactly, remove debug registration.

Validate: `poetry run pytest unit_tests/ -v`
If still failing, repeat from Step 1.

## Running Tests

```bash
# Run all unit tests
poetry run pytest unit_tests/ -v

# Run single file
poetry run pytest unit_tests/test_source.py -v

# Run with stdout (see print() debug output)
poetry run pytest unit_tests/ -s

# Run with coverage
poetry run pytest unit_tests/ --cov=source_acumatica --cov-report=term-missing
```

Target: >80% line coverage in `source_acumatica/source.py`.

See the **pytest** skill for fixture organization and parametrize patterns.
See the **oauth** skill for the token flow being mocked here.