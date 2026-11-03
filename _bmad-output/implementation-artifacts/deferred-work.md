- source_spec: `_bmad-output/implementation-artifacts/spec-1-1-project-scaffold-stack-integration-core-infrastructure.md`
  summary: No portrait-only orientation lock is enforced anywhere in the app shell (`ios/Runner/Info.plist` still lists landscape orientations alongside portrait).
  evidence: `docs/input/requirements.md` fixes the app to a single 390x844 portrait-only frame with no landscape path, but Story 1.1 is core infrastructure only (no screens/app-shell UI) and the architecture spine doesn't assign this lock to any specific story. Likely belongs to Story 1.6 (Base Navigation Shell with Feature Placeholders), the first story that builds real app-shell UI — should be picked up there rather than silently falling through the cracks.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-design-token-system-core-component-library.md`
  summary: `lib/core/widgets/avatar.dart`'s `Avatar` renders raw initials text with no `Semantics` wrapper, so a screen reader announces e.g. "W D" instead of something like "Avatar, Wagner Duarte".
  evidence: Accessibility semantics were never required by Story 1.2's spec (no boundary, acceptance criterion, or epic-context requirement mentions it) and the prototype gives no guidance either, so adding it now would be scope creep beyond the frozen intent. Worth a deliberate pass across all shared widgets (button/text-field/avatar) once an accessibility requirement exists, rather than bolting it onto one widget ad hoc.

## Deferred from: code review of story-1-2-design-token-system-core-component-library (2026-10-27)

- `AppButton` has no loading/busy state, even though most of its real call sites (login submit, insertion-modal "Salvar", export actions) are async network calls. Not required by Story 1.2's boundaries (§6's button component table lists only normal/pressed/disabled variations) — pick up when the first async-submit screen (Story 1.3) needs it, rather than letting each feature improvise its own busy treatment.
- `AppTextField` exposes no `enabled`/`readOnly`, `onSubmitted`, `autofocus`, `textCapitalization`, or `inputFormatters` — all plausible needs for the upcoming login/signup and inline-name-edit screens. Not required by Story 1.2's acceptance criteria; let Story 1.3 (its first real consumer) request exactly what it needs instead of speculatively widening the shared primitive now.
- `lib/core/design_tokens.dart` now imports `package:flutter/widgets.dart` (needed for `Color`/`TextStyle`/`EdgeInsets`/`BoxShadow`), but nothing in the repo (lint rule or architecture test) would catch a future `domain/` layer importing it for a color/style constant, which would transitively violate RNF06. No domain code exists yet to violate this, so it's not a bug today — worth a lint rule or architecture test once the first feature's `domain/` layer is scaffolded.

## Deferred from: code review of story-1-3-account-creation-and-login (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: `Failure.message` is rendered verbatim as the inline form error on `AuthScreen`, but `ApiClient`'s own fallback messages (`'Empty response body'`, `'Malformed response'`, raw `DioException.message`, `'Unknown error'`) are hardcoded English technical strings, so a user can see raw English on an otherwise all-Portuguese screen.
  evidence: Root cause is in `lib/core/network/api_client.dart` (Story 1.1), not this story's diff — `AuthScreen` is simply the first screen to render `Failure.message` directly to an end user, surfacing a pre-existing gap. No `Failure`→localized-copy mapping layer exists anywhere in the project; worth addressing once more than one screen needs to render failures, rather than inventing a one-off mapping for auth alone.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: Neither `AppTextField` on Tela 0.1a reacts to the keyboard's "done"/"next" action to submit the form, and both fields stay fully editable while a signup/login request is in flight (the submitted values can be edited before the response returns).
  evidence: Fixing either requires extending `AppTextField` with `onSubmitted` and `enabled`/`readOnly` params, which this story's frozen spec explicitly rules out ("No new params on `AppButton`/`AppTextField`"). Story 1.2 already flagged both gaps and deferred them to "whichever story needs them first" — Story 1.3 needs them but deliberately didn't request the widening to stay in scope; revisit when a story is willing to extend the shared text field.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-3-account-creation-and-login.md`
  summary: Neither the e-mail nor senha `AppTextField` on Tela 0.1a sets `autofillHints` (`AutofillHints.email`/`.password`), so iOS's Keychain/password-manager autofill won't surface suggestions on this screen.
  evidence: Not required by any requirement or acceptance criterion; a minor iOS-platform completeness gap worth picking up alongside the `AppTextField` widening above rather than as a one-off change now.

## Deferred from: code review of spec-1-2-design-token-system-core-component-library, round 2 (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-design-token-system-core-component-library.md`
  summary: The new `test/core/widgets/component_library_interaction_test.dart` harness sets `textInputAction: TextInputAction.done` on the senha field, but `AppTextField` exposes no `onSubmitted` param to wire a handler to it.
  evidence: Same pre-existing gap already tracked under "Deferred from: code review of story-1-3-account-creation-and-login" above (`AppTextField` widening deliberately deferred to whichever story is willing to extend the shared primitive) — not a new gap, just re-surfaced by this new test harness.

