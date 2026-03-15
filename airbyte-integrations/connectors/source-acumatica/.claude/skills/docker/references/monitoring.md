# Monitoring Reference

## Contents
- Connector Logging
- Debugging Sync Failures
- State Inspection
- Common Failure Signatures
- Observability Gaps

## Connector Logging

The connector uses Python's standard logging via the Airbyte CDK logger. Log output goes to stdout and is captured by Airbyte's platform.

Key log points in `source.py`:
- OAuth token acquisition (success/failure)
- Metadata fetch for stream discovery
- Pagination progress (`$skip` / `$top` values)
- Schema flattening results

To see full output locally:

```bash
# Local (verbose)
poetry run source-acumatica read \
  --config secrets/config.json \
  --catalog sample_files/configured_catalog.json 2>&1 | tee sync.log

# Docker
docker run --rm \
  -v $(pwd)/secrets:/secrets \
  -v $(pwd)/sample_files:/sample_files \
  airbyte/source-acumatica:dev \
  read --config /secrets/config.json \
       --catalog /sample_files/configured_catalog.json 2>&1 | tee sync.log
```

## Debugging Sync Failures

Iterate until passing:

1. Check OAuth: `poetry run source-acumatica check --config secrets/config.json`
2. If check fails → OAuth credentials issue (CLIENTID, CLIENTSECRET, USERNAME, PASSWORD)
3. Check discovery: `poetry run source-acumatica discover --config secrets/config.json`
4. If discovery fails → BASEURL unreachable or metadata endpoint changed
5. Run read with minimal catalog (single stream) to isolate
6. Inspect logs for `$skip`/`$top` values — if stuck at same offset, pagination loop issue
7. Validate schema: compare JSON schema in `source_acumatica/schemas/` against actual API response

## State Inspection

Incremental streams write cursor state after each sync. To inspect current state:

```bash
# State is output as AirbyteStateMessage records in the sync output
poetry run source-acumatica read \
  --config secrets/config.json \
  --catalog sample_files/configured_catalog.json \
  | grep '"type": "STATE"'
```

Cursor fields are `LastModified` or `LastModifiedDateTime` depending on the entity. If state is missing from output, the stream is running as full refresh.

For cursor implementation details, see the **airbyte-cdk** skill.

## Common Failure Signatures

| Symptom | Likely Cause | Investigation |
|---------|-------------|---------------|
| `401 Unauthorized` on every request | Expired/invalid OAuth token | Re-run `check` command; verify CLIENTSECRET |
| Empty catalog from `discover` | Metadata endpoint unreachable | Check BASEURL; test OData metadata URL manually |
| Sync hangs at large offset | Pagination bug or Acumatica timeout | Reduce PAGESIZE in config (try 100) |
| Records missing nested fields | Schema flattening dropped data | Check `flatten_json_array()` in `source.py` |
| `StreamNotFound` in acceptance tests | Stream name mismatch | Verify stream names in `configured_catalog.json` match `discover` output |

## Observability Gaps

The connector has no built-in:
- Request latency tracking
- Per-stream record count metrics
- Retry attempt counters
- Rate limit detection

If Acumatica rate limits the connector, it will appear as HTTP 429 errors in logs with no automatic backoff. Reduce `PAGESIZE` and add delays manually if this occurs.

For unit test coverage of error paths, see the **pytest** skill.