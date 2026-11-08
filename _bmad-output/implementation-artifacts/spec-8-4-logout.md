---
title: 'Story 8.4: Logout'
type: 'feature'
created: '2026-11-08'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '150b89db7aef65fe75834a13d23f4af76cffe260'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Configurações has no way to end the session — "Sair" is a dead action (epic-8-context.md's Story 8.4 scope; FR-42, RF03).

**Approach:** Add `logout()`/`lock()`/`clearLocalCache()` to `SessionRepository`/`VaultRepository`/`EntriesRepository`/`ChatRepository` respectively; `AccountSettingsCubit` orchestrates all four behind one `logout()` call triggered by a new "Sair" button. No new navigation code — the existing `app_router.dart` redirect (already watching both streams) takes the user to Biometria once the vault relocks.

## Boundaries & Constraints

**Always:**
- `SessionRepository.logout()` (mirrors `restoreSession()`): calls new `AuthRemoteDataSource.logout()` (`POST auth-logout`, bearerAuth, no body), then UNCONDITIONALLY calls `AccessTokenProvider.clearSession()` and emits `SessionStatus.unauthenticated` — must work even offline.
- `VaultRepository.lock()` (new, sync, mirrors `markAuthenticated()`): `_emit(VaultStatus.locked)`. Cubit calls this BEFORE awaiting `sessionRepository.logout()` — AD-14's vault-gate-first redirect then lands on `/vault` (Biometria) with no transient `/auth` hop (prototype-extract.md:40-41, Story 8.5 shares this destination).
- `EntriesRepository`/`ChatRepository` gain `clearLocalCache()` (`Either<Failure, Unit>`, `try`/`catch` around box `.clear()`) — closes deferred-work.md's "no clear-on-logout hook" gap now that a logout feature exists.
- `AccountSettingsCubit` gains the 4 repos above as constructor deps (same direct-domain-interface precedent as `EntryDetailCubit`→`SessionRepository`) + `logout()`: guard re-entry via new `isLoggingOut`, `vaultRepository.lock()`, `await sessionRepository.logout()` (result ignored — local session already ended regardless), `await Future.wait([entries.clearLocalCache(), chat.clearLocalCache()])`, same `isClosed` guard as `toggleBiometric`.
- Screen: `AppButton(secondaryOutline, 'Sair', onPressed: state.isLoggingOut ? null : cubit.logout)` as the scroll column's last child, below `DashboardChartSection`.

**Ask First:** None.

**Never:** `sl.reset()`/re-running `setupCoreDependencies()` (strands `_CerneAppState`'s captured repo instances); clearing in-memory cubit/tracker state — scoped to only the two Hive boxes deferred-work.md names; an "Apagar conta" button/dialog (Story 8.5); surfacing a backend-logout-failure error.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap Sair | `isLoggingOut: false` | vault relocks immediately -> router redirects to `/vault`; `auth-logout` fires; local tokens + both Hive boxes clear | N/A |
| `auth-logout` backend call fails (offline/expired/...) | any | local session still clears, same redirect | `Left` swallowed, no UI message |
| Double-tap Sair | `isLoggingOut: true` | second tap no-ops (button disabled) | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/auth/domain/repositories/session_repository.dart` / `data/repositories/session_repository_impl.dart:117-173` -- add + implement `logout()`, mirrors `restoreSession()`
- `lib/features/auth/data/datasources/auth_remote_data_source.dart:21-24` -- add `logout()` (`_apiClient.post('auth-logout')` -> `Either<Failure, Unit>`)
- `lib/features/vault/domain/repositories/vault_repository.dart` / `data/repositories/vault_repository_impl.dart:139-158` (`_emit`) -- add + implement `lock()`
- `lib/features/entries/domain/repositories/entries_repository.dart` / `data/repositories/entries_repository_impl.dart:21-29` (`_entriesBox`) -- add `clearLocalCache()`
- `lib/features/chat/domain/repositories/chat_repository.dart` / `data/repositories/chat_repository_impl.dart:21-32` (`_sessionsBox`/`_messagesBox`) -- add `clearLocalCache()`
- `lib/features/account/presentation/cubit/account_settings_cubit.dart:148-171` -- constructor deps + `isLoggingOut` + `logout()`
- `lib/features/account/presentation/screens/account_settings_screen.dart:429-540` -- "Sair" `AppButton`, after `DashboardChartSection`
- `lib/features/account/account_injection.dart:34-37` -- widen `AccountSettingsCubit` registration with the 4 new `sl<...>()` deps
- `lib/core/widgets/app_button.dart` -- reused as-is (`secondaryOutline`)
- `docs/input/backend/api/openapi.yaml:292-313` (`auth-logout`, bearerAuth) + `README.md:28`
- `docs/input/prototype/prototype-extract.md:40-41,116` -- "Sair" → Biometria; only "Apagar conta" (Story 8.5) is red
- `_bmad-output/implementation-artifacts/deferred-work.md` (spec-3-1's "no clear-on-logout hook" entry) -- the gap this story closes
- `test/features/{auth/data/repositories/session_repository_impl,vault/data/repositories/vault_repository_impl,entries/data/repositories/entries_repository_impl,chat/data/repositories/chat_repository_impl,account/presentation/cubit/account_settings_cubit,account/presentation/screens/account_settings_screen}_test.dart` -- extend fakes/mocks + new coverage

## Tasks & Acceptance

**Execution:**
- [x] `session_repository.dart`/`_impl.dart` -- `logout()`
- [x] `auth_remote_data_source.dart` -- `logout()`
- [x] `vault_repository.dart`/`_impl.dart` -- `lock()`
- [x] `entries_repository.dart`/`_impl.dart` -- `clearLocalCache()`
- [x] `chat_repository.dart`/`_impl.dart` -- `clearLocalCache()`
- [x] `account_settings_cubit.dart` -- constructor deps, `isLoggingOut`, `logout()`
- [x] `account_settings_screen.dart` -- "Sair" button
- [x] `account_injection.dart` -- widen registration
- [x] Tests: I/O matrix + new unit coverage for every new repository method; update `AccountSettingsCubit`'s fakes for the widened constructor

**Acceptance Criteria:**
- Given Configurações, when "Sair" is tapped, then `POST /auth/logout` fires and the user is routed to the Biometric Vault screen (epics.md Story 8.4 AC).
- Given the backend call fails, then the user is still routed away with no error shown (local session already ended).
- Given logout completes, then the entries and chat Hive boxes are empty (deferred-work.md gap closed).

## Spec Change Log

- Post-implementation review (3-layer: blind-hunter, edge-case-hunter, verification-gap) found 4 trivially-fixable issues, all applied:
  1. `ChatRepositoryImpl.clearLocalCache()` now clears `_sessionsBox`/`_messagesBox` independently (separate try/catch each) so a throw on one never skips the other.
  2. `AccountSettingsCubit.logout()` now `debugPrint`s (debug-only, never UI-visible) if either cache-clear call returns `Left`, instead of silently discarding both results.
  3. `auth_remote_data_source_test.dart` gained direct coverage of `AuthRemoteDataSource.logout()` (exact `'auth-logout'` endpoint string, `Left` passthrough) — previously only exercised indirectly through a wholesale mock.
  4. `account_settings_screen_test.dart`'s "tapping Sair" test now asserts the router actually lands on `/vault`, via a new dedicated vault-gated test router (`pumpWithLogoutFakesAndVaultGate`) kept separate from the plain stub the other "Sair" tests still use (a real vault-gate redirect would otherwise unmount the screen mid-test for those).

## Design Notes

Cross-story (epic-8-context.md): Story 8.5 (account deletion) reuses this same lock+logout+clear sequence after its own `DELETE /account` call — write `AccountSettingsCubit.logout()` so that story can call it (or extract a shared private helper) rather than duplicating it.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test test/features/auth test/features/vault test/features/entries test/features/chat test/features/account test/core/navigation` -- expected: all pass

## Suggested Review Order

**Orchestration (the "Sair" flow, end to end)**

- Entry point — lock-before-await ordering, the result-ignored session call, and the now-logged (never UI-surfaced) cache-clear failures.
  [`account_settings_cubit.dart:348`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L348)
- The re-entry guard and in-flight state the "Sair" button's disabled state depends on.
  [`account_settings_cubit.dart:85`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L85)

**Session end (backend + local, unconditional)**

- `restoreSession()`'s inverse — backend call, then UNCONDITIONAL local clear + `unauthenticated` emission regardless of outcome.
  [`session_repository_impl.dart:176`](../../lib/features/auth/data/repositories/session_repository_impl.dart#L176)
- The real HTTP call — bearerAuth, no body, posts to exactly `auth-logout`.
  [`auth_remote_data_source.dart:54`](../../lib/features/auth/data/datasources/auth_remote_data_source.dart#L54)

**Vault relock (the AD-14 ordering this story's whole redirect story depends on)**

- One-line, synchronous, mirrors `markAuthenticated()`'s opposite direction — fired before the session call to avoid a transient `/auth` hop.
  [`vault_repository_impl.dart:293`](../../lib/features/vault/data/repositories/vault_repository_impl.dart#L293)

**Local cache clearing (closes the deferred-work.md shared-device gap)**

- Entries box clear, wrapped per RNF09.
  [`entries_repository_impl.dart:234`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L234)
- Chat's two boxes cleared independently (review patch) — a disk failure on one never skips the other.
  [`chat_repository_impl.dart:163`](../../lib/features/chat/data/repositories/chat_repository_impl.dart#L163)

**UI + DI wiring**

- The "Sair" button — `secondaryOutline`, disabled while `isLoggingOut`, last child below the chart section.
  [`account_settings_screen.dart:550`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L550)
- `AccountSettingsCubit`'s widened registration — the 4 new repos it now orchestrates.
  [`account_injection.dart:47`](../../lib/features/account/account_injection.dart#L47)

**Tests**

- The full I/O & Edge-Case Matrix against the real cubit (ordering, concurrency, double-tap, backend-failure-still-clears).
  [`account_settings_cubit_test.dart:674`](../../test/features/account/presentation/cubit/account_settings_cubit_test.dart#L674)
- The three Acceptance Criteria proved against the real screen + a real vault-gated router — including the review-patch assertion that the route actually lands on `/vault`.
  [`account_settings_screen_test.dart:1386`](../../test/features/account/presentation/screens/account_settings_screen_test.dart#L1386)
- Review-patch coverage: the real `auth-logout` HTTP call, previously only exercised through a wholesale mock.
  [`auth_remote_data_source_test.dart:115`](../../test/features/auth/data/datasources/auth_remote_data_source_test.dart#L115)
- Review-patch coverage: a disk failure on either chat Hive box never skips clearing the other.
  [`chat_repository_impl_test.dart:324`](../../test/features/chat/data/repositories/chat_repository_impl_test.dart#L324)
