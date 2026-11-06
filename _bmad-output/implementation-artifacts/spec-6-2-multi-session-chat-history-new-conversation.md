---
title: 'Story 6.2 — Multi-Session Chat History & New Conversation'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
baseline_commit: '53de1f87bba2564a87e998b7bb1a515068dd299a'
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Home/Chat (story 6.1) hard-codes a single auto-bootstrapped session with no way to see past sessions or start a fresh one; `AppDrawer` has no session list at all, just a dead "Novo Chat" button.

**Approach:** Add `ChatCubit.switchSession`/`startNewSession` methods that reuse the existing `listSessions()`/`createSession()` repository calls (already backend-correct — no data-layer change needed), carry the session list and a per-session scroll offset on `ChatReady`, and wire `AppDrawer`'s missing "CONVERSAS" section to read/call that same cubit instance via the `BlocProvider<ChatCubit>` already wrapping the drawer's `Scaffold`.

## Boundaries & Constraints

**Always:**
- Drawer reads `context.read<ChatCubit>()`/`BlocBuilder` — the instance `ChatScreen` already provides via `BlocProvider<ChatCubit>.value` (`chat_screen.dart:83-87`); never a second `sl<ChatCubit>()` inside `AppDrawer`.
- `switchSession`/`startNewSession` return `Future<Either<Failure, void>>`, `await`ed by their `AppDrawer` tap handlers (closes a gap spec-6-1's review flagged: a cubit action's result must be observed by its caller).
- Offline "Novo Chat" leaves the current session untouched; caller shows a transient `SnackBar`, not a dedicated offline banner (Story 6.3's job).
- Scroll-offset restore is in-memory only, keyed by `sessionId`, on `ChatCubit` (never Hive) — survives session switches within one app run, resets on restart.
- Reuse `_DrawerNavItem`'s tokens (`drawerNavItemPadding`, `textBodyMd`, `textMonoCaption`) — no new design tokens.
- An empty `title` renders fallback label "Nova conversa" (contract leaves an untitled session's `title` undocumented).

**Ask First:** none identified.

**Never:** session rename/delete (no endpoint); paginating past the backend's default first page; Story 6.3's offline composer lock/banner; persisting scroll offset or active-session choice across app restarts.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Switch session | Drawer open, tap a past session row | `ChatReady` updates to that session's history; scroll jumps to its last recorded offset (or bottom if none) | N/A |
| New session online | Tap "Novo Chat" while online | `POST /chat/sessions` succeeds; new empty session becomes active, composer focused, drawer closes | N/A |
| New session offline | Tap "Novo Chat" while offline | `createSession()` resolves `Left(Failure.networkOffline)`; current session stays active, drawer closes, `SnackBar` shown | `Failure.networkOffline` surfaced, no crash |
| Switch to already-active session | Tap the currently open session's own row | No-op reload; drawer just closes | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/chat/presentation/cubit/chat_state.dart:40-69` -- `ChatReady`: add `sessions: List<ChatSession>`, `restoreScrollOffset: double?`; extend `copyWith`.
- `lib/features/chat/presentation/cubit/chat_cubit.dart:64-114` (`_bootstrap`) -- capture resolved sessions into the emitted `ChatReady`; add `Map<String, double> _scrollOffsets`, `recordScrollOffset`, `switchSession`, `startNewSession` (mirror `_bootstrap`'s match-based error handling, lines 92-113).
- `lib/features/chat/domain/repositories/chat_repository.dart:21,31` -- `listSessions()`/`createSession()`, reused as-is.
- `lib/core/widgets/app_drawer.dart:17-131` -- wrap body in `BlocBuilder<ChatCubit, ChatState>`; insert a "CONVERSAS" section (mirrors bordered `Container`, lines 78-108) between `_DrawerPrimaryAction` (65-71) and it, shown only when `state is ChatReady`; wire `_DrawerPrimaryAction.onTap` (70) to `startNewSession()`.
- `lib/features/chat/presentation/screens/chat_screen.dart:33,59-79` -- on `ChatReady.restoreScrollOffset != null`, `jumpTo` it once instead of `_scrollToBottomSoon()`; add a listener calling `cubit.recordScrollOffset`.
- `docs/input/backend/api/openapi.yaml:1071-1155` -- confirms no rename/delete/pagination-required endpoint.
- `test/core/navigation/app_router_test.dart:128-156` -- `_FakeChatRepository`, the DI-override pattern to extend.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/chat/presentation/cubit/chat_state.dart` -- add `sessions`/`restoreScrollOffset` to `ChatReady` -- no second state container (AD-12).
- [x] `lib/features/chat/presentation/cubit/chat_cubit.dart` -- add `switchSession`, `startNewSession`, `recordScrollOffset`; populate `sessions` in `_bootstrap` -- one cubit stays the source of truth.
- [x] `lib/core/widgets/app_drawer.dart` -- render CONVERSAS from `ChatReady.sessions`, wire tap → `switchSession`/`startNewSession`, `await` + `SnackBar` on `Left` -- closes the gap at doc-comment lines 8-16.
- [x] `lib/features/chat/presentation/screens/chat_screen.dart` -- scroll-offset capture + restore-on-switch -- fulfils the scroll-position AC.
- [x] `test/features/chat/presentation/cubit/chat_cubit_test.dart` -- unit-test `switchSession`/`startNewSession`/offline-create/no-op-on-same-session per the I/O matrix.
- [x] `test/core/widgets/app_drawer_test.dart` (pre-existing from Story 1.6, rewritten in place rather than duplicated — its old assertions asserted the now-obsolete "no CONVERSAS section" behavior) -- widget tests: CONVERSAS rendering, tap-to-switch, offline `SnackBar`, mirroring `_FakeChatRepository` (`app_router_test.dart:128-156`).

**Acceptance Criteria:**
- Given existing Chat Sessions, when I open the side menu, then they're listed under "CONVERSAS" and tapping one switches the active conversation.
- Given I tap "Novo Chat", when the new session is created, then it opens empty, composer focused, placeholder "Escreva uma mensagem...".
- Given I'm offline, when I tap "Novo Chat", then no session is created, the current conversation is untouched, and I see an error message.
- Given I switch back to a session I was previously scrolled up in, when it loads, then it restores that scroll position instead of jumping to the bottom.

### Review Findings

**Patch:**
- [x] [Review][Patch] `ChatCubit.switchSession()`/`startNewSession()` didn't cancel an in-flight `_sendSubscription` or check `_isSending` before switching the active session — a response still streaming into the old session kept mutating whatever session became active next (cross-session message leakage). Fixed via a new `_cancelInFlightSend()`, mirroring `close()`'s own cleanup. [lib/features/chat/presentation/cubit/chat_cubit.dart]
- [x] [Review][Patch] `_ConversasSection`'s new sort used `DateTime.parse` (not `tryParse`) on `updatedAt` — a malformed timestamp crashed the whole drawer build. Fixed to the same crash-safe `tryParse` pattern already used by `_formatSessionTimestamp` next to it. [lib/core/widgets/app_drawer.dart] (The same pattern, found and fixed in the pre-existing, otherwise-untouched `ChatCubit._bootstrap` sort, blocked exercising this very fix — disclosed by the implementer, not one of the original four findings.)
- [x] [Review][Patch] No test drove `ChatScreen` itself (only `ChatCubit`'s state field or a bare-`Scaffold` drawer harness) through a session switch, leaving 2 of this story's 4 acceptance criteria (composer-focus-on-new-session, scroll-restore-on-switch) unverified at the layer that implements them. Added screen-level tests to `chat_screen_test.dart`. [test/features/chat/presentation/screens/chat_screen_test.dart]
- [x] [Review][Patch] `_focusComposerSoon`'s doc comment overclaimed it only fires for a brand-new session, when the actual guard (`messages.isEmpty`) also fires when switching back to an empty past session. Comment corrected. [lib/features/chat/presentation/screens/chat_screen.dart]

**Defer:** 11 findings (UX nits, pre-existing-code verification gaps surfaced incidentally by this review, cross-site duplication) appended to `deferred-work.md` under "review of story-6-2-multi-session-chat-history-new-conversation".

**Reject (noise, dropped):** `restoreScrollOffset`'s inability to be reset to `null` via `copyWith` — already documented as deliberate in this spec's own Design Notes; not a bug.

## Spec Change Log

## Design Notes

- `switchSession`/`startNewSession` don't re-emit `ChatBootstrapLoading` (a 4th visible state isn't worth it — "exactly three" governs bubbles, not session-switch chrome). `_scrollOffsets` lives on the long-lived cubit (`chat_injection.dart:50-53`), not `ChatReady`.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass, including new cubit/drawer tests

## Suggested Review Order

**Session switching (the new cubit API)**

- Entry point — fetches the target session's history and makes it active; the no-op-on-same-session branch is why "switch to already-active" never re-fetches.
  [`chat_cubit.dart:155`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L155)

- Mirrors `switchSession`, but always runs (no same-session branch) since a new session is never the current one.
  [`chat_cubit.dart:196`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L196)

- Review fix: cancels an in-flight send before switching away, so a still-streaming response can't mutate the session that replaces it.
  [`chat_cubit.dart:407`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L407)

**State shape**

- `ChatReady` gains `sessions` (for the drawer) and `restoreScrollOffset` (for scroll restore) — both set only via direct construction, not `copyWith`.
  [`chat_state.dart:41`](../../lib/features/chat/presentation/cubit/chat_state.dart#L41)

**Drawer UI (CONVERSAS section)**

- Renders the session list and routes taps to `switchSession`/`startNewSession`, `await`ing the result for a `SnackBar` on failure.
  [`app_drawer.dart:170`](../../lib/core/widgets/app_drawer.dart#L170)

- Same await-and-surface shape for switching.
  [`app_drawer.dart:196`](../../lib/core/widgets/app_drawer.dart#L196)

- The "CONVERSAS" list itself — title + timestamp rows, most-recent-first.
  [`app_drawer.dart:307`](../../lib/core/widgets/app_drawer.dart#L307)

- Review fix: `tryParse` instead of `parse` on `updatedAt`, so a malformed timestamp can't crash the whole drawer build.
  [`app_drawer.dart:333`](../../lib/core/widgets/app_drawer.dart#L333)

**Screen wiring (scroll restore + composer focus)**

- Detects a genuine session change (vs. an in-session update) to decide whether to jump/focus at all.
  [`chat_screen.dart:157`](../../lib/features/chat/presentation/screens/chat_screen.dart#L157)

- Jumps to a session's last recorded scroll offset once its history has attached to the scrollable.
  [`chat_screen.dart:112`](../../lib/features/chat/presentation/screens/chat_screen.dart#L112)

- Requests composer focus when the newly active session has no messages yet (AC2).
  [`chat_screen.dart:129`](../../lib/features/chat/presentation/screens/chat_screen.dart#L129)

- Feeds `ChatCubit.recordScrollOffset` on every scroll update, the data `_jumpToOffset` later reads back.
  [`chat_screen.dart:67`](../../lib/features/chat/presentation/screens/chat_screen.dart#L67)

**Peripherals (tests)**

- Review-fix regression tests: a send in flight during a switch/new-session no longer leaks into the new active session.
  [`chat_cubit_test.dart:357`](../../test/features/chat/presentation/cubit/chat_cubit_test.dart#L357)

- Review-fix regression test: a malformed `updatedAt` in the drawer list no longer throws.
  [`app_drawer_test.dart:159`](../../test/core/widgets/app_drawer_test.dart#L159)

- Review-fix regression tests: composer focus and scroll restore, driven through the real `ChatScreen` rather than the cubit's state alone.
  [`chat_screen_test.dart:288`](../../test/features/chat/presentation/screens/chat_screen_test.dart#L288)

- Full I/O-matrix coverage for `switchSession`/`startNewSession`.
  [`chat_cubit_test.dart:210`](../../test/features/chat/presentation/cubit/chat_cubit_test.dart#L210)
