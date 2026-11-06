---
title: 'Story 6.4 — Bookmark a Chat Message into an Entry'
type: 'feature'
created: '2026-11-06'
status: 'done'
review_loop_iteration: 1
baseline_commit: '03b76ffef4d1896d48e591270aa05de464fd3abf'
context: ['{project-root}/_bmad-output/implementation-artifacts/epic-6-context.md']
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A user's own reflective Chat Message can't become a journal Entry without retyping it — `ChatUiMessage` has no bookmark affordance, `EntriesRepository.create()` has no `chatMessageId` slot even though `Entry.chatMessageId`/`EntrySource.chat` already reserve it, and `core/isolated_side_effect.dart` is still an `UnimplementedError` stub explicitly waiting for this story.

**Approach:** Add a four-state (`idle`/`saving`/`saved`/`error`) bookmark button to user-only chat bubbles. `ChatCubit.bookmarkMessage(messageId)` calls the real `isolatedSideEffect` (replacing the stub) wrapping a call to a new `SaveChatMessageAsEntryUseCase` (`entries/domain/usecases/`) — the shared interface AGENTS.md's RF10 rule requires — which itself wraps `EntriesRepository.create(..., source: EntrySource.chat, chatMessageId: ...)`. `ChatCubit` never imports `EntriesRepository` or anything under `entries/data`/`entries/presentation`.

## Boundaries & Constraints

