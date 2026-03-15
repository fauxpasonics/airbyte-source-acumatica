---
# Mocking Patterns Reference

## Contents
- OAuth Token Mocking
- OData Metadata Mocking
- Stream Pagination Mocking
- Error Simulation
- Anti-Patterns
---

## OAuth Token Mocking

`get_access_token()` in `source.py` POSTs to `{BASEURL}/identity/connect/token`. Always mock this first — every other call depends on it.

```python
CONFIG = {
    "BASEURL": "https://test.acumatica.com",
    "CLIENTID": "test-client",
    "CLIENTSECRET": "test-secret",
    "USERNAME": "user",
    "PASSWORD": "pass",
    "PAGESIZE": 100,
}

def test_get_access_token(requests_mock):
    requests_mock.post(
        f"{CONFIG['BASEURL']}/identity/connect/token",
        json={"access_token": "test-token-123", "token_type": "Bearer", "expires_in": 3600},
    )
    token = get_access_token(CONFIG)
    assert token == "test-token-123"
```

Mock failed auth (wrong credentials → 401):

```python
def test_get_access_token_failure(requests_mock):
    requests_mock.post(
        f"{CONFIG['BASEURL']}/identity/connect/token",
        status_code=401,
        json={"error": "invalid_client"},
    )
    with pytest.raises(Exception):
        get_access_token(CONFIG)
```

## OData Metadata Mocking

`getodata4metadata()` fetches `{BASEURL}/{TENANTNAME}/odata/Default/$metadata`. Return minimal valid OData JSON:

```python
METADATA_RESPONSE = {
    "value": [
        {"name": "Customers", "kind": "EntitySet", "url": "Customers"},
        {"name": "SalesOrder", "kind": "EntitySet", "url": "SalesOrder"},
    ]
}

def test_streams_discovery(requests_mock):
    requests_mock.post(f"{CONFIG['BASEURL']}/identity/connect/token",
                       json={"access_token": "tok"})
    requests_mock.get(
        f"{CONFIG['BASEURL']}/odata/Default/$metadata",
        json=METADATA_RESPONSE,
    )
    source = SourceAcumatica()
    streams = source.streams(CONFIG)
    stream_names = [s.name for s in streams]
    assert "DAC__Customers" in stream_names
```

## Stream Pagination Mocking

`AcumaticaStream` uses `$skip`/`$top` for pagination. Simulate multi-page responses with a list of dicts:

```python
def test_pagination(requests_mock):
    requests_mock.post(f"{CONFIG['BASEURL']}/identity/connect/token",
                       json={"access_token": "tok"})
    requests_mock.get(
        f"{CONFIG['BASEURL']}/odata/Default/SalesOrder",
        [
            {"json": {"value": [{"OrderNbr": f"SO-{i:03d}"} for i in range(100)]}},
            {"json": {"value": [{"OrderNbr": "SO-100"}]}},  # partial page → last page
            {"json": {"value": []}},                         # safety: never reached
        ],
    )
    records = list(stream.read_records(sync_mode=SyncMode.full_refresh))
    assert len(records) == 101
```

requests-mock returns list items in order, one per request — perfect for pagination.

## Error Simulation

Test retry and error handling without a live server:

```python
def test_connection_error(requests_mock):
    requests_mock.post(
        f"{CONFIG['BASEURL']}/identity/connect/token",
        exc=requests.exceptions.ConnectionError("Network unreachable"),
    )
    ok, msg = SourceAcumatica().check_connection(logger, CONFIG)
    assert ok is False
    assert "Network unreachable" in msg

def test_server_error_retries(requests_mock):
    requests_mock.get(
        f"{CONFIG['BASEURL']}/odata/Default/Customers",
        [
            {"status_code": 500},
            {"status_code": 500},
            {"json": {"value": [{"CustomerID": "C001"}]}},  # succeeds on 3rd attempt
        ],
    )
```

## Anti-Patterns

### WARNING: Matching on partial URLs without anchoring

**The Problem:**

```python
# BAD - matches ANY URL containing this substring
requests_mock.get("acumatica.com", json={...})
```

**Why This Breaks:**
1. Matches unintended URLs in multi-request tests
2. Hides bugs where the wrong endpoint is called
3. Makes test failures non-deterministic when URL construction changes

**The Fix:**

```python
# GOOD - exact URL match
requests_mock.get("https://test.acumatica.com/odata/Default/SalesOrder", json={...})
```

---

### WARNING: Not mocking the logout endpoint

`logoutFromAcumatica()` is called after every read. If unmocked, requests-mock raises `NoMockAddress` and your test fails with a confusing error unrelated to what you're actually testing.

```python
# GOOD - always include logout stub when testing full read flows
requests_mock.post(f"{CONFIG['BASEURL']}/entity/auth/logout", status_code=204)