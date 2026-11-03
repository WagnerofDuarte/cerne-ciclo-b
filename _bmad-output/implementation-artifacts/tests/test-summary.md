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
