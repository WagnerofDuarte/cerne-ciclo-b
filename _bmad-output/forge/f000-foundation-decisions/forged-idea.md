# F000 foundation — forged decisions

Source: 2026-10-25 brainstorm (`_bmad-output/brainstorming/brainstorm-f000-foundation-choices-2026-10-25/`) hardened against `docs/input/requirements.md`, `docs/input/backend/api/openapi.yaml`, and the rest of `docs/input/backend/`.

## Free-choice decisions

- **Local cache: Hive.** Not drift. Confirmed every filter/search dimension (`source`, `dateFrom`, `dateTo`, semantic search) is a server-side query param — the client never filters, joins or sorts cached data. Two boxes (`entries` by id, `chat_messages` by session id) + `chat_sessions` by id + a cursor string. Rejected: local secondary sort on My Records, client-side dashboard fallback aggregation — neither is a stated requirement.
- **Vault: flutter_secure_storage (plain PIN-hash item) + local_auth.** Rejected `biometric_storage` — gating storage behind biometric success can't satisfy RF03's "biometric failure falls back to PIN without lockout" (checking the PIN would need the hash, which would need biometric success, which is what just failed). Both paths owned by one vault state machine.
- **DI: plain get_it.** No injectable/codegen. Per-feature registration function, called from main.
- **DTOs/entities: freezed + json_serializable.** Justified by field count, not blanket codegen — Entry has 11 required fields in the contract; hand-written `==`/`copyWith` for that is a bug magnet. Also used for sealed unions (Failure, Resource).
- **Routing: go_router.** Single `redirect` callback keyed off one `SessionStatus` stream. No screen independently checks auth or opts out.
- **HTTP client: dio + one interceptor.** Owns apikey/Authorization headers. Retries only on server `retryable:true` codes (NETWORK_TIMEOUT, NETWORK_OFFLINE, PII_CHECK_FAILED, EMBEDDING_FAILED, AI_GENERATION_TIMEOUT, RATE_LIMITED) — never the 7 `retryable:false` codes.
- **Chart: fl_chart.** Unchanged from the brainstorm — pure Dart, matches the 3 fixed RF09 scenarios.

## Shared abstractions (the real F000 deliverable)

- **Failure hierarchy:** sealed class, exactly 13 server-mirrored subtypes (full closed list — AuthExpired, AuthInvalid, NetworkTimeout, NetworkOffline, Validation, PiiCheckFailed, EmbeddingFailed, AiGenerationTimeout, NotFound, RateLimited, ExportEmptyPeriod, PayloadTooLarge, OcrNoText) + exactly 1 local-only variant, `MalformedResponse` (retryable hardcoded false), for RNF09's "malformed response" test leg — that leg isn't one of the 13 codes, it's the client's own parse-failure detection. requirements.md §11 shows only 10 of the 13 as "minimum" — the hierarchy covers all 13.
- **RNF09 test harness:** mocktail stubs a single `ApiClient` interface (thin dio wrapper) per repository test — not a fake transport/adapter layer. One shared table-driven helper drives the 5 endpoints × 3 failure-types = 15 scenario matrix.
- **View-state:** generic `Resource<T>` (idle/loading/data/error) in core, but only for single-source-of-truth fetch screens (RF06 results, RF09 dashboard). Rejected forcing it onto RF02 (capture pipeline: recording/processing/transcribed/error is its own state machine) or RF07 (composite of auth × sync × data, three independent streams) — downgraded the brainstorm's "one enum for all nine screens" claim as the wrong abstraction for those two.
- **isolatedSideEffect helper** (RF08/RF10 shared failure-isolation wording): contract decided now — never-throws wrapper returning `Either<Failure,T>` — but implementation deferred to RF10, its first real consumer (RF04 → RF10 → RF08), not built speculatively in F000. Must live in `core/` so RF08 reuses it without a cross-feature import.
- **Entry domain model:** carries `serverRevision` (int) + `updatedAt` (timestamp), **not** `sync_status`. requirements.md §8's data-model table is wrong on this field — confirmed against `sync-badge.md` and the Entry schema in openapi.yaml. The 3-state sync badge is a pure function of these two fields plus pending-local-write state, computed client-side, never supplied by the server.

## Corrections to prior material

- requirements.md §8 (`entries.sync_status` column) contradicts `docs/input/backend/sync-badge.md`; the backend docs win per requirements.md's own precedence rule.
- requirements.md §11's error table is a 10-of-13 excerpt, not the full taxonomy; `error-taxonomy.md` is the complete closed list and must be what the Failure hierarchy is built from.
- AUTH_INVALID's "invalid credentials / biometrics" wording (§11) is imprecise — no biometric call ever reaches the server, so it can only originate from `POST /auth/login`.

## Open / explicitly deferred (not F000's job)

- isolatedSideEffect's concrete implementation — ships with RF10.
- Dashboard cache-invalidation behavior (RF09 AC) — a presentation-layer concern for whichever unit builds RF09, not a local-cache architecture decision.
