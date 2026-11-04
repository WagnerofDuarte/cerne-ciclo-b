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

## Deferred from: code review of story-2-1-biometric-pin-app-access-gate (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-2-1-biometric-pin-app-access-gate.md`
  summary: `VaultRepositoryImpl.authenticate()`'s single `on LocalAuthException` catch collapses every `LocalAuthExceptionCode` (including `lockedOut`/`biometryLockout`) into one generic `Failure.malformedResponse`, discarding the lockout-vs-other-failure distinction `epic-2-context.md` says is needed to route an OS-level lockout to the app's own PIN fallback rather than retrying the OS.
  evidence: Not required by spec-2-1's own frozen Boundaries or I/O matrix — no PIN screen exists yet for this story to route to. Story 2.2 (Biometric-Failure Fallback to PIN) is the explicit, already-planned owner of this distinction; revisit there rather than widening 2.1's error mapping speculatively now.
  resolved_by: Story 2.2 (code review, 2026-11-03) — every `authenticate()` failure now falls through to the same `PinKeypad`, so the lockout-vs-other-failure distinction this entry worried about is moot: there's no second OS-retry affordance to mis-route to regardless of which `LocalAuthExceptionCode` fired. `vault_repository_impl_test.dart` and `vault_lock_screen_test.dart` now each include a case exercising a `biometricLockout`-flavored failure to prove this explicitly rather than only by comment.

- source_spec: `_bmad-output/implementation-artifacts/spec-2-1-biometric-pin-app-access-gate.md`
  summary: No timeout wraps the OS biometric prompt in `VaultLockScreen._attemptAuthenticate`; if `authenticate()` never resolves (a hung native call, not covered by `persistAcrossBackgrounding: true`), the lock screen stays on its initial "autenticando" state forever with no retry button and no escape — the one gate blocking every screen in the app.
  evidence: Outside spec-2-1's own I/O & Edge-Case Matrix, which only covers success/declined-or-cancelled, not a hang. No device/simulator exists yet (AGENTS.md) to reproduce or verify a real-world hang either way; revisit if this proves reachable in practice or once device testing exists.

- source_spec: `_bmad-output/implementation-artifacts/spec-2-1-biometric-pin-app-access-gate.md`
  summary: `main.dart`'s `_CerneAppState.initState` fires `_sessionRepository.restoreSession()` (a real backend network call) unconditionally, with no gating on `VaultRepository.currentStatus` — in tension with `epic-2-context.md`'s own framing that "the vault gates whether anything may be shown at all, before any network/session state is considered."
  evidence: Unchanged since Story 1.4 (pre-existing, not introduced by this diff) — `VaultRepository` makes zero network calls itself (spec-2-1's own boundary), and this call's outcome only ever reaches the UI through `SessionStatus`/`statusStream`, which the vault gate already overrides while locked. A real architectural tension worth a deliberate decision once a later epic cares about exactly when the first network call fires relative to the vault, not a correctness bug in 2.1 itself.

## Deferred from: code review of story-2-2-biometric-failure-fallback-to-pin (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-2-2-biometric-failure-fallback-to-pin.md`
  summary: The prototype's `Tela 0.1 — Biometria` block (`docs/input/prototype/prototype-extract.md` §2.1) names two links — "Usar PIN" and a secondary "usar e-mail e senha" — but only the first is built; there is still no path from the vault screen back to the existing password login/signup screen (Story 1.3).
  evidence: Pre-existing gap, not introduced by this story — spec-2-1 built `_BiometricView`'s predecessor with neither link (PIN didn't exist yet), and no story in Epic 2 (2.1-2.4) names this link in its own scope. No epic currently owns reconnecting the vault screen to password login; revisit once a story claims it rather than bolting it onto 2.2's own frozen intent (PIN fallback only).

