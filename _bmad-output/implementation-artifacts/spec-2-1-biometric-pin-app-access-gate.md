---
title: 'Biometric/PIN App-Access Gate'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'a2b0a109edce69fb6f111084566cedc60057dd71'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Epic 1 left every screen reachable with no device-level access barrier; Epic 2 requires Face ID/Touch ID (PIN fallback is Story 2.2) to block all screens except the vault/login screen, on cold start, before any data is shown.

**Approach:** Add a `features/vault/` module exposing a `VaultStatus` stream that mirrors `features/auth/domain`'s `SessionStatus` pattern exactly, and extend the single existing `go_router` redirect so it composes `VaultStatus` first, then `SessionStatus` (the seam is already commented in-place). A new `/vault` route shows a minimal lock screen that auto-triggers the OS biometric prompt via `local_auth` and offers a manual retry on failure — no PIN entry UI (that's Story 2.2).

## Boundaries & Constraints

**Always:** `_redirect` checks `VaultStatus` before `SessionStatus`, never a second `GoRouter`/`redirect`. Vault makes zero network calls; `authenticate()` never produces `Failure.authInvalid` (reserved for password login). `local_auth.authenticate()` is called with `biometricOnly: true` so it never silently falls back to the OS's own device passcode screen. `VaultStatus` starts `locked` at construction (not nullable — no async warm-up needed) and only a successful `authenticate()` flips it to `unlocked`.

**Ask First:** None — remaining technical choices (lock-screen copy, retry-button wording) are decided per AGENTS.md's "decide and proceed."

