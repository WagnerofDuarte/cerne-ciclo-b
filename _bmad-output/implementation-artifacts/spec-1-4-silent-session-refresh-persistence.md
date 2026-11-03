---
title: 'Story 1.4: Silent Session Refresh & Persistence'
type: 'feature'
created: '2026-10-27'
status: 'done'
review_loop_iteration: 0
baseline_commit: '8a4b94403d05281d58068aa4dac46dc08adf1873'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/docs/input/backend/api/openapi.yaml'
  - '{project-root}/docs/input/backend/error-taxonomy.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `AccessTokenProvider` only persists the access token (`access_token_provider.dart:8-35`); the refresh token already decoded into `AuthResponseDto` is discarded (`auth_repository_impl.dart:63-65`), and `main.dart` hardcodes `AuthScreen` as home with zero bootstrap check (`main.dart:36-46`) — so a valid session never survives a restart.

**Approach:** Persist the refresh token; add a `SessionRepository` in the auth domain that, on launch, unconditionally exchanges any stored refresh token for a fresh pair via `auth-refresh`, exposing the result as the epic's one singleton `SessionStatus` stream. `main.dart` branches its `home` on that stream's first emission instead of hardcoding `AuthScreen`.

## Boundaries & Constraints

**Always:**
- Boot calls `auth-refresh` once, unconditionally, whenever a refresh token is stored — no client-side expiry math or clock comparison; the server is the sole source of truth for validity.
- `AccessTokenProvider` gains `saveSession({accessToken, refreshToken})`, `readRefreshToken()`, `clearSession()`; existing `readAccessToken`/`saveAccessToken`/`clearAccessToken` stay untouched for `HeaderInterceptor` (`access_token_provider.dart:8-14`).
- `auth-refresh` stays in `HeaderInterceptor.anonKeyOnlyFunctions` (`header_interceptor.dart:20-24`) — refresh must never need the (possibly dead) access-token bearer.
- `SessionRepository.statusStream`/`restoreSession()` is the ONE new DI-singleton access point for session validity (epic AD) — no second stream, no raw-401 re-derivation.
- `AuthRepositoryImpl._authenticate` (`auth_repository_impl.dart:46-74`) persists the refresh token returned by signup/login too, via the same `saveSession`.
- A dead/missing refresh token reuses the closed 14-subtype `Failure` hierarchy (`AuthExpired`/`AuthInvalid`) — no new subtype (`failure.dart`).

**Ask First:** if the backend's `auth-refresh` response omits any field `openapi.yaml:197-234` marks required, HALT before guessing a fallback.

**Never:**
- No reactive refresh-and-retry-on-401 interceptor — mid-session expiry while the app is running is Story 1.5's overlay scope, not this story's.
- No `go_router` wiring (Story 1.6) — `main.dart` keeps its current `MaterialApp`/`Navigator` shape; only `home` changes.
- No new Cubit for this story — `main.dart` drives directly off `SessionRepository`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Cold boot, valid refresh token | refreshToken stored, backend accepts | `auth-refresh` succeeds, new pair saved, stream emits `authenticated`, home = post-auth placeholder | N/A |
| Cold boot, no stored session | no refresh token (fresh install / post-logout) | no network call, stream emits `unauthenticated` immediately, home = `AuthScreen` | N/A |
| Cold boot, dead refresh token | refreshToken stored, backend returns `AUTH_EXPIRED`/`AUTH_INVALID` | session cleared, stream emits `unauthenticated`, home = `AuthScreen` | silent — no error UI |
| Cold boot, offline | refreshToken stored, no connectivity | stream emits `unauthenticated` (fail-closed), storage left untouched | silent; next boot retries naturally |
| Successful signup/login (1.3 path) | — | refresh token now also saved via `saveSession` | N/A |

</frozen-after-approval>

## Code Map

