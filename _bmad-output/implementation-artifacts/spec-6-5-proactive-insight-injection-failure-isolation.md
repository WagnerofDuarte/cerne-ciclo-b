---
title: 'Story 6.5 — Proactive Insight Injection & Failure Isolation'
type: 'feature'
created: '2026-11-06'
status: 'done'
review_loop_iteration: 0
baseline_commit: '09b24965a5ca704f231b1899c7792e83f150bf87'
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The assistant never surfaces a pattern from the user's own history unprompted — `ChatRepository` has no insight-generation method, `ChatReady` has no slot for one, and nothing counts messages or idle time within a session.

**Approach:** `ChatCubit` tracks a per-session trigger window (5 user messages sent OR 2 minutes idle, whichever first) and fires `ChatRepository.generateInsight()` fire-and-forget through `isolatedSideEffect` (story 6.4's helper, its first unawaited caller) the instant the window closes, reopening a fresh window immediately. A successful, `status: 'ready'` result is appended onto `ChatReady` as a single nullable `activeInsight` value — rendered as the ochre-spine "INSIGHT" card at the end of the message list — never a second state container. Any failure (transport or in-payload `status != 'ready'`) is silently dropped.

## Boundaries & Constraints

**Always:**
- Per active session: a counter (user messages sent via `sendMessage` only, never `retryMessage`) and a `Timer` (restarted on every `sendMessage` and every fire) race; whichever hits its threshold first calls `generateInsight(sessionId, triggerType:, triggerKey:)`, then immediately resets the counter, generates a fresh `triggerKey`, and restarts the timer — before the network call resolves, so the window closes structurally and the other condition can never also fire for it.
- The call goes through `isolatedSideEffect`, **unawaited** — the first caller not to await it (6.4's `bookmarkMessage` does await it).
- A failure — transport `Left`, or a 200 with `status != 'ready'` (RF08: "never an HTTP error; a failure becomes `status='failed'`") — is dropped silently: no card, no overlay, no retry affordance.
- `ChatReady.activeInsight` (nullable `ChatInsight`) is the only new state; the 3 existing direct `ChatReady(...)` constructions in `_bootstrap`/`switchSession`/`startNewSession` already start it `null` — only the counter/timer need an explicit reset call at those sites.
- `dismissInsight()` clears `activeInsight` via a direct `ChatReady(...)` construction (`copyWith`'s `??` can't express "set to null", same reason `restoreScrollOffset` never clears instead of fixing `copyWith`); never calls the backend (no dismiss endpoint in the contract) and never touches any other field.
- An insight resolving after `switchSession`/`startNewSession` moved away is dropped (`ChatReady.sessionId` no longer matches).
- Insight card tokens (spine width, card padding, label spacing, dismiss icon size) go in `design_tokens.dart`, never hardcoded (AGENTS.md).

**Ask First:** none — the single-nullable-`activeInsight` shape, reset-before-fire ordering, and the `Duration` test seam are reasonable technical decisions for a mechanism-only story (`docs/input/` silent on them; AGENTS.md: "decide and proceed").

**Never:**
- Never call the backend on dismiss, or show a card / surface `errorCode` for any `status` other than `'ready'`.
- Never let the counter/timer leak across sessions.
- Never route insight generation through `SaveChatMessageAsEntryUseCase`/`EntriesRepository`.
- Never await the insight `isolatedSideEffect` call.
- Never persist `ChatInsight` (no new Hive box, no cross-session reconciliation unlike bookmark state).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| 5th user message | `sendMessage()` called a 5th time within the current window | `message_count` trigger fires once; counter/key reset, fresh timer starts | N/A |
| 2 minutes idle | No `sendMessage()` call for the configured duration since the window opened | `inactivity` trigger fires once; counter/key reset, fresh timer starts | N/A |
| Near-simultaneous | 5th message sent right as the inactivity timer would fire | Only `message_count` fires — sending synchronously cancels/restarts the timer first | N/A |
| Generation fails | `generateInsight` resolves `Left` or `Right` with `status != 'ready'` | `activeInsight` stays null; composer/bubbles/chat unaffected | Silently dropped |
| Session switched mid-flight | `switchSession`/`startNewSession` called while a call is pending | Result dropped on arrival — `sessionId` no longer matches | N/A |
| Dismiss | `dismissInsight()` tapped | `activeInsight` → null; scroll position and every other field unchanged | N/A |
| Dismiss with none active | `dismissInsight()` called while `activeInsight` is already null | No-op | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/chat/domain/entities/chat_insight.dart` (new) -- plain `ChatInsight` (`id`, `content`; manual `==`/`hashCode`/`toString`, mirrors `ChatSession`) + `enum InsightTriggerType { messageCount, inactivity }` + a `wireValue` extension mapping to `'message_count'`/`'inactivity'` (names don't match wire strings, unlike `EntrySource.name`).
- `lib/features/chat/domain/insight_trigger_config.dart` (new) -- `const int insightMessageCountThreshold = 5;`, `const Duration defaultInsightInactivityTimeout = Duration(minutes: 2);`, mirroring `vault_idle_timeout.dart`'s standalone-constant convention.
- `lib/features/chat/domain/repositories/chat_repository.dart` -- add `Future<Either<Failure, ChatInsight?>> generateInsight(String sessionId, {required InsightTriggerType triggerType, required String triggerKey})`; `null` = "no insight to show" (non-`ready` status), not a failure.
- `lib/features/chat/data/models/insight_dto.dart` (new, + generated `.g.dart`) -- `@JsonSerializable()` DTO for `chat-insight-create`'s response `data`: `id`, `sessionId`, `triggerType`/`status`/`errorCode` (all raw `String`, only `status` is ever inspected), `content`/`dismissedAt` (`String?`), `createdAt`.
- `lib/features/chat/data/datasources/chat_remote_data_source.dart` -- add `generateInsight(sessionId, {required String triggerType, required String triggerKey})` via `_apiClient.post('chat-insight-create', pathParams: [sessionId], data: {...})`, same try/catch-to-`malformedResponse` shape as `createSession()`.
- `lib/features/chat/data/repositories/chat_repository_impl.dart` -- implement `generateInsight`: pure passthrough (no Hive, mirrors `sendMessage`/`retryMessage`), mapping `Right(dto)` to `right(dto.status == 'ready' && dto.content != null ? ChatInsight(id: dto.id, content: dto.content!) : null)`; `Left` unmapped.
- `lib/features/chat/presentation/cubit/chat_state.dart` (`ChatReady`, L42-113) -- add `final ChatInsight? activeInsight` (default `null`); extend `copyWith` with `ChatInsight? activeInsight` using the existing `??` pattern (covers *setting* a new one; clearing bypasses `copyWith`, see Boundaries).
- `lib/features/chat/presentation/cubit/chat_cubit.dart` -- the core of this story. Ctor: optional named `Duration insightInactivityTimeout = defaultInsightInactivityTimeout` → `_insightTimeout` (test seam; no `chat_injection.dart` change). New fields: `_insightMessagesSinceWindowStart` (int), `_insightInactivityTimer` (Timer?), `_insightTriggerKey` (String), `_insightWindowCounter` (int, mirrors `_localIdCounter`/`_nextLocalId()` for key generation). `_resetInsightWindow(sessionId)` cancels the timer, zeroes the counter, assigns a fresh key, restarts the timer firing `_fireInsightTrigger(sessionId, .inactivity)` — called from the 3 existing direct `emit(ChatReady(...))` sites (`_bootstrap`/`switchSession`/`startNewSession`, L~184/~250/~295) and from `_fireInsightTrigger` itself. `sendMessage()` (L354, right after the `_isSending = true` guard): increment the counter; at threshold call `_fireInsightTrigger(current.sessionId, .messageCount)`, else just cancel+restart the timer (counter/key untouched). `_fireInsightTrigger(sessionId, triggerType)`: capture the current key, call `_resetInsightWindow(sessionId)` (opens the next window immediately), then `unawaited(isolatedSideEffect(() => _generateInsight(...)).then((r) => _applyInsightResult(sessionId, r)))`. `_generateInsight(...) => _repository.generateInsight(...)` — same double-`Either` shape as `_saveChatMessageAsEntry` (L738). `_applyInsightResult` flattens both `Either`s; any `Left`/null inner value is a no-op; on a real insight, guard `isClosed` + `state is ChatReady && sessionId` match, then `emit(current.copyWith(activeInsight: insight))`. `dismissInsight()`: guard `isClosed`/non-`ChatReady`, else construct `ChatReady(...)` directly (every current field carried forward, `activeInsight: null`). `close()` (L789): cancel `_insightInactivityTimer`.
- `lib/features/chat/presentation/widgets/insight_card.dart` (new) -- stateless `InsightCard({required ChatInsight insight, required VoidCallback onDismiss})`: spine via a `Stack`/`Positioned` 3px-wide `colorAccent` bar (or a `Container` + `BoxDecoration` border, implementer's choice), mono "INSIGHT" label (`textMonoCaption`-based), dismiss icon mirroring `chat_bubble.dart`'s bookmark button's `InkWell` + min-tap-target + `Semantics(button: true)` shape (L187-211).
- `lib/features/chat/presentation/screens/chat_screen.dart` (`ListView.builder`, L191-211) -- `itemCount: messages.length + (activeInsight != null ? 1 : 0)`; `itemBuilder` returns `InsightCard(insight: activeInsight!, onDismiss: cubit.dismissInsight)` when `index == messages.length`, else the existing `ChatBubble` branch unchanged.
- `lib/core/design_tokens.dart` -- new standalone tokens: `chatInsightSpineWidth` (3.0), `chatInsightCardPadding` (`EdgeInsets.fromLTRB(20, 14, 16, 14)`), `chatInsightLabelSpacing` (6.0), `chatInsightDismissIconSize` (14.0). Reuse existing `radiusMd`, `colorSurfaceElevated`, `elevation1`, `colorAccent`, `colorTextSecondary`, `colorTextPrimary`, `textMonoCaption`, `textBodyMd`.
- `test/features/chat/data/datasources/chat_remote_data_source_test.dart` -- extend: `generateInsight` call shape + response parsing.
- `test/features/chat/data/repositories/chat_repository_impl_test.dart` -- extend: passthrough, `wireValue` strings reach the datasource, `status` → entity-or-null mapping (`ready`/`failed`/`generating`/`dismissed`), `Left` propagation.
- `test/features/chat/presentation/cubit/chat_cubit_test.dart` -- extend: fires at the 5th message, fires after the injected short inactivity duration, never both/never twice per window, fire-and-forget (composer/other sends unaffected while pending), failure isolation (`Left` and non-`ready` `Right`), drop-on-session-switch, `dismissInsight` clears without touching other fields, reset on `switchSession`/`startNewSession`/bootstrap.
- `test/features/chat/presentation/widgets/insight_card_test.dart` (new) -- renders label/content/spine color, dismiss tap calls the callback, min tap target.
- `test/features/chat/presentation/screens/chat_screen_test.dart` -- extend: card renders as the trailing list item when `activeInsight` is set, tapping dismiss wires through to `ChatCubit.dismissInsight()`.

## Tasks & Acceptance

**Execution:** (rationale for each is in the Code Map above)
- [x] `chat/domain/entities/chat_insight.dart` (new)
- [x] `chat/domain/insight_trigger_config.dart` (new)
- [x] `chat/domain/repositories/chat_repository.dart` -- add `generateInsight`
- [x] `chat/data/models/insight_dto.dart` (new) + `build_runner`
- [x] `chat/data/datasources/chat_remote_data_source.dart` -- `generateInsight`
- [x] `chat/data/repositories/chat_repository_impl.dart` -- `generateInsight`
- [x] `chat/presentation/cubit/chat_state.dart` -- `activeInsight`
- [x] `chat/presentation/cubit/chat_cubit.dart` -- trigger window + `_fireInsightTrigger`/`_applyInsightResult`/`dismissInsight`
- [x] `chat/presentation/widgets/insight_card.dart` (new)
- [x] `chat/presentation/screens/chat_screen.dart` -- interleave card
- [x] `core/design_tokens.dart` -- 4 new tokens
- [x] extend the 5 test files listed in the Code Map

**Acceptance Criteria:**
- Given either 5 user messages sent or 2 minutes of inactivity within the active Chat Session, when that condition is satisfied first, then `generateInsight` is called exactly once for that window — never both, never twice.
- Given the Insight card appears, when it renders, then it is interleaved into the chat stream (after the last message) as the only accent-colored element, via `ChatReady.activeInsight` — never a second state container.
- Given Insight generation fails (transport or in-payload), when the failure occurs, then it is fully silent — composer stays enabled, no error overlay, ordinary chat keeps working.
- Given an Insight is visible, when I dismiss it, then scroll position and all other conversation state are unaffected.

### Review Findings

- [x] [Review][Patch] `ChatRepositoryImpl.generateInsight` maps `status == 'ready'` with blank/whitespace-only `content` to a real `ChatInsight`, rendering an empty "INSIGHT" card — guard isn't just `!= null` [lib/features/chat/data/repositories/chat_repository_impl.dart:152-155]
- [x] [Review][Patch] The inactivity side of the trigger race fires `generateInsight`'s real network call even while `ChatReady.isOffline` is true, a guaranteed-to-fail attempt; `retryMessage` already guards an equivalent case on `isOffline` [lib/features/chat/presentation/cubit/chat_cubit.dart:847-879]
- [x] [Review][Patch] No regression test exercises `close()` while a `generateInsight` call is still in flight — the `isClosed` guard in `_applyInsightResult` is real and correct but untested; sibling feature `bookmarkMessage` has this exact test shape, spec-6-5 doesn't [lib/features/chat/presentation/cubit/chat_cubit.dart:921; test/features/chat/presentation/cubit/chat_cubit_test.dart:1388]
- [x] [Review][Patch] No test asserts `retryMessage()` (either branch) never increments the insight trigger counter / never calls `generateInsight` — the "never retryMessage" boundary is correctly implemented but entirely unverified [lib/features/chat/presentation/cubit/chat_cubit.dart:495-548; test/features/chat/presentation/cubit/chat_cubit_test.dart:723-890]
- [x] [Review][Patch] `late ChatCubit insightCubit` in the spec-6-5 test group isn't guarded in `tearDown` — a test that fails before the `insightCubit = await initInsightCubit(...)` line throws `LateInitializationError` on cleanup, masking the real failure [test/features/chat/presentation/cubit/chat_cubit_test.dart:1389,1420-1422]
- [x] [Review][Patch] `app_router_test.dart`'s and `chat_screen_test.dart`'s local `testWidgets` overrides close their tracked `ChatCubit`(s) without an `isClosed` guard — this codebase has already hit and documented the exact hazard ("double `close()` on an already-closed Cubit never resolves inside flutter_test's fake-async zone, freezing the suite") in `app_drawer_test.dart`'s/`main_test.dart`'s own tearDown, but didn't carry the same guard here [test/core/navigation/app_router_test.dart:300-309; test/features/chat/presentation/screens/chat_screen_test.dart:232-243]
- [x] [Review][Patch] No test covers a real insight resolving and being applied while `ChatReady.isSending` is `true` (AI response still streaming) — only the reverse direction (pending insight doesn't block a new send) is covered [test/features/chat/presentation/cubit/chat_cubit_test.dart:1388]
- [x] [Review][Patch] No test covers a second successful insight resolving while a prior one is still visible/undismissed (window N shows insight A, window N+1 resolves insight B before A is dismissed) — code silently replaces A with B via `copyWith`, but this path is unverified [lib/features/chat/presentation/cubit/chat_cubit.dart:928; test/features/chat/presentation/cubit/chat_cubit_test.dart:1388]
- [x] [Review][Patch] `## Spec Change Log` below is empty, even though this diff's own "Review fix:" comments describe at least three real implementation-time corrections (stale-request-sequence guard, INSIGHT-label accent-color fix, `testWidgetsWithCleanup` extraction) that this section exists to record
- [x] [Review][Patch] No widget-level test confirms the `ListView`'s actual scroll position/offset is visually unaffected when dismissing the insight card shrinks `itemCount` by one — only the `ChatReady.restoreScrollOffset` field is confirmed unchanged at the cubit level [test/features/chat/presentation/screens/chat_screen_test.dart:809,838]
- [x] [Review][Patch] `testWidgetsWithCleanup`'s bare `try { ... } finally { await cleanup(); }` lets a `cleanup()` exception silently replace/mask the original test-callback failure (standard Dart finally semantics) — relevant because `cleanup()` closures in this same diff do unconditional `.close()` calls that can themselves throw [test/support/testwidgets_with_cleanup.dart:20-26]

## Spec Change Log

- Review fix: added `_insightRequestSeq`, a monotonic counter bumped once per `_fireInsightTrigger` call, so `_applyInsightResult` can discard a stale result from a request a later-fired one has since superseded — without it, two overlapping in-flight `generateInsight` calls for the same session could resolve out of order and resurrect a dismissed insight or overwrite a newer one.
- Review fix: `InsightCard`'s "INSIGHT" label uses `colorTextSecondary`, not an accent color — the ochre spine is the card's only accent-colored element (Intent), an earlier draft had the label accent-colored too.
- Review fix: factored the four near-identical local `testWidgets` overrides (`app_router_test.dart`, `app_drawer_test.dart`, `main_test.dart`, `chat_screen_test.dart`) into a shared `test/support/testwidgets_with_cleanup.dart` helper, needed once a bootstrapped `ChatCubit` started a real `_insightInactivityTimer` that has to be closed before `testWidgets`' own `!timersPending` check runs.

## Design Notes

- `triggerKey` is client-generated (own counter, mirrors `_nextLocalId()`) — the contract only requires `minLength: 1` with no documented semantics beyond echoing it back.
- The inactivity `Duration` is constructor-overridable purely for test speed (no `fake_async` dependency exists in this project); production needs no DI change since the default is the real 2-minute constant.

## Verification

**Commands:**
- `fvm flutter pub get` -- expected: resolves, no conflicts
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- expected: `insight_dto.g.dart` generates cleanly
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass, including new insight trigger/card/wiring coverage

## Suggested Review Order

**Trigger window — the counter/Timer race**

- Entry point: the race itself — counts `sendMessage` only, fires at threshold, else restarts the inactivity timer.
  [`chat_cubit.dart:418`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L418)

- Fires whichever condition won, captures the request's own sequence number, reopens the next window immediately (before the call resolves).
  [`chat_cubit.dart:863`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L863)

- Review fix: the stale-result guard — discards a result whose request has since been superseded by a later-fired one.
  [`chat_cubit.dart:911`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L911)

- Opens a fresh window (counter/key/timer) — called at every session-start site and after every fire.
  [`chat_cubit.dart:837`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L837)

- The 3 session-start sites that each open a fresh window so nothing leaks across sessions.
  [`chat_cubit.dart:242`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L242), [`:311`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L311), [`:365`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L365)

- `dismissInsight` clears the overlay via a direct `ChatReady(...)` construction, since `copyWith`'s `??` can't express "set to null."
  [`chat_cubit.dart:942`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L942)

- `close()` cancels the pending timer so it never fires into a dead cubit.
  [`chat_cubit.dart:1003`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L1003)

**State shape — the single appended overlay value**

- `ChatReady.activeInsight`, nullable, default `null` — appended onto the existing state, never a second container.
  [`chat_state.dart:111`](../../lib/features/chat/presentation/cubit/chat_state.dart#L111)

**Repository/datasource — the silent-failure mapping**

- The port: `null` means "nothing to show" (non-`ready` status), never a `Failure` — RF08's own "never an HTTP error."
  [`chat_repository.dart:87`](../../lib/features/chat/domain/repositories/chat_repository.dart#L87)

- The mapping itself: `status == 'ready' && content != null` is the only path to a real `ChatInsight`.
  [`chat_repository_impl.dart:134`](../../lib/features/chat/data/repositories/chat_repository_impl.dart#L134)

- The real HTTP call, `chat-insight-create` with `sessionId` as the one trailing path segment.
  [`chat_remote_data_source.dart:172`](../../lib/features/chat/data/datasources/chat_remote_data_source.dart#L172)

- The trigger-type enum and its wire-string mapping (names don't match the backend's own strings).
  [`chat_insight.dart:30`](../../lib/features/chat/domain/entities/chat_insight.dart#L30)

- The two fixed business-rule constants (5 messages / 2 minutes), mirroring `vault_idle_timeout.dart`'s own convention.
  [`insight_trigger_config.dart:6`](../../lib/features/chat/domain/insight_trigger_config.dart#L6)

**UI — the card and its interleaving**

- The card itself: ochre spine, neutral mono label (review fix: label is no longer accent-colored), dismiss affordance.
  [`insight_card.dart:13`](../../lib/features/chat/presentation/widgets/insight_card.dart#L13)

- `ChatScreen` interleaves exactly one card as the list's trailing item whenever `activeInsight` is set.
  [`chat_screen.dart:194`](../../lib/features/chat/presentation/screens/chat_screen.dart#L194)

- The 4 new standalone tokens, their values taken verbatim from the frozen prototype's own pixel spec.
  [`design_tokens.dart:703`](../../lib/core/design_tokens.dart#L703)

**Tests**

- The full I/O matrix plus the review-fix regression tests for out-of-order/stale insight results.
  [`chat_cubit_test.dart:1388`](../../test/features/chat/presentation/cubit/chat_cubit_test.dart#L1388), [`:1624`](../../test/features/chat/presentation/cubit/chat_cubit_test.dart#L1624)

- The corrected "only accent-colored element" assertion (was previously asserting the bug).
  [`insight_card_test.dart:43`](../../test/features/chat/presentation/widgets/insight_card_test.dart#L43)

- The end-to-end render/dismiss coverage through a real `ChatScreen`.
  [`chat_screen_test.dart:809`](../../test/features/chat/presentation/screens/chat_screen_test.dart#L809), [`:838`](../../test/features/chat/presentation/screens/chat_screen_test.dart#L838)

- Review fix: the shared `testWidgets`-plus-cleanup helper, factored out of 4 near-identical copies.
  [`testwidgets_with_cleanup.dart:15`](../../test/support/testwidgets_with_cleanup.dart#L15)
