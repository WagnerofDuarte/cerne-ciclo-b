---
title: 'Story 1.6: Base Navigation Shell with Feature Placeholders'
type: 'feature'
created: '2026-11-02'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'b9870eb4f6e85d84aeb3f03125a2be7d91ffc5d6'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/docs/input/prototype/prototype-extract.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Today `main.dart` hardcodes a single `MaterialApp(home: StreamBuilder(...))` with three throwaway screens — no real navigation exists, and none of the four base destinations (Home/Chat, side menu, Meus Registros, Configurações) or the extension-feature entry (Planos de Ação) do either.

**Approach:** Introduce the pinned `go_router` with one top-level `redirect` keyed off `SessionStatus` (AD-8), leaving the documented seam for RF03's `VaultStatus` (AD-14). Build the side-menu `Drawer` (the sole navigation hub) and five polished placeholder screens. Also lock portrait orientation (deferred from Story 1.1 — this is the first story with real app-shell UI).

## Boundaries & Constraints

**Always:**
- Exactly one `GoRouter`/`redirect`; it composes only `SessionStatus` for now — leave an explicit code-comment seam where RF03 plugs `VaultStatus` in first (AD-14), never a second competing `redirect`.
- Routes: `/boot`, `/auth`, `/reauth` (Story 1.5's target), `/` (Home/Chat + drawer), `/meus-registros`, `/planos-de-acao`, `/configuracoes`. The three non-Home destinations' back-arrow always targets `/` (matches prototype's `goHome` on all three) — no drawer-within-drawer.
- Story 1.5's overlay boundaries are unchanged: expiry never navigates away, screen state is preserved, one-shot-per-episode, "Entrar novamente" still ends at the same throwaway placeholder (now at `/reauth`).
- New `SessionRepository.markAuthenticated()` is called by `AuthCubit.submit()`'s success branch *before* emitting success, so the router's redirect already sees `authenticated` by the time `onAuthenticated` navigates to `/` — without this, a fresh login would redirect straight back to `/auth` on the very first post-login navigation.
- Drawer header uses a generic (non-personalized) `Avatar` + static label — deferred-work.md records why real identity isn't wired up yet.
- Planos de Ação renders the prototype's static 3-column kanban with its exact hardcoded example cards — zero backend calls, zero drag/drop (AGENTS.md: extension features stay non-functional).
- Every new color/size literal goes in `design_tokens.dart` (RNF08): heavier drawer scrim `rgba(36,31,25,.4)`, drawer width, kanban spacing/sizing.
- Native Flutter `Drawer`/`Scaffold.drawer` for the side menu (not a hand-rolled overlay like `ConfirmationDialog`) — single low-stakes use, avoids a second bespoke overlay mechanism.
- Lock portrait-only orientation in `ios/Runner/Info.plist` (deferred-work.md, from Story 1.1) — no landscape path anywhere (epic UX constraint).

**Ask First:** if hitting correct synchronous `redirect` re-evaluation on each `statusStream` emission seems to need any package beyond the already-pinned `go_router` (e.g. a different state-management dependency), stop and ask before adding one.

**Never:**
- No `CONVERSAS`/past-chat-session list in the drawer and no real chat (RF04/RF07 not built) — only the static "Novo Chat" action (closes the drawer, no-op) and the three nav items.
- No vault/biometric logic added to the redirect (RF03/Epic 2's job) — leave the seam, don't hardcode a session-only assumption.
- No persisted/real user identity in the drawer (deferred-work.md), no editable profile name/avatar-upload (Epic 8).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boot, status not yet known | app launch | `/boot` splash (unchanged >300ms-threshold spinner) | N/A |
| Boot, unauthenticated | no/dead stored session | redirected to `/auth` | silent |
| Boot, authenticated/expired | valid stored session | redirected to `/` | silent |
| Fresh login/signup success | `AuthCubit.submit()` resolves `right` | `markAuthenticated()` emits `authenticated`, then `/` | N/A |
| Mid-session expiry, any of the 5 routes | `AUTH_EXPIRED` | overlay over current route, route unchanged (Story 1.5 behavior) | silent |
| Tap a drawer nav item | drawer open | navigates to that route; back-arrow returns to `/` | N/A |
| Tap "Novo Chat" | drawer open | drawer closes, stays on `/` | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/auth/domain/repositories/session_repository.dart` -- add `SessionStatus? get currentStatus` and `void markAuthenticated()`.
- `lib/features/auth/data/repositories/session_repository_impl.dart:63-167` -- expose `_lastStatus` via `currentStatus`; `markAuthenticated()` calls `_emit(SessionStatus.authenticated)` directly (no network/storage — tokens are already persisted by `AuthRepositoryImpl` by this point).
- `lib/features/auth/presentation/cubit/auth_cubit.dart` -- new constructor dep `SessionRepository`; `submit()`'s success branch calls `markAuthenticated()` before emitting `ResourceData` (AD-1: presentation→domain, same feature — not a BLoC-to-BLoC reference, AD-7).
- `lib/features/auth/auth_injection.dart` -- wire `sl<SessionRepository>()` into `AuthCubit`'s registration.
- `lib/core/navigation/app_router.dart` -- new: the one `GoRouter`; a private `ChangeNotifier` wraps `statusStream` as `refreshListenable` (no `GoRouterRefreshStream` export in pinned go_router 18.1.1 — write a small local class); `redirect` reads `currentStatus` synchronously per the matrix above.
- `lib/core/navigation/expiry_overlay_host.dart` -- new: `MaterialApp.router`'s `builder:`; same one-shot guard/`ConfirmationDialog` call as `main.dart` today (spec-1-5), confirm now does `context.go('/reauth')`.
- `lib/core/widgets/app_drawer.dart` -- new: header = generic `Avatar` (reuse, `lib/core/widgets/avatar.dart`) + static label (no real identity — see Boundaries); "Novo Chat" + 3 nav items (`context.go(...)`).
- `lib/core/navigation/placeholder_screens.dart` -- new: `BootSplashScreen` (moved from `main.dart`'s `_BootLoadingScreen`), `HomeChatPlaceholderScreen` (☰ opens `AppDrawer`, dark-green header), `BiometricReauthPlaceholderScreen` (moved from `_BiometricReauthPlaceholder`), `MeusRegistrosPlaceholderScreen`/`ConfiguracoesPlaceholderScreen` (shared back-arrow-header placeholder body), `ActionPlansPlaceholderScreen` (static kanban).
- `lib/main.dart` -- `_CerneAppState` keeps the boot `restoreSession()` call; `build()` returns `MaterialApp.router(routerConfig: ..., builder: ...)`; delete the moved classes/StreamBuilder logic.
- `lib/core/design_tokens.dart` -- add `colorScrimHeavy` (`0x66241F19`, `rgba(36,31,25,.4)` per `cerne-prototype.html`'s `OVERLAY: Drawer` block), `drawerWidth` (312 = 80% of the fixed 390 frame), kanban constants (column gap/min-width, card padding, spine width, dot size) per the same file's `Tela 5 — Planos de Ação` block.
- `ios/Runner/Info.plist` -- portrait-only orientation keys (deferred-work.md item from Story 1.1).
- Ground truth: `docs/input/prototype/cerne-prototype.html`'s `<!-- OVERLAY: Drawer -->` and `<!-- Tela 5 — Planos de Ação -->` blocks; headers in the `Tela 1/4/6` blocks; `prototype-extract.md` §1-2.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/auth/domain/repositories/session_repository.dart` + impl -- `currentStatus`/`markAuthenticated()` -- sync redirect after login
- [x] `lib/features/auth/presentation/cubit/auth_cubit.dart` + `auth_injection.dart` -- call `markAuthenticated()` pre-success
- [x] `lib/core/navigation/app_router.dart` -- GoRouter + redirect + refresh-listenable
- [x] `lib/core/navigation/expiry_overlay_host.dart` -- moved overlay wiring, now go_router-based
- [x] `lib/core/widgets/app_drawer.dart` -- side menu, generic header
- [x] `lib/core/navigation/placeholder_screens.dart` -- 5 screens (boot, home, reauth, meus-registros/configurações, planos-de-ação)
- [x] `lib/main.dart` -- switch to `MaterialApp.router`
- [x] `lib/core/design_tokens.dart` -- new tokens
- [x] `ios/Runner/Info.plist` -- portrait lock
- [x] Test files listed in Verification -- redirect matrix, drawer, placeholders, updated `main_test.dart`

**Acceptance Criteria:**
- Given a fresh install, when the app launches, then all four destinations are reachable with zero broken links or crashes.
- Given `fvm flutter analyze`, when run after this change, then zero issues and no hardcoded `Color(0x`/`EdgeInsets.*` literal outside `design_tokens.dart`.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves, no conflicts
- `fvm flutter test` -- all tests pass, including new/extended: `test/features/auth/data/repositories/session_repository_impl_test.dart`, `test/features/auth/presentation/cubit/auth_cubit_test.dart`, `test/core/navigation/app_router_test.dart` (new), `test/core/widgets/app_drawer_test.dart` (new), `test/core/navigation/placeholder_screens_test.dart` (new), `test/main_test.dart` (rewritten), `test/core/design_tokens_test.dart`
- `fvm flutter analyze` -- zero issues
- `grep -rn "Color(0x\|fontSize:\|EdgeInsets\.\(all\|symmetric\|only\)(" lib/core/navigation lib/core/widgets/app_drawer.dart lib/main.dart --include=*.dart` -- expected: no matches outside `design_tokens.dart`

## Suggested Review Order

**The redirect skeleton (AD-8/AD-14 seam)**

- Entry point: composes only `SessionStatus` for now, with the AD-14 comment seam for Epic 2's `VaultStatus` check.
  [`app_router.dart:97`](../../lib/core/navigation/app_router.dart#L97)

- Builds the one `GoRouter`, now taking an explicit `navigatorKey` (post-review patch) instead of reaching into go_router's internals elsewhere.
  [`app_router.dart:38`](../../lib/core/navigation/app_router.dart#L38)

- Local `ChangeNotifier` re-runs `redirect` on every `statusStream` emission — go_router 18.1.1 ships no built-in equivalent.
  [`app_router.dart:120`](../../lib/core/navigation/app_router.dart#L120)

**Session/auth plumbing — making a fresh login redirect correctly**

- The new synchronous accessor the redirect reads directly, and the method that flips it without a network/storage round trip.
  [`session_repository.dart:23`](../../lib/features/auth/domain/repositories/session_repository.dart#L23)

- Implementation: `currentStatus` mirrors `_lastStatus`; `markAuthenticated()` is a pure in-memory `_emit`.
  [`session_repository_impl.dart:63`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L63)

- `AuthCubit.submit()` calls `markAuthenticated()` *before* emitting success — the ordering the redirect-correctness fix depends on.
  [`auth_cubit.dart:137`](../../lib/features/auth/presentation/cubit/auth_cubit.dart#L137)

- DI: `AuthCubit` now also takes `SessionRepository`.
  [`auth_injection.dart:47`](../../lib/features/auth/auth_injection.dart#L47)

**Expired-session overlay, reworked for go_router (Story 1.5 behavior preserved)**

- Reads a context below the `Navigator` via a directly-owned `navigatorKey` (post-review patch, not `router.routerDelegate`); one-shot guard, confirm navigates via `router.go`, never `context.go`.
  [`expiry_overlay_host.dart:84`](../../lib/core/navigation/expiry_overlay_host.dart#L84)

**Side menu**

- Native `Drawer`, generic avatar/label header, no `SafeArea` (post-review patch — the fixed `drawerContentPadding` top value already clears it, matching every other header).
  [`app_drawer.dart:17`](../../lib/core/widgets/app_drawer.dart#L17)

- "Novo Chat" is a deliberate no-op (closes the drawer, stays on `/`) — no real chat yet.
  [`app_drawer.dart:55`](../../lib/core/widgets/app_drawer.dart#L55)

**Placeholder screens**

- Home/Chat: the only screen with the dark-green header + drawer; body is still a polished placeholder.
  [`placeholder_screens.dart:77`](../../lib/core/navigation/placeholder_screens.dart#L77)

- Shared back-arrow header — every non-Home destination's back arrow targets `/` directly.
  [`placeholder_screens.dart:247`](../../lib/core/navigation/placeholder_screens.dart#L247)

- Planos de Ação: the prototype's exact static 3-column kanban, hardcoded example cards, zero logic.
  [`placeholder_screens.dart:194`](../../lib/core/navigation/placeholder_screens.dart#L194)

**Design tokens**

- New Story 1.6 block: drawer, nav header, and kanban constants, all derived from the prototype's markup.
  [`design_tokens.dart:242`](../../lib/core/design_tokens.dart#L242)

**Composition root**

- `MaterialApp.router` replaces the old `StreamBuilder`/`Navigator` shell; owns the shared `navigatorKey`.
  [`main.dart:103`](../../lib/main.dart#L103)

**Platform config**

- Portrait-only orientation lock (deferred-work.md item picked up here, Story 1.1).
  [`Info.plist`](../../ios/Runner/Info.plist)

**Tests**

- Full redirect matrix, including the `/reauth`-while-`expired` and zero-broken-links cases.
  [`app_router_test.dart:165`](../../test/core/navigation/app_router_test.dart#L165)

- The post-review patch's own regression test: overlay fires once a `Navigator` is actually mounted, not stuck after an early miss.
  [`expiry_overlay_host_test.dart:47`](../../test/core/navigation/expiry_overlay_host_test.dart#L47)

- `currentStatus`/`markAuthenticated` unit coverage.
  [`session_repository_impl_test.dart:195`](../../test/features/auth/data/repositories/session_repository_impl_test.dart#L195)

- `AuthCubit.submit()` calls `markAuthenticated()` on success, never on failure.
  [`auth_cubit_test.dart:184`](../../test/features/auth/presentation/cubit/auth_cubit_test.dart#L184)

- Drawer nav taps, "Novo Chat" no-op, generic identity.
  [`app_drawer_test.dart:70`](../../test/core/widgets/app_drawer_test.dart#L70)

- `drawerScrimColor` actually wired to the token (post-review patch), kanban rendering.
  [`placeholder_screens_test.dart:67`](../../test/core/navigation/placeholder_screens_test.dart#L67)

- Composition-root proof: boot→auth→home flow and the Story 1.5 overlay behavior, now go_router-based.
  [`main_test.dart:260`](../../test/main_test.dart#L260)

- Every new token's value, individually asserted.
  [`design_tokens_test.dart:209`](../../test/core/design_tokens_test.dart#L209)
