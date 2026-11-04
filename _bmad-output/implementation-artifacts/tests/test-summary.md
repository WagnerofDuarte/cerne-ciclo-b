# Test Automation Summary

## Context

Cerne has no device/simulator or CI pipeline yet (AGENTS.md), so a true
platform-level E2E (`integration_test` on a real/simulated device) isn't
viable right now. The project already substitutes composition-root widget
tests — `CerneApp` pumped with only a single named boundary faked (the
`AuthRepository`/`SessionRepository` interface, or, in
`network_pipeline_integration_test.dart`, the `HttpClientAdapter`) — as its
E2E equivalent. `ApiClient`'s own docstring states the convention
explicitly: tests mock `ApiClient` directly; only one dedicated suite is
allowed to fake the transport boundary beneath it. All API-level coverage
(status codes, response mapping, the 3-error write-failure matrix per
write endpoint, retry behavior, header/URL building) already exists across
`test/core/network/` and `test/features/auth/data/`.

Before adding anything, the full suite was run: **194/194 tests passing**,
`flutter analyze`: **0 issues**. Given that density, the only legitimate
gap found was in the composition-root (E2E-equivalent) layer.

## Generated Tests

### E2E Tests (composition-root, `test/main_test.dart`)

- [x] `test/main_test.dart` — **new**: "CerneApp resolves the real AuthCubit
  and navigates to the post-auth placeholder once signup succeeds" —
  mirrors the existing real-wiring login test, but drives the
  toggle-to-signup path. Previously, signup was only exercised against a
  directly-constructed `AuthScreen`/`AuthCubit` pair
  (`auth_screen_test.dart`), never through `main.dart`'s actual
  `sl<AuthCubit>()` resolution and `onAuthenticated` → `Navigator`
  wiring — only the login path had that proof.

No other E2E or API gaps were found; everything else implemented so far
(design tokens/component library, auth validators, auth cubit, auth
repository/data source, session repository, network pipeline, DI bootstrap)
already has dedicated coverage at the appropriate layer.

## Coverage

- Composition-root E2E scenarios: login ✅, **signup ✅ (added)**,
  authenticated-boot ✅, unauthenticated-boot ✅, boot-loading-threshold ✅
- API/data-source coverage: auth-login, auth-signup, auth-refresh — happy
  path + the full 3-case write-failure matrix (timeout/malformed/offline)
  each, plus retry and non-retry behavior proven over a faked transport
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.4
  (scaffold, design tokens, auth, session refresh) — all covered. Stories
  1.5+ are still `backlog`, so out of scope for this pass.

## Verification

- `fvm flutter test` → 195/195 passing (194 pre-existing + 1 new)
- `fvm flutter analyze` → 0 issues

## Next Steps

- Revisit the "no device/CI" constraint (AGENTS.md) once a simulator or CI
  step exists — at that point, a real `integration_test` driver test
  becomes possible and composition-root tests can be retired in its favor.
- Re-run this pass after each future story (1.6 navigation shell, …) lands,
  since each adds a new composition-root surface worth the same
  login/signup-style proof.

---

# Story 1.5 — Expired-Session Recovery Overlay

## Context

Story 1.5 adds a new core port (`SessionExpiryNotifier`), a third
`SessionStatus` value (`expired`), a new shared `ConfirmationDialog`
overlay widget, and `main.dart`'s reaction to the two together. Each new
unit gets its own isolated test, and the composition-root suite
(`test/main_test.dart`) gets the end-to-end proof that a mid-session
`AUTH_EXPIRED` actually surfaces the overlay over the live screen and
routes on confirm — same E2E-equivalent pattern this file's Story 1.4
section established.

Code review of this story's own diff surfaced and fixed four gaps before
landing: a rebuild that could reopen an already-dismissed overlay (no
guard against calling `show()` more than once per `expired` episode), the
system back gesture being able to dismiss the overlay despite the
non-dismissible-barrier requirement (`PopScope` was missing), a synchronous
`showGeneralDialog` failure permanently locking the single-overlay guard,
and a stored-but-empty refresh token not short-circuiting
`restoreSession()` the same way a `null` one does.

## Generated Tests

### Unit (new core/feature code)