## Deferred from: code review of story-1-4-silent-session-refresh-persistence (2026-10-27)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-4-silent-session-refresh-persistence.md`
  summary: `AuthCubit.toggleMode()`'s `state.copyWith(...)` fix (so an in-flight `status` survives a mode toggle, instead of the previous raw `AuthState(...)` constructor silently resetting it) has no test that can actually observe the regression it fixes — every existing `toggleMode()` call site in the test suite toggles while `status` is already the default idle value.
  evidence: Code review of story-1-4 corrected this entry's earlier "not touched by story 1.4's diff" claim — the change to `lib/features/auth/presentation/cubit/auth_cubit.dart` IS part of this diff. It's deferred on its own merits instead: `toggleMode()`'s only call site is a button disabled whenever `isSubmitting` is true, and every submit-failure path resets `status` back to idle in the same `emit` that sets `formError` — so there is no path through the real `AuthScreen` that can currently drive `status` non-idle at the moment `toggleMode()` runs. Needs a test that calls `submit()` to put `status` in a non-idle state, then `toggleMode()`, then asserts `status` is unchanged — revisit if a future change makes that sequence reachable.

## Deferred from: code review of story-1-5-expired-session-recovery-overlay (2026-11-02)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-5-expired-session-recovery-overlay.md`
  summary: Nothing transitions `SessionStatus` back from `expired` to `authenticated` anywhere (`SessionRepositoryImpl`, `main.dart`), so once a user confirms "Entrar novamente" the status stream itself never leaves `expired` — only the UI route changes.
  evidence: By design for this story: the frozen spec scopes "Entrar novamente" to a throwaway placeholder standing in for Epic 2's real biometric/PIN flow, and that epic is the one that will actually re-authenticate the user and needs to decide how/when the status returns to `authenticated`. Not a bug in this story's own scope (nothing today re-enters the `authenticated` screen while still showing stale `expired` state), but unlike this diff's own similarly-scoped `toggleMode` gap above, it wasn't recorded as a known future obligation — flagging here so Epic 2's own story doesn't have to rediscover it from scratch.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-5-expired-session-recovery-overlay.md`
  summary: `_BiometricReauthPlaceholder` has no `PopScope`/back-gesture guard — the system back gesture pops back to `_PostAuthPlaceholder`, which still looks authenticated even though `SessionStatus` is still `expired` and nothing can ever re-trigger the overlay (the one-shot guard is already spent, and the repository only re-emits `expired` from `authenticated`). The user is stuck looking "logged in" with a dead session, no visible error, until the app restarts.
  evidence: Deferred rather than patched now: the frozen spec explicitly scopes this screen as a throwaway placeholder Epic 2 deletes wholesale, and blocking back-navigation today would trade a silently-stuck-but-restart-recoverable state for a true dead end, without building the real fix — Epic 2's actual biometric/PIN flow is what will own a correct back-navigation story for this screen.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-5-expired-session-recovery-overlay.md`
  summary: `main.dart`'s `_expiryOverlayShown` is set to `true` before confirming `ConfirmationDialog.show()` actually presented anything — if `show()` silently no-ops because `ConfirmationDialog.isOpen` is already held by a different consumer, the session-expiry overlay never appears and the flag is never reset, leaving the user stuck in `expired` with no visible recovery.
  evidence: Unreachable today — `ConfirmationDialog` has exactly one call site in the whole app (this story's own overlay), so `isOpen` can never already be `true` from an unrelated caller when `_maybeShowExpiryOverlay` runs. Becomes reachable the moment a second consumer is added (the widget's own doc comment names Epic 8's account-deletion confirm as that future consumer, reusing the same static `isOpen` guard) — revisit there rather than speculatively guarding against a caller that doesn't exist yet.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: The side menu's drawer header shows a generic avatar/label instead of the real logged-in user's identity (initials/email), even though the prototype's `Tela 3 — Menu lateral` block shows `{{ profileInitials }}`/`{{ profileName }}`.
  evidence: No display name exists anywhere yet (Epic 8 introduces `displayName`), and the only identity the backend ever returns — the login/signup response's `email` — is never persisted anywhere today, so it doesn't survive a silent-refresh restart. Building that (new `AccessTokenProvider.saveUserEmail`/`readUserEmail`, a `SessionRepository.currentUserEmail` accessor, and `AuthRepositoryImpl` wiring) pushed this story's spec well past its token budget (≈2.5k vs. the 900-1600 target) alongside the go_router shell itself, which is the story's actual goal. Carved off rather than folded in; revisit once Epic 8's `displayName` exists, or sooner if a real identity in the drawer is wanted before then — the generic header is still fully polished (not grayed-out/broken), satisfying this story's own acceptance bar.

## Deferred from: code review of story-1-6-base-navigation-shell-with-feature-placeholders (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: The one `GoRouter` in `lib/core/navigation/app_router.dart` configures no `errorBuilder`/`onException`, so an unmatched or invalid route would fall through to Flutter's own unstyled default error page instead of something consistent with the app shell.
  evidence: Not reachable today — the route set is closed (7 fixed paths, no deep-linking, no user-typed URLs) and every navigation call site in this diff uses one of the named `AppRoutePaths` constants, so nothing in the current app can produce an unmatched route. Worth revisiting once deep-linking or a less-constrained navigation surface exists.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: The ☰ menu icon (`HomeChatPlaceholderScreen`) and the back-arrow icon (`_BackArrowHeader`, shared by `MeusRegistrosPlaceholderScreen`/`ActionPlansPlaceholderScreen`/`ConfiguracoesPlaceholderScreen`) are bare `GestureDetector`+`Icon` with no `Semantics`/tooltip label and no enforced minimum touch-target size.
  evidence: Same unaddressed pattern already deferred for `Avatar` (Story 1.2's own deferred-work entry) and not required by any requirement, acceptance criterion, or epic-context boundary for this story. Worth a deliberate accessibility pass across every shared/nav control once an accessibility requirement actually exists, rather than patching one control at a time.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: No test asserts that the side-menu `Drawer` is reachable only from `HomeChatPlaceholderScreen` — the three back-arrow placeholder screens (`MeusRegistrosPlaceholderScreen`/`ActionPlansPlaceholderScreen`/`ConfiguracoesPlaceholderScreen`) have no `drawer:`/`Scaffold.drawer` wiring at all, and nothing would fail today if that asymmetry regressed.
  evidence: Intentional per the prototype and this story's own boundaries ("no drawer-within-drawer," side menu is the sole hub reached only from Home) — not a bug today, just an unguarded invariant. A regression test would catch an accidental divergence (e.g. a future story adding a drawer to one of the other three) earlier than manual QA would.

## Deferred from: code review of story-1-6-base-navigation-shell-with-feature-placeholders (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: `_GoRouterRefreshStream` (`lib/core/navigation/app_router.dart`) is constructed inline as `GoRouter`'s `refreshListenable` with no external reference kept anywhere, and its own `dispose()` cancels the `statusStream` subscription with no `_disposed` guard before any in-flight `notifyListeners()`.
  evidence: Whether go_router 18.1.1 actually calls `.dispose()` on a `refreshListenable` it didn't create itself isn't confirmed from this diff alone — if it doesn't, the subscription could leak; if it does, a `statusStream` emission racing that teardown could in theory throw `ChangeNotifier used after being disposed` in debug builds. No test or production run has surfaced this, and the fix depends on first confirming go_router's actual disposal contract for an externally-supplied `Listenable` — revisit once that's verified rather than guessing at a guard.

- source_spec: `_bmad-output/implementation-artifacts/spec-1-6-base-navigation-shell-with-feature-placeholders.md`
  summary: `ios/Runner/Info.plist`'s portrait-only orientation lock has no `UIRequiresFullScreen` — iPadOS Split View/Slide Over can still resize this fixed-390×844-frame app regardless of the declared orientation restriction.
  evidence: Not in this story's own stated boundaries (which only ask for the orientation keys), and no device/simulator exists yet (AGENTS.md) to verify the actual iPad behavior either way. Revisit once iPad support is an explicit target or device testing exists.
