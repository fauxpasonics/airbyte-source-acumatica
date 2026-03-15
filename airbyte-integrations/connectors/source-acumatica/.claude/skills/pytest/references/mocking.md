# Mocking Reference

## Contents
- Mocking OAuth (get_access_token)
- Mocking HTTP via requests-mock
- Mocking Metadata Discovery
- Mocking HttpClient (CDK)
- WARNING: MagicMock for config

## Mocking OAuth (get_access_token)

`check_connection` and `streams` both call `get_access_token(config)` which makes a real POST to Acumatica. Always patch it in unit tests:

```python
def test_check_connection_success(mocker):
    mocker.patch("source_acumatica.source.get_access_token", return_value="fake-token")
    source = SourceAcumatica()
    ok, err = source.check_connection(MagicMock(), {"BASEURL": "https://test.acumatica.com"})
    assert ok is True

def test_check_connection_fails_on_none_token(mocker):
    mocker.patch("source_acumatica.source.get_access_token", return_value=None)
    source = SourceAcumatica()
    ok, _ = source.check_connection(MagicMock(), {})
    assert ok is False
```

See the **oauth** skill for the full token request flow.

## Mocking HTTP via requests-mock

The `requests-mock` library intercepts `requests.Session` calls at the transport layer. Use it to mock OData endpoints:

```python
import requests_mock as requests_mock_module

def test_read_records_odata(requests_mock):
    odata_response = {
        "@odata.context": "https://test.acumatica.com/odata/test/$metadata#SalesOrder",
        "value": [
            {"OrderNbr": "SO000001", "Status": "Open", "LastModifiedDateTime": "2024-01-01T00:00:00"}
        ]
    }
    requests_mock.get(
        "https://test.acumatica.com/entity/Default/23.200.001/SalesOrder",
        json=odata_response
    )
    config = {"BASEURL": "https://test.acumatica.com", "TENANTNAME": "test", "PAGESIZE": 100}
    stream = AcumaticaStream(name="SalesOrder", endpointtype="contract", config=config, schema={}, primary_key="OrderNbr")
    records = list(stream.read_records(sync_mode=SyncMode.full_refresh))
    assert len(records) == 1
    assert records[0]["OrderNbr"] == "SO000001"
```

Pagination termination — mock a second call returning empty `value` to trigger the `pagination_complete` condition:

```python
def test_pagination_terminates(requests_mock):
    url = "https://test.acumatica.com/entity/Default/23.200.001/SalesOrder"
    requests_mock.get(url, [
        {"json": {"value": [{"id": "1"}]}},
        {"json": {"value": []}}
    ])
    config = {"BASEURL": "https://test.acumatica.com", "TENANTNAME": "t", "PAGESIZE": 1}
    stream = AcumaticaStream(name="SalesOrder", endpointtype="contract", config=config, schema={}, primary_key="id")
    records = list(stream.read_records(sync_mode=SyncMode.full_refresh))
    assert len(records) == 1
```

## Mocking Metadata Discovery

`streams()` calls `getmetatdata`, `getodata3metadata`, and `getodata4metadata`. Mock all three to test stream construction without network calls:

```python
def test_streams_construction(mocker):
    mocker.patch("source_acumatica.source.get_access_token", return_value="tok")
    mocker.patch("source_acumatica.source.logoutFromAcumatica")
    mocker.patch("source_acumatica.source.getmetatdata", return_value=[
        {"name": "SalesOrder", "schema": {"type": "object", "properties": {}}, "primary_key": "OrderNbr"}
    ])
    mocker.patch("source_acumatica.source.getodata3metadata", return_value=[])
    mocker.patch("source_acumatica.source.getodata4metadata", return_value=[])
    source = SourceAcumatica()
    config = {"BASEURL": "https://test.acumatica.com", "TENANTNAME": "test", "PAGESIZE": 100}
    streams = source.streams(config)
    assert any(s.name == "contract__SalesOrder" for s in streams)
```

## Mocking HttpClient (CDK)

`AcumaticaStream` uses `self._http_client.send_request()` from `airbyte_cdk`. Patch it when testing `read_records` without `requests-mock`:

```python
def test_read_records_via_http_client(mocker, patch_base_class):
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.content = b'{"value": [{"id": "1"}]}'
    mock_response.json.return_value = {"value": [{"id": "1"}]}

    config = {"BASEURL": "https://test.acumatica.com", "TENANTNAME": "t", "PAGESIZE": 100}
    stream = AcumaticaStream(name="Orders", endpointtype="contract", config=config, schema={}, primary_key="id")
    mocker.patch.object(stream._http_client, "send_request", return_value=(None, mock_response))

    records = list(stream.read_records(sync_mode=SyncMode.full_refresh))
    assert records == [{"id": "1"}]
```

## WARNING: MagicMock for config

### The Problem

```python
# BAD — config is a MagicMock
config_mock = MagicMock()
stream = AcumaticaStream(name="X", endpointtype="contract", config=config_mock, ...)
params = stream.request_params(stream_state={}, next_page_token=0)
# config_mock["PAGESIZE"] returns another MagicMock, not an int
# $top param will be a MagicMock object — assertion on params["$top"] == 100 will fail
```

**Why This Breaks:**
1. `config.get("PAGESIZE", 1000)` on a MagicMock returns a new MagicMock, not `1000`.
2. Arithmetic comparisons against MagicMock raise `TypeError` in some contexts.
3. URL construction (`config["BASEURL"] + "/entity/..."`) will concatenate "MagicMock + string", producing a nonsensical URL.

**The Fix:**
```python
# GOOD — always use a real dict for config
config = {
    "BASEURL": "https://test.acumatica.com",
    "TENANTNAME": "test",
    "PAGESIZE": 100
}
```