- [x] `test/core/session/session_expiry_notifier_test.dart` — **new**:
  `SessionExpiryNotifierImpl.notifyExpired()`/`expiredEvents`/`dispose()`.
- [x] `test/features/auth/data/repositories/session_repository_impl_test.dart`
  — **extended**: the `expired` bridge's whole I/O matrix (mid-session
  expiry while authenticated, while unauthenticated, before any status
  yet, a second event while already `expired`, `dispose()` cancelling the
  subscription), plus a stored-but-empty refresh token now being treated
  as "no session" the same as `null`.
- [x] `test/core/network/api_client_test.dart` — **extended**: the
  notifier fires only for a mid-session `AUTH_EXPIRED` outside
  `anonKeyOnlyFunctions`.
- [x] `test/core/network/network_pipeline_integration_test.dart` —
  **extended**: an `AUTH_EXPIRED` response on a bearer call reaches the
  notifier through the real wiring, not just the mocked `ApiClient` unit.

### Composition/interaction (shared widget)

- [x] `test/core/widgets/confirmation_dialog_test.dart` — **new**: neutral
  vs. destructive `titleColor`, the non-dismissible scrim (including a
  dedicated check that the tap is actually absorbed by the barrier rather
  than just leaving the dialog on screen), the back-gesture `PopScope`
  guard, the single-overlay guard, `onConfirm` firing, focus staying
  trapped on the dialog under Tab traversal, and no overflow at 3.0x
  Dynamic Type.

### E2E Tests (composition-root, `test/main_test.dart`)

- [x] `test/main_test.dart` — **extended**, new "Story 1.5" group: the
  overlay appearing over the still-mounted authenticated screen, a second
  `expired` emission never stacking a second dialog, "Entrar novamente"
  dismissing the overlay and routing to the biometric/PIN placeholder, and
  a later rebuild while `statusStream` is still `expired` (simulated by
  pumping the same `CerneApp` root again) not reopening an
  already-confirmed overlay.

## Coverage

- Composition-root E2E scenarios: mid-session expiry overlay ✅, no
  second overlay on a repeat event ✅, confirm-and-route ✅, no reopen on
  an unrelated rebuild ✅ (added)
- Core/unit coverage: `SessionExpiryNotifier`, the `expired` bridge's full
  I/O matrix, `ConfirmationDialog`'s accessibility/dismissal guarantees —
  all covered at the layer where coverage is cheapest and clearest.
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.5 —
  all covered. Story 1.6 is still `backlog`, so out of scope for this pass.

## Verification

- `fvm flutter test` → 223/223 passing
- `fvm flutter analyze` → 0 issues

## Next Steps

- When Story 1.6 (base navigation shell) replaces `main.dart`'s
  `MaterialApp`/`Navigator` shape with `go_router`, re-home this story's
  composition-root assertions onto whatever replaces `_CerneAppState`.
- Epic 2's real biometric/PIN re-auth flow is the first thing that will
  need to transition `SessionStatus` back out of `expired` — extend this
  story's bridge coverage there rather than re-deriving it (tracked in
  `deferred-work.md`).

---

# QA Verification Pass (2026-11-02)

## Context

Re-ran this skill against the current working tree (sprint status still
shows 1.1–1.5 `done`, 1.6 `backlog`). Before generating anything, checked
for gaps: every `lib/` file has a corresponding test at the appropriate
layer (unit for pure logic, widget for shared components, composition-root
in `test/main_test.dart` for the E2E-equivalent flows), including the files
not yet reflected in this document's own history —
`lib/core/widgets/confirmation_dialog.dart`'s later review-round additions
(the synchronous-`showGeneralDialog`-throw guard, the Tab-traversal
focus-trap test) and the shared `test/support/mock_session_expiry_notifier.dart`
helper (replacing the two duplicate inline mocks per story-1-5's own review
finding).

## Result

No new API or E2E test was generated — no gap was found. The full suite
passes (**229/229**, up from the 223 recorded in this file's last pass,
reflecting review-round test additions landed since) and
`fvm flutter analyze` reports **0 issues**. Story 1.6+ is still `backlog`
(`lib/` has no navigation-shell code to test yet), so out of scope.

## Verification

