# Cerne backend — documentation package

The backend is already built and frozen. This package documents what the app needs to consume it. The backend source code is not part of it.

## Contents

| File | What it is |
|---|---|
| `api/openapi.yaml` | API contract of the 23 endpoints — the source of truth |
| `error-taxonomy.md` | The 13 error codes, with HTTP status and `retryable` |
| `export-screen-states.md` | Mapping between the export screen states and the export job statuses (RF05) |
| `sync-badge.md` | Semantics of the per-entry synchronization badge |
| `known-bugs.md` | Known non-blocking backend defects, with workarounds |
| `fixtures/` | Test media (audio, images for OCR), the expected transcription of the audio, and the three seeded entries used by semantic search |

Credentials (project URL and keys) are not in this package: they are provided in the app's `.env`.

## Contract path → function

`api/openapi.yaml` has no router: each operation is served by its own Edge Function at `{FUNCTIONS_BASE_URL}/<function>` (see `servers` and each operation's `x-cerne-function` in the YAML) — **never** directly at the REST path below. Path parameters are appended as the final URL segments, in the same order as they appear in the path; any literal segment after the last parameter (e.g., the `/retry` of `chat.messages.retry`) does not exist in the real URL.

| Contract path | Function (`{FUNCTIONS_BASE_URL}/<function>`) |
|---|---|
| `POST /auth/signup` | `auth-signup` |
| `POST /auth/login` | `auth-login` |
| `POST /auth/refresh` | `auth-refresh` |
| `GET /auth/session` | `auth-session` |
| `POST /auth/logout` | `auth-logout` |
| `POST /entries` | `entries-create` |
| `GET /entries` | `entries-list` |
| `GET /entries/{id}` | `entries-get` |
| `GET /entries/search` | `entries-search` |
| `POST /media/ocr` | `media-ocr` |
| `POST /chat/sessions` | `chat-sessions-create` |
| `GET /chat/sessions` | `chat-sessions-list` |
| `GET /chat/sessions/{id}/messages` | `chat-messages-list` |
| `POST /chat/sessions/{id}/messages` | `chat-messages-send` |
| `POST /chat/sessions/{id}/messages/{userMessageId}/retry` | `chat-messages-retry` |
| `POST /chat/sessions/{id}/insight` | `chat-insight-create` |
| `POST /export/summary` | `export-summary-create` |
| `GET /export/{jobId}/status` | `export-status-get` |
| `GET /export/{jobId}/download` | `export-download-get` |
| `GET /dashboard/aggregate` | `dashboard-aggregate-get` |
| `GET /dashboard/narrative` | `dashboard-narrative-get` |
| `PATCH /account/settings` | `account-settings-update` |
| `DELETE /account` | `account-delete` |
