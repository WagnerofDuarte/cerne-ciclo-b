# Error taxonomy — 13 codes

Every endpoint returns errors as `{ code, message, retryable }`. The list below is closed: no other code exists.

| Code | HTTP | Retryable |
|---|---|---|
| `AUTH_EXPIRED` | 401 | no |
| `AUTH_INVALID` | 401 | no |
| `NETWORK_TIMEOUT` | 504 | yes |
| `NETWORK_OFFLINE` | _(no HTTP response — see note)_ | yes |
| `VALIDATION_ERROR` | 400 | no |
| `PII_CHECK_FAILED` | 502 | yes |
| `EMBEDDING_FAILED` | 502 | yes |
| `AI_GENERATION_TIMEOUT` | 504 | yes |
| `NOT_FOUND` | 404 | no |
| `RATE_LIMITED` | 429 | yes |
| `EXPORT_EMPTY_PERIOD` | 400 | no |
| `PAYLOAD_TOO_LARGE` | 413 | no |
| `OCR_NO_TEXT` | 400 | no |

**Two deliberate design choices (these never happen in this API):**
- **Never `403`** — a resource belonging to another user always answers `404 NOT_FOUND` (so its existence is not revealed).
- **Never `409`** — the idempotency of RF10 (re-sending the same chat message as an entry) always answers `200`; there is no "conflict" code.

**`NETWORK_OFFLINE` has no HTTP status:** it is the only code that never becomes an actual response — it represents a connection that ends without any response.