- `fvm flutter pub get` — resolved, no conflicts
- `fvm flutter test` → 229/229 passing
- `fvm flutter analyze` → 0 issues

## Next Steps

- Re-run this pass once Story 1.6 lands — it's the next story expected to
  add a composition-root surface worth the same E2E-equivalent proof this
  file's login/signup/session-expiry sections already establish.

---

# Story 1.6 — Base Navigation Shell with Feature Placeholders

## Context

Story 1.6 replaces `main.dart`'s ad hoc `StreamBuilder`/`Navigator` shell
with the pinned `go_router`, adds the side-menu `Drawer` (the sole
navigation hub), five placeholder screens (including the static Planos de
Ação kanban), and the `SessionRepository.markAuthenticated()` fix that
keeps a fresh login's redirect correct. This is the first story with real
app-shell UI, so it is also the first to lock portrait-only orientation
(deferred from Story 1.1).

This section was missing from a prior pass of this document (the "QA
Verification Pass (2026-11-02)" entry above still says "Story 1.6+ is
still backlog... out of scope", which went stale the moment this story's
diff actually landed in the same commit) — added here during code review
rather than when the story itself was implemented.

## Generated Tests

### Unit (new core/feature code)

- [x] `test/core/navigation/app_router_test.dart` — **new**: the full
  redirect matrix (boot/auth/authenticated/expired transitions, the
  `/reauth`-while-`expired` case, and — post-review — the
  `/reauth`-while-`authenticated` bounce-home case), zero-broken-links
  across all seven routes.
- [x] `test/core/navigation/expiry_overlay_host_test.dart` — **new**: the
  go_router-based rework of Story 1.5's overlay wiring, including the
  not-yet-mounted-`Navigator` regression case.
- [x] `test/core/widgets/app_drawer_test.dart` — **new**: nav-item taps,
  "Novo Chat" no-op, generic header identity.
- [x] `test/core/navigation/placeholder_screens_test.dart` — **new**: all
  five placeholder screens, including the kanban's static rendering and
  the drawer-scrim token wiring.
- [x] `test/core/design_tokens_test.dart` — **extended**: every new
  Story 1.6 token (drawer, nav header, kanban) individually asserted.
- [x] `test/features/auth/data/repositories/session_repository_impl_test.dart`
  / `test/features/auth/presentation/cubit/auth_cubit_test.dart` —
  **extended**: `currentStatus`/`markAuthenticated()`, and
  `AuthCubit.submit()` calling `markAuthenticated()` on success only.

### E2E Tests (composition-root, `test/main_test.dart`)

- [x] `test/main_test.dart` — **rewritten** for `MaterialApp.router`: boot
  → auth → home, and the Story 1.5 overlay/confirm/re-route flow, now
  go_router-based.
- [x] `test/main_test.dart` — **new** (code review): tapping "Entrar
  novamente" twice in quick succession, before the dialog's exit fade
  settles, does not throw and routes to `/reauth` only once — regression
  test for the `_reauthRouteRequested` guard that had none.

## Coverage

- Composition-root E2E scenarios: boot→auth→home ✅, mid-session expiry
  overlay (go_router-based) ✅, confirm-and-route ✅, double-tap-safe
  confirm ✅ (added)
- Core/unit coverage: full redirect matrix including the post-review
  `/reauth`-while-`authenticated` guard, drawer nav, all five placeholder
  screens, every new design token.
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.6 —
  all covered.

## Verification

- `fvm flutter pub get` — resolved, no conflicts
- `fvm flutter test` → 264/264 passing
- `fvm flutter analyze` → 0 issues

## Next Steps

- Epic 2's real biometric/PIN re-auth flow is the next thing to transition
  `SessionStatus` back out of `expired` — re-home the overlay's one-shot
  guards' coverage there once that path exists (tracked in
  `deferred-work.md`).

---

# Story 2.1 — Biometric/PIN App-Access Gate

## Context

