---
name: oauth
description: |
  Manages OAuth 2.0 authentication and token lifecycle for the Acumatica source connector.
  Use when: implementing or debugging token acquisition, wiring TokenAuthenticator into streams,
  handling logout after metadata or data fetches, or testing connection validation via check_connection().
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
---

# OAuth Skill

This connector uses Acumatica's OAuth 2.0 Resource Owner Password Credentials (ROPC) flow — not the standard authorization code flow. Tokens are fetched via `POST /identity/connect/token` with `grant_type=password`, then wrapped in CDK's `TokenAuthenticator`. Every metadata fetch and data read **must** call `logoutFromAcumatica()` after completion to terminate the server-side session.

## Quick Start

### Acquire a token and wire it into streams

```python
# source.py — streams()
accesstoken = get_access_token(config)
auth = TokenAuthenticator(token=accesstoken)
stream = AcumaticaStream(name="SalesOrder", endpointtype="contract",
                         config=config, schema=schema,
                         primary_key="id", authenticator=auth)
```

### Validate credentials in check_connection

```python
# source.py — check_connection()
def check_connection(self, logger, config) -> Tuple[bool, any]:
    token = get_access_token(config)
    if token is not None:
        return True, None
    return False, None
```

### Logout after every fetch

```python
# Required after getmetatdata(), getodata3metadata(), getodata4metadata(), and read_records()
logoutFromAcumatica(httpclient=self._http_client, config=self.config)
```

## Key Concepts

| Concept | Location | Notes |
|---------|----------|-------|
| Token acquisition | `source.py:540` `get_access_token()` | ROPC flow; raises on non-200 |
| Token injection | `source.py:187` | `TokenAuthenticator(token=accesstoken)` |
| Session termination | `source.py:503` `logoutFromAcumatica()` | POST to `/entity/auth/logout` |
| Connection validation | `source.py:178` `check_connection()` | Token != None = success |

## Common Patterns

### Token used for both metadata and data reads

```python
# streams() acquires ONE token, reuses it across all three metadata calls
accesstoken = get_access_token(config)
auth = TokenAuthenticator(token=accesstoken)
self.http_client = HttpClient(name="StreamClient", logger=logger, authenticator=auth)
contractschemas = getmetatdata(httpclient=self.http_client, config=config)
```

Each metadata function calls `logoutFromAcumatica()` internally — the token is invalidated after each call, so `streams()` calls `get_access_token()` once per function.

## See Also

- [patterns](references/patterns.md)
- [workflows](references/workflows.md)

## Related Skills

- See the **airbyte-cdk** skill for wiring `TokenAuthenticator` into `HttpClient` and `AcumaticaStream`
- See the **pytest** skill for mocking `get_access_token()` and `requests.post` in unit tests
- See the **requests-mock** skill for intercepting token endpoint calls in tests