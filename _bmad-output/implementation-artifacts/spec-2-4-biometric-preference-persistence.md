---
title: 'Biometric Preference Persistence'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '81d7509dc1b0a9be2094ef9113b73402ebf5b19f'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The vault's biometric gate (spec-2-1) always attempts Face ID/Touch ID first with no way to turn it off, and nothing reads/writes `biometricEnabled` server-side — Epic 1's Configurações placeholder has no real content.

**Approach:** Introduce `features/account/` with an `AccountSettingsRepository` (sync-getter-plus-stream, like `VaultRepository`/`SessionRepository`, AD-14) backed by `PATCH /account/settings` — the only account-settings endpoint, called empty to read, with `biometricEnabled` to write. Fetch once at boot, feed the value into `VaultLockScreen` so it skips biometric when disabled, and build the real Configurações screen (replacing the placeholder) around the toggle.

## Boundaries & Constraints

**Always:** `PATCH /account/settings` (`{FUNCTIONS_BASE_URL}/account-settings-update`) is called with `{}` to read, `{"biometricEnabled": <bool>}` to write — no GET endpoint exists (`openapi.yaml`). `AccountSettingsRepository.currentBiometricEnabled` starts `true` (never null), the single source for both the vault gate and the toggle. Toggling is optimistic: switch flips immediately (RNF01, <100ms), PATCH fires, a failure reverts the switch and shows the `Failure`'s message. `VaultLockScreen.initState` calls `authenticate()` only when the preference is `true`; `false` shows the PIN keypad directly — PIN remains the access method regardless. Domain imports neither `flutter` nor `data/` (RNF06); repository returns `Either<Failure, T>` (RNF09).

**Ask First:** None.

**Never:** No new `Failure` subtype — `Failure.fromCode` already covers PATCH errors. No change to `VaultRepository`'s contract, `vault_injection.dart`, or vault's "zero network calls" boundary. No GET endpoint invented. No `displayName`/`persona` touched (Epic 8's scope).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Boot fetch resolves `false` | `PATCH {}` returns `biometricEnabled: false` before `/vault` builds | `VaultLockScreen` skips biometric, shows PIN keypad | N/A |
| Boot fetch resolves `true` / still in flight | Returns `true`, or unresolved | `VaultLockScreen` attempts biometric first (default `true`) | N/A |
| Boot fetch fails | `PATCH {}` returns a `Failure` | `currentBiometricEnabled` unchanged | Swallowed, fire-and-forget like `restoreSession()` |
| Toggle succeeds | User taps the switch | Switch flips, persists, no error | N/A |
| Toggle fails | Network/backend error | Switch reverts to previous value | `Failure.message` shown inline |

</frozen-after-approval>

## Code Map

- `lib/features/account/domain/repositories/account_settings_repository.dart` (new) — `biometricEnabledStream`, `currentBiometricEnabled` (bool, starts `true`), `fetchBiometricEnabled()`, `setBiometricEnabled(bool)`, `dispose()`; mirrors `vault_repository.dart`.
- `lib/features/account/data/{datasources/account_remote_data_source.dart, models/account_settings_dto.dart, repositories/account_settings_repository_impl.dart}` (new) — data source calls `ApiClient.patch('account-settings-update', data: {...})` (mirrors `auth_remote_data_source.dart`); DTO carries only the response's `biometricEnabled` field; repo impl is a broadcast `StreamController<bool>` default `true`.
- `lib/features/account/account_injection.dart` (new) — `registerAccountFeature()`, called from `injection_container.dart`'s `setupCoreDependencies()` (`:80-81`), next to auth/vault.
- `lib/features/account/presentation/{cubit/account_settings_cubit.dart, screens/account_settings_screen.dart}` (new) — cubit's `toggleBiometric(bool)` is the optimistic flip/revert from the I/O matrix; screen is a header + one switch row, replacing `ConfiguracoesPlaceholderScreen`.
- `lib/core/widgets/back_arrow_header.dart` (new) — `BackArrowHeader` extracted from `placeholder_screens.dart`'s private `_BackArrowHeader` (`:247-280`); `MeusRegistrosPlaceholderScreen` repointed to it.
- `lib/core/navigation/placeholder_screens.dart` — delete `ConfiguracoesPlaceholderScreen` (`:165-188`).
- `lib/core/navigation/app_router.dart` — `buildAppRouter` gains `required AccountSettingsRepository accountSettingsRepository`; stream joins `_GoRouterRefreshStream` (`:52-55`); `/vault` (`:59-63`) passes `attemptBiometricFirst: accountSettingsRepository.currentBiometricEnabled`; `/configuracoes` (`:91-94`) builds the new screen.
- `lib/features/vault/presentation/screens/vault_lock_screen.dart` — add `required bool attemptBiometricFirst`; `initState` (`:72-75`) calls `_attemptAuthenticate()` only if true, else sets `_showPinKeypad = true` directly.
- `lib/main.dart` — resolve `sl<AccountSettingsRepository>()`, pass into `buildAppRouter`, fire `unawaited(fetchBiometricEnabled())` beside the existing `restoreSession()` call (`:82-84`).

## Tasks & Acceptance

**Execution:**
- [x] New `features/account/` module (domain/data/DI, cubit, screen) -- per Code Map.
- [x] `back_arrow_header.dart` extraction -- reuse, no duplication -- per Code Map.
- [x] `placeholder_screens.dart`, `app_router.dart`, `main.dart` -- wire the new repository + screen, remove the placeholder -- per Code Map.
- [x] `vault_lock_screen.dart` -- gate `_attemptAuthenticate()` on `attemptBiometricFirst` -- per I/O matrix.
- [x] Tests for every file above -- cover all five I/O-matrix rows -- regression coverage.

**Acceptance Criteria:**
- Given the Configurações screen opens, then it shows only the biometric toggle (minimal — Epic 8 extends it, never rebuilds it).
- Given I reinstall or restart after changing this setting elsewhere, when the app loads, then the preference is fetched fresh, never read from a stale local cache.

## Design Notes

Mirrors AD-14's stream-plus-sync-getter shape, not `Resource<T>` (AD-12) — read persistently in two places, not fetched once on screen entry. Defaulting `true` before boot-fetch resolves matches pre-2.4 behavior: a slow/offline fetch degrades to "try biometric first", never silent PIN-only. Switch active color reuses `DesignTokens.colorAccent` — no new tokens.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues.
- `fvm flutter test` -- expected: all pass, including new account-feature and vault_lock_screen tests.

## Suggested Review Order

**Repository contract & concurrency safety**

- Entry point: the AD-14-style stream-plus-sync-getter contract this whole story hangs off.
  [`account_settings_repository.dart:15`](../../lib/features/account/domain/repositories/account_settings_repository.dart#L15)

- Generation guard added in review: sequences `fetchBiometricEnabled`/`setBiometricEnabled` so a stale call can never stomp a newer one's settled value.
  [`account_settings_repository_impl.dart:43`](../../lib/features/account/data/repositories/account_settings_repository_impl.dart#L43)

- Optimistic flip, then the superseded-call short-circuit before the revert/confirm branch.
  [`account_settings_repository_impl.dart:99`](../../lib/features/account/data/repositories/account_settings_repository_impl.dart#L99)

- The only two calls this feature ever makes — empty body to read, `biometricEnabled` to write, no GET endpoint exists.
  [`account_remote_data_source.dart:14`](../../lib/features/account/data/datasources/account_remote_data_source.dart#L14)

**Boot wiring & the vault gate**

- Fire-and-forget boot fetch, same rationale as `restoreSession()` right above it.
  [`main.dart:97`](../../lib/main.dart#L97)

- `/vault`'s builder reads `currentBiometricEnabled` synchronously at build time — the one line `attemptBiometricFirst` actually comes from.
  [`app_router.dart:94`](../../lib/core/navigation/app_router.dart#L94)

- Doc comment explaining why no `refreshListenable` entry is needed here — written after proving the alternative was dead code (go_router 18.1.1 short-circuits an unchanged route match).
  [`app_router.dart:35`](../../lib/core/navigation/app_router.dart#L35)

- `attemptBiometricFirst` gates the auto-biometric-attempt vs. straight-to-keypad branch.
  [`vault_lock_screen.dart:84`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L84)

- Added in review: defensive `didUpdateWidget` honors a changed preference if this already-mounted screen is ever rebuilt by any future means.
  [`vault_lock_screen.dart:145`](../../lib/features/vault/presentation/screens/vault_lock_screen.dart#L145)

**Configurações screen & optimistic toggle**

- `toggleBiometric`'s end-to-end optimistic flip/revert, plus `isSaving` added in review to disable the switch mid-flight.
  [`account_settings_cubit.dart:89`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L89)

- Added in review: clears a stale toggle-failure error left over from a previous visit to this DI-singleton cubit.
  [`account_settings_cubit.dart:108`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L108)

- The one switch row; `onChanged: null` while `isSaving` is the UI half of the double-tap fix.
  [`account_settings_screen.dart:58`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L58)

- Added in review: calls `clearStaleError()` on mount — `AccountSettingsScreen` became `StatefulWidget` for this.
  [`account_settings_screen.dart:23`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L23)

**DI wiring**

- `AccountSettingsCubit`'s `dispose:` callback, added in review to match the repository registration right above it.
  [`account_injection.dart:28`](../../lib/features/account/account_injection.dart#L28)

**Tests**

- Added in review: proves `registerAccountFeature()` resolves end-to-end through the real container, mirroring the existing auth/vault wiring tests.
  [`bootstrap_integration_test.dart:125`](../../test/core/di/bootstrap_integration_test.dart#L125)

- Added in review: the two generation-guard race tests (stale fetch vs. newer toggle; older toggle vs. newer toggle).
  [`account_settings_repository_impl_test.dart:227`](../../test/features/account/data/repositories/account_settings_repository_impl_test.dart#L227)

- Added in review: proves the `didUpdateWidget` fix actually switches to the keypad mid-flight on a true→false rebuild.
  [`vault_lock_screen_test.dart:201`](../../test/features/vault/presentation/screens/vault_lock_screen_test.dart#L201)

- Added in review: the switch disables itself while `isSaving`, and a stale error doesn't survive a fresh screen instance.
  [`account_settings_screen_test.dart:138`](../../test/features/account/presentation/screens/account_settings_screen_test.dart#L138)