Story 2.1 adds the AD-14 seam: `VaultRepository`/`VaultRepositoryImpl`
(zero network calls, `local_auth` only, `biometricOnly: true`), the new
`VaultStatus` entity, `VaultLockScreen` at `/vault`, and `app_router.dart`
composing `VaultStatus` ahead of `SessionStatus` in `_redirect`. Before
generating anything, checked for gaps across the whole implemented
surface: `VaultRepositoryImpl` already had full unit coverage
(`vault_repository_impl_test.dart`, the complete success/decline/
exception/dispose matrix) and `app_router_test.dart` already proved the
*routing* consequences of `VaultStatus` end-to-end (locked overrides an
authenticated session, bounces any explicit navigation back to `/vault`,
unlock routes through to Home). The one gap: `VaultLockScreen` itself —
the epic's only new screen — had no widget test at all, so its own
user-visible behavior (the auto-prompt-on-mount, the pending-vs-settled
UI, and the decline → "Tentar novamente" → retry loop) was proved only
indirectly, through the router/composition-root suites.

## Generated Tests

### E2E/widget (new screen, isolated from routing)

- [x] `test/features/vault/presentation/screens/vault_lock_screen_test.dart`
  — **new**: mounts and auto-triggers `authenticate()` exactly once with
  no user interaction; while the call is still pending (held open via a
  `Completer`-gated fake) the lock copy is shown and no retry button is
  offered; a success on mount shows no retry button and flips
  `currentStatus` to `unlocked` with no exception; a decline on mount
  shows "Tentar novamente" and keeps the vault `locked`; tapping "Tentar
  novamente" re-invokes `authenticate()` and a subsequent success hides
  the button again; repeated declines keep the button available and keep
  incrementing the call count on every tap.

No API test was generated — `VaultRepository` makes zero network calls by
design (Boundaries: "Vault makes zero network calls"), so there is no
backend contract surface for this story to exercise.

## Coverage

- Widget-level E2E scenarios for `VaultLockScreen`: auto-prompt-on-mount
  ✅, pending-state UI ✅, decline→retry→success loop ✅, repeated-decline
  loop ✅ (all added)
- Already covered elsewhere (unchanged by this pass): `VaultRepositoryImpl`
  I/O matrix (`vault_repository_impl_test.dart`), `VaultStatus`-ahead-of-
  `SessionStatus` routing (`app_router_test.dart`), full composition-root
  proof of the cold-start-locked → retry → unlock → Home flow through the
  real `main.dart` wiring (`test/main_test.dart`'s "AD-14" group).
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.6
  and 2.1 — all covered. Stories 2.2+ are still `backlog`, so out of scope
  for this pass.

## Verification

- `fvm flutter test` → 284/284 passing (278 pre-existing + 6 new)
- `fvm flutter analyze` → 0 issues

## Next Steps

- Story 2.2 (biometric-failure fallback to PIN) will add PIN-entry UI to
  this same screen — extend `vault_lock_screen_test.dart` in place rather
  than starting a parallel suite, since the fake repository and `_wrap`
  helper here already generalize to that case.
- **Superseded by Story 2.2** (see below): the "Tentar novamente"-based
  cases this section describes (decline → retry → success loop,
  repeated-decline loop) no longer exist — Story 2.2 replaced the retry
  button with a PIN keypad entirely, per spec-2-2's own frozen intent, and
  rewrote this suite's cases accordingly rather than keeping both paths.
  This section is left as-is as the historical record of what Story 2.1's
  own test-generation pass produced at the time.

---

# Story 2.2 — Biometric-Failure Fallback to PIN

## Context

Story 2.2 replaces `VaultLockScreen`'s "Tentar novamente" biometric-retry
button with a real `PinKeypad` fallback: every `authenticate()` failure
(decline/cancel/any OS lockout — no code-specific branch) now falls
through to the keypad, a new "Usar PIN" link reaches it directly, and
`VaultRepository.submitPin` implements set-on-first-use/compare PIN
semantics. The code-review pass on this diff also fixed a dropped-input
risk, a hang-induced dead end, a test-naming overclaim, and a verification
gap around screen-reader announcements — see "Generated Tests" below for
what was added for those findings specifically.

## Generated Tests

### Unit (`VaultRepositoryImpl`)

- [x] `test/features/vault/data/repositories/vault_repository_impl_test.dart`
  — **extended**: `submitPin`'s full I/O matrix (no-PIN-yet stores and
  unlocks, match unlocks, mismatch stays locked with no attempt cap,
  storage-exception fails closed); `authenticate()`'s generic
  (non-`LocalAuthException`) catch branch; a real `LocalAuthException`
  with `LocalAuthExceptionCode.biometricLockout` proving the lockout code
  routes through the exact same generic catch as any other code (review
  finding: closes the gap where only `userCanceled`/`noBiometricsEnrolled`
  were exercised).