**Never:** No PIN entry screen, no idle-timeout re-lock, no biometric-preference persistence — Stories 2.2/2.3/2.4. Never set `biometricOnly: false` (would let the OS's own passcode bypass Cerne's intended PIN flow).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Cold start, biometrics succeed | `VaultStatus.locked`, app opened, OS prompt confirms | `authenticate()` emits `unlocked`; redirect falls through to existing `SessionStatus` logic (Home if authenticated) | N/A |
| Cold start, biometrics fail/cancelled/unavailable | `authenticate()` returns `false` or throws `LocalAuthException` | Status stays `locked`; lock screen shows retry button | `Left(Failure.malformedResponse(...))`, no crash |
| Any navigation while locked | `location != /vault`, `VaultStatus.locked` | redirect returns `/vault` | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/auth/domain/entities/session_status.dart`, `.../repositories/session_repository.dart`, `data/repositories/session_repository_impl.dart` — exact pattern to mirror (`Stream.multi` replay-to-late-listeners, `_emit`/`isClosed` guard, `dispose:` wiring).
- `lib/core/navigation/app_router.dart:17-25` (`AppRoutePaths`), `:38-81` (`buildAppRouter`), `:94-98` (seam comment already marks this exact change), `:99-123` (`_redirect`), `:129-148` (`_GoRouterRefreshStream`, currently wraps one stream).
- `lib/main.dart:48,63-67` — `_sessionRepository = sl<SessionRepository>()` call site to mirror for vault.
- `lib/core/di/injection_container.dart:79` — `registerAuthFeature()` call site; add `registerVaultFeature()` after it.
- `lib/features/auth/auth_injection.dart` — DI registration pattern (`registerLazySingleton` + `dispose:`) to mirror.
- `lib/core/failure/failure.dart:38-39` — `Failure.malformedResponse` is the only local-failure subtype to use here.
- `pubspec.yaml:49-50` — `local_auth: ^3.0.2`, `flutter_secure_storage: ^11.2.0` already present, no change.
- `~/.pub-cache/.../local_auth-3.0.2/lib/src/local_auth.dart` — current API: `authenticate()` returns `Future<bool>`, throws `LocalAuthException` (not `PlatformException`) on error.
- `ios/Runner/Info.plist` — `NSFaceIDUsageDescription` absent, must be added.
- `test/core/navigation/app_router_test.dart` — every existing case constructs `buildAppRouter(sessionRepository: ..., ...)` directly; each call site needs a second fake `VaultRepository` (default `unlocked`) added.
- `test/main_test.dart:89-97` — `setUp` calls real `setupCoreDependencies()`; since `CerneApp` will now also resolve `sl<VaultRepository>()`, swap in a fake pre-`unlocked` one here so existing auth/session cases are unaffected.

## Tasks & Acceptance

**Execution:**
- [x] `lib/features/vault/domain/entities/vault_status.dart` -- create `enum VaultStatus { locked, unlocked }` -- mirrors `SessionStatus`.
- [x] `lib/features/vault/domain/repositories/vault_repository.dart` -- create `abstract class VaultRepository` (`statusStream`, non-null `currentStatus` defaulting `locked`, `authenticate()`, `dispose()`) -- mirrors `SessionRepository` (RNF09: `Either<Failure, Unit>`).
- [x] `lib/features/vault/data/repositories/vault_repository_impl.dart` -- create `VaultRepositoryImpl(LocalAuthentication)`; `authenticate()` calls `.authenticate(localizedReason: ..., biometricOnly: true, persistAcrossBackgrounding: true)`; success emits `unlocked`+`right(unit)`; `false`/`LocalAuthException` -> `left(Failure.malformedResponse(...))`, status unchanged -- zero network, never `authInvalid`.
- [x] `lib/features/vault/vault_injection.dart` -- create `registerVaultFeature()` -- mirrors `auth_injection.dart`.
- [x] `lib/core/di/injection_container.dart` -- call `registerVaultFeature()` after `registerAuthFeature()`.
- [x] `lib/core/navigation/app_router.dart` -- add `vaultLock` path; thread `vaultRepository` through `buildAppRouter`/`_redirect`; new top branch returns `vaultLock` whenever status isn't `unlocked`; extend the existing authenticated/expired `location == boot || auth` check to also include `vaultLock`; extend `_GoRouterRefreshStream` to subscribe to both streams -- composes the two gates in fixed order (AD-14).
- [x] `lib/features/vault/presentation/screens/vault_lock_screen.dart` -- `StatefulWidget` calling `vaultRepository.authenticate()` once in `initState`, with a "Tentar novamente" retry button on failure -- no PIN UI; `DesignTokens` only.
- [x] `lib/main.dart` -- resolve `sl<VaultRepository>()`, pass into `buildAppRouter`.
- [x] `ios/Runner/Info.plist` -- add `NSFaceIDUsageDescription`.
- [x] `test/features/vault/data/repositories/vault_repository_impl_test.dart` -- unit-test the I/O matrix with a mocked `LocalAuthentication`.
- [x] `test/core/navigation/app_router_test.dart` -- add a fake `VaultRepository` (default `unlocked`) to every existing call site; add cases: locked overrides any `SessionStatus`; unlocked + authenticated at `/vault` routes home.
- [x] `test/main_test.dart` -- swap in a fake pre-unlocked `VaultRepository` in `setUp`; add one new test: cold start stays on `/vault` until a fake `authenticate()` success routes to Home.

**Acceptance Criteria:**
- Given the app is cold-started, when the vault gate evaluates, then no screen other than `/vault` is reachable until `authenticate()` succeeds.
- Given the redirect evaluates on any navigation attempt, then it composes exactly two gates in fixed order (`VaultStatus` then `SessionStatus`) and neither ever makes a network call.
- Given Face ID/Touch ID is available and the user opens the app, when the OS prompt succeeds, then the app routes to Home/Chat via the existing session logic, and `features/vault/domain` exposes `VaultStatus` registered once in DI.

### Review Findings

- [x] [Review][Patch] `authenticate()` only catches `on LocalAuthException`; any other thrown exception (e.g. a platform-channel failure) escapes the `Either` contract (RNF09) unmapped and leaves `VaultLockScreen` permanently stuck on "autenticando" with no retry option — on the one gate blocking every screen in the app. The sibling `session_repository_impl.dart` this class is documented to mirror uses a broad `catch (error)` for exactly this reason. [lib/features/vault/data/repositories/vault_repository_impl.dart:96] — fixed: added a plain `catch (error)` branch mapping to `Failure.malformedResponse`.
- [x] [Review][Patch] `test/main_test.dart`'s global `setUp()` override (`sl.registerLazySingleton<VaultRepository>(() => _FakeVaultRepository())`) omits the `dispose:` callback the real registration always wires, leaking a `StreamController` for every pre-existing test case in the file. [test/main_test.dart:147] — fixed: added the `dispose:` callback.
- [x] [Review][Patch] `Semantics(liveRegion: true, ...)` is primarily honored by Android/TalkBack; on this iOS-only app, VoiceOver may not reliably announce the lock→retry transition the epic's UX notes require. Pair it with an explicit `SemanticsService.announce()` call when `_showRetry` flips, which is honored cross-platform. [lib/features/vault/presentation/screens/vault_lock_screen.dart:75] — fixed: added a `SemanticsService.sendAnnouncement()` call (the current, non-deprecated API on this Flutter version) alongside `liveRegion`.
- [x] [Review][Defer] `authenticate()`'s single `on LocalAuthException` catch collapses every `LocalAuthExceptionCode` (including `lockedOut`/`biometryLockout`) into one generic `Failure.malformedResponse`, discarding the lockout-vs-other-failure distinction `epic-2-context.md` says Story 2.2 needs to route lockouts to the PIN fallback instead of retrying the OS. [lib/features/vault/data/repositories/vault_repository_impl.dart:96] — deferred, owned by Story 2.2
- [x] [Review][Defer] No timeout wraps the OS biometric prompt; if `authenticate()` never resolves (a hung native call not covered by `persistAcrossBackgrounding`), the lock screen stays on its initial state forever with no retry button and no escape. Outside spec-2-1's own I/O matrix (success/declined/cancelled only). [lib/features/vault/presentation/screens/vault_lock_screen.dart:43] — deferred, pre-existing risk class
- [x] [Review][Defer] `main.dart`'s `restoreSession()` fires unconditionally in `initState` regardless of `VaultStatus` (unchanged since Story 1.4), in tension with `epic-2-context.md`'s own framing that the vault gates "before any network/session state is considered." [lib/main.dart:82] — deferred, pre-existing

## Design Notes

`biometricOnly: true` is the one easy-to-miss detail: `local_auth`'s default (`false`) lets the OS's own device-passcode UI satisfy `authenticate()`, which would bypass Cerne's own PIN screen (Story 2.2) entirely — `true` forces biometrics-or-fail, matching the epic's intent that PIN is Cerne's own screen, never iOS's/Android's.

`VaultStatus.currentStatus` is deliberately non-nullable (unlike `SessionStatus?`) — the vault's "locked" state is known synchronously at construction, with no async restore step, so there's no boot-loading gap to represent with `null`.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues.
- `fvm flutter test` -- expected: all pass, including new vault tests.

**Manual checks (if no CLI):**
- No device/simulator exists yet (AGENTS.md) — the real OS biometric prompt itself is unverifiable until one does; this is a known, pre-existing gap, not introduced by this story.

## Suggested Review Order

**Redirect composition (AD-14)**

- Entry point: the vault gate is checked strictly before `SessionStatus`, returning early whenever not `unlocked`.
  [`app_router.dart:125`](../../lib/core/navigation/app_router.dart#L125)

- `vaultLock` is folded into the existing boot/auth fall-through so unlocking while still at `/vault` reaches Home.
  [`app_router.dart:149`](../../lib/core/navigation/app_router.dart#L149)

- `buildAppRouter` now requires both repositories as parameters, never reaching into `sl` itself.
  [`app_router.dart:45`](../../lib/core/navigation/app_router.dart#L45)

- New `/vault` route constant, added alongside Story 1.6's original set.
  [`app_router.dart:25`](../../lib/core/navigation/app_router.dart#L25)

**VaultRepository contract and implementation**

- The domain contract: non-nullable `currentStatus` (no boot-loading gap, unlike `SessionStatus?`), `Either<Failure, Unit>` return (RNF09).
  [`vault_repository.dart:14`](../../lib/features/vault/domain/repositories/vault_repository.dart#L14)

- `biometricOnly: true` — the one easy-to-miss detail preventing the OS's own passcode screen from silently satisfying this call.
  [`vault_repository_impl.dart:73`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L73)

- `LocalAuthException` maps to `Failure.malformedResponse`, never `authInvalid` — zero network calls anywhere in this class.
  [`vault_repository_impl.dart:96`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L96)

- `_emit` guards against `dispose()` racing an in-flight `authenticate()` call, mirroring `SessionRepositoryImpl`.
  [`vault_repository_impl.dart:59`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L59)

- `VaultStatus` is a closed 2-value enum; only Stories 2.2/2.3 may extend it.
  [`vault_status.dart:13`](../../lib/features/vault/domain/entities/vault_status.dart#L13)

**Presentation (lock screen)**

- Auto-triggers `authenticate()` once on mount; never navigates imperatively — the router's `refreshListenable` does that.
  [`vault_lock_screen.dart:29`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L29)

- `Semantics(liveRegion: true, ...)` announces the lock→retry transition to screen readers.
  [`vault_lock_screen.dart:74`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L74)

**DI wiring and composition root**

- `registerVaultFeature()` mirrors `auth_injection.dart`'s singleton + `dispose:` pattern.
  [`vault_injection.dart:11`](../../lib/features/vault/vault_injection.dart#L11)

- Called right after `registerAuthFeature()` during bootstrap.
  [`injection_container.dart:81`](../../lib/core/di/injection_container.dart#L81)

- `CerneApp` resolves `VaultRepository` and threads it into `buildAppRouter`.
  [`main.dart:66`](../../lib/main.dart#L66)

- `NSFaceIDUsageDescription` added — required by iOS for the Face ID prompt to appear at all.
  [`Info.plist:29`](../../ios/Runner/Info.plist#L29)

**Tests (peripherals)**

- Unit coverage of the full I/O matrix against a mocked `LocalAuthentication`.
  [`vault_repository_impl_test.dart:17`](../../test/features/vault/data/repositories/vault_repository_impl_test.dart#L17)

- Router-level proof that `VaultStatus.locked` overrides any `SessionStatus`, with a fake defaulting `unlocked` so Story 1.6's cases are unaffected.
  [`app_router_test.dart:233`](../../test/core/navigation/app_router_test.dart#L233)

- End-to-end through the real composition root: cold start locked, then the real retry-button wiring tapped to unlock.
  [`main_test.dart:474`](../../test/main_test.dart#L474)

- Fake `VaultRepository` swapped in globally so every pre-existing auth/session test stays unaffected by the new gate.
  [`main_test.dart:147`](../../test/main_test.dart#L147)

- Review-added: forces real `sl<VaultRepository>()` resolution so a broken DI wiring surfaces here, not only at app launch.
  [`bootstrap_integration_test.dart:104`](../../test/core/di/bootstrap_integration_test.dart#L104)
