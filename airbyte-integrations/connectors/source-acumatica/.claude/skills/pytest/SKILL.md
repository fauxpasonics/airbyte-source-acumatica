---
name: pytest
description: |
  Writes unit tests with mocks and validates Acumatica connector behavior using pytest and requests-mock.
  Use when: writing or updating tests for streams, source connection checks, incremental state, pagination, or HTTP retry logic. Also use when a test is failing and you need to debug or fix it.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# Pytest Skill

Unit tests for this connector live in `unit_tests/` and use `pytest` + `pytest-mock` + `requests-mock`. The existing test files are heavily scaffolded with TODOs — most assertions are stubs that need real values. When writing tests, mock the OAuth token fetch and HTTP responses; never hit a live Acumatica instance from unit tests.

## Quick Start

### Patch abstract class and instantiate stream

```python
@pytest.fixture
def patch_base_class(mocker):
    mocker.patch.object(AcumaticaStream, "path", "v0/example_endpoint")
    mocker.patch.object(AcumaticaStream, "primary_key", "test_primary_key")
    mocker.patch.object(AcumaticaStream, "__abstractmethods__", set())

def test_request_params(patch_base_class):
    config = {"BASEURL": "https://test.acumatica.com", "PAGESIZE": 100}
    stream = AcumaticaStream(
        name="SalesOrder", endpointtype="contract",
        config=config, schema={}, primary_key="id"
    )
    params = stream.request_params(stream_state={}, next_page_token=0)
    assert params["$top"] == 100
    assert params["$skip"] == 0
```

### Mock OAuth token in check_connection

```python
def test_check_connection(mocker):
    mocker.patch("source_acumatica.source.get_access_token", return_value="mock-token")
    source = SourceAcumatica()
    ok, err = source.check_connection(MagicMock(), {"BASEURL": "https://test.acumatica.com"})
    assert ok is True
    assert err is None
```

### Test incremental cursor state update

```python
def test_get_updated_state(patch_incremental_base_class):
    stream = IncrementalAcumaticaStream(
        name="SalesOrder", endpointtype="contract",
        config={}, schema={}, primary_key="id", cursor_field="LastModifiedDateTime"
    )
    state = {"LastModifiedDateTime": "2024-01-01T00:00:00"}
    record = {"LastModifiedDateTime": "2024-06-01T00:00:00"}
    new_state = stream.get_updated_state(state, record)
    assert new_state["LastModifiedDateTime"] > state["LastModifiedDateTime"]
```

## Key Concepts

| Concept | Usage | Location |
|---------|-------|----------|
| Patch abstract methods | `mocker.patch.object(cls, "__abstractmethods__", set())` | All stream tests |
| Mock OAuth | `mocker.patch("source_acumatica.source.get_access_token", ...)` | `test_source.py` |
| Parametrize retry | `@pytest.mark.parametrize(("status", "should_retry"), [...])` | `test_streams.py` |
| Fixture scope | `@pytest.fixture` (default function scope) | All test files |
| requests-mock | `requests_mock.get(url, json={...})` | HTTP response mocking |

## Common Patterns

### Parametrize HTTP retry behavior

```python
@pytest.mark.parametrize(
    ("http_status", "should_retry"),
    [
        (HTTPStatus.OK, False),
        (HTTPStatus.TOO_MANY_REQUESTS, True),
        (HTTPStatus.INTERNAL_SERVER_ERROR, True),
    ],
)
def test_should_retry(patch_base_class, http_status, should_retry):
    response_mock = MagicMock()
    response_mock.status_code = http_status
    stream = AcumaticaStream(...)
    assert stream.should_retry(response_mock) == should_retry
```

### Add a new stream test workflow

Copy this checklist and track progress:
- [ ] Step 1: Add fixture that patches abstract methods for the new stream class
- [ ] Step 2: Write `test_request_params` verifying `$top`, `$skip`, and `$filter`
- [ ] Step 3: Write `test_parse_response` with a mocked OData JSON payload
- [ ] Step 4: Write `test_get_updated_state` if incremental
- [ ] Step 5: Run `poetry run pytest unit_tests/` — fix failures before proceeding

## See Also

- [unit](references/unit.md)
- [integration](references/integration.md)
- [mocking](references/mocking.md)
- [fixtures](references/fixtures.md)

## Related Skills

- See the **airbyte-cdk** skill for stream class implementation details
- See the **oauth** skill for `get_access_token` behavior being mocked
- See the **poetry** skill for running tests and managing dev dependencies
