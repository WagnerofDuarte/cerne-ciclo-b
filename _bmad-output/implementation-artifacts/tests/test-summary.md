# Test Automation Summary

## Framework

Flutter/Dart has no Playwright/Jest-style web E2E stack. This project's own established "E2E" convention (`test/features/**/*_e2e_test.dart`) drives the real production object graph (`sl` / `get_it`) — real `Dio` with both real interceptors, real `UrlBuilder`, real `hive_ce` persistence — with only the HTTP transport (`HttpClientAdapter`) faked. No device/simulator exists yet (per `AGENTS.md`), so these are not widget/UI-driven tests; they exercise the repository/cubit layer against the real network+disk pipeline. Generated tests follow this existing pattern exactly rather than introducing a new framework.

## Target

`_bmad-output/implementation-artifacts/spec-5-3-combined-search-filter-non-disruptive-clearing.md` and `deferred-work.md` both self-disclosed the same gap: no e2e test drove `entries-search` with the new `source`/`dateFrom`/`dateTo` params over the real network/Hive pipeline — only the mocked-`ApiClient` tier and the fake-repository (cubit/widget) tier covered them.

## Generated Tests

### E2E Tests (real pipeline, faked HTTP transport only)

- [x] `test/features/entries/entries_search_flow_e2e_test.dart` — 2 new cases added to the existing file:
  - "source filter: search(source: audio) sends {q, source} to entries-search over the real pipeline and persists the real result"
  - "date range filter: search(dateFrom/dateTo) sends both as their own UTC ISO8601 strings to entries-search over the real pipeline, with no source param"

Both mirror the serialization convention already proven for `list()` in `entries_filters_flow_e2e_test.dart` (`source` as `.name`, `dateFrom`/`dateTo` as `.toUtc().toIso8601String()`), driven directly against `EntriesRepository.search()` (same tier split as the file's existing tests — cubit-level debounce/race logic is covered separately by `entries_search_cubit_test.dart`).

## Verification

- `fvm flutter analyze` — zero issues
- `fvm flutter test` — 841/841 passed (full suite, including the 2 new cases)

## Coverage

- `entries-search` query-param combinations: unfiltered `q` (pre-existing) + `source` (new) + `dateFrom`/`dateTo` (new) now all covered at the e2e tier.
- Closes the specific gap `deferred-work.md` logged on 2026-11-05 for spec-5-3; does not re-test the combined all-three-params-at-once case, since the unit/cubit tier already covers every I/O-matrix row for that interaction and the e2e tier's job (per the sibling `list()` e2e file's own precedent) is proving the transport/serialization boundary per-param, not the filter-interaction logic itself.

## Next Steps