### Widget (`PinKeypad`, new)

- [x] `test/features/vault/presentation/widgets/pin_keypad_test.dart` —
  **new**: digit entry/backspace/auto-advance/no-overflow at the largest
  `TextScaler`; backspace-during-the-350ms-auto-advance-window regression
  (cancels the pending submit instead of racing it).

### E2E/widget (`VaultLockScreen`)

- [x] `test/features/vault/presentation/screens/vault_lock_screen_test.dart`
  — **rewritten**: the obsolete retry-button cases are gone, replaced
  with: biometric failure → PIN keypad + error band, never a retry
  affordance; an OS-lockout-flavored failure (a distinct `Failure.
  message`) routes identically, proving the "no code-specific branch"
  claim instead of asserting it only by comment (review finding — the
  original test reused the plain-decline fake under a misleading name);
  "Usar PIN" reachable pre-failure, including when a still-pending
  `authenticate()` later fails without clobbering the keypad; the full
  `submitPin` flow (first-use store, match, mismatch-with-retry, re-
  entrancy guard against a fast second entry).
  — **added by the code-review pass**: a dedicated group mocking
  `SystemChannels.accessibility` directly to assert the real announcement
  *content* fires on biometric failure and on PIN mismatch, and that
  tapping "Usar PIN" pre-failure sends none at all (review finding — every
  pre-existing assertion only read visible `Text` widgets, so a deleted or
  inverted `_announce()` call would have passed every test unnoticed).

## Coverage

- `submitPin` I/O matrix ✅, PIN keypad entry/backspace/auto-advance/
  Dynamic-Type ✅, biometric-failure→keypad fallthrough (plain decline and
  lockout-flavored) ✅, "Usar PIN" direct path ✅, re-entrancy guard ✅,
  screen-reader announcement content for both real transitions ✅ (all
  added or extended this pass)
- Already covered elsewhere (unchanged by this pass): `VaultStatus`-ahead-
  of-`SessionStatus` routing (`app_router_test.dart`), cold-start
  composition-root wiring (`test/main_test.dart`) — both only needed a
  `submitPin` override added to their existing fakes for the interface
  change.
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.6,
  2.1, and 2.2 — all covered. Stories 2.3+ are still `backlog`, so out of
  scope for this pass.

## Verification

- `fvm flutter test` → all passing (pre-existing suite + this pass's new/
  extended cases)
- `fvm flutter analyze` → 0 issues

## Next Steps

- Story 2.3 (fixed 5-minute idle re-authentication timeout) is the next
  consumer of this same lock-screen surface — no new gap identified here
  for it to inherit.

---

# QA Generate E2E Tests Pass (2026-11-03)

## Context

