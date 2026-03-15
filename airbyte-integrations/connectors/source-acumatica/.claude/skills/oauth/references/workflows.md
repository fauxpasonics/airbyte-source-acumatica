# OAuth Workflows Reference

## Contents
- New Connection Setup Checklist
- Debugging Token Failures
- Adding Auth to a New Stream
- Testing OAuth Without Live Credentials

---

## New Connection Setup Checklist

Copy this checklist when wiring OAuth for a new Acumatica integration:

```
- [ ] Step 1: Confirm BASEURL, CLIENTID, CLIENTSECRET, USERNAME, PASSWORD in secrets/config.json
- [ ] Step 2: Run check_connection: poetry run source-acumatica check --config secrets/config.json
- [ ] Step 3: Verify token endpoint reachable: POST {BASEURL}/identity/connect/token returns 200
- [ ] Step 4: Confirm TENANTNAME set if using DAC or Inquiry endpoints
- [ ] Step 5: Verify logout endpoint accessible: POST {BASEURL}/entity/auth/logout returns 200
- [ ] Step 6: Run discover to confirm streams list without auth errors
```

---

## Debugging Token Failures

### Symptom: check_connection returns False

`check_connection()` returns `(False, None)` only if `get_access_token()` returns `None`. But the current implementation raises on failure — so `False` is effectively unreachable. If you see `False`, the token URL returned 200 with no `access_token` key.

```python
# Verify the token response shape manually
import requests
response = requests.post(
    f'{config["BASEURL"]}/identity/connect/token',
    data={'client_id': '...', 'client_secret': '...', 'grant_type': 'password',
          'username': '...', 'password': '...', 'scope': 'api offline_access'}
)
print(response.status_code, response.json().keys())
```

Expected: `200`, keys include `access_token`, `token_type`, `expires_in`.

### Symptom: 401 on metadata or stream fetch

Most likely cause: logout was called on the shared `HttpClient` before the next request. Validate:

1. Check logs for "Logged Out" appearing before the failing request
2. Confirm each metadata function in `streams()` is using a fresh `HttpClient` or that logout hasn't been called mid-sequence
3. Check if Acumatica session limit is reached (check instance admin console)

---

## Adding Auth to a New Stream

Follow this exact pattern when instantiating a new stream in `SourceAcumatica.streams()`:

```python
# source.py — streams()
def streams(self, config: Mapping[str, Any]) -> List[HttpStream]:
    accesstoken = get_access_token(config)           # 1. Acquire token
    auth = TokenAuthenticator(token=accesstoken)     # 2. Wrap in authenticator

    # 3. Pass auth to every stream constructor
    my_stream = AcumaticaStream(
        name="MyEntity",
        endpointtype="contract",
        config=config,
        schema=my_schema,
        primary_key="id",
        authenticator=auth    # <-- required
    )
    return [my_stream]
```

NEVER construct a stream without passing `authenticator=auth`. An unauthenticated `HttpClient` will fail with 401 on the first request.

---

## Testing OAuth Without Live Credentials

See the **pytest** and **requests-mock** skills for full mock setup. The minimal pattern for mocking `get_access_token()`:

```python
# unit_tests/test_source.py
from unittest.mock import patch, MagicMock
from source_acumatica.source import SourceAcumatica

def test_check_connection_success():
    with patch("source_acumatica.source.get_access_token") as mock_token:
        mock_token.return_value = "fake-token-abc123"
        source = SourceAcumatica()
        ok, err = source.check_connection(logger=MagicMock(), config={
            "BASEURL": "https://example.acumatica.com",
            "CLIENTID": "test-id",
            "CLIENTSECRET": "test-secret",
            "USERNAME": "user",
            "PASSWORD": "pass"
        })
        assert ok is True
        assert err is None
```

Mock the token endpoint directly with `requests-mock` when testing `get_access_token()` itself:

```python
import requests_mock as rm
from source_acumatica.source import get_access_token

def test_get_access_token(requests_mock):
    requests_mock.post(
        "https://example.acumatica.com/identity/connect/token",
        json={"access_token": "test-token", "token_type": "Bearer", "expires_in": 3600}
    )
    config = {
        "BASEURL": "https://example.acumatica.com",
        "CLIENTID": "id", "CLIENTSECRET": "secret",
        "USERNAME": "user", "PASSWORD": "pass"
    }
    token = get_access_token(config)
    assert token == "test-token"
```

Validate/iterate loop:

1. Write mock test
2. Run: `poetry run pytest unit_tests/ -v`
3. If 401 or connection errors appear, confirm `requests_mock` fixture is intercepting the correct URL
4. If `get_access_token` is importing `requests` at module level, ensure the mock patches `source_acumatica.source.requests` not `requests` directly