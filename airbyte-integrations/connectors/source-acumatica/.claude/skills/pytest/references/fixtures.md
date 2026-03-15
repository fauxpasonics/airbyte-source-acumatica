# Fixtures Reference

## Contents
- Abstract Class Patching Fixtures
- Shared Config Fixture
- Incremental Stream Fixture
- Fixture Scope
- WARNING: Reusing Stateful Stream Fixtures

## Abstract Class Patching Fixtures

`AcumaticaStream` and `IncrementalAcumaticaStream` are abstract. The existing fixtures in `unit_tests/test_streams.py` and `unit_tests/test_incremental_streams.py` patch `__abstractmethods__` to allow instantiation:

```python
@pytest.fixture
def patch_base_class(mocker):
    mocker.patch.object(AcumaticaStream, "path", "v0/example_endpoint")
    mocker.patch.object(AcumaticaStream, "primary_key", "test_primary_key")
    mocker.patch.object(AcumaticaStream, "__abstractmethods__", set())

@pytest.fixture
def patch_incremental_base_class(mocker):
    mocker.patch.object(IncrementalAcumaticaStream, "path", "v0/example_endpoint")
    mocker.patch.object(IncrementalAcumaticaStream, "primary_key", "test_primary_key")
    mocker.patch.object(IncrementalAcumaticaStream, "__abstractmethods__", set())
```

These patches are automatically undone after each test because `mocker` has function scope by default.

## Shared Config Fixture

Centralizing config in a fixture prevents copy-paste drift — if `BASEURL` changes in tests, update one place:

```python
@pytest.fixture
def base_config():
    return {
        "BASEURL": "https://test.acumatica.com",
        "TENANTNAME": "testcompany",
        "PAGESIZE": 100,
        "CLIENTID": "test-client-id",
        "CLIENTSECRET": "test-secret",
        "USERNAME": "testuser",
        "PASSWORD": "testpass",
    }

@pytest.fixture
def contract_stream(patch_base_class, base_config):
    return AcumaticaStream(
        name="SalesOrder",
        endpointtype="contract",
        config=base_config,
        schema={"type": "object", "properties": {"OrderNbr": {"type": "string"}}},
        primary_key="OrderNbr",
    )
```

## Incremental Stream Fixture

```python
@pytest.fixture
def incremental_stream(patch_incremental_base_class, base_config):
    return IncrementalAcumaticaStream(
        name="SalesOrder",
        endpointtype="contract",
        config=base_config,
        schema={"type": "object", "properties": {}},
        primary_key="OrderNbr",
        cursor_field="LastModifiedDateTime",
    )

def test_cursor_field(incremental_stream):
    assert incremental_stream.cursor_field == "LastModifiedDateTime"

def test_supports_incremental(incremental_stream):
    assert incremental_stream.supports_incremental is True
```

## Fixture Scope

| Scope | Use When | Cost |
|-------|----------|------|
| `function` (default) | Stream instances, mocks | Rebuilt each test — safe for stateful objects |
| `module` | Expensive read-only setup | Shared across file — NEVER use for stateful streams |
| `session` | One-time global setup (e.g., real DB) | Avoid in unit tests entirely |

Always use `function` scope for stream instances because `AcumaticaStream` tracks `_current_page` as mutable state.

## WARNING: Reusing Stateful Stream Fixtures

### The Problem

```python
# BAD — module-scoped stream fixture
@pytest.fixture(scope="module")
def contract_stream(base_config):
    return AcumaticaStream(name="SalesOrder", endpointtype="contract", config=base_config, ...)

def test_first_page(contract_stream):
    # stream._current_page == 0 here — passes

def test_second_call(contract_stream):
    # stream._current_page is now 1 from previous test — wrong starting state!
    params = contract_stream.request_params(stream_state={}, next_page_token=0)
    # $skip is calculated from _current_page, not next_page_token alone
```

**Why This Breaks:**
1. `AcumaticaStream._current_page` is incremented during `read_records`. Module-scoped fixtures share this state across tests.
2. Test execution order is not guaranteed — tests that depend on `_current_page == 0` will fail intermittently.
3. Pagination bugs become invisible because the stream's internal counter is already dirty.

**The Fix:**
```python
# GOOD — function scope (default), fresh instance per test
@pytest.fixture
def contract_stream(patch_base_class, base_config):
    return AcumaticaStream(
        name="SalesOrder", endpointtype="contract",
        config=base_config, schema={}, primary_key="OrderNbr"
    )
```

See the **airbyte-cdk** skill for details on how `_current_page` interacts with pagination.