- `lib/core/network/access_token_provider.dart:8-35` -- add `saveSession`/`readRefreshToken`/`clearSession` to the abstract port + the `FlutterSecureStorage` impl (new key alongside existing `_key`).
- `lib/features/auth/data/models/auth_response_dto.dart` -- `AuthSessionDto` already decodes `refreshToken`; reuse as-is, no DTO change.
- `lib/features/auth/data/datasources/auth_remote_data_source.dart:12-47` -- add `refresh(String refreshToken)`, posting `{refreshToken}` to `auth-refresh` (own body shape, can't reuse the email/password `_post` helper as-is).
- `lib/features/auth/data/repositories/auth_repository_impl.dart:46-74` -- `_authenticate` calls `saveSession(...)` instead of `saveAccessToken` only.
- `lib/features/auth/domain/entities/session_status.dart` -- new: `enum SessionStatus { authenticated, unauthenticated }`.
- `lib/features/auth/domain/repositories/session_repository.dart` -- new: `Stream<SessionStatus> get statusStream; Future<Either<Failure, Unit>> restoreSession();`.
- `lib/features/auth/data/repositories/session_repository_impl.dart` -- new: owns the broadcast `StreamController`, calls `AuthRemoteDataSource.refresh`, persists/clears via `AccessTokenProvider`.
- `lib/features/auth/auth_injection.dart:13-24` -- register `SessionRepository` singleton (after `AccessTokenProvider`/`AuthRemoteDataSource`).
- `lib/main.dart:23-67` -- `CerneApp` calls `sl<SessionRepository>().restoreSession()` once, branches `home` on a `StreamBuilder<SessionStatus>` (no-data yet = brief blank, per RNF01's 300ms threshold) between `AuthScreen` and the existing `_PostAuthPlaceholder`.
- `docs/input/backend/api/openapi.yaml:179-240` -- `auth-refresh` ground truth: `{refreshToken}` in, same `session` shape out, `security: []`.

## Tasks & Acceptance

**Execution:**
- [x] `access_token_provider.dart` -- add `saveSession`/`readRefreshToken`/`clearSession` -- new secure-storage surface for the refresh token
- [x] `auth_remote_data_source.dart` -- add `refresh()` -- calls `auth-refresh` per contract
- [x] `auth_repository_impl.dart` -- `_authenticate` persists the refresh token too -- closes the gap 1.3 flagged
- [x] `session_status.dart` -- new enum -- the two-state status the epic's AD requires
- [x] `session_repository.dart` (domain) + `session_repository_impl.dart` (data) -- new -- singleton stream + boot-time restore
- [x] `auth_injection.dart` -- register `SessionRepository` -- DI wiring
- [x] `main.dart` -- boot-time `restoreSession()` + `StreamBuilder` home branch -- replaces the hardcoded `AuthScreen` home
- [x] `test/.../session_repository_impl_test.dart` -- cover the I/O matrix rows (valid/none/dead/offline) with `mocktail`
- [x] `test/.../auth_remote_data_source_test.dart` -- `refresh()` write-failure matrix (timeout/malformed/offline) per RNF09
- [x] `test/main_test.dart` -- extend for both boot branches (authenticated vs unauthenticated home)

**Acceptance Criteria:**
- Given a stored refresh token the backend accepts, when the app launches, then the user reaches the authenticated placeholder with no login prompt and no visible loading UI in the happy path (<300ms).
- Given no stored session or a refresh token the backend rejects, when the app launches, then the user lands on `AuthScreen` with no error message shown.
- Given a successful signup/login, when `AuthRepositoryImpl` returns, then both the access token and refresh token are persisted, unchanged `Either<Failure,T>` signature (RNF09).

### Review Findings

- [x] [Review][Patch] `_asUnauthenticated`'s comment overstates what `restoreSession()`'s `catchError` "insurance" (`main.dart:54-75`) actually does — it suppresses an unhandled zone exception, but since the whole call is `unawaited`, its return value is discarded and never reaches `statusStream`; it does NOT unblock the UI from `_BootLoadingScreen`. Today this is unreachable dead code (every repository method in this diff returns `Either` and never throws), and fixing the underlying gap for real would mean widening the frozen `SessionRepository` interface ("the ONE new DI-singleton access point... no second stream") for a path with no current trigger — not worth renegotiating the frozen spec for. Fix: reword the comment to say it only prevents an unhandled zone exception, not that it recovers the UI. [lib/main.dart:69-75]
- [x] [Review][Patch] `statusStream` getter returns a new `Stream.multi` instance on every access; `main.dart` passes it directly into `StreamBuilder` instead of caching it — currently inert because `_CerneAppState.build()` only runs once (no `setState`, no `InheritedWidget` dependency), but it's a latent resubscription/flash-to-boot-screen bug waiting for any future rebuild trigger. Fix: cache `late final Stream<SessionStatus> _statusStream = _sessionRepository.statusStream;` once in `_CerneAppState` and reference that field in `build()`. [lib/main.dart:82]
- [x] [Review][Patch] No `isClosed` guard before `_statusController.add()` in `_emit()`; `dispose()` closes that same controller. If `dispose()` (wired to `get_it`'s `sl.reset()`) ever runs while a `restoreSession()` call is still in flight, the pending `.add()` throws an unhandled `StateError` — not exercised by any current test, but a real race the moment DI is torn down with a boot restore still pending (dev hot-restart, a future logout-reset flow). Fix: guard `_emit()` with `if (!_statusController.isClosed) { ... }`. [lib/features/auth/data/repositories/session_repository_impl.dart:68]
- [x] [Review][Patch] `_BootLoadingScreen`'s 300ms blank→spinner `Timer` logic has zero test coverage — explicitly called out by the spec as this story's own new UI (the reason RNF01's verification grep was widened to `lib/main.dart`), but every `main_test.dart` boot test uses `pumpAndSettle()`, which fast-forwards past the internal `Timer`. Neither "stays blank below 300ms" nor "shows spinner past 300ms" is ever asserted. Fix: add a widget test using `tester.pump(duration)` (not `pumpAndSettle`) to assert the blank state before 300ms and the spinner after. [lib/main.dart:137]
- [x] [Review][Patch] `readRefreshToken()` returning a non-null empty string isn't treated as "no session" — `restoreSession()` only null-checks the result (`session_repository_impl.dart:86`), so a stored empty-string refresh token (the response schema has no `minLength` on this field) would fire a network call to `auth-refresh` with an empty token (itself `minLength: 1` on the request) instead of short-circuiting like the no-token case. Low-impact (fails via the normal `VALIDATION_ERROR` path and still ends up `unauthenticated`), but a one-line fix. Fix: treat `refreshToken == null || refreshToken.isEmpty` as "no stored session." [lib/features/auth/data/repositories/session_repository_impl.dart:86]
- [x] [Review][Patch] `deferred-work.md`'s new entries (added by this diff) claim `AuthCubit.toggleMode()`'s and `passwordChanged()`'s behavior changes are "pre-existing uncommitted work... not touched by story 1.4's diff" — but this diff does modify and ship `auth_cubit.dart`'s `toggleMode()`/`passwordChanged()`, so that framing is factually wrong regardless of where the change originated. Compounding this, `passwordChanged()`'s new symmetric `emailError` clear is reachable through the real `AuthScreen` (malformed-email submit sets `emailError`, then editing only the password field should clear it) and has no regression test in either `auth_cubit_test.dart` or `auth_screen_test.dart` — this one should be fixed now, not deferred, since it's in-scope and the fix is unambiguous. Fix: correct both `deferred-work.md` bullets' "not touched" claim, and add the missing `passwordChanged`-clears-`emailError` test. [lib/features/auth/presentation/cubit/auth_cubit.dart:45]
- [x] [Review][Defer] `AuthCubit.toggleMode()`'s `copyWith`-based status-preservation fix has no regression test that can observe the regression it fixes. Checked reachability: its only call site is a button disabled whenever `isSubmitting` is true, and every failure path resets `status` to idle in the same `emit` as the one that sets `formError` — so there's no path in the current UI that can exercise a non-idle `status` at `toggleMode()` time. Legitimately deferred (unlike the `passwordChanged` item above), but the reason recorded in `deferred-work.md` should say "unreachable via current UI," not "not touched by story 1.4's diff." [lib/features/auth/presentation/cubit/auth_cubit.dart:23] — deferred, pre-existing

## Design Notes

- `StreamBuilder` over a Cubit: `SessionRepository` already exposes a `Stream`; wrapping it in a Cubit just to re-expose the same stream would be a redundant layer — Story 1.6's nav shell/`go_router` redirect consumes it directly instead.
- Unconditional refresh-at-boot (no client-side expiry math) trades one always-on network round trip for zero clock-skew bugs; revisit only if the 300ms-threshold UX proves this too slow in practice.
- Mid-session reactive refresh-on-401 is deliberately deferred to Story 1.5 (the overlay) rather than solved here with a second mechanism.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves, no conflicts
- `fvm flutter test` -- all tests pass
- `fvm flutter analyze` -- zero issues
- `grep -rn "Color(0x\|fontSize:\|EdgeInsets\.\(all\|symmetric\|only\)(" lib/features/auth lib/core/network lib/main.dart --include=*.dart` -- expected: no matches (RNF08) -- widened to include `lib/main.dart`, where this story's own new UI (the `StreamBuilder`/boot-loading screen) actually lives

## Suggested Review Order

**Domain contract (entry point)**

- The one new DI-singleton access point for session validity — a stream plus a one-shot restore call, nothing else.
  [`session_repository.dart:11`](../../lib/features/auth/domain/repositories/session_repository.dart#L11)
- The two-state status the epic's AD requires — no third "expired-mid-session" state, deliberately deferred to Story 1.5.
  [`session_status.dart:1`](../../lib/features/auth/domain/entities/session_status.dart#L1)

**Boot-time restore (the core mechanism)**

- `restoreSession()` — unconditional refresh, no client-side expiry math; the server is the sole source of truth.
  [`session_repository_impl.dart:74`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L74)
- Only a backend-confirmed dead token clears storage; any other failure leaves it untouched so the next boot retries.
  [`session_repository_impl.dart:96-110`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L96-L110)
- Replay-last-value stream: a late subscriber still sees current status immediately, not just future changes.
  [`session_repository_impl.dart:46-66`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L46-L66)

**Refresh-token persistence**

- `saveSession`/`clearSession` write the refresh token first — the one field `restoreSession()` actually keys its next-boot decision on.
  [`access_token_provider.dart:60-86`](../../lib/core/network/access_token_provider.dart#L60-L86)
- `AuthRepositoryImpl._authenticate` now persists the refresh token too, not just the access token.
  [`auth_repository_impl.dart:46-62`](../../lib/features/auth/data/repositories/auth_repository_impl.dart#L46-L62)
- `auth-refresh`'s own body/response shape can't reuse `_post`/`AuthResponseDto` — decodes the nested `session` object directly.
  [`auth_remote_data_source.dart:26-48`](../../lib/features/auth/data/datasources/auth_remote_data_source.dart#L26-L48)

**Boot UI (main.dart)**

- `home` branches on `statusStream` instead of hardcoding `AuthScreen`; `restoreSession()` fires once in `initState`.
  [`main.dart:47-63`](../../lib/main.dart#L47-L63)
- Blank for the happy path, spinner only past RNF01's 300ms threshold — a slow/offline boot no longer looks frozen.
  [`main.dart:130-170`](../../lib/main.dart#L130-L170)

**Wiring (DI)**

- `SessionRepository` registered as a singleton with `dispose:` wired into `get_it`'s own reset lifecycle.
  [`auth_injection.dart:33-39`](../../lib/features/auth/auth_injection.dart#L33-L39)

**Tests (peripherals)**

- The four I/O-matrix rows plus the two exception-mapping paths and the replay-semantics check.
  [`session_repository_impl_test.dart:1`](../../test/features/auth/data/repositories/session_repository_impl_test.dart#L1)
- `refresh()`'s write-failure matrix (timeout/malformed/offline) per RNF09.
  [`auth_remote_data_source_test.dart:1`](../../test/features/auth/data/datasources/auth_remote_data_source_test.dart#L1)
- Real `SecureStorageAccessTokenProvider` round-trip coverage for the new session methods.
  [`access_token_provider_test.dart:1`](../../test/core/network/access_token_provider_test.dart#L1)
- `auth-refresh` proven over the real pipeline with the anon-key bearer, mirroring the existing `auth-login` case.
  [`network_pipeline_integration_test.dart:1`](../../test/core/network/network_pipeline_integration_test.dart#L1)
- Both boot branches (authenticated vs unauthenticated home) driven through the real composition root.
  [`main_test.dart:1`](../../test/main_test.dart#L1)
