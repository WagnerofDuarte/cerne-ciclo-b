---
title: 'Story 6.3 — Dropped-Stream Resilience & Offline Composer Lock'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
baseline_commit: '43351cf59fa0a85125a5d50eefbe984600c7b403'
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A dropped/failed AI response is marked `failed` with no retry path — `ChatCubit` has none. The composer has no offline-awareness either; `_ChatComposer`'s own doc (`chat_screen.dart:284-288`) names this gap as "Story 6.3's job," and no connectivity detection exists anywhere in the app.

**Approach:** Add `ChatCubit.retryMessage`, backed by a new `ChatRepository.retryMessage`/`ChatRemoteDataSource.retryMessage` mirroring `sendMessage`'s SSE consumption against `chat-messages-retry`. Add a feature-local `ConnectivityWatcher` (domain service, `connectivity_plus` impl) that `ChatCubit` consumes into a new `ChatReady.isOffline` flag, gating the composer, a new offline banner, and the drawer's "Novo Chat".

## Boundaries & Constraints

**Always:**
- Tap-to-retry renders only on a `failed` AI bubble — copy "Falha ao gerar resposta — toque para tentar novamente" (`cerne-prototype.html`), replacing `chat_bubble.dart:136-141`; tappable, 44pt min (`DesignTokens.insertionModalTapTargetMin`), `Semantics(button: true)`.
- Retry resets the *same* bubble (id, position) to `streaming`/empty, then reuses `_applyStreamEvent`/`_markFailed` (`chat_cubit.dart:358-421`) unchanged — never a second bubble, never a duplicate question.
- Retry is keyed by the user message's persisted id, captured from `message_created` (currently a no-op, `chat_cubit.dart:366-371`). Add `ChatUiMessage.serverId`: from `_fromDomain` (`chat_cubit.dart:251-256`, `= message.id`) and, for an in-session send, from `message_created`'s `userMessageId`.
- `ConnectivityWatcher`: feature-local domain service (`chat/domain/services/`) + `connectivity_plus` impl (`chat/data/services/`), injected into `ChatCubit`'s ctor — mirrors `MicRecorder`'s domain/data split (`lib/features/capture/domain/services/mic_recorder.dart`), never through `ChatRepository`.
- `ChatReady` gains `isOffline` (default `false`), driving: `_ChatComposer.canSend` (`chat_screen.dart:304`, text+send only — "+" stays tappable); an offline banner between `_ChatHeader` and the list (`chat_screen.dart:148-150`), copy "Sem conexão — histórico disponível, novas mensagens bloqueadas", `Icons.wifi_off`, `DesignTokens.colorInfoOffline`/`colorOnPrimary` (existing tokens); `AppDrawer`'s "Novo Chat" (`app_drawer.dart:73-77`, disabled + dimmed).
- Add `'chat-messages-retry'` to `RetryInterceptor.neverRetriedFunctions` (`retry_interceptor.dart:36-39`).

**Ask First:** none identified.

