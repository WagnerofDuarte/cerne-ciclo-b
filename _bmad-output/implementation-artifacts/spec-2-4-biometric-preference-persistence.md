---
title: 'Biometric Preference Persistence'
type: 'feature'
created: '2026-11-03'
status: 'done'
review_loop_iteration: 1
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

### Review Findings

- [x] [Review][Patch] Cold-start biometric-prompt race almost certainly defeats AC2's exact named scenario on every normal cold start, not just "reinstall" — `VaultRepository.currentStatus` defaults synchronously to `locked`, and AD-14 composes the vault gate strictly first in `_redirect`, so it routes to `/vault` on the very first redirect evaluation regardless of `/boot`'s own session-status wait, before `main.dart`'s fire-and-forget `fetchBiometricEnabled()` network call can possibly resolve. `/vault`'s `GoRoute.builder` reads `accountSettingsRepository.currentBiometricEnabled` synchronously at that moment (still the untouched default `true`), and `VaultLockScreen.initState` captures `attemptBiometricFirst` once. No `refreshListenable` entry is wired for `biometricEnabledStream` (the doc comment at `app_router.dart:35-62` explains go_router 18.1.1 short-circuits an unchanged route match), so even if the fetch resolves while still on `/vault`, the screen is never told. — fixed: `main()` now awaits `sl<AccountSettingsRepository>().fetchBiometricEnabled()` (bounded by a 2s timeout so a hung network call can't delay launch indefinitely) before calling `runApp()`, so `currentBiometricEnabled` already reflects the real preference by the time the vault gate's very first redirect evaluation runs — no change to `_redirect`'s AD-14 ordering, `VaultLockScreen`, or the "no `refreshListenable` entry needed" convention. `CerneApp.initState`'s own fire-and-forget fetch is left in place (now a harmless redundant re-fetch); the shared `catchError` handler was promoted to a top-level function so both call sites use it. [lib/main.dart:15-43]
- [x] [Review][Patch] A superseded `setBiometricEnabled` call surfaces its raw, English, internal "Superseded by a newer preference update" message verbatim in the otherwise fully Portuguese Configurações UI — on supersession the repository returns `Left(Failure.malformedResponse(message: 'Superseded by a newer preference update'))`, and `AccountSettingsCubit.toggleBiometric` shows `failure.message` verbatim with no filtering. `Failure.malformedResponse` is also reserved by the architecture spine for genuine client-side parse failures, not reused as an internal control-flow sentinel. — fixed: the sentinel message is now a shared `AccountSettingsRepository.supersededMessage` constant; `toggleBiometric` recognizes it and suppresses the error (just clears `isSaving`) instead of showing it, since the winning call already settled the value correctly. Repository's `Left`-on-supersession contract itself is unchanged (an existing test already pins that down). [lib/features/account/domain/repositories/account_settings_repository.dart:15-21] [lib/features/account/data/repositories/account_settings_repository_impl.dart:112-116] [lib/features/account/presentation/cubit/account_settings_cubit.dart:89-106]
- [x] [Review][Patch] `submitPin()`'s generation guard checks staleness only once, right after `read()` — not again before the subsequent `write()`/`_emit()` for the first-time-PIN branch — so a call whose `write()` is the slow step can pass its check, then still land its (stale) PIN and unconditionally call `_emit(VaultStatus.unlocked)` after being superseded by a second call that finished first. — fixed: a second generation check now runs right after `write()`, before `_emit`/`return right(unit)`; returns `Left` if superseded. Note: this closes the "still emits unlocked/reports success after being superseded" gap, but not the deeper, lower-level race of which of two concurrent first-time-PIN `write()` calls physically lands last in storage — that would need serializing the whole read-write section, out of scope for this fix. Covered by a new test (gates `write()` instead of `read()`, per the review's own suggested shape). [lib/features/vault/data/repositories/vault_repository_impl.dart:230-250] [test/features/vault/data/repositories/vault_repository_impl_test.dart]
- [x] [Review][Patch] `fetchBiometricEnabled()` always returns `Right(unit)` even when its own result was discarded for being stale — the `generation == _generation` check only gated whether `_emit` ran, not the return value, inconsistent with the sibling `setBiometricEnabled`. — fixed: returns `Left(Failure.malformedResponse(message: AccountSettingsRepository.supersededMessage))` on the same stale-generation branch, mirroring `setBiometricEnabled`. Covered by a new assertion on the existing overlapping-calls test. [lib/features/account/data/repositories/account_settings_repository_impl.dart:78-96] [test/features/account/data/repositories/account_settings_repository_impl_test.dart]
- [x] [Review][Patch] `AccountSettingsCubit.toggleBiometric` can call `emit()` after `close()`, which `bloc` 9.2.1 throws a `StateError` for — the cubit is a lazy singleton with `dispose: (cubit) => cubit.close()`; `resetCoreDependencies()` isn't called in production yet (test-teardown only) but becomes a live crash risk once Epic 8's logout implements it. — fixed: `toggleBiometric` now returns early if `isClosed` once its `await` resolves, matching the guard the repository-layer `_emit` methods already use. [lib/features/account/presentation/cubit/account_settings_cubit.dart:89-106]
- [x] [Review][Patch] No screen-reader announcement when a biometric toggle fails and reverts — the reverted switch + error message were shown as a plain `Text`, with no `SemanticsService.sendAnnouncement`, unlike `vault_lock_screen.dart`'s `_announce()` for the equivalent transition. — fixed: added the same `_announce()` pattern, wired through a `BlocConsumer` listener that fires whenever `state.errorMessage` becomes non-null. [lib/features/account/presentation/screens/account_settings_screen.dart]
- [x] [Review][Patch] The biometric `Switch` and its label aren't semantically merged for screen readers — a plain `Row(Text, Switch)` with no `MergeSemantics`/`Semantics(label:)`. — fixed: wrapped the row in `MergeSemantics` + an explicit `Semantics(label: 'Entrar com biometria', ...)`, with `ExcludeSemantics` on the plain `Text` so the label isn't announced twice. [lib/features/account/presentation/screens/account_settings_screen.dart]
- [x] [Review][Patch] Toggling the switch gives no visible loading feedback while `isSaving`, only disables it — no spinner or copy change, unlike this app's established async-feedback pattern. RNF01 expects a loading indicator for calls over 300ms. — fixed: added a small inline `CircularProgressIndicator` next to the switch while `isSaving`; its size/stroke width added as new `design_tokens.dart` tokens (`accountSettingsSavingIndicatorSize`/`-StrokeWidth`), per AGENTS.md's single-source-of-truth rule for visual values. [lib/features/account/presentation/screens/account_settings_screen.dart] [lib/core/design_tokens.dart]
- [x] [Review][Patch] `VaultRepositoryImpl`'s constructor only catches `FlutterError` around `WidgetsBinding.instance`, which is dead code in release builds — `BindingBase.checkInstance`'s null-binding check is wrapped entirely in `assert(() {...})`, so a release build never actually throws `FlutterError` here; it returns `null` typed as non-nullable, and the next call fails with an unrelated, uncaught error instead. — fixed: widened the catch clause to `on Object catch (error)`, so the guard works identically in every build mode. Currently unreachable either way (`get_it` only constructs this after `main()`'s own binding init). [lib/features/vault/data/repositories/vault_repository_impl.dart:69-81]
- [x] [Review][Patch] `AccountSettingsCubit` always emits a redundant duplicate initial-state event right after construction — the stream listener's first delivery (`biometricEnabledStream`'s immediate replay of `_currentValue`) is itself the first real `emit()` call and is never skipped by `bloc`'s equal-state dedup, which only applies once something has already been emitted. — fixed: the listener now compares the incoming value against `state.biometricEnabled` and returns early on an exact match, instead of relying on `bloc`'s own dedup. [lib/features/account/presentation/cubit/account_settings_cubit.dart:74-89]
- [x] [Review][Defer] Frozen spec-2-3 boundary violation ("No changes to `app_router.dart` or `vault_lock_screen.dart`") was committed anyway and accepted after the fact only in spec-2-3's own Spec Change Log — not disclosed anywhere in this file (spec-2-4), even though this commit (`3bb2d5d`, the only commit after `81d7509`) is the one that actually ships those changes alongside this story's own work. Process/governance concern (precedent for bypassing frozen boundaries as long as it's documented after the fact somewhere), not a functional defect in this story's own scope. [lib/core/navigation/app_router.dart] [lib/features/vault/presentation/screens/vault_lock_screen.dart] — deferred, pre-existing
- [x] [Review][Defer] No UX source-of-truth doc (`DESIGN.md`/`EXPERIENCE.md`/`prototype-extract.md`) documents the new biometric toggle, even though `epics.md`'s FR-7/acceptance criteria do — none of these planning files are touched by this diff, and Epic 8 (`epics.md:499`) will extend this same screen with no documented guidance to build on. [_bmad-output/planning-artifacts/ux-designs/ux-cerne-ciclo-b-2026-10-26/DESIGN.md] [_bmad-output/planning-artifacts/ux-designs/ux-cerne-ciclo-b-2026-10-26/EXPERIENCE.md] — deferred, pre-existing

**Dismissed as noise (4):** "no retry/fallback for a failed boot fetch" — contradicts the frozen spec's own explicit fire-and-forget/swallow-on-failure boundary, which mirrors `restoreSession()`'s established pattern; "the `true` default is an unverified assumption about the backend's default" — the frozen Boundaries explicitly mandate starting `true`, not a code choice open to second-guessing here; "extensive 'Review finding:' process narrative baked into production comments" — consistent, deliberate convention already established across every prior story in this codebase (2.1-2.3), not specific to this diff; "spec-2-4.md's own `status`/`review_loop_iteration` metadata disagrees with `sprint-status.yaml`" — this review's own Section 6 status sync resolves it, same as it did for spec-2-3.

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
