---
title: 'Story 6.1 — Send Message & Receive RAG-Grounded Streaming Response'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'f6eb83a3c07be75879b88469a6c962785f0eea24'
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Home/Chat is still `HomeChatPlaceholderScreen` — a non-functional placeholder. RF04's core promise (a conversation grounded in the user's own Entries via the real backend) doesn't exist yet.

**Approach:** Build chat's first vertical slice (domain/data/presentation) to send a message and stream a RAG-grounded response over SSE, rendering exactly three per-message states (streaming, error, complete). Replace the placeholder screen with a minimal real one: header+drawer chrome reused, a message list, and a composer ("+" → existing `InsertionModal`, text field, send icon).

## Boundaries & Constraints

**Always:**
- Exactly 3 visible message states: streaming (progressive text + blinking cursor, cursor skipped under `MediaQuery.of(context).disableAnimations`), error, complete. Bubble text is never cleared once any text streamed in, even on failure.
- `ChatRepository.sendMessage` returns `Stream<Either<Failure, ChatStreamEvent>>`; every other method returns `Future<Either<Failure, T>>` (RNF09).
- Call the backend only via `{FUNCTIONS_BASE_URL}/<x-cerne-function>` (`chat-sessions-list`, `chat-sessions-create`, `chat-messages-list`, `chat-messages-send`) with `apikey` + `Bearer <user token>` headers, never the literal OpenAPI path.
- No connectivity → send resolves immediately to `Failure.networkOffline`; never queued.
- Add streaming to the shared `ApiClient` (`lib/core/network/api_client.dart`) instead of bypassing it — it stays the one façade every datasource calls through (AD-2/AD-5).
- Domain layer (`chat/domain`) imports neither `package:flutter` nor `chat/data` (RNF06).
- Chat's state is its own sealed class, never forced into `Resource<T>` (AD-12).
- On opening Home/Chat, silently ensure one Chat Session exists (reuse the most recent from `chat-sessions-list`, else `chat-sessions-create` with no title) — kept in memory only, no session-switcher UI (Story 6.2's job).
- Reuse `InsertionModal.show(...)` unchanged for the composer's "+".

**Ask First:** none identified — session bootstrap is explicitly scoped to an in-memory value (see Design Notes) to avoid colliding with 6.2.

**Never:** the retry-tap action / `chat-messages-retry` call, offline composer banner/lock, multi-session switcher, bookmark/save-to-journal button, insight card (all Stories 6.2–6.5); rendering the SSE `context` event's retrieval/citation data; any direct AI-provider call.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Session exists, backend streams `message_created→token*→done` | Bubble fills progressively, ends `complete` | N/A |
| Mid-stream drop | Connection closes after some tokens, no `done`/`error` | Bubble keeps partial text, status `failed`, generic error indicator (not retry copy) | `Failure.networkTimeout` surfaced, no exception escapes |
| In-band `error` event | SSE emits `error` with a taxonomy code | Message marked `failed` | `Failure.fromCode(code, message)` |
| Send while offline | No connectivity | Send fails immediately, bubble marked `failed` | `Failure.networkOffline` |
| Bootstrap failure | `chat-sessions-list`/`create` fails on screen open | Screen shows a generic error state, not infinite spinner | Failure surfaced, no crash |

</frozen-after-approval>

## Code Map

- `docs/input/backend/api/openapi.yaml:1156-1306` -- `chat.messages.list/send/retry`, `chat.sessions.list/create`: x-cerne-function names, request/response schemas, SSE order `message_created→context→token*→done|error` (no per-event field schema given).
- `docs/input/backend/error-taxonomy.md` -- closed 13-code set; `NETWORK_OFFLINE` never an actual HTTP response.
- `docs/input/requirements.md:30-35` -- RF04 AC (3 states; dropped stream keeps partial text); `:170-179` -- endpoint-to-RF04 table.
- `lib/core/failure/failure.dart:14-83` -- sealed `Failure`, `retryable`, `Failure.fromCode`.
- `lib/core/resource.dart:1-33` -- doc comment explicitly excludes RF04's chat stream from `Resource<T>`.
- `lib/core/network/api_client.dart:27-148` -- façade to extend with a streaming method; mirror `_send`/`_mapDioException` (88-127) for error mapping.
- `lib/core/di/injection_container.dart:84-92` -- feature-registration call order to extend with `registerChatFeature()`.
- `lib/features/entries/entries_injection.dart:20-84`, `entries/domain/repositories/entries_repository.dart`, `entries/data/repositories/entries_repository_impl.dart`, `entries/data/datasources/entries_remote_data_source.dart` -- DI/Hive-box convention and Either-construction/DTO-parse pattern to mirror for chat's non-streaming calls.
- `lib/core/design_tokens.dart:27,39,51,60,66,90,201-210` -- `colorAccent`, `colorSurfaceElevated`, `colorError`, `colorInfoOffline`, `colorChatBubbleUser`, `colorErrorBg`, radii.
- `lib/features/capture/presentation/widgets/insertion_modal.dart:56-78` -- Reduce Motion pattern to mirror for the streaming cursor.
- `lib/core/navigation/app_router.dart:105-108` -- swap `HomeChatPlaceholderScreen` for the real `ChatScreen`.
- `lib/core/navigation/placeholder_screens.dart:78-150` -- `HomeChatPlaceholderScreen` (header/drawer/composer-trigger chrome to reuse, then delete the class).
- `lib/core/widgets/app_drawer.dart:40`, `lib/features/entries/presentation/widgets/entry_record_card.dart:19` -- stale doc-comment mentions of `HomeChatPlaceholderScreen` to fix.
- `test/core/navigation/app_router_test.dart:257-268` -- existing fake-cubit DI-override pattern (`MeusRegistrosCubit`) to mirror for `ChatCubit`; same file has 13 `find.byType(HomeChatPlaceholderScreen)` assertions (incl. `test/main_test.dart`, `test/core/navigation/placeholder_screens_test.dart:143-192`) needing the swap.
- `docs/input/prototype/prototype-extract.md:63-70` -- Tela 1 visual states (default/streaming/falha/offline).

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/network/api_client.dart` -- add `Stream<Either<Failure,String>> postStream(...)` via `ResponseType.stream`, reusing `_mapDioException` -- keeps ApiClient the one façade; SSE line-splitting stays feature-local.
- [x] `lib/features/chat/domain/entities/{chat_session,chat_message,chat_stream_event}.dart` -- `ChatSession`, `ChatMessage` (role/status enums), sealed `ChatStreamEvent` (`messageCreated`/`token`/`done`) -- no flutter import (RNF06).
- [x] `lib/features/chat/domain/repositories/chat_repository.dart` -- abstract `ChatRepository`: `listSessions()`, `createSession()`, `listMessages(sessionId)` (`Future<Either<Failure,T>>`), `sendMessage(sessionId, content)` (`Stream<Either<Failure,ChatStreamEvent>>`).
- [x] `lib/features/chat/data/models/{chat_session_dto,chat_message_dto}.dart` -- `json_serializable` DTOs + `toEntity()`, mirroring `entry_dto.dart`.
- [x] `lib/features/chat/data/datasources/chat_remote_data_source.dart` -- non-streaming calls via `ApiClient` JSON methods; `sendMessage` via `postStream`, parsing `event:`/`data:` blocks into `ChatStreamEvent`s, mapping an in-band `error` event through `Failure.fromCode` and an unterminated close to `Failure.networkTimeout`; `context` event received and discarded.
- [x] `lib/features/chat/data/repositories/chat_repository_impl.dart` -- implement `ChatRepository`; Hive box cache for `listSessions`/`listMessages` (local fallback), same convention as `entries_injection.dart`.
- [x] `lib/features/chat/chat_injection.dart` + `injection_container.dart:92` -- `registerChatFeature()` opening the chat Hive box and registering datasource/repository/cubit.
- [x] `lib/features/chat/presentation/cubit/{chat_state,chat_cubit}.dart` -- sealed `ChatState` (bootstrap loading/ready/error + append-only message list with per-message streaming/complete/failed); `ChatCubit.init()` (bootstrap session+history) and `.sendMessage(content)` (optimistic user bubble, subscribe to repo stream, append tokens, finalize/fail, never clear text on failure).
- [x] `lib/features/chat/presentation/widgets/chat_bubble.dart` -- user (`colorChatBubbleUser`, squared bottom-right) vs AI (`colorSurfaceElevated`, squared bottom-left) bubble; blinking cursor skipped under Reduce Motion; failure indicator (`colorError`/`colorErrorBg`) replaces timestamp slot on `failed`.
- [x] `lib/features/chat/presentation/screens/chat_screen.dart` -- real screen: same header/drawer chrome as the former placeholder; composer row ("+" → `InsertionModal.show` unchanged, text field placeholder "Escreva uma mensagem...", send icon → `cubit.sendMessage`).
- [x] `lib/core/navigation/app_router.dart:107` -- `ChatScreen(cubit: sl<ChatCubit>())` replacing `const HomeChatPlaceholderScreen()`.
- [x] `lib/core/navigation/placeholder_screens.dart` -- delete the now-unused `HomeChatPlaceholderScreen`.
- [x] `lib/core/widgets/app_drawer.dart:40`, `entry_record_card.dart:19` -- fix the stale comment mentions.
- [x] `test/core/navigation/app_router_test.dart`, `test/main_test.dart`, `test/core/navigation/placeholder_screens_test.dart` -- swap `find.byType(HomeChatPlaceholderScreen)` → `ChatScreen`; add a fake-`ChatRepository`-backed `ChatCubit` DI override mirroring `MeusRegistrosCubit`'s (lines 257-268); drop the placeholder's own test group.
- [x] `test/features/chat/**` -- unit tests for `ChatRepositoryImpl` (SSE parsing incl. drop/offline/error-event cases) and `ChatCubit` (3-state transitions, append-only-on-error) covering the I/O matrix.

**Acceptance Criteria:**
- Given an existing session with prior messages, when Home/Chat opens, then history loads (cache-first where offline-readable) and the composer is enabled.
- Given no session exists yet, when Home/Chat opens, then exactly one session is silently created and reused for subsequent sends.
- Given a message referencing a weeks-old Entry, when the response streams, then it is grounded in semantic retrieval end-to-end against the real backend.
- Given a response is streaming, when it renders, then only streaming/error/complete are visible, with Reduce Motion skipping the cursor blink.
- Given a stream drops or returns an in-band error, when detected, then the partial bubble text is never cleared and no exception escapes the cubit.

### Review Findings

**Patch:**
- [x] [Review][Patch] New `ApiClient.postStream`/`_mapStreamDioException` `AUTH_EXPIRED` → `SessionExpiryNotifier.notifyExpired()` branch has zero test coverage — the sibling non-stream path (`_mapDioException`) is fully covered by the existing Story 1.5 test group, but none of the 6 new `postStream` tests construct an `AUTH_EXPIRED` in-band stream error, so a regression in this duplicated branch (e.g. a mid-chat token expiry) would silently fail to surface the re-auth overlay with no test catching it. [lib/core/network/api_client.dart:171]
- [x] [Review][Patch] `ChatCubit.close()` cancels `_sendSubscription` without completing the in-flight `sendMessage()`'s `Completer` — `StreamSubscription.cancel()` never fires `onDone`/`onError`, so closing the cubit mid-send leaves that `Future` permanently unresolved (a leak, currently unobserved since no caller awaits it — see the related finding below). [lib/features/chat/presentation/cubit/chat_cubit.dart:279-282]
- [x] [Review][Patch] `ChatRemoteDataSource.sendMessage()` normalizes `\r\n` → `\n` on each raw chunk *before* appending to `buffer` (`buffer += chunk.replaceAll('\r\n', '\n')`), so a `\r\n` line ending split exactly across two stream chunks (chunk ends `\r`, next starts `\n`) is never normalized — the literal `\r\n` survives inside `buffer`, risking a corrupted event-name/data-line parse (a spurious `malformedResponse`/failed bubble) for that message. Fix: concatenate first, then normalize the whole buffer. [lib/features/chat/data/datasources/chat_remote_data_source.dart:119]
- [x] [Review][Patch] "Most recent session" selection (`ChatCubit._bootstrap()`) and the offline-cache session ordering (`ChatRepositoryImpl._cachedSessions()`) both sort via raw `String.compareTo` on the `updatedAt` ISO-8601 field, diverging from `EntriesRepositoryImpl`'s own convention of `DateTime.parse(...).compareTo(...)` for the same kind of timestamp — any drift in fractional-second precision or offset notation between records would silently reorder which session counts as "most recent," with no error surfaced. [lib/features/chat/presentation/cubit/chat_cubit.dart:76, lib/features/chat/data/repositories/chat_repository_impl.dart:143]
- [x] [Review][Patch] `ChatRemoteDataSource.listSessions()`/`listMessages()` parse the live response in one all-or-nothing `try`/`catch` around `data.map(...).toList()` — a single malformed item discards every other valid session/message in that response (`Left(malformedResponse)` for the whole call), while the offline-cache fallback (`ChatRepositoryImpl._cachedSessions`/`_cachedMessages`) explicitly decodes item-by-item and skips just the bad one. The live path is strictly worse-handled than the same data once cached — apply the same per-item isolation to the live parse step. [lib/features/chat/data/datasources/chat_remote_data_source.dart:24-43,60-81]
- [x] [Review][Patch] `RetryInterceptor`'s new `neverRetriedFunctions` exclusion tests (`retry_interceptor_test.dart`) build `DioException`s with bare paths like `/chat-messages-send`, but the real call always goes through `pathParams: [sessionId]`, producing `/chat-messages-send/{sessionId}`. The exclusion happens to still work today because `HeaderInterceptor.functionNameOf` only reads the first path segment, but nothing proves the exclusion against that actual trailing-segment shape. [test/core/network/retry_interceptor_test.dart:169]
- [x] [Review][Patch] This story's own Design Notes say chat-session bootstrap is "kept in memory only, never persisted to a Hive entry," but `ChatRepositoryImpl.createSession()`/`listSessions()` do write every session (including the one bootstrap just created) to the `chat_sessions` Hive box — the Code Map's own separate instruction ("Hive box cache for `listSessions`/`listMessages`") confirms this caching is intentional and correct, so the code isn't wrong; the Design Notes wording is. Reword to scope "in memory only" to the active-session *selection*, not the cache. [Design Notes, below]
- [x] [Review][Patch] `_ChatComposer`'s doc comment claims the composer is "Disabled as a whole while the bootstrap hasn't resolved yet or while an AI bubble is still streaming," but the "+" `IconButton` (`InsertionModal.show`) is never gated by `canSend` — only the text field and send button are. Functionally this mirrors the deleted placeholder's own always-tappable "+", which is plausibly correct; the comment is what's wrong. [lib/features/chat/presentation/screens/chat_screen.dart:208-211]
- [x] [Review][Patch] `entry_record_card.dart`'s Code-Map-mandated stale-comment fix replaces one stale `HomeChatPlaceholderScreen` reference with a new inaccurate one — it claims `Icons.chat_bubble_outline` is now used by `ChatScreen`'s `_ChatBootstrapErrorView`, but that view actually renders `Icons.error_outline`; no icon in the new `ChatScreen` uses `chat_bubble_outline`. [lib/features/entries/presentation/widgets/entry_record_card.dart:18-20]

**Defer:**
- [x] [Review][Defer] `_ChatBootstrapErrorView` renders every bootstrap-failure cause (offline, timeout, server error) identically via `colorError`, even though the spec's own Code Map lists `colorInfoOffline` as a relevant token for this story and it's never referenced anywhere in the diff — no acceptance criterion requires differentiated styling per cause. [lib/features/chat/presentation/screens/chat_screen.dart:173-204] — deferred, pre-existing
- [x] [Review][Defer] `ChatScreen`'s `BlocConsumer` listener calls `_scrollToBottomSoon()` on every `ChatReady` emission, which fires once per streamed token — a long AI response registers a fresh `addPostFrameCallback` on nearly every frame. Harmless today (cheap, idempotent `jumpTo`), but unthrottled. [lib/features/chat/presentation/screens/chat_screen.dart:64] — deferred, pre-existing
- [x] [Review][Defer] The composer's client-side 8000-char cap (`TextField(maxLength: 8000, ...)`) assumes the backend counts `content` length the same way Flutter's `maxLength` does; nothing in this diff confirms the backend's own counting unit, and this can't be verified from the client repo alone. [lib/features/chat/presentation/screens/chat_screen.dart:253] — deferred, pre-existing
- [x] [Review][Defer] No test drives an `authExpired` bootstrap failure through `ChatCubit`/`ChatScreen` — the underlying re-auth-overlay trigger is already covered generically by Story 1.5's `_mapDioException` test group (which `listSessions`/`createSession`/`listMessages` all go through), so this is a thin-spot regression test, not a live gap. [test/features/chat/presentation/cubit/chat_cubit_test.dart] — deferred, pre-existing
- [x] [Review][Defer] The streaming AI bubble (`ChatBubble`) renders growing text via plain `Text.rich` with no `Semantics(liveRegion: true)` — a screen-reader user gets no incremental announcement while tokens stream in. Same unaddressed accessibility pattern already deferred for other widgets elsewhere in this codebase; no accessibility requirement is scoped for this story. [lib/features/chat/presentation/widgets/chat_bubble.dart] — deferred, pre-existing
- [x] [Review][Defer] The two new `chat_sessions`/`chat_messages` Hive boxes accumulate every session/message ever fetched with no eviction/TTL — the same unbounded-growth pattern already deferred for the `entries` Hive box (spec-4-1). [lib/features/chat/chat_injection.dart] — deferred, pre-existing
- [x] [Review][Defer] `ChatCubit.sendMessage()`'s internal `await completer.future` is never awaited by its only caller (`ChatScreen._send()`), making the method effectively fire-and-forget from the UI. Harmless today (nothing throws after that await point), but a future story (e.g. 6.5's insight-trigger counting) adding logic there would have its errors/results silently dropped unless the call site starts awaiting. [lib/features/chat/presentation/screens/chat_screen.dart:55] — deferred, pre-existing

**Reject (noise, dropped):** Unguarded `Hive.openBox<Map>()` calls in `chat_injection.dart` and the lack of a retry affordance on `ChatBootstrapError` were both independently raised by two review layers each, but both are already self-disclosed in `deferred-work.md` by this story's own commit — the Hive-open gap as a pre-existing cross-cutting pattern shared with `entries_injection.dart`, and the no-retry gap as satisfying the written I/O matrix ("a generic error state, not infinite spinner") rather than a regression. Handled elsewhere; not re-added here.

## Spec Change Log

## Design Notes

- SSE per-event field names aren't specified beyond the ordering `message_created→context→token*→done|error` (openapi.yaml:1257) — this spec assumes `token` carries a `delta` text field and `message_created` carries the persisted user-message id; anything that fails to parse as expected becomes `Failure.malformedResponse`, never a crash.
- A connection closing without a `done`/`error` event (mid-stream drop) is treated as `Failure.networkTimeout` — the taxonomy has no dedicated "dropped stream" code.
- Session bootstrap (list-or-create one session) is a minimal stand-in for Story 6.2's real session management: *which* session is the active one is kept in memory only (`ChatReady.sessionId`), never written to Hive as a dedicated "active session" record, so 6.2 can own that persistence shape without migrating this story's data. The `chat_sessions` Hive box itself does cache every session returned by `listSessions()`/`createSession()` (including the one this story's own bootstrap creates) — that's the ordinary offline read-cache the Code Map already calls for, not the active-session selection.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass, including new chat tests and updated navigation tests
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- expected: regenerates chat DTOs' `.g.dart` with no conflicts

## Suggested Review Order

**Streaming transport (SSE + network layer)**

- Entry point — owns all SSE event-boundary buffering/parsing, the core new mechanism this story introduces.
  [`chat_remote_data_source.dart:103`](../../lib/features/chat/data/datasources/chat_remote_data_source.dart#L103)

- Maps each SSE event name to a domain event or an in-band `Failure`, skipping `context` and unknown events.
  [`chat_remote_data_source.dart:163`](../../lib/features/chat/data/datasources/chat_remote_data_source.dart#L163)

- New raw-streaming method on the shared network façade — kept feature-agnostic, no SSE grammar here.
  [`api_client.dart:108`](../../lib/core/network/api_client.dart#L108)

- Review fix: incremental UTF-8 decode across chunk boundaries — a per-chunk decode corrupted pt-BR accented characters.
  [`api_client.dart:131`](../../lib/core/network/api_client.dart#L131)

- Review fix: excludes the two non-idempotent chat POSTs from transparent retry, which could otherwise silently resend a message.
  [`retry_interceptor.dart:36`](../../lib/core/network/retry_interceptor.dart#L36)

**Chat state machine (bootstrap + send guard)**

- Concurrency-safe session bootstrap — a second concurrent call reuses the same in-flight future, never creates two sessions.
  [`chat_cubit.dart:51`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L51)

- Review fix: the send-in-flight guard is its own field now, not derived from scanning loaded messages' persisted status.
  [`chat_cubit.dart:130`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L130)

- Clears the guard and the UI-facing signal together, the one place both flip back after a send ends.
  [`chat_cubit.dart:200`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L200)

- The composer's one enable/disable signal — a dedicated field, not a scan over message statuses.
  [`chat_state.dart:61`](../../lib/features/chat/presentation/cubit/chat_state.dart#L61)

**Offline cache resilience**

- Review fix: one corrupted cache entry is skipped per-item now, instead of discarding the whole cached list.
  [`chat_repository_impl.dart:132`](../../lib/features/chat/data/repositories/chat_repository_impl.dart#L132)

- Review fix: a local cache-write failure after a successful remote create no longer masks that success as an error.
  [`chat_repository_impl.dart:64`](../../lib/features/chat/data/repositories/chat_repository_impl.dart#L64)

**Screen & UI wiring**

- Replaces the deleted placeholder at the real Home/Chat route — the one line that makes this story reachable.
  [`app_router.dart:109`](../../lib/core/navigation/app_router.dart#L109)

- Review fix: only auto-scrolls to the bottom when the view was already there, so manual scroll-up survives streaming.
  [`chat_screen.dart:64`](../../lib/features/chat/presentation/screens/chat_screen.dart#L64)

- Review fix: a client-side 8000-char cap surfaces the backend's own limit before a failed round trip.
  [`chat_screen.dart:253`](../../lib/features/chat/presentation/screens/chat_screen.dart#L253)

- Review fix: stops the cursor's ticker once a message finishes streaming, instead of animating forever.
  [`chat_bubble.dart:52`](../../lib/features/chat/presentation/widgets/chat_bubble.dart#L52)

**Peripherals (DI, tokens, tests)**

- Feature registration, mirroring `entries_injection.dart`'s pattern — two Hive boxes, repository, long-lived cubit.
  [`chat_injection.dart:22`](../../lib/features/chat/chat_injection.dart#L22)

- New chat-bubble visual tokens (prototype is silent on exact sizing — decided per AGENTS.md policy).
  [`design_tokens.dart:643`](../../lib/core/design_tokens.dart#L643)

- Review fix: closes the gap where no test resolved the real `registerChatFeature()` DI graph end-to-end.
  [`bootstrap_integration_test.dart`](../../test/core/di/bootstrap_integration_test.dart)

- Full SSE/cubit/repository test coverage for this story's I/O matrix plus every review-fix regression test.
  [`test/features/chat/`](../../test/features/chat/)
