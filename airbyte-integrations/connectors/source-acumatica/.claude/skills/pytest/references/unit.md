# Unit Test Reference

## Contents
- Stream Instantiation
- request_params Assertions
- Retry Logic
- Incremental State
- WARNING: Stub Tests

## Stream Instantiation

`AcumaticaStream` is abstract — you cannot instantiate it directly without patching `__abstractmethods__`. Use a fixture:

```python
@pytest.fixture
def patch_base_class(mocker):
    mocker.patch.object(AcumaticaStream, "path", "v0/example_endpoint")
    mocker.patch.object(AcumaticaStream, "primary_key", "test_primary_key")
    mocker.patch.object(AcumaticaStream, "__abstractmethods__", set())
```

The constructor requires all positional args — never pass `MagicMock()` for `config` because `request_params` reads `config["PAGESIZE"]` directly:

```python
def make_stream(endpointtype="contract", cursor_field=None):
    config = {"BASEURL": "https://test.acumatica.com", "PAGESIZE": 100, "TENANTNAME": "test"}
    if cursor_field:
        return IncrementalAcumaticaStream(
            name="SalesOrder", endpointtype=endpointtype,
            config=config, schema={}, primary_key="id", cursor_field=cursor_field
        )
    return AcumaticaStream(
        name="SalesOrder", endpointtype=endpointtype,
        config=config, schema={}, primary_key="id"
    )
```

## request_params Assertions

Pagination params are only injected when `next_page_token` is truthy or zero. Test both the initial page and subsequent pages:

```python
def test_request_params_first_page(patch_base_class):
    stream = make_stream()
    params = stream.request_params(stream_state={}, next_page_token=0)
    assert params["$top"] == 100
    assert params["$skip"] == 0

def test_request_params_second_page(patch_base_class):
    stream = make_stream()
    params = stream.request_params(stream_state={}, next_page_token=2)
    assert params["$skip"] == 200

def test_request_params_with_state(patch_base_class):
    stream = make_stream(cursor_field="LastModifiedDateTime")
    params = stream.request_params(
        stream_state={"LastModifiedDateTime": "2024-01-01T00:00:00"},
        next_page_token=0
    )
    assert "$filter" in params
    assert "LastModifiedDateTime" in params["$filter"]
```

## Retry Logic

The parametrize pattern in `test_streams.py` is the right approach. Extend it with all status codes you care about:

```python
@pytest.mark.parametrize(
    ("http_status", "should_retry"),
    [
        (HTTPStatus.OK, False),
        (HTTPStatus.BAD_REQUEST, False),
        (HTTPStatus.UNAUTHORIZED, False),
        (HTTPStatus.TOO_MANY_REQUESTS, True),
        (HTTPStatus.INTERNAL_SERVER_ERROR, True),
        (HTTPStatus.SERVICE_UNAVAILABLE, True),
    ],
)
def test_should_retry(patch_base_class, http_status, should_retry):
    stream = make_stream()
    response_mock = MagicMock()
    response_mock.status_code = http_status
    assert stream.should_retry(response_mock) == should_retry
```

## Incremental State

`get_updated_state` uses `dateutil.parser.parse` — always pass ISO 8601 strings in test state and records:

```python
def test_get_updated_state_advances(patch_incremental_base_class):
    stream = make_stream(cursor_field="LastModifiedDateTime")
    state = {"LastModifiedDateTime": "2024-01-01T00:00:00+00:00"}
    newer_record = {"LastModifiedDateTime": "2024-06-01T00:00:00+00:00"}
    new_state = stream.get_updated_state(state, newer_record)
    assert new_state["LastModifiedDateTime"] > state["LastModifiedDateTime"]

def test_get_updated_state_no_regression(patch_incremental_base_class):
    stream = make_stream(cursor_field="LastModifiedDateTime")
    state = {"LastModifiedDateTime": "2024-06-01T00:00:00+00:00"}
    older_record = {"LastModifiedDateTime": "2024-01-01T00:00:00+00:00"}
    new_state = stream.get_updated_state(state, older_record)
    assert new_state == state  # state must not go backward
```

## WARNING: Stub Tests

### The Problem

```python
# BAD — current state in test_source.py
def test_streams(mocker):
    source = SourceAcumatica()
    config_mock = MagicMock()
    streams = source.streams(config_mock)
    expected_streams_number = 2  # TODO: replace this
    assert len(streams) == expected_streams_number
```

**Why This Breaks:**
1. `MagicMock()` for config causes `source.streams()` to call real HTTP endpoints — this test will fail without live credentials.
2. The hardcoded `2` is a placeholder; the real stream count depends on metadata discovery.
3. Tests that always pass without asserting real behavior give false confidence.

**The Fix:**
```python
def test_streams(mocker):
    mocker.patch("source_acumatica.source.get_access_token", return_value="tok")
    mocker.patch("source_acumatica.source.getmetatdata", return_value=[])
    mocker.patch("source_acumatica.source.getodata3metadata", return_value=[])
    mocker.patch("source_acumatica.source.getodata4metadata", return_value=[])
    source = SourceAcumatica()
    config = {"BASEURL": "https://test.acumatica.com", "TENANTNAME": "t", "PAGESIZE": 100}
    streams = source.streams(config)
    assert isinstance(streams, list)
```

See the **oauth** skill for details on `get_access_token` behavior.
