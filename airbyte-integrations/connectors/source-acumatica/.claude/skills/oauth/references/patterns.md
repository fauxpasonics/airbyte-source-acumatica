# OAuth Patterns Reference

## Contents
- Token Acquisition (ROPC Flow)
- TokenAuthenticator Wiring
- Logout Protocol
- WARNING: Anti-Patterns
- Error Handling

---

## Token Acquisition (ROPC Flow)

Acumatica uses `grant_type=password` (Resource Owner Password Credentials). The token endpoint is always `{BASEURL}/identity/connect/token`.

```python
# source.py:540 — get_access_token()
def get_access_token(config):
    payload = {
        'client_id': config["CLIENTID"],
        'client_secret': config["CLIENTSECRET"],
        'grant_type': 'password',
        'username': config["USERNAME"],
        'password': config["PASSWORD"],
        'scope': 'api offline_access'
    }
    token_url = f'{config["BASEURL"]}/identity/connect/token'
    response = requests.post(token_url, data=payload)
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        raise Exception(f"Failed to obtain access token: {response.status_code}, {response.text}")
```

The scope `api offline_access` is required — `offline_access` enables refresh token issuance by Acumatica's IdentityServer.

---

## TokenAuthenticator Wiring

`TokenAuthenticator` from `airbyte_cdk.sources.streams.http.requests_native_auth` injects `Authorization: Bearer <token>` into every request made by `HttpClient`.

```python
# Correct wiring pattern (source.py:186-192)
from airbyte_cdk.sources.streams.http.requests_native_auth import TokenAuthenticator

accesstoken = get_access_token(config)
auth = TokenAuthenticator(token=accesstoken)
http_client = HttpClient(name="StreamClient", logger=logger, authenticator=auth)
```

Pass `auth` to every `AcumaticaStream` constructor — streams create their own `HttpClient` internally with the same authenticator:

```python
# AcumaticaStream.__init__ (source.py:45-49)
self._http_client = HttpClient(
    name=self.name,
    logger=self.logger,
    authenticator=authenticator  # TokenAuthenticator passed here
)
```

---

## Logout Protocol

NEVER skip logout. Acumatica maintains server-side sessions. Failing to logout leaks sessions and can exhaust the concurrent session limit on the Acumatica instance.

```python
# source.py:503 — logoutFromAcumatica()
def logoutFromAcumatica(httpclient: HttpClient, config):
    headers = {'Accept': 'application/json', 'Connection': 'Close',
                'Content-Type': 'application/json', 'Cache-Control': 'no-cache'}
    logout_url = urljoin(config["BASEURL"], '/entity/auth/logout')
    _, logout_response = httpclient.send_request(
        http_method="POST", url=logout_url,
        request_kwargs={}, headers=headers, data={}
    )
    if logout_response.ok:
        logger.info("Logged Out")
```

Logout is called in three places:
- After `getmetatdata()` — contract metadata fetch
- After `getodata3metadata()` — OData v3 Inquiry metadata fetch
- After `getodata4metadata()` — OData v4 DAC metadata fetch
- In `read_records()` — after each page of data (in the `else` clause)

---

## WARNING: Anti-Patterns

### WARNING: Reusing a Token Across Logout Boundaries

**The Problem:**

```python
# BAD — token is invalidated after logoutFromAcumatica() but reused
auth = TokenAuthenticator(token=get_access_token(config))
contractschemas = getmetatdata(httpclient=http_client, config=config)
# logoutFromAcumatica() called inside getmetatdata() — token now invalid
odata3schemas = getodata3metadata(httpclient=http_client, config=config)
# ^^^ This will 401 because the session was terminated
```

**Why This Breaks:**
1. Acumatica's logout endpoint invalidates the Bearer token server-side
2. The `HttpClient` still holds the old token in `TokenAuthenticator`
3. All subsequent requests with the same `HttpClient` return 401 Unauthorized

**The Fix:**

```python
# GOOD — current code pattern: each metadata function logs out internally,
# but the http_client in streams() is shared across all three calls.
# If extending, acquire a fresh token per logical operation boundary.
accesstoken = get_access_token(config)
auth = TokenAuthenticator(token=accesstoken)
```

---

### WARNING: Calling print() Instead of logger

**The Problem:**

```python
# BAD — exists in current get_access_token() (source.py:560)
print("Access token obtained successfully!")
```

**Why This Breaks:**
1. `print()` output does not appear in Airbyte platform logs
2. Breaks structured logging — operators can't filter or search token events
3. Mixes stdout with Airbyte's protocol message stream

**The Fix:**

```python
# GOOD
logger.info("Access token obtained successfully")
```

---

## Error Handling

`get_access_token()` raises `Exception` on non-200. `check_connection()` catches this implicitly because `AbstractSource` wraps the call — but if you call `get_access_token()` outside `check_connection()`, wrap it:

```python
# In streams() — unhandled exception will surface as a connector error
try:
    accesstoken = get_access_token(config)
except Exception as e:
    logger.error(f"Token acquisition failed: {e}")
    raise