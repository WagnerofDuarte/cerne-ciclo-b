---
title: 'Story 1.5: Expired-Session Recovery Overlay'
type: 'feature'
created: '2026-10-28'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'b9870eb4f6e85d84aeb3f03125a2be7d91ffc5d6'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/docs/input/prototype/prototype-extract.md'
  - '{project-root}/docs/input/backend/error-taxonomy.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `ApiClient._mapDioException` already maps any mid-session `AUTH_EXPIRED` response to `Failure.authExpired` (`api_client.dart:95-111`), but nothing reacts to it — `SessionStatus` only ever emits from the boot-time `restoreSession()` call (`session_repository_impl.dart:81-136`), so an expired session mid-use today surfaces only as a raw inline error on whatever screen made the call, and the user is never routed back to re-auth.

**Approach:** Add a core `SessionExpiryNotifier` port (in the already-scaffolded empty `lib/core/session/`) that `ApiClient` signals on any non-boot `AUTH_EXPIRED`; `SessionRepositoryImpl` bridges that into one new `SessionStatus.expired` value on the epic's existing single stream. `main.dart` keeps rendering the same authenticated screen across that transition and shows a new shared `ConfirmationDialog` overlay (neutral title) whose "Entrar novamente" button routes to a throwaway re-auth placeholder standing in for Epic 2's biometric/PIN flow.

## Boundaries & Constraints

