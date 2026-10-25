<!-- bmad:context -->
<!-- Verified 2026-10-25 against 6bbc585c29455a103645acb07c93e257dc710cd0. Managed by bmad-project-context; edits inside this block are replaced on refresh. Keep anything you want preserved outside the markers. -->

## Cerne

Reflective-journaling mobile app with an AI assistant. Flutter/Dart (pinned via fvm), `flutter_bloc`, Clean Architecture. Product spec, screen flow and delivery order: `docs/input/requirements.md`. Visual reference: `docs/input/prototype/`. Backend contract (already built, frozen): `docs/input/backend/`.

## Policy

- Where `docs/input/` is silent on a technical choice, decide and proceed — it is the product source of truth, not an exhaustive spec.
- Never edit files under `docs/input/` — frozen product input, not project output.
- Never change the backend, its API contract, or its configuration — consume it as documented in `docs/input/backend/`.
- Never call an AI provider (Claude, Voyage AI) directly from the app — every AI feature, including semantic search, goes through the backend.
- Never commit `.env` or any credential — it is gitignored; it holds exactly `FUNCTIONS_BASE_URL` and `SUPABASE_ANON_KEY`.
- Never write a visual value (color, font, spacing, radius) outside `lib/core/design_tokens.dart` — it is the single source, built from `docs/input/prototype/prototype-extract.md` section 3.
- Never implement an extension feature (`docs/input/requirements.md` section 2) — a menu entry may exist as a placeholder, nothing functional behind it.
- Implement functional requirements in the delivery order given in `docs/input/requirements.md` section 12, not request order.

## Where things are

- Product spec (requirements, acceptance criteria, screen flow, endpoint-to-requirement mapping, delivery order): `docs/input/requirements.md`
- Visual tokens and navigable states: `docs/input/prototype/prototype-extract.md`; raw prototype: `docs/input/prototype/cerne-prototype.html`
- Backend API contract: `docs/input/backend/api/openapi.yaml`; path-to-function mapping: `docs/input/backend/README.md`; error taxonomy, sync-badge semantics, known bugs, test fixtures: rest of `docs/input/backend/`

## Running and verifying

- TODO: no Flutter project exists yet (F000 not started) — no `pubspec.yaml`, no `.fvmrc`. Do not guess `flutter test` / `flutter analyze` invocations; once F000 scaffolds the project, verify the real fvm-wrapped commands and record them here.

## Conventions that differ from defaults

- Call the backend only at `{FUNCTIONS_BASE_URL}/<x-cerne-function>`, never at the literal REST path shown in `openapi.yaml` — each operation's real URL is its `x-cerne-function` name, with path parameters appended as trailing segments. E.g. `POST /chat/sessions/{id}/messages/{userMessageId}/retry` calls `{FUNCTIONS_BASE_URL}/chat-messages-retry/{id}/{userMessageId}` — the literal `/retry` segment does not exist in the real URL.
- Send header `apikey: <SUPABASE_ANON_KEY>` on every call. Send `Authorization: Bearer <SUPABASE_ANON_KEY>` only on the three operations with `security: []` in the contract (signup, login, refresh); send `Authorization: Bearer <user access token>` on every operation marked `bearerAuth`.
- Audio speech-to-text runs on-device via `whisper_ggml` — never send an audio file to the backend.
- Repositories return `Either<Failure, T>` (`fpdart`); no repository signature outside this pattern (RNF09).
- Three layers per feature (`data/domain/presentation`) under `lib/features/<feature>/`; the domain layer imports neither `package:flutter` nor anything from `data/` (RNF06).
- RF10 (save chat message as entry) must call the entries feature through a shared interface/use case, never by importing the entries repository or data source directly — doing so also violates RNF06.

<!-- /bmad:context -->