- Only remaining self-disclosed test gap in `deferred-work.md` is the source-chip "x" removal bridge while a date-range chip is also active (widget-tier, not e2e — out of this workflow's scope).
- No device/simulator or CI exists yet; revisit true on-device E2E once one is introduced (per `AGENTS.md`).

---

## Target (2026-11-05)

`_bmad-output/implementation-artifacts/spec-6-1-send-message-receive-rag-grounded-streaming-response.md` — chat's first vertical slice had no `*_flow_e2e_test.dart` at all (every other feature with an e2e-covered story does), and none of its existing mocked tests (`chat_cubit_test.dart` against a fake `ChatRepository`; `chat_repository_impl_test.dart`/`chat_remote_data_source_test.dart` against a mocked `ApiClient`) drove a real SSE byte stream through the real `ApiClient.postStream` → `ChatRemoteDataSource` buffering → `ChatCubit` token-append pipeline together, the way the app does on every real send.

## Generated Tests

### E2E Tests (real pipeline, faked HTTP transport only)

- [x] `test/features/chat/chat_flow_e2e_test.dart` — new file, 3 cases, driven directly against the real DI-resolved `ChatCubit` (`init()`/`sendMessage()`), with only `HttpClientAdapter` and the native secure-storage/path_provider channels faked:
  - "happy path" — no existing session → bootstrap creates one via a genuine `chat-sessions-create` call, then `sendMessage()` fires a genuine multi-chunk SSE POST to `chat-messages-send/{sessionId}`, with one `token` event deliberately split mid-event across two network chunks to prove the real `\n\n`-boundary buffer joins it correctly; asserts the final `ChatReady` state (both bubbles `complete`, joined AI text) and the real `chat_sessions` Hive write-through.
  - "mid-stream drop" — a queued SSE stream that ends with no `done`/`error` event; asserts the AI bubble's partial text is kept (never cleared) and marked `failed`, with no exception escaping the cubit.
  - "in-band error event" — a queued `error` SSE event with a taxonomy code (`RATE_LIMITED`); asserts the bubble is marked `failed` and exactly one POST fires (`chat-messages-send` is excluded from `RetryInterceptor`'s transparent retry).

## Verification

- `fvm flutter analyze` — zero issues (project-wide)
- `fvm flutter test` — 906/906 passed (full suite, including the 3 new cases)

## Coverage

- Story 6.1's 3 visible message states (streaming→complete, mid-stream-drop→failed, in-band-error→failed) are now each proven once at the real-pipeline tier, on top of the existing mocked-tier coverage of the full I/O matrix.
- Session bootstrap's "create when none exists" branch is exercised through the real `chat-sessions-create` call; the "reuse most recent existing session" branch is exercised in the other two cases.

## Next Steps

- Not covered here (out of scope for this run, no gap self-disclosed for it): the bootstrap-failure path (`chat-sessions-list`/`create` erroring on screen open) and the offline-cache fallback for `listSessions`/`listMessages` — both already have dedicated mocked-tier coverage, and no deferred-work entry flags a real-pipeline gap for them.
- No device/simulator or CI exists yet; revisit true on-device E2E once one is introduced (per `AGENTS.md`).

---

## Target (2026-11-05, second pass)

Working-tree diff at the start of this run held 3 uncommitted "round-2 review fix" changes to story 6.2's chat feature, none of them yet covered by any test:

1. `chat_remote_data_source.dart` `listSessions()`/`listMessages()` — a non-empty response where *every* item fails to decode now maps to `Left(MalformedResponse)` instead of `Right([])` (previously indistinguishable from "zero sessions/messages", which would make `ChatCubit._bootstrap()` spuriously `createSession()` and hide the user's real sessions, or silently render a session's history as empty).
2. `chat_repository_impl.dart` `_cachedSessions()` — the offline-cache sort now uses `DateTime.tryParse` (falling back to `DateTime(0)`) instead of `DateTime.parse`, so one cached entry with a malformed `updatedAt` can no longer throw out of the whole offline fallback.
3. `chat_cubit.dart` `switchSession()`/`startNewSession()` — on failure, a stale `ChatReady.isSending: true` (left behind by `_cancelInFlightSend()`, which resets the internal guard but never emits) is now explicitly flipped back to `false`; previously a failed switch/new-session call during an in-flight send left the composer disabled for the rest of the app run.

API-tier tests are the right altitude for all three (pure response-shape/state-transition logic, no real SSE byte-stream or transport-timing concern) — not e2e, which this project reserves for proving the real transport/serialization boundary.

## Generated Tests

### API Tests (mocked `ApiClient`/`ChatRepository`, existing project convention)

- [x] `test/features/chat/data/datasources/chat_remote_data_source_test.dart` — 6 new cases:
  - `listSessions`: "one malformed item is skipped, valid items still decode"
  - `listSessions`: "review fix: a non-empty response where every item fails to decode maps to Left(MalformedResponse), never Right([])"
  - `listMessages`: "a shape mismatch maps to Left(MalformedResponse), never throws" (this case existed for `listSessions` already but was missing entirely for `listMessages`)
  - `listMessages`: "one malformed item is skipped, valid items still decode"
  - `listMessages`: "review fix: a non-empty response where every item fails to decode maps to Left(MalformedResponse), never Right([])"
- [x] `test/features/chat/data/repositories/chat_repository_impl_test.dart` — 1 new case:
  - `listSessions`: "review fix: a malformed cached updatedAt never throws — DateTime.tryParse falls back to DateTime(0), sorting that entry last rather than crashing the whole offline-cache fallback"
- [x] `test/features/chat/presentation/cubit/chat_cubit_test.dart` — 2 new cases (under the existing `switchSession()/startNewSession() — spec-6-2` group):
  - "review fix: a switchSession failure while a send was in flight flips the stale isSending flag back to false, so the composer isn't left disabled for the rest of the app run"
  - "review fix: a startNewSession failure while a send was in flight flips the stale isSending flag back to false too"

## Verification

- `fvm flutter analyze` — zero issues (project-wide)
- `fvm flutter test` — 928/928 passed (full suite, including all 9 new cases)

## Coverage

- All 3 uncommitted round-2 review fixes now have a regression test that fails without the fix and passes with it (verified by reading each fix's diff against its corresponding new test, not just running green).
- `listMessages()` now has parity with `listSessions()` on malformed-response handling (shape-mismatch, per-item-skip, and all-items-malformed cases), closing an asymmetry that predates this run.

## Next Steps

- No e2e-tier test was added for the `isSending` stuck-flag fix: reproducing it at the real-pipeline tier would require extending `chat_flow_e2e_test.dart`'s fake `HttpClientAdapter` to hold an SSE response open mid-stream (via a `StreamController` instead of its current pre-baked chunk list) purely to interleave a concurrent `switchSession()`/`startNewSession()` call — nontrivial plumbing for a mechanism (a `Left` branch flipping a boolean in cubit state) that has no interaction with real SSE parsing. The cubit-level fake-repository test already gives precise control over that interleaving.
- No device/simulator or CI exists yet; revisit true on-device E2E once one is introduced (per `AGENTS.md`).

---

## Target (2026-11-06)

User-requested scope: e2e coverage for story 6.3 (dropped-stream resilience & offline composer lock), now `done` in `sprint-status.yaml`. Its own spec's review-findings list was already fully checked off with unit/widget/datasource-tier regression tests, but `chat_flow_e2e_test.dart` (the real-pipeline tier) had none of it: no test drove `retryMessage()` through the real `chat-messages-retry` endpoint, and no test ever pushed a live event through the real `connectivity_plus` event channel — `connectivityEventChannel` was mocked with an empty `setMockMethodCallHandler` stub that could never actually deliver a reading, and was also declared as the wrong channel type (`MethodChannel` instead of `EventChannel`, invisible until a real stream-push was attempted).

## Generated Tests

### E2E Tests (real pipeline, faked HTTP transport + native channels only)

- [x] `test/features/chat/chat_flow_e2e_test.dart` — 4 new cases, plus one fixture fix:
  - Fixed `connectivityEventChannel`'s declared type (`MethodChannel` → `EventChannel`) and its mock from `setMockMethodCallHandler` (a no-op stub) to `setMockStreamHandler`/`MockStreamHandler.inline`, capturing the live `MockStreamHandlerEventSink` so a test can actually push a connectivity reading — added an `emitConnectivity()` helper that pushes one event and flushes the 5 microtask hops between the fake channel and `ChatCubit`'s own listener.
  - "tap-to-retry ... regenerates that exact bubble in place through the real chat-messages-retry endpoint" — `message_created` arrives then the stream drops; `retryMessage()` is called directly against the real DI-resolved cubit; asserts the same bubble id/position goes `failed` → `complete` with no new bubble pair, and the real request hits `chat-messages-retry/{sessionId}/{serverId}` (`UrlBuilder`-built).
  - "tap-to-retry ... falls back to a full chat-messages-send resend ... never calls chat-messages-retry with no serverId" — stream drops before `message_created` ever arrives; asserts the fallback resend lands in the same bubble slot and no request ever touches `chat-messages-retry`.
  - "a live 'offline' reading ... flips ChatReady.isOffline to true" — pushes `['none']` through the real event-channel pipeline.
  - "connectivity returning flips ChatReady.isOffline back to false" — same pipeline, `['none']` then `['wifi']`.

## Verification

- `fvm flutter analyze` — zero issues (project-wide)
- `fvm flutter test` — 971/971 passed (full suite, including all 4 new cases)

## Coverage

- Story 6.3's 4 acceptance criteria (retry-in-place, offline composer lock, offline "Novo Chat" disable via drawer-level widget tests already in place, connectivity recovery) now each have real-pipeline-tier proof for the two that are cubit/network-shaped (retry, connectivity toggling); the two that are pure-widget-shaped (composer/drawer disabling) remain correctly covered at the widget tier only, matching this project's existing altitude convention.
- Closed a latent gap in the existing fixture itself (the mistyped `EventChannel`/`setMockMethodCallHandler` combination), which meant no prior test — including this story's own dev-authored ones — could ever have exercised a real connectivity change end-to-end; `fvm flutter analyze` catching the type mismatch only after the mock call was switched to `setMockStreamHandler` suggests the old stub was silently inert.

## Next Steps

- Not covered here: a flapping-connectivity e2e case (rapid on/off/on) — already logged in spec-6-3 as a deferred, pre-existing architectural trade-off, not a gap introduced by this run.
- No device/simulator or CI exists yet; revisit true on-device E2E once one is introduced (per `AGENTS.md`).