**Always:**
- Bookmark affordance: `ChatMessageRole.user` bubbles only.
- `ChatCubit` depends on `SaveChatMessageAsEntryUseCase` (`entries/domain/usecases/`) — never `EntriesRepository` directly, never `entries/data/` or `entries/presentation/` (AGENTS.md: "RF10 must call the entries feature through a shared interface/use case, never by importing the entries repository or data source directly").
- Save runs through `isolatedSideEffect` (real body, replacing the `UnimplementedError` stub), awaited before bookmark state updates.
- Tapping `saved` is a client-side no-op; repeat backend calls for the same `chatMessageId` are themselves idempotent (200, not 409 — `openapi.yaml`'s `entries.create` doc) so no extra client dedup needed.
- A save failure never freezes the session: only the tapped bubble's state flips to `error` (retryable); composer/history/other bubbles unaffected.
- Icon + color together, never color alone: `idle` outline, `saving` spinner (static label under Reduce Motion), `saved` ochre check (`colorAccent`, `0xFFC98A3E`), `error` red warning (`colorError`). Tap target ≥44pt, `Semantics(button: true)`.
- Bookmarking requires a non-null `serverId` (the id sent as `chatMessageId`); tapping before that is a no-op, mirroring `retryMessage`'s guard.
- Both of `bookmarkMessage`'s `emit()` calls (before and after the `isolatedSideEffect` await) check `isClosed` first — not just the one after the await.
- A bookmark glyph's Reduce-Motion static label sits in a width-capped slot (e.g. wrapped the same way `bubbleContainer` is `Flexible`-constrained), so it cannot squeeze the message bubble under large accessibility text scaling.

**Ask First:** none — `chatMessageId` on `create()` is a pre-reserved slot (`Entry.chatMessageId`/`EntrySource.chat` already exist for this story), not a new architectural call.

**Never:**
- Never import `EntriesRepository`, `entries/data/`, or `entries/presentation/` from `chat/` — only `SaveChatMessageAsEntryUseCase`.
- Never route the bookmark save through `PendingEntryWriteTracker` — its `create()` clears *any* app-wide failed pending-write on each call (written for exactly one capture flow in flight at a time), so a concurrent chat bookmark could silently clear an unrelated capture flow's visible error card.
- Never persist bookmark state across restarts — in-memory only; a stale `idle` post-reload is harmless given backend idempotency.
- Never let a bookmark failure disable the composer or affect other bubbles.
- Never introduce a second Entry model or bypass `EntriesRepository` (the use case's own only caller).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path | Tap bookmark on a user bubble with `serverId` set, `idle` | Bubble flips `idle` → `saving` → `saved` (ochre check); `SaveChatMessageAsEntryUseCase(content, chatMessageId: serverId)` called once | N/A |
| Already saved | Tap a `saved` bubble | No-op — no new call, no state change | N/A |
| No serverId yet | Tap bookmark before `message_created` SSE event set `serverId` | No-op — same guard shape as `retryMessage` | N/A |
| Save fails | `create()` resolves `Left(Failure)` | Bubble flips to `error` (red warning); rest of session (composer, other bubbles, scroll) unaffected | Tapping `error` re-attempts the same save, returning to `saving` |
| Side-effect throws | `action()` inside `isolatedSideEffect` throws synchronously or async | Caught, mapped to `Left(Failure.malformedResponse(...))`, never propagates to caller | Bubble flips to `error`, same as above |
| Second tap while saving | Tap bookmark again while a save is already in flight for that message | No-op (re-entrancy guard, mirrors `_isSending`-style check scoped to that message) | N/A |

</frozen-after-approval>

## Code Map

- `lib/core/isolated_side_effect.dart` -- replace `UnimplementedError` stub: `try { return right(await action()); } catch (e) { return left(Failure.malformedResponse(message: e.toString())); }` (mirrors `entries_repository_impl.dart:46-50`'s existing catch-to-`malformedResponse` convention).
- `lib/features/entries/domain/repositories/entries_repository.dart:18-22` -- add optional `String? chatMessageId` to `create()`.
- `lib/features/entries/data/repositories/entries_repository_impl.dart:32-53` -- thread it to the remote data source call.
- `lib/features/entries/data/datasources/entries_remote_data_source.dart:21-33` -- add `'chatMessageId': ?chatMessageId` to the `entries-create` body (mirrors existing `?mediaDurationSeconds`).
- `lib/features/entries/domain/usecases/save_chat_message_as_entry_use_case.dart` (new) -- the shared interface/use case AGENTS.md's RF10 rule requires: abstract `SaveChatMessageAsEntryUseCase` with `Future<Either<Failure, Entry>> call({required String content, required String chatMessageId})`, impl `SaveChatMessageAsEntryUseCaseImpl(EntriesRepository repository)` forwarding to `repository.create(content: content, source: EntrySource.chat, chatMessageId: chatMessageId)`. Port+impl in one file, pure domain (no `package:flutter`/`data` import), mirrors `pending_entry_write_tracker.dart`'s own structural convention. Deliberately narrow (just `content`/`chatMessageId`) rather than exposing `create()`'s full signature — this is the one caller that only ever needs `source: EntrySource.chat`.
- `lib/features/entries/entries_injection.dart` -- register `SaveChatMessageAsEntryUseCase` as a `lazySingleton` wrapping `sl<EntriesRepository>()`, mirroring `PendingEntryWriteTracker`'s own registration right above `MeusRegistrosCubit`'s.
- `lib/features/chat/domain/entities/bookmark_state.dart` (new) -- sealed `BookmarkState`, `const factory` `idle()`/`saving()`/`saved()`/`error(Failure)`, mirrors `entries/domain/entities/sync_badge_state.dart:13-21`.
- `lib/features/chat/presentation/cubit/chat_state.dart:121-193` (`ChatUiMessage`) -- add `BookmarkState bookmarkState` (default `.idle()`), extend `copyWith`/`==`/`hashCode`/`toString`.
- `lib/features/chat/presentation/cubit/chat_cubit.dart:18` (ctor) -- add `SaveChatMessageAsEntryUseCase` param (import `entries/domain/usecases/save_chat_message_as_entry_use_case.dart` only — never `entries/domain/repositories/`).
- `lib/features/chat/presentation/cubit/chat_cubit.dart` (new, near `retryMessage`) -- `bookmarkMessage(String messageId)`: guard `current is! ChatReady` (and `isClosed`); find message; no-op if role != user, `serverId == null`, already `saved`, or already `saving`; emit `.saving()` for that message (guarded by `isClosed` too); call `isolatedSideEffect(() => _saveChatMessageAsEntry(content: message.content, chatMessageId: message.serverId!))`; map `Right`→`.saved()`/`Left(f)`→`.error(f)` via the same `for...if...else` rebuild `retryMessage` uses (`chat_cubit.dart:405-411`), guarded by `isClosed` before this second `emit()` too.
- `lib/features/chat/chat_injection.dart:62` -- add `sl<SaveChatMessageAsEntryUseCase>()` as 3rd `ChatCubit(...)` arg; import only the use-case file.
- `lib/features/chat/presentation/widgets/chat_bubble.dart:22-24,81,104-131,212-213` -- add `onBookmark: ValueChanged<String>?`; gate on `isUser`; bookmark button beside `timeCaption`, mirrors `onRetry`'s conditional-`Semantics` pattern; icon per `BookmarkState`; static label under Reduce Motion instead of spinner, wrapped so it cannot grow past the icon slot's width and squeeze the bubble.
- `lib/core/design_tokens.dart` -- `chatBookmarkIconSize` as its own standalone `16.0` literal (not an alias of `entriesSearchBarIconSize` — the two are unrelated design decisions that only coincide today).
- `lib/features/chat/presentation/screens/chat_screen.dart` (near `onRetry:` wiring) -- wire `onBookmark: (id) => cubit.bookmarkMessage(id)`.
- `test/core/isolated_side_effect_test.dart` (new) -- success passthrough + thrown→`malformedResponse`.
- `test/features/entries/data/repositories/entries_repository_impl_test.dart`, `.../data/datasources/entries_remote_data_source_test.dart` -- extend for `chatMessageId` passthrough.
- `test/features/entries/domain/usecases/save_chat_message_as_entry_use_case_test.dart` (new) -- asserts it forwards to `EntriesRepository.create()` with `source: EntrySource.chat` and the given `chatMessageId`, passing through both `Right`/`Left`.
- `test/features/chat/presentation/cubit/chat_cubit_test.dart`, `.../presentation/widgets/chat_bubble_test.dart` -- extend per the I/O matrix and the user-only/icon+color rules; fake `SaveChatMessageAsEntryUseCase` instead of `EntriesRepository`.
- `test/features/chat/presentation/screens/chat_screen_test.dart` -- add one test tapping the bookmark icon through a pumped `ChatScreen` and asserting the wired-through use-case fake was called with the expected `content`/`chatMessageId` (mirrors this file's existing `onRetry` coverage at its retry test) — the previous round left `chat_screen.dart`'s own wiring line untested.
- `test/main_test.dart` -- swap `sl<EntriesRepository>()` for a throwing fake `SaveChatMessageAsEntryUseCase`, matching every other touched test file's "never expected to be called" fake convention, instead of resolving the real DI-backed instance.
- `test/features/entries/domain/services/pending_entry_write_tracker_test.dart` -- fix the previous round's 2-space-indented `chatMessageId` param line to match the surrounding 4-space indentation (`dart format` nit).

## Tasks & Acceptance

**Execution:** (file path -- action; rationale is in the Code Map above)
- [x] `core/isolated_side_effect.dart` -- implement the real never-throws body.
- [x] `entries/domain/repositories/entries_repository.dart`, `data/repositories/entries_repository_impl.dart`, `data/datasources/entries_remote_data_source.dart` -- add `chatMessageId` through all three layers.
- [x] `entries/domain/usecases/save_chat_message_as_entry_use_case.dart` (new) -- the shared use case, port+impl.
- [x] `entries/entries_injection.dart` -- register `SaveChatMessageAsEntryUseCase`.
- [x] `chat/domain/entities/bookmark_state.dart` (new) -- four-state sealed class.
- [x] `chat/presentation/cubit/chat_state.dart` -- `ChatUiMessage.bookmarkState`.
- [x] `chat/presentation/cubit/chat_cubit.dart` -- `SaveChatMessageAsEntryUseCase` dependency + `bookmarkMessage()` (with `isClosed` guards on both emits).
- [x] `chat/chat_injection.dart` -- wire `SaveChatMessageAsEntryUseCase` into `ChatCubit`.
- [x] `chat/presentation/widgets/chat_bubble.dart`, `presentation/screens/chat_screen.dart` -- bookmark button UI + wiring.
- [x] `core/design_tokens.dart` -- standalone `chatBookmarkIconSize`.
- [x] Extend/add the test files listed in the Code Map per the I/O matrix, including `chat_screen_test.dart`'s new wiring test and `main_test.dart`'s fake swap.

**Acceptance Criteria:**
- Given one of my own Chat Messages (never an AI response), when I tap the bookmark affordance, then it creates an Entry (`source=chat`, carrying `chatMessageId`) through `SaveChatMessageAsEntryUseCase` only — `ChatCubit` never imports `EntriesRepository` or anything under entries' data/presentation layers.
- Given the save executes, when it runs, then it goes through the real (non-stub) `isolatedSideEffect` helper, awaited before the button's state updates.
- Given a message already in `saved`, when I tap it again, then it is a no-op — no duplicate Entry, no error surfaced.
- Given a save fails, when the error state shows, then the surrounding Chat Session remains fully usable and the button resets to a retryable `error` state rather than freezing, with state carried by icon + color together.

### Review Findings

- [x] [Review][Decision] Bookmark save outcome silently dropped on session switch — `bookmarkMessage()` awaits `isolatedSideEffect` then re-reads `state` and rebuilds `messages` by id; `switchSession()`/`startNewSession()` (`chat_cubit.dart:206-300`) replace `ChatReady.messages` wholesale and only cancel the send/retry stream (`_cancelInFlightSend`) — never a bookmark save in flight. If the user switches sessions (or starts a new one) while a save is pending, the eventual `saved`/`error` result finds no matching message in the new `ChatReady.messages` and is silently discarded: no confirmation, no error, no retryable state surfaced. **Resolved:** tracked the save's outcome in a new `_bookmarkStateByServerId` map on `ChatCubit`, keyed by the message's `serverId` (stable across a reload, unlike the in-session local `id`) — same in-memory-only, survives-session-switches lifetime as the existing `_scrollOffsets` map. `_fromDomain` applies any recorded override when a session's history (re)loads, so re-entering a session that carries the bookmarked message picks the outcome back up instead of losing it; the live emit at the end of `bookmarkMessage()` now also matches by `serverId` rather than the possibly-stale local `id`. Chose this over blocking session switches (a new UX constraint the spec never asked for) since it fixes the gap without adding one. New regression test: `test/features/chat/presentation/cubit/chat_cubit_test.dart` ("review fix (round 2): a save that resolves after the user has switched sessions..."). [`lib/features/chat/presentation/cubit/chat_cubit.dart:592-624`]
- [x] [Review][Patch] No test for `bookmarkMessage()`'s pre-save `isClosed`/non-`ChatReady` guards or cross-message concurrency — only the `isClosed` guard *after* the `isolatedSideEffect` await is tested; the guard before the first `saving` emit, the `current is! ChatReady` early-return, and two independent messages bookmarked concurrently without cross-talk are all unexercised. **Fixed:** added all three cases to `chat_cubit_test.dart`'s `bookmarkMessage()` group. [`test/features/chat/presentation/cubit/chat_cubit_test.dart`]
- [x] [Review][Patch] `bookmarkMessage()` tests index `messages[0]`/`messages[1]` directly, reintroducing fragility a nearby helper explicitly avoids — `sendAndCompleteWithServerId`'s own comment says it filters by role "so this helper keeps working if message ordering ever changes... instead of silently asserting on the wrong bubble," but the surrounding assertions in the same group use raw indices instead. **Reassessed, no change needed:** every existing assertion in the group has exactly one user message on screen at that point (same single-round-trip convention the `sendMessage()`/`retryMessage()` groups already use elsewhere in this file without any role-filter helper at all), so the index is never actually ambiguous there — the helper's role-filter exists for the id-lookup-after-a-round-trip use case specifically, not as a group-wide convention this violates. The one place it would have mattered (two user messages on screen at once) is the new concurrency test added above, which looks its second message up by content instead of by index or by the role-only helper (confirmed necessary: the helper always returns the *first* user message, which the new concurrency test initially tripped over before this fix).
- [x] [Review][Patch] New `chat_screen_test.dart` wiring test uses unscoped global icon finders — `find.byIcon(Icons.bookmark_border)`/`find.byIcon(Icons.check)` search the entire pumped `ChatScreen` tree rather than being scoped to the tapped bubble/button, so the test would start matching an unrelated icon elsewhere on screen if one is ever added. **Fixed:** both scoped via `find.descendant(of: find.byType(ChatBubble), matching: ...)`. [`test/features/chat/presentation/screens/chat_screen_test.dart`]
- [x] [Review][Patch] Throwing `SaveChatMessageAsEntryUseCase` fake duplicated across 5 test files instead of factored into `test/support/` — a near-identical "never expected to be called" fake is hand-rolled independently in `main_test.dart`, `app_router_test.dart`, `app_drawer_test.dart`, `chat_cubit_test.dart`, and `chat_screen_test.dart`, instead of a shared helper (where `fake_connectivity_watcher.dart` already lives). **Fixed:** extracted the 3 byte-identical "never called" copies (`main_test.dart`, `app_router_test.dart`, `app_drawer_test.dart`) into `test/support/unused_save_chat_message_as_entry_use_case.dart`. Left `chat_cubit_test.dart`'s and `chat_screen_test.dart`'s own fakes as-is — they're genuinely different shapes (completer-based vs. fixed-result) serving different test needs, not duplicates of this one or each other. [`test/support/unused_save_chat_message_as_entry_use_case.dart`]

## Spec Change Log

- **Round 1 review finding (intent_gap):** The original frozen Boundaries said "`ChatCubit` depends on `EntriesRepository` from `entries/domain/repositories/` only" — implemented faithfully, but that directly violates AGENTS.md's explicit RF10 rule ("must call the entries feature through a shared interface/use case, never by importing the entries repository or data source directly — doing so also violates RNF06"). Root cause was inside the frozen block, so this is an intent_gap, not a patch.
  **Amended:** `ChatCubit` now depends on a new `SaveChatMessageAsEntryUseCase` (`entries/domain/usecases/`) instead of `EntriesRepository` directly; `EntriesRepository`/`entries/data`/`entries/presentation` imports from `chat/` are now explicitly forbidden in Boundaries.
  **Known-bad state avoided:** a cross-feature import the project's own instructions name by story number (RF10) as forbidden, which would also have made every future review of this story flag the same violation.
  **Also folded in** (surfaced by the same review round, cheap to fix alongside the use-case change since the touched files are being re-derived anyway): both `bookmarkMessage()` emits now need an `isClosed` guard, not just the second one; the Reduce-Motion label needs a width-capped slot; `chatBookmarkIconSize` should be its own literal, not an alias of an unrelated token; `chat_screen_test.dart` needs a real end-to-end tap test for the `onBookmark` wiring (previously only `ChatBubble`/`ChatCubit` were tested in isolation); `test/main_test.dart` should use a throwing fake like every other touched test file, not the real DI-resolved dependency; the `pending_entry_write_tracker_test.dart` fake's new param line had a stray 2-space indent.
  **KEEP (verified correct, must survive re-derivation):** the `BookmarkState` sealed-class shape and its placement in `chat/domain/entities/`; `ChatUiMessage.bookmarkState`'s default-idle/`copyWith` extension; the `chatMessageId` threading through `entries/domain/repositories/entries_repository.dart` → `data/repositories/entries_repository_impl.dart` → `data/datasources/entries_remote_data_source.dart` (unaffected by this amendment — the use case sits *above* this, not instead of it); `isolatedSideEffect`'s real catch-to-`malformedResponse` body; `bookmarkMessage()`'s guard chain (role/serverId/already-saved/already-saving) and its `Either`-flattening from `isolatedSideEffect`; the `ChatBubble` icon/color-per-state mapping and 44pt tap target; every I/O-matrix-covering test case already written for `chat_cubit_test.dart`/`chat_bubble_test.dart` (only their `EntriesRepository` fake swaps for a `SaveChatMessageAsEntryUseCase` fake — the test *logic* is unchanged).

## Design Notes

- `BookmarkState` lives in `chat/domain/entities/`, mirroring `SyncBadgeState`'s per-feature placement — promote only if a second feature needs it.
- `chatMessageId` sent is `ChatUiMessage.serverId`, never the local UI `id` — same distinction story 6.3 established for `retryMessage`.
- No persisted bookmark flag: reload-then-re-tap is harmless given backend idempotency — simpler than threading a new field through the Hive message cache for no behavioral gain.
- `SaveChatMessageAsEntryUseCase` is deliberately narrower than `EntriesRepository.create()` (just `content`/`chatMessageId`, `source` is implicit) — it exists only to satisfy AGENTS.md's RF10 boundary, not to become a general-purpose entries port; a future caller needing more of `create()`'s surface gets its own use case rather than this one growing extra optional params.

## Verification

**Commands:**
- `fvm flutter pub get` -- expected: resolves, no conflicts
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass, including new `isolated_side_effect`, `entries` `chatMessageId`, and `chat` bookmark coverage

## Suggested Review Order

**RF10 layering fix — the shared use-case interface**

- Entry point: the narrow port AGENTS.md's RF10 rule requires, wrapping `EntriesRepository.create()` so `ChatCubit` never imports it directly.
  [`save_chat_message_as_entry_use_case.dart:21`](../../lib/features/entries/domain/usecases/save_chat_message_as_entry_use_case.dart#L21)

- DI registration, wrapping the existing `EntriesRepository` singleton — no new box/dependency.
  [`entries_injection.dart:59`](../../lib/features/entries/entries_injection.dart#L59)

- `ChatCubit`'s own dependency field is this use case, not `EntriesRepository` — the boundary this round's loopback exists to fix.
  [`chat_cubit.dart:53`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L53)

- Wired into `ChatCubit` as its 3rd constructor arg, resolved after `registerEntriesFeature()` always runs first.
  [`chat_injection.dart:75`](../../lib/features/chat/chat_injection.dart#L75)

**Bookmark save flow**

- `bookmarkMessage()`'s full guard chain (role/serverId/already-saved/already-saving), the `isolatedSideEffect` call, the outer/inner `Either` flatten, and both `isClosed` guards.
  [`chat_cubit.dart:619`](../../lib/features/chat/presentation/cubit/chat_cubit.dart#L619)

- The real never-throws body `bookmarkMessage` depends on — catches a genuine throw, maps it to `malformedResponse`.
  [`isolated_side_effect.dart:21`](../../lib/core/isolated_side_effect.dart#L21)

**`chatMessageId` threading (entries data/domain)**

- The pre-reserved optional param, documented as forwarding to a backend already idempotent on it.
  [`entries_repository.dart:26`](../../lib/features/entries/domain/repositories/entries_repository.dart#L26)

- Threaded straight through to the remote data source, no other change to `create()`'s own logic.
  [`entries_repository_impl.dart:36`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L36)

- Sent as `'chatMessageId': ?chatMessageId` in the `entries-create` body, mirroring the existing `mediaDurationSeconds` convention.
  [`entries_remote_data_source.dart:26`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L26)

**Bookmark state shape**

- The 4-state sealed class (`idle`/`saving`/`saved`/`error`), mirroring `SyncBadgeState`'s own convention.
  [`bookmark_state.dart:11`](../../lib/features/chat/domain/entities/bookmark_state.dart#L11)

- `ChatUiMessage.bookmarkState`, default-idle, threaded through `copyWith`/`==`/`hashCode`/`toString`.
  [`chat_state.dart:122`](../../lib/features/chat/presentation/cubit/chat_state.dart#L122)

**UI wiring**

- `onBookmark` callback + lazy bookmark-button construction (only inside the `isUser` branch) + the overflow-safe caption row.
  [`chat_bubble.dart:186`](../../lib/features/chat/presentation/widgets/chat_bubble.dart#L186)

- Icon/color per `BookmarkState`, the width-capped Reduce-Motion label.
  [`chat_bubble.dart:320`](../../lib/features/chat/presentation/widgets/chat_bubble.dart#L320)

- The one-line glue connecting the tapped icon to `ChatCubit.bookmarkMessage` — round 1's own coverage gap, closed this round.
  [`chat_screen.dart:209`](../../lib/features/chat/presentation/screens/chat_screen.dart#L209)

- Standalone icon-size token (not aliased to an unrelated search-bar token).
  [`design_tokens.dart:680`](../../lib/core/design_tokens.dart#L680)

**Tests**

- The full I/O matrix, including the retry-after-error case restored this round.
  [`chat_cubit_test.dart:1101`](../../test/features/chat/presentation/cubit/chat_cubit_test.dart#L1101)

- Per-state icon/color, Reduce-Motion label width cap, AI-bubble exclusion, 44pt tap target.
  [`chat_bubble_test.dart:280`](../../test/features/chat/presentation/widgets/chat_bubble_test.dart#L280)

- The end-to-end wiring test that closes round 1's "untested glue line" gap.
  [`chat_screen_test.dart:699`](../../test/features/chat/presentation/screens/chat_screen_test.dart#L699)

- `isolatedSideEffect`'s own success/throw unit coverage.
  [`isolated_side_effect_test.dart:11`](../../test/core/isolated_side_effect_test.dart#L11)

- The use case's own forwarding/passthrough coverage.
  [`save_chat_message_as_entry_use_case_test.dart:28`](../../test/features/entries/domain/usecases/save_chat_message_as_entry_use_case_test.dart#L28)