**Never:**
- Changing `ChatRepositoryImpl`'s existing reactive `Failure.networkOffline` handling — `isOffline` is additive only.
- Calling `chat-messages-retry` with no `serverId` (stream dropped before `message_created`) — falls back to a full `sendMessage` resend of the same content into the same bubble slot.
- A second retry while one is in flight — reuses `_isSending` verbatim.
- Disabling the "+" when offline, or removing `AppDrawer._startNewSession`'s offline `SnackBar` (spec-6-2) — both stay.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap retry, normal | Failed AI bubble; preceding user message has `serverId` | Bubble resets to `streaming`/empty, fills via `chat-messages-retry`'s SSE, ends `complete` | A second failure re-marks `failed`, stays tappable |
| Tap retry, no `serverId` | Stream dropped before `message_created` arrived | Falls back to `sendMessage`, same content, same slot | Same handling as any send |
| Goes offline mid-session | `ConnectivityWatcher` emits `false` | Composer + "Novo Chat" disable, banner appears, history stays scrollable | N/A |
| Comes back online | `ConnectivityWatcher` emits `true` | Banner disappears, composer + "Novo Chat" re-enable | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/chat/presentation/cubit/chat_cubit.dart:18` (ctor) -- add `ConnectivityWatcher` param; subscribe, store `_isOffline`, emit on `ChatReady` when it changes.
- `lib/features/chat/presentation/cubit/chat_cubit.dart:313-317` (`sendMessage` `onData`) -- on `ChatMessageCreatedEvent`, set `userMessage.serverId` before `_applyStreamEvent`.
- `lib/features/chat/presentation/cubit/chat_cubit.dart:251-256` (`_fromDomain`) -- `serverId: message.id`.
- `lib/features/chat/presentation/cubit/chat_cubit.dart:274-341` (`sendMessage`) -- mirror for new `retryMessage(aiMessageId)`: same guards, find target + preceding user message's `serverId`, reset content/status, subscribe (`retryMessage` or `sendMessage` fallback), reuse `_applyStreamEvent`/`_markFailed`/`_finishSending`.
- `lib/features/chat/presentation/cubit/chat_state.dart:41-98` (`ChatReady`) -- add `isOffline` + `copyWith`.
- `lib/features/chat/presentation/cubit/chat_state.dart:108-144` (`ChatUiMessage`) -- add `serverId` + `copyWith`/`==`/`hashCode`/`toString`.
- `lib/features/chat/domain/repositories/chat_repository.dart:53-56` -- add `retryMessage(sessionId, userMessageId)`.
- `lib/features/chat/data/repositories/chat_repository_impl.dart:116-122` (`sendMessage`) -- sibling `retryMessage` passthrough.
- `lib/features/chat/data/datasources/chat_remote_data_source.dart:137-271` -- extract shared SSE buffer/parse helper; add `retryMessage` hitting `chat-messages-retry`, `pathParams: [sessionId, userMessageId]`, `data: const {}`.
- `lib/features/chat/domain/services/connectivity_watcher.dart` (new) -- `abstract class ConnectivityWatcher { Stream<bool> watch(); }`, mirrors `mic_recorder.dart`.
- `lib/features/chat/data/services/connectivity_plus_watcher.dart` (new) -- `connectivity_plus` impl.
- `lib/features/chat/chat_injection.dart:32-53` -- register `ConnectivityWatcher`; inject into `ChatCubit` (line 50-51).
- `lib/core/network/retry_interceptor.dart:36-39` -- add `'chat-messages-retry'`.
- `lib/features/chat/presentation/widgets/chat_bubble.dart:17-24,126-143` -- add `onRetry` callback; tappable region, min 44pt, `Semantics(button: true)`.
- `lib/features/chat/presentation/screens/chat_screen.dart:181-189` -- wire `onRetry: () => cubit.retryMessage(messages[index].id)`.
- `lib/features/chat/presentation/screens/chat_screen.dart:148-150` -- insert offline banner (`state is ChatReady && state.isOffline`).
- `lib/features/chat/presentation/screens/chat_screen.dart:304` -- `canSend` += `!state.isOffline`.
- `lib/core/widgets/app_drawer.dart:73-77` -- gate "Novo Chat" on `!isOffline` via `BlocBuilder`.
- `pubspec.yaml` -- add via `fvm flutter pub add connectivity_plus`.
- `test/features/chat/**`, `test/core/widgets/app_drawer_test.dart` -- extend per the I/O matrix; reuse `test/core/navigation/app_router_test.dart:128-156`'s `_FakeChatRepository`; add a fake `ConnectivityWatcher`.

## Tasks & Acceptance

**Execution:**
- [x] `chat/domain/services/connectivity_watcher.dart`, `chat/data/services/connectivity_plus_watcher.dart` -- create the abstraction + impl.
- [x] `chat/presentation/cubit/chat_state.dart` -- `ChatReady.isOffline`, `ChatUiMessage.serverId`.
- [x] `chat/presentation/cubit/chat_cubit.dart` -- connectivity subscription, `serverId` capture, `retryMessage`.
- [x] `chat/domain/repositories/chat_repository.dart`, `data/repositories/chat_repository_impl.dart`, `data/datasources/chat_remote_data_source.dart` -- `retryMessage` through all three layers.
- [x] `chat/chat_injection.dart` -- wire `ConnectivityWatcher` into DI and `ChatCubit`.
- [x] `core/network/retry_interceptor.dart` -- exclude `chat-messages-retry` from transparent retry.
- [x] `chat/presentation/widgets/chat_bubble.dart`, `presentation/screens/chat_screen.dart`, `core/widgets/app_drawer.dart` -- tap-to-retry UI, offline banner, composer lock, "Novo Chat" disable.
- [x] Extend the test files listed in the Code Map per the I/O matrix.

**Acceptance Criteria:**
- Given a dropped/failed AI response, when I tap its retry copy, then the same bubble regenerates in place, with no new question bubble and no re-send of the question.
- Given I'm offline, when Home/Chat is open, then the composer is disabled with the offline banner visible, while history stays fully visible and scrollable.
- Given I'm offline, when I open the side menu, then "Novo Chat" is disabled.
- Given connectivity returns, when `isOffline` flips back, then the composer and "Novo Chat" re-enable automatically.

### Review Findings

- [x] [Review][Patch] Add an e2e regression test for the stale-`_sendSubscription`-nulling fix — a second `sendMessage`/`retryMessage` on the same cubit after a prior one completed could hang again if this regresses, and no current test (fake-stream-backed) would catch it [lib/features/chat/presentation/cubit/chat_cubit.dart:479]
- [x] [Review][Patch] Add a regression test for `ChatCubit.close()` while `retryMessage()` is in-flight — the "cancel() alone leaves the Future unresolved" bug's existing regression test covers `sendMessage` but was never duplicated for `retryMessage` [lib/features/chat/presentation/cubit/chat_cubit.dart:432]
- [x] [Review][Patch] Wrap `ConnectivityPlusWatcher.watch()`'s `onConnectivityChanged.listen()` call in try/catch, mirroring the already-guarded `checkConnectivity()` seed path right beside it [lib/features/chat/data/services/connectivity_plus_watcher.dart:40]
- [x] [Review][Patch] Add a negative-case test proving a `failed` bubble built with `onRetry: null` exposes no button semantics node, matching the code's own "must never" comment [lib/features/chat/presentation/widgets/chat_bubble.dart:136]
- [x] [Review][Patch] Add retry-path test coverage for the `context` SSE event — `openapi.yaml` documents the same event order for `chat-messages-retry` as `sendMessage`, but no retry test exercises it [lib/features/chat/data/datasources/chat_remote_data_source.dart]
- [x] [Review][Patch] Document `ConnectivityWatcher.watch()`'s single-vs-multiple-call contract — safe today with one caller, but undocumented as a constraint [lib/features/chat/domain/services/connectivity_watcher.dart]
- [x] [Review][Patch] Add a widget-level test proving a rapid double-tap on the retry affordance is swallowed — only the cubit-level "second retry while in flight" case is covered today [lib/features/chat/presentation/widgets/chat_bubble.dart]
- [x] [Review][Defer] `ConnectivityPlusWatcher` reports interface state, not real reachability — the composer can show enabled while a send simultaneously fails as `NetworkOffline`; mitigated in practice by this same story's own tap-to-retry affordance, and reconciling the two signals would mean touching `ChatRepositoryImpl`'s existing `networkOffline` handling, which this story's Boundaries forbid [lib/features/chat/data/services/connectivity_plus_watcher.dart] — deferred, pre-existing architectural trade-off
- [x] [Review][Defer] No test covers a flapping connectivity signal (rapid on/off/on, or a transition arriving mid-send) verifying the banner/composer/`_isSending` stay consistent — expected behavior for this case is unspecified anywhere in the spec [lib/features/chat/presentation/cubit/chat_cubit.dart] — deferred, pre-existing
- [x] [Review][Defer] `ChatRepositoryImpl.retryMessage` never writes a successful retry's new content back to the Hive cache — stale cached content could reappear after an offline relaunch right after a successful retry; mirrors `sendMessage`'s existing no-persist-on-success design from story 6.1, not newly introduced here [lib/features/chat/data/repositories/chat_repository_impl.dart:125] — deferred, pre-existing

## Spec Change Log

## Design Notes

- `serverId` (not reusing `id`) avoids ever swapping a `ChatUiMessage.id` mid-stream — `id` stays the stable lookup key; `serverId` is only the value sent to `chat-messages-retry`.
- `ConnectivityWatcher` lives in `chat/domain/services/`, not `core/`, since no other feature needs connectivity yet; promote it later if one does.

## Verification

**Commands:**
- `fvm flutter pub get` -- expected: resolves with `connectivity_plus` added, no conflicts
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass, including new retry/offline coverage

## Suggested Review Order

**Dropped-stream retry**

- Entry point — regenerates the same bubble in place via `chat-messages-retry`, or falls back to a full resend when no `serverId` was ever captured; guarded by `_isSending`/`isOffline`.
  [`chat_cubit.dart:384`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L384)

- Shared SSE-subscription plumbing behind both `sendMessage` and `retryMessage` — one `onData`/`onError`/`onDone` shape, no duplicated wiring.
  [`chat_cubit.dart:446`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L446)

- `ChatUiMessage.serverId` — the persisted user-message id `retryMessage` keys off, captured from `message_created`.
  [`chat_state.dart:146`](../../lib/features/chat/presentation/cubit/chat_state.dart#L146)

- The new port, mirroring `sendMessage`'s own terminal-handling doc.
  [`chat_repository.dart:69`](../../lib/features/chat/domain/repositories/chat_repository.dart#L69)

- Pure passthrough, same "no Hive persistence" rationale as `sendMessage`.
  [`chat_repository_impl.dart:125`](../../lib/features/chat/data/repositories/chat_repository_impl.dart#L125)

- Calls `chat-messages-retry` through the shared `_consumeSse` helper extracted from `sendMessage`'s own buffer/parse loop.
  [`chat_remote_data_source.dart:156`](../../lib/features/chat/data/datasources/chat_remote_data_source.dart#L156)

- Excludes the new endpoint from transparent interceptor-level retry — same non-idempotent-POST rationale as `chat-messages-send`.
  [`retry_interceptor.dart:38`](../../lib/core/network/retry_interceptor.dart#L38)

- Tap-to-retry UI — the exact prototype copy, deduped into one constant, `Semantics(button:true)` only when `onRetry` is actually wired.
  [`chat_bubble.dart:123`](../../lib/features/chat/presentation/widgets/chat_bubble.dart#L123)

- Wires the tap to `ChatCubit.retryMessage`.
  [`chat_screen.dart:202`](../../lib/features/chat/presentation/screens/chat_screen.dart#L202)

**Offline composer lock**

- The feature-local connectivity port — mirrors `MicRecorder`'s domain/data split, never routed through `ChatRepository`.
  [`connectivity_watcher.dart:10`](../../lib/features/chat/domain/services/connectivity_watcher.dart#L10)

- `connectivity_plus` impl — live `onConnectivityChanged` subscription starts immediately; the initial `checkConnectivity()` read is a non-blocking best-effort seed (review fix: a hang there can no longer stall live updates).
  [`connectivity_plus_watcher.dart:36`](../../lib/features/chat/data/services/connectivity_plus_watcher.dart#L36)

- Folds each reading into `_isOffline`, re-emitting it onto the current `ChatReady` — the one place the signal enters cubit state.
  [`chat_cubit.dart:600`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L600)

- `ChatReady.isOffline` — the field every UI gate below reads.
  [`chat_state.dart:96`](../../lib/features/chat/presentation/cubit/chat_state.dart#L96)

- Composer text field + send icon disable — the "+" stays tappable regardless.
  [`chat_screen.dart:360`](../../lib/features/chat/presentation/screens/chat_screen.dart#L360)

- The offline banner, docked above the message list.
  [`chat_screen.dart:157`](../../lib/features/chat/presentation/screens/chat_screen.dart#L157)

- "Novo Chat" disable in the drawer.
  [`app_drawer.dart:82`](../../lib/core/widgets/app_drawer.dart#L82)

- DI wiring — the one real `Connectivity`/`ConnectivityWatcher` registration feeding `ChatCubit`.
  [`chat_injection.dart:51`](../../lib/features/chat/chat_injection.dart#L51)

**Peripherals**

- New dependency, commented inline.
  [`pubspec.yaml:67`](../../pubspec.yaml#L67)

- Unit coverage for the real adapter's online/offline mapping and hang-safety — the one thing every other test bypasses via the fake.
  [`connectivity_plus_watcher_test.dart:1`](../../test/features/chat/data/services/connectivity_plus_watcher_test.dart#L1)

- Shared controllable fake used everywhere else `ChatCubit` is constructed directly.
  [`fake_connectivity_watcher.dart:1`](../../test/support/fake_connectivity_watcher.dart#L1)