**Always:**
- `ApiClient` notifies expiry only for `AUTH_EXPIRED` on calls outside `HeaderInterceptor.anonKeyOnlyFunctions` (`header_interceptor.dart:20-24`, matched via its `functionNameOf`) — boot-time `auth-refresh` keeps going through Story 1.4's existing `restoreSession()` path untouched.
- `SessionStatus` gains exactly one new `expired` value; `statusStream`/`restoreSession`/`dispose` signatures are unchanged — still the epic's one singleton stream (AD), no second stream.
- `SessionRepositoryImpl` emits `expired` only when `_lastStatus == SessionStatus.authenticated`; any other current status ignores the event (no spurious overlay during boot or after logout).
- Overlay = new `ConfirmationDialog` (`lib/core/widgets/`): neutral `colorTextPrimary` title (never `colorError`), non-dismissible barrier, focus-trapped, at most one open at a time (UX-DR16/25/27/36). Entrance is exactly `scrimIn` (0.18s ease-out fade) — the system's only other animation, `sheetUp`, is untouched.
- The authenticated screen's widget instance is never replaced across `authenticated`↔`expired` transitions — scroll/state preserved; the `AuthScreen` branch is unaffected.
- Copy never implies data loss; must state history/scroll position are preserved (mirrors the prototype's own "Sessão expirada" copy).

**Ask First:** if a future consumer needs a session state beyond this story's single new `expired` value, HALT before adding a fourth `SessionStatus` member — renegotiate the epic's AD first.

**Never:**
- No `go_router` — `main.dart` keeps its current `MaterialApp`/`Navigator` shape (Story 1.6).
- No Epic 2 biometric/PIN implementation — "Entrar novamente" only navigates to a throwaway placeholder that Epic 2 deletes wholesale.
- No new icon-font dependency — approximate the prototype's `ph-lock-key` with a built-in Material icon.
- No Reduce-Motion handling — out of this epic's scope.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Mid-session expiry | authenticated, any screen, any endpoint returns `AUTH_EXPIRED` | overlay appears over the current screen; its scroll/state is preserved | silent — no extra inline error |
| Already-open overlay | a second `AUTH_EXPIRED` arrives while the dialog is showing | no second dialog stacks | silent, single-overlay guard holds |
| Expiry while not authenticated | notifier fires but `_lastStatus != authenticated` (e.g. post-logout race) | no emission, no overlay | silent no-op |
| Boot-time refresh expiry | `restoreSession()`'s own `auth-refresh` call returns `AUTH_EXPIRED` | unchanged Story 1.4 behavior — lands on `AuthScreen`, never the overlay | existing path, untouched |
| "Entrar novamente" tapped | overlay visible | dialog dismissed, user routed to the biometric/PIN placeholder | N/A |

</frozen-after-approval>

## Code Map

- `lib/core/session/session_expiry_notifier.dart` -- new: `SessionExpiryNotifier` port + broadcast-stream impl, pure Dart (no Flutter/feature import, RNF06) — the directory exists today as a Story 1.1 scaffold (`.gitkeep` only).
- `lib/core/network/api_client.dart:95-111` -- `_mapDioException` additionally calls `SessionExpiryNotifier.notifyExpired()` when the mapped failure `is AuthExpired` and `HeaderInterceptor.functionNameOf(e.requestOptions.path)` isn't in `anonKeyOnlyFunctions` (`header_interceptor.dart:20-24,80-83`) — new constructor dependency.
- `lib/core/di/injection_container.dart:33-61` -- register `SessionExpiryNotifier` as a singleton (with `dispose:`) before `ApiClient`; pass it into `ApiClient`'s constructor.
- `lib/features/auth/domain/entities/session_status.dart` -- add third value `expired` to the current 2-value enum.
- `lib/features/auth/data/repositories/session_repository_impl.dart:27-140` -- constructor takes `SessionExpiryNotifier`; subscribes to `expiredEvents`, emits `SessionStatus.expired` per the "Always" guard above; cancels the subscription in `dispose()` (`:139`).
- `lib/features/auth/auth_injection.dart:33-39` -- pass `sessionExpiryNotifier: sl<SessionExpiryNotifier>()` into `SessionRepositoryImpl`.
- `lib/core/widgets/confirmation_dialog.dart` -- new shared component (UX-DR16): scrim + centered card, `titleColor` param (neutral here; Epic 8's account-deletion dialog later passes `colorError`), non-dismissible barrier, single-overlay guard, `scrimIn` entrance.
- `lib/core/design_tokens.dart` -- add `colorScrim` (see Design Notes) plus any new named spacing/padding constants the dialog card needs beyond the existing scale (RNF08).
- `lib/main.dart:90-132` -- `StreamBuilder` treats `authenticated`/`expired` as the same `_PostAuthPlaceholder` render; a small listener shows/dismisses `ConfirmationDialog` on that transition; new throwaway `_BiometricReauthPlaceholder` (same pattern as `_PostAuthPlaceholder`) is "Entrar novamente"'s target.
- Ground truth for copy/visuals: `docs/input/prototype/cerne-prototype.html` ("OVERLAY: Sessão expirada" block) and `prototype-extract.md:69,174-176,227`; `docs/input/backend/error-taxonomy.md:7` (`AUTH_EXPIRED`, 401, non-retryable).

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/session/session_expiry_notifier.dart` -- new port + impl -- lets core signal expiry without importing the auth feature
- [x] `lib/core/network/api_client.dart` -- call the notifier on mid-session `AUTH_EXPIRED` -- the one detection point (AD-2/AD-5)
- [x] `lib/core/di/injection_container.dart` -- register + wire the notifier into `ApiClient` -- DI
- [x] `lib/features/auth/domain/entities/session_status.dart` -- add `expired` -- the signal `main.dart` branches on
- [x] `lib/features/auth/data/repositories/session_repository_impl.dart` -- bridge the notifier into `statusStream` -- epic AD, one stream only
- [x] `lib/features/auth/auth_injection.dart` -- wire the notifier into `SessionRepositoryImpl` -- DI
- [x] `lib/core/design_tokens.dart` -- add `colorScrim` + any new dialog-card constants -- RNF08
- [x] `lib/core/widgets/confirmation_dialog.dart` -- new shared overlay component -- UX-DR16/25/27/36
- [x] `lib/main.dart` -- show/dismiss the overlay across `authenticated`↔`expired` without replacing the screen; add `_BiometricReauthPlaceholder`
- [x] `test/core/session/session_expiry_notifier_test.dart` -- new -- notify/listen/dispose
- [x] `test/core/network/api_client_test.dart` -- extend -- notifies only on non-anon-key-function `AUTH_EXPIRED`
- [x] `test/features/auth/data/repositories/session_repository_impl_test.dart` -- extend -- `expired` only fires from `authenticated`
- [x] `test/core/widgets/confirmation_dialog_test.dart` -- new -- neutral title color, non-dismissible barrier, single-overlay guard, Dynamic Type
- [x] `test/main_test.dart` -- extend -- overlay appears/dismisses without losing the underlying screen; "Entrar novamente" routes to the placeholder

**Acceptance Criteria:**
- Given the overlay is open, when the user taps the scrim, then nothing happens (barrier is non-dismissible, focus stays trapped on the dialog).
- Given `fvm flutter analyze`, when run after this change, then zero issues and no hardcoded `Color(0x`/`EdgeInsets.*` literal outside `design_tokens.dart`.

### Review Findings

- [x] [Review][Patch] `session_status.dart`'s doc comment grammar: "never a extra enum value" -> "never an extra enum value" [lib/features/auth/domain/entities/session_status.dart:4]
- [x] [Review][Patch] `main.dart`'s `_maybeShowExpiryOverlay` could reopen an already-confirmed-and-dismissed overlay on any later rebuild that still observes `expired` (nothing transitions the status away from it) — `ConfirmationDialog.isOpen` alone only guards against *concurrent* stacking, not a reopen after the first close. Fixed with a separate one-shot-per-episode `_expiryOverlayShown` flag on `_CerneAppState`. [lib/main.dart]
- [x] [Review][Patch] The overlay's non-dismissible requirement (UX-DR16/25/27/36) only blocked a scrim tap (`barrierDismissible: false`) — the system/hardware back gesture could still pop the route and dismiss it. Fixed by wrapping the dialog's route content in `PopScope(canPop: false, ...)`. [lib/core/widgets/confirmation_dialog.dart]
- [x] [Review][Patch] `ConfirmationDialog.show()` set `isOpen = true` before calling `showGeneralDialog`, with no guard against a synchronous throw (e.g. a future caller passing a context with no `Navigator` ancestor) — would permanently lock the app-wide single-overlay guard. Fixed with a try/catch that resets `isOpen` and rethrows. [lib/core/widgets/confirmation_dialog.dart]
- [x] [Review][Patch] `SessionRepositoryImpl`'s `_expirySubscription.listen(...)` had no `onError`, unlike `statusStream`'s own internal subscription a few lines below — a future `SessionExpiryNotifier` implementation that ever errored would surface as an unhandled zone exception. Fixed with a matching `onError: (_, _) {}`. [lib/features/auth/data/repositories/session_repository_impl.dart]
- [x] [Review][Patch] `main.dart`'s `onConfirm` closure re-used its captured outer `context` to push the biometric placeholder without re-checking `context.mounted` immediately before the call (only checked once, at the point the overlay was scheduled). Unreachable today (nothing can unmount `_PostAuthPlaceholder` while the dialog is open), but cheap to guard. Fixed with a second `mounted` check inside `onConfirm`. [lib/main.dart]
- [x] [Review][Patch] No test covered a stored-but-empty refresh token on `restoreSession()` — the `refreshToken == null || refreshToken.isEmpty` short-circuit added by this diff had no regression coverage. Fixed with a new test case. [test/features/auth/data/repositories/session_repository_impl_test.dart]
- [x] [Review][Patch] The `dispose()` subscription-cancel test only asserted `expiryController.add(null)` didn't throw — that's true regardless of whether `_expirySubscription.cancel()` actually ran (the `_emit()` `isClosed` guard added by this same diff swallows the result either way), so it couldn't actually catch a regression. Fixed by asserting no event reaches `statusStream` after dispose. [test/features/auth/data/repositories/session_repository_impl_test.dart]
- [x] [Review][Patch] No test covered the Boundaries' "focus-trapped" requirement for `ConfirmationDialog`. Fixed with a Tab-traversal test asserting a background `TextField` never gains focus while the overlay is open. [test/core/widgets/confirmation_dialog_test.dart]
- [x] [Review][Patch] The existing "tapping the scrim does nothing" test only re-asserted the dialog's title text was still present — it would keep passing even if the tap missed everything entirely (e.g. if the card ever grew to cover that corner), not just if the barrier genuinely absorbed it. Fixed by adding a dedicated test with a background `GestureDetector` that proves the tap never reaches it. [test/core/widgets/confirmation_dialog_test.dart]
- [x] [Review][Defer] Nothing transitions `SessionStatus` back from `expired` to `authenticated` anywhere — by design for this story (Epic 2's real re-auth owns that), but it wasn't recorded as a known future obligation the way this diff's own `toggleMode` gap is. Recorded in `deferred-work.md`. [lib/features/auth/data/repositories/session_repository_impl.dart, lib/main.dart] — deferred, Epic 2's concern

### Code Review (2026-11-02)

- [x] [Review][Defer] `_BiometricReauthPlaceholder` (the "Entrar novamente" destination) has no `PopScope`/back-gesture guard, unlike `ConfirmationDialog`'s own route — the system back gesture pops straight back to `_PostAuthPlaceholder`, which still renders exactly like a normal authenticated screen even though `SessionStatus` is still `expired`. Once there, `_expiryOverlayShown` is already `true` (one-shot guard) and `SessionRepositoryImpl._onSessionExpired()` only re-emits from `authenticated` (never from `expired`), so no later `AUTH_EXPIRED` response can ever reopen the overlay — the user is stuck looking "authenticated" with a dead session until they restart the app, with no visible error. Deferred rather than patched now: the frozen spec explicitly scopes this screen as a throwaway placeholder Epic 2 deletes wholesale, and adding a back-gesture block today would just trade a silently-stuck-but-recoverable-by-restart state for a true dead end, without building the real fix (Epic 2's actual biometric/PIN flow is what will own a correct back-navigation story here). [lib/main.dart:217-229] — deferred, Epic 2's concern
- [x] [Review][Patch] "Entrar novamente" has no debounce: `AppButton` has no built-in disable-after-tap (pre-existing, already deferred in story 1.2's own review), and the dialog's 180ms exit `FadeTransition` leaves the button hit-testable while fading out. A rapid double-tap can fire `onConfirm` twice — the second `Navigator.of(dialogContext).pop()` races the first pop already in flight, and the second `Navigator.of(context).push(...)` pushes a duplicate `_BiometricReauthPlaceholder` onto the stack. Fix: guard `onConfirm` with a one-shot flag (same pattern already used for `_expiryOverlayShown`), or disable the button synchronously on first tap. [lib/main.dart:132-142]
- [x] [Review][Patch] `ConfirmationDialog.show()`'s `catch (_) { isOpen = false; rethrow; }` branch — added specifically so a synchronous throw from `showGeneralDialog` (e.g. a future caller passing a `context` with no `Navigator` ancestor) doesn't permanently lock the app-wide single-overlay guard — has no test exercising it. Every test in `confirmation_dialog_test.dart` and `main_test.dart` calls `show()` with a context that does have a `Navigator` ancestor, so the branch never runs; a regression here (e.g. dropping the `catch`, or dropping `isOpen = false` inside it) would leave the whole suite green while silently disabling every future `ConfirmationDialog.show()` call — including Epic 8's account-deletion dialog, which reuses the same static guard — for the rest of the running app. Fix: add a test that forces the synchronous throw (e.g. call `show()` from a `Builder` with no `MaterialApp`/`Navigator` ancestor) and assert `isOpen` is `false` afterward. [lib/core/widgets/confirmation_dialog.dart:67-111]
- [x] [Review][Patch] The five new `DesignTokens` constants this story adds (`colorScrim`, `dialogIconSize`, `dialogContentGap`, `dialogScreenMargin`, `dialogCardPadding`) have no direct value assertion in `design_tokens_test.dart` — they're only ever passed through as parameters in `confirmation_dialog_test.dart`, never asserted against a rendered value. Breaks the per-token test convention story 1.2's own review established (e.g. its "layout insets" test group for `buttonPadding`/`textFieldContentPadding`). Fix: add assertions for the five new constants to `design_tokens_test.dart`. [test/core/design_tokens_test.dart]
- [x] [Review][Patch] `_maybeShowExpiryOverlay` calls `ConfirmationDialog.show(...)` as a bare, un-awaited statement inside a (non-`async`) `addPostFrameCallback` callback — inconsistent with this same file's own `unawaited(...)` convention a few lines above for exactly this situation. If the dialog's `Future` ever completes with an error, it becomes an unhandled `Future` rejection instead of a logged message. Fix: wrap the call in `unawaited(...)`. [lib/main.dart:121]
- [x] [Review][Patch] `class MockSessionExpiryNotifier extends Mock implements SessionExpiryNotifier {}` is declared identically in both `test/core/network/api_client_test.dart` and `test/features/auth/data/repositories/session_repository_impl_test.dart` instead of one shared test helper. Fix: factor into a single shared mock (e.g. alongside the project's other shared test helpers). [test/core/network/api_client_test.dart, test/features/auth/data/repositories/session_repository_impl_test.dart]
- [x] [Review][Patch] `api_client_test.dart`'s "a non-AUTH_EXPIRED failure never notifies, even on a bearer function" test throws a `DioException` built from the `setUp`-level `requestOptions` fixture (path `auth-signup`, anon-key-only) while the call under test actually targets `entries-create` (bearer) — currently harmless (the thrown `connectionError` type never reaches the anon-key-only check at all), but the fixture contradicts the scenario the test's own name describes. Fix: build a `RequestOptions` for `entries-create` for this test instead of reusing the shared anon-key fixture. [test/core/network/api_client_test.dart]
- [x] [Review][Patch] `main.dart`'s `onConfirm` checks `context.mounted` before pushing the follow-up route but never checks `dialogContext.mounted` before the `Navigator.of(dialogContext).pop()` call immediately preceding it — an inconsistent mounted-guard pattern, though unreachable today (the callback only ever fires from a live tap on a still-mounted dialog). Fix: add the matching `dialogContext.mounted` check for consistency. [lib/main.dart:132-136]
- [x] [Review][Patch] `injection_container.dart`'s comment says `SessionExpiryNotifier` is "registered before `ApiClient` so it's ready to inject" — but `registerLazySingleton` resolves its factory lazily on first `sl<T>()` access, not at registration time, so registration order isn't actually why the wiring works. Fix: reword the comment to not claim a causal ordering effect that `get_it`'s lazy singletons don't have. [lib/core/di/injection_container.dart:40-43]
- [x] [Review][Defer] `_expiryOverlayShown` is set to `true` *before* confirming `ConfirmationDialog.show()` actually presented anything. If `show()` silently no-ops because `ConfirmationDialog.isOpen` is already held by a different consumer (e.g. a future Epic 8 account-deletion dialog open at the same moment), the session-expiry overlay never appears and this flag is never reset — the user is stuck in `expired` with no visible recovery until the other dialog closes and nothing re-triggers this one. Unreachable today: `ConfirmationDialog` has exactly one call site in the whole app. Revisit when a second consumer (Epic 8) is added. [lib/main.dart:112-146, lib/core/widgets/confirmation_dialog.dart] — deferred, unreachable until a second `ConfirmationDialog` consumer exists

## Design Notes

- `colorScrim` must be `Color(0x38241F19)` — `rgba(36,31,25,.22)`, the exact value `cerne-prototype.html` uses for *this* overlay specifically. Its other overlays (drawer, insertion modal, filter/export sheets, account-deletion confirm) use `rgba(36,31,25,.4)` (`0x66...`) instead — don't reuse that heavier value here; it belongs to whichever later story builds those.
- `SessionExpiryNotifier` lives in core (not the auth feature) specifically so `ApiClient` can signal expiry without importing anything from `features/auth` (RNF06) — `SessionRepositoryImpl` is the one bridge back onto the single `SessionStatus` stream.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves, no conflicts
- `fvm flutter test` -- all tests pass
- `fvm flutter analyze` -- zero issues
- `grep -rn "Color(0x\|fontSize:\|EdgeInsets\.\(all\|symmetric\|only\)(" lib/core/session lib/core/network lib/core/widgets lib/features/auth lib/main.dart --include=*.dart` -- expected: no matches outside `design_tokens.dart` (RNF08)

## Suggested Review Order

**The core expiry signal (RNF06 — core knows nothing of `features/auth`)**

- New port: a broadcast stream of expiry events, with a `dispose()`-safe guard against a late signal after teardown.
  [`session_expiry_notifier.dart:31`](../../lib/core/session/session_expiry_notifier.dart#L31)

- The one detection point — maps a mid-session `AUTH_EXPIRED` to a notifier call, skipping the three anon-key-only operations.
  [`api_client.dart:123`](../../lib/core/network/api_client.dart#L123)

- Mirrors `HeaderInterceptor`'s own fail-open behavior to decide whether a call is boot-time `auth-refresh` or a real mid-session expiry.
  [`api_client.dart:139`](../../lib/core/network/api_client.dart#L139)

**Bridging the signal onto `SessionStatus` (the epic's one stream, AD)**

- Third enum value — the signal `main.dart` branches on; no new stream, no new DI singleton.
  [`session_status.dart:13`](../../lib/features/auth/domain/entities/session_status.dart#L13)

- The bridge itself: subscribes at construction, emits `expired` only from `authenticated`, cancels in `dispose()`.
  [`session_repository_impl.dart:39`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L39)

- The "Always" guard that makes every other current status a silent no-op — the heart of this story's I/O matrix.
  [`session_repository_impl.dart:100`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L100)

- Widened alongside the bridge: a stored-but-empty refresh token is now also "no session," not just `null`.
  [`session_repository_impl.dart:119`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L119)

**The recovery overlay (new shared widget, UX-DR16/25/27/36)**

- `show()`'s single-overlay guard, now exception-safe, plus the `PopScope(canPop: false)` that actually blocks the system back gesture.
  [`confirmation_dialog.dart:67`](../../lib/core/widgets/confirmation_dialog.dart#L67)

- The card itself — neutral title color by default, the later destructive variant already designed in via `titleColor`.
  [`confirmation_dialog.dart:136`](../../lib/core/widgets/confirmation_dialog.dart#L136)

- The scrim's exact color and the dialog card's new spacing constants — this story's only non-frozen visual additions.
  [`design_tokens.dart:77`](../../lib/core/design_tokens.dart#L77)

**Wiring it all into `main.dart`**

- The one-shot-per-episode guard that stops a later rebuild from reopening an already-confirmed overlay.
  [`main.dart:99`](../../lib/main.dart#L99)

- `expired` renders the same screen as `authenticated` — the overlay layers on top instead of replacing it.
  [`main.dart:162`](../../lib/main.dart#L162)

**DI**

- `SessionExpiryNotifier` registered before `ApiClient`, with `dispose:` wired into `get_it`'s own teardown.
  [`injection_container.dart:44`](../../lib/core/di/injection_container.dart#L44)

- The notifier threaded into both `ApiClient` and `SessionRepositoryImpl`.
  [`injection_container.dart:73`](../../lib/core/di/injection_container.dart#L73), [`auth_injection.dart:38`](../../lib/features/auth/auth_injection.dart#L38)

**Tests**

- The bridge's full I/O matrix, including the two regression tests added by this review round (empty token, dispose's real effect).
  [`session_repository_impl_test.dart:268`](../../test/features/auth/data/repositories/session_repository_impl_test.dart#L268)

- The overlay's accessibility/dismissal guarantees — non-dismissible scrim (tap actually absorbed), back-gesture block, focus trap.
  [`confirmation_dialog_test.dart:45`](../../test/core/widgets/confirmation_dialog_test.dart#L45)

- The composition-root proof: overlay appears over the live screen, never double-stacks, confirm routes away, and a later rebuild can't reopen it.
  [`main_test.dart:239`](../../test/main_test.dart#L239)

- `SessionExpiryNotifier`'s own isolated unit test, and the real-wiring pipeline test proving `AUTH_EXPIRED` reaches it outside mocks.
  [`session_expiry_notifier_test.dart`](../../test/core/session/session_expiry_notifier_test.dart), [`network_pipeline_integration_test.dart`](../../test/core/network/network_pipeline_integration_test.dart)