- source_spec: `_bmad-output/implementation-artifacts/spec-2-2-biometric-failure-fallback-to-pin.md`
  summary: Tapping "Usar PIN" switches `VaultLockScreen` to the PIN keypad but never cancels or acknowledges the still-pending native `authenticate()` call it escaped from — on a real device, the OS Face ID/Touch ID sheet may still be visible (or about to appear) underneath the app's own PIN keypad.
  evidence: `local_auth` exposes no universal cancel API for an in-flight `authenticate()` call, so there is no code-level fix available today — only a known-limitation to track. `_attemptAuthenticate`'s own `alreadyOnKeypad` guard already prevents the pending call's eventual result from clobbering the keypad's UI state once it resolves, but that doesn't address the native OS UI itself. No device/simulator exists yet (AGENTS.md) to observe or verify the actual on-device behavior either way; revisit once device testing exists or `local_auth` adds a cancellation API.

## Deferred from: code review of story-2-3-fixed-5-minute-idle-re-authentication-timeout (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-2-3-fixed-5-minute-idle-re-authentication-timeout.md`
  summary: `VaultRepositoryImpl.didChangeAppLifecycleState`'s idle-timeout check computes elapsed time from wall-clock `DateTime.now()` (via the injectable `_now`), so a device clock change (manual adjustment, timezone shift, NTP correction) between `paused` and `resumed` can defeat or spuriously trigger the re-lock.
  evidence: This was a frozen, explicit boundary of spec-2-3 itself ("Elapsed time read via an injectable `DateTime Function() now` constructor param (default `DateTime.now`) for deterministic tests") rather than an implementation deviation. Kept for simplicity (no `clock`/`fake_async` dependency, matches Design Notes) rather than for any robustness reason — a monotonic source (e.g. `Stopwatch`) would avoid clock-tampering/skew, but isn't actually a stronger guarantee here: both approaches are lost identically if the app process is killed while backgrounded, since `VaultRepositoryImpl` itself is recreated on relaunch either way. Changing the device clock already requires the OS itself to be unlocked, so this only matters for Cerne's own vault layer specifically, not overall device access. Revisit if a stronger timing guarantee is ever required (e.g. hardening the vault beyond a reflective-journal app's current threat model).

## Deferred from: code review of story-2-4-biometric-preference-persistence (2026-11-03)

- source_spec: `_bmad-output/implementation-artifacts/spec-2-4-biometric-preference-persistence.md`
  summary: Frozen spec-2-3 boundary violation ("No changes to `app_router.dart` or `vault_lock_screen.dart`") was committed anyway and accepted after the fact only in spec-2-3's own Spec Change Log — not disclosed anywhere in spec-2-4.md, even though commit `3bb2d5d` (the only commit after `81d7509`) is the one that actually ships those changes alongside this story's own work.
  evidence: Process/governance concern (a precedent for bypassing a frozen boundary as long as it's documented after the fact somewhere, not necessarily in the spec whose commit actually ships it), not a functional defect in story 2.4's own scope — the idle-timeout/vault fixes themselves were already reviewed and accepted under spec-2-3. Worth raising in the epic-2 retrospective so the next story's review explicitly cross-checks which spec file a bundled fix's disclosure actually lives in.

- source_spec: `_bmad-output/implementation-artifacts/spec-2-4-biometric-preference-persistence.md`
  summary: No UX source-of-truth doc (`DESIGN.md`/`EXPERIENCE.md`/`prototype-extract.md`) documents the new biometric toggle on the Configurações screen, even though `epics.md`'s FR-7 and its acceptance criteria do.
  evidence: None of `_bmad-output/planning-artifacts/ux-designs/ux-cerne-ciclo-b-2026-10-26/DESIGN.md` or `EXPERIENCE.md` are touched by this diff, and `EXPERIENCE.md` currently attributes `PATCH /account/settings`'s role on this screen exclusively to the persona toggle (an extension feature, never to be implemented per AGENTS.md policy). Epic 8 (`epics.md:499`) extends this same screen with profile editing/dashboard/account actions; revisit by updating those UX docs before or during that epic so there's documented guidance to build on.