Re-ran this skill against the current working tree. Found the working
tree already had an uncommitted code-review round on top of Story 2.2
(`vault_lock_screen.dart`, `pin_keypad.dart`) that this file's own Story
2.2 section above doesn't mention: a 10-second `.timeout()` bound on
`VaultRepository.submitPin()` (so a hung secure-storage call can't leave
`_submittingPin` stuck `true` forever) and a new `PinKeypad.enabled` flag
that the screen wires as `enabled: !_submittingPin`, so a fast second PIN
entry is rejected by the keypad itself rather than only by the screen's
own re-entrancy guard. The test files for both had already been edited in
the same uncommitted change (a lockout-code case and the screen-reader
announcement group), but neither the timeout path nor the `enabled` flag
itself had any coverage anywhere in the suite — confirmed by reading
`pin_keypad_test.dart` (no mention of `enabled`) and
`vault_lock_screen_test.dart` (the existing re-entrancy test only proves
the call count stays flat, which the screen-level guard alone would also
produce, so it can't distinguish "keypad disabled" from "keypad enabled
but guarded upstream").

## Generated Tests

### Unit (`PinKeypad`, new `enabled` flag)

- [x] `test/features/vault/presentation/widgets/pin_keypad_test.dart` —
  **new** `enabled: false` group: digit taps and backspace are both
  no-ops (no `onSubmit`, no exception) while disabled; digits ignored
  while disabled aren't silently queued in the buffer — toggling back to
  `enabled: true` on the same `State` (same `Key`) and entering a fresh 4
  digits submits only the new PIN, never a stale mix of the ignored ones.

### E2E/widget (`VaultLockScreen`)

- [x] `test/features/vault/presentation/screens/vault_lock_screen_test.dart`
  — **extended** the existing re-entrancy test with a direct
  `tester.widget<PinKeypad>(...).enabled` assertion (`isFalse` while
  `submitPin()` is gated open), closing the gap where the call-count-only
  assertion couldn't tell the keypad-level guard from the screen-level one.
  — **new** group "submitPin() timeout": a `submitPin()` held open past
  the 10s bound shows the timeout message, keeps the vault `locked`, and
  — critically — resets `_submittingPin`/re-enables the keypad so a fresh
  entry is accepted afterward even though the original call is still
  hung (proves the review finding's actual guarantee, not just that the
  message appears).
  — **new** case in the "AC3 — screen-reader announcements" group: the
  timeout path sends its message as a real `SystemChannels.accessibility`
  announcement, same proof-by-real-channel standard as the file's
  existing biometric-failure/PIN-mismatch cases.

No API test was generated — `VaultRepository` still makes zero network
calls (unchanged boundary from Story 2.1/2.2).

## Coverage

- `PinKeypad.enabled` semantics (digit/backspace no-ops, no queued input)
  ✅ (added)
- `VaultLockScreen` ↔ `PinKeypad` `enabled` wiring, checked directly
  rather than inferred ✅ (added)
- `submitPin()` 10s timeout: message, retryability, re-enabled keypad,
  screen-reader announcement ✅ (all added)
- Everything else already covered by prior passes (`VaultRepositoryImpl`
  I/O matrix, biometric-failure→keypad fallthrough, "Usar PIN" direct
  path, PIN mismatch/match, routing) — unchanged by this pass.
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.6,
  2.1, and 2.2 — all covered, including this pass's uncommitted
  review-round diff. Stories 2.3+ are still `backlog`.

## Verification

- `fvm flutter test` → 309/309 passing
- `fvm flutter analyze` → 0 issues

## Next Steps

- When Story 2.2's uncommitted changes land in a commit, this section's
  findings should be folded into that story's own record rather than kept
  as a separate dated pass, to avoid the same "section missing from a
  prior pass" drift the Story 1.6 section above already called out once.
- Superseded by Story 2.3 below: Story 2.2's uncommitted changes landed in
  commit `81d7509`, bundled alongside Story 2.3's own idle-timeout work
  (code review finding — see spec-2-3's own Review Findings and Spec
  Change Log). Story 2.3 is no longer "next" — it's covered in its own
  section immediately below.

---

# Story 2.3 — Fixed 5-Minute Idle Re-Authentication Timeout

## Context

Story 2.3 adds idle-based re-authentication: `VaultRepositoryImpl` observes
app-lifecycle transitions directly (`WidgetsBindingObserver`), records a
timestamp on `AppLifecycleState.paused`, and on `resumed` re-emits
`VaultStatus.locked` if `vaultIdleTimeout` (a fixed 5-minute,
domain-owned constant) has elapsed while the vault was `unlocked`. The
code-review pass on this diff fixed six issues found in that logic and
its neighbors (including two in the Story 2.2 surfaces bundled into this
same commit — see spec-2-3's own Review Findings) — see "Generated
Tests" below for what was added for each.

## Generated Tests

### Unit (`VaultRepositoryImpl`)

- [x] `test/features/vault/data/repositories/vault_repository_impl_test.dart`
  — **new** `didChangeAppLifecycleState() — idle re-authentication
  (spec-2-3)` group: all four frozen I/O-matrix rows (backgrounded < 5min
  stays unlocked, >= 5min re-locks, already-locked has no duplicate
  emission, bare `resumed` with no prior `paused` no-ops) via an
  injectable fake clock; a real `WidgetsBinding`-dispatched case proving
  the constructor's `addObserver(this)` wiring is actually in effect;
  `inactive`/`hidden` confirmed as no-ops; a tight boundary case one
  second short of the threshold.
  — **added by the code-review pass**: a case proving a mid-background
  unlock (e.g. a persisted biometric call resolving while still `paused`)
  resets the idle clock rather than immediately re-locking on the next
  `resume`; a case proving a second `paused` before any `resumed` keeps
  the earliest timestamp instead of resetting it; a case proving a
  superseded (stale) `submitPin` call — one whose UI-level timeout already
  fired and was retried — never mutates storage or emits `unlocked`.

### Widget (`PinKeypad`, `VaultLockScreen`)

- [x] `test/features/vault/presentation/widgets/pin_keypad_test.dart` —
  **added by the code-review pass**: a case proving `enabled: false`
  buttons report `Semantics(enabled: false)` and are visually dimmed
  (`Opacity`), and report `enabled: true`/full opacity again once
  re-enabled — closes the gap where the `enabled` flag (added in Story
  2.2's review pass) had no visual or semantic cue at all.
- [x] `test/features/vault/presentation/screens/vault_lock_screen_test.dart`
  — **added by the code-review pass**: a case proving a fresh PIN
  attempt immediately clears the previous mismatch error, rather than
  leaving it on screen unchanged through the new attempt.

## Coverage

- Idle re-lock I/O matrix (all four frozen rows) ✅, real-dispatch wiring
  proof ✅, `inactive`/`hidden` no-op ✅, tight threshold boundary ✅ (all
  from the story's own implementation pass)
- Mid-background unlock resets the idle clock ✅, double-`paused` keeps
  the earliest timestamp ✅, superseded `submitPin` call is a safe no-op
  ✅, `PinKeypad.enabled` has a visual/semantic disabled cue ✅, stale
  error message is cleared on a fresh attempt ✅ (all added by the
  code-review pass)
- Implemented feature scope (per `sprint-status.yaml`): stories 1.1–1.6,
  2.1, 2.2, and 2.3 — all covered.

## Verification

- `fvm flutter test` → all passing (pre-existing suite + this pass's new
  idle-timeout and code-review cases)
- `fvm flutter analyze` → 0 issues

## Next Steps

- Story 2.4 (biometric preference persistence) is the next `backlog`
  story in Epic 2.

---

# QA Verification Pass (2026-11-03, second)

## Context

Re-ran this skill against the current working tree. The working tree
still carries the uncommitted Story 2.3 code-review round described in
this file's own section immediately above (the `addObserver` →
`StateError` guard, `_backgroundedAt` reset-on-unlock, `??=` on `paused`,
the `submitPin` generation counter, `_errorMessage` cleared on a fresh
attempt, `PinKeypad`'s `Opacity`/`Semantics.enabled` treatment) — verified
by diff that every one of those changes has a matching test already in
place (`vault_repository_impl_test.dart`'s "superseded (stale) call",
"resets the idle clock", earliest-timestamp-kept cases;
`vault_lock_screen_test.dart`'s stale-error-cleared and timeout groups;
`pin_keypad_test.dart`'s `enabled: false` opacity/semantics case).

The one new-code path with no test, and left that way: the constructor's
`try`/`on FlutterError catch` around `WidgetsBinding.instance.addObserver(this)`
that rethrows as a named `StateError`. `TestWidgetsFlutterBinding
.ensureInitialized()` runs once per test process and a real binding is
already live by the time any test's `VaultRepositoryImpl` is constructed,
so there is no way to reach the `catch` branch from this suite — forcing
it would require faking the static `WidgetsBinding.instance` getter
itself, not a seam this codebase exposes. Treated as an unreachable-in-test
defensive guard (same category as other framework-guarantee checks this
project doesn't add tests for), not a gap.

## Result

No new API or E2E test was generated — no reachable gap was found.

## Verification

- `fvm flutter pub get` — resolved, no conflicts
- `fvm flutter test` → 321/321 passing
- `fvm flutter analyze` → 0 issues

## Next Steps

- Commit the Story 2.3 code-review round (currently uncommitted) so its
  test coverage stops being re-verified every pass.
- Story 2.4 (biometric preference persistence) is the next `backlog`
  story in Epic 2.

---

# QA Verification Pass (2026-11-04) — Story 3.2 Audio Entry Capture

## Context

Re-ran this skill against the current working tree, now carrying Stories
2.4 (biometric preference persistence), 3.1 (text entry capture), and 3.2
(audio entry capture & on-device transcription) — all `done` per
`sprint-status.yaml`. Checked each for a composition-root/pipeline
E2E-equivalent gap, this project's substitute for a real
`integration_test` (no device/CI yet — AGENTS.md):

- Story 2.4 — already covered: `test/main_test.dart`'s "Story 2.4 —
  AccountSettingsRepository feeds VaultLockScreen through the real
  composition root" group drives the real wiring for both the
  `currentBiometricEnabled: false` and boot-fetch-failure rows.
- Story 3.1 — already covered: `capture_flow_e2e_test.dart` drives the
  real, DI-resolved `TextEntryCubit` through the real
  `EntriesRepositoryImpl` → `ApiClient` → `Dio` (both interceptors) → a
  real `entries` Hive box, with only the transport boundary and native
  plugins (secure storage, path_provider) faked. Happy path + the
  non-retryable-failure path both covered.
- Story 3.2 — **gap found**: no equivalent existed for `AudioEntryCubit`.
  `audio_entry_cubit_test.dart` already covers every state transition
  (recording, permission, transcription, retry) against mocked
  `MicRecorder`/`AudioTranscriber`/`EntriesRepository`, and that same
  file's own doc comment records a deliberate boundary — "no automated
  test exercises the real `record`/`whisper_ggml` native plugins" — so
  the gap is specifically the real-network + real-Hive save() leg that
  `capture_flow_e2e_test.dart` already proves for the Texto tab but
  nothing proved for the Áudio tab.

## Generated Tests

### E2E (composition-root/pipeline, `test/features/capture/`)

- [x] `test/features/capture/audio_entry_flow_e2e_test.dart` — **new**,
  mirrors `capture_flow_e2e_test.dart`'s structure exactly. Drives the
  real, DI-resolved `AudioEntryCubit` through `startRecording()` →
  `stopRecording()` → `save()` against the real `EntriesRepositoryImpl` →
  `ApiClient` → `Dio` (both real interceptors) → a real `entries` Hive
  box. Three things are faked: the transport boundary
  (`HttpClientAdapter`), the native plugins (secure storage,
  path_provider), and — honoring the "Never" boundary above —
  `MicRecorder`/`AudioTranscriber` themselves, swapped into the real `sl`
  container *before* `AudioEntryCubit` is first resolved, so the real
  `record`/`whisper_ggml` singletons `registerCaptureFeature()` would
  otherwise build are never instantiated.
  - Happy path: POST to `entries-create` carries `source: audio` +
    `mediaDurationSeconds` with the right URL/headers/body, `AudioSaved`
    is emitted, the entry lands in the real Hive box, and the temp
    recording file is deleted (best-effort cleanup on success).
  - Failure path: a non-retryable `VALIDATION_ERROR` surfaces as
    `AudioError` carrying `Failure.message` verbatim, exactly one request
    fires (no retry), nothing is written to the Hive box, and the
    recording file is preserved (for a retried Salvar).

## Coverage

- Composition-root/pipeline E2E-equivalent scenarios: Texto save (happy +
  failure) ✅ pre-existing, **Áudio save (happy + failure) ✅ added**,
  account-settings-fed vault boot (both rows) ✅ pre-existing.
- Implemented feature scope (per `sprint-status.yaml`): epics 1–2 (all
  stories) and epic 3's done stories (3.1, 3.2) — all covered at this
  layer. 3.3 (photo capture) and 3.4 (cancel-safe capture) are still
  `backlog`, out of scope for this pass.

## Verification

- `fvm flutter test` → 473/473 passing (471 pre-existing + 2 new)
- `fvm flutter analyze` → 0 issues

## Next Steps

- Story 3.3 (photo entry capture, backend OCR) and 3.4 (cancel-safe
  capture across all tabs) are the next `backlog` stories in Epic 3 —
  each will need its own composition-root/pipeline E2E-equivalent pass
  once implemented.
