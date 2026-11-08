---
title: 'Story 8.5: Account Deletion'
type: 'feature'
created: '2026-11-08'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '45b2dcd7ef5d7e7a5d8434ed4b1cfabbc3df43c4'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Configurações's "Apagar conta" is a dead action — no confirmation dialog, no `DELETE /account` call (epic-8-context.md Story 8.5; FR-43, RNF05, LGPD).

**Approach:** Add a destructive-styled `ConfirmationDialog` (red title/confirm button, `Cancelar` outline) triggered by a new "Apagar conta" button; on confirm, `AccountSettingsCubit.deleteAccount()` calls the new `AccountSettingsRepository.deleteAccount()` (`DELETE /account`), then reuses `logout()`'s existing lock+logout+clear sequence (extracted into a shared private helper) — same post-action destination as Story 8.4 (FR-42), no new navigation code.

## Boundaries & Constraints

**Always:**
- `ConfirmationDialog` gains optional `confirmButtonColor` (null → `colorPrimary`, unchanged default) and `cancelLabel`/`onCancel` (both null together → no cancel button, exact current session-expiry shape preserved). `AppButton` gains optional `backgroundColor`, consulted only for `AppButtonVariant.primary` (mirrors `textColor`'s existing "only consulted for textGhost" convention), null → `colorPrimary`.
- "Apagar conta": `AppButtonVariant.textGhost` + `textColor: colorError`, the scroll column's last child after "Sair" (prototype-extract.md:116). Disabled while `isDeletingAccount`.
- Tap opens `ConfirmationDialog` (title `'Apagar sua conta?'`, message on permanent/irreversible LGPD deletion, `titleColor`/`confirmButtonColor: colorError`, `barrierColor: colorScrimHeavy`, `confirmLabel: 'Apagar tudo'`, `cancelLabel: 'Cancelar'`) — reuses the same focus-trap/single-overlay widget session-expiry already uses (epic-8-context.md).
- `onCancel` pops the dialog only, no network call. `onConfirm` pops the dialog synchronously, then calls `AccountSettingsCubit.deleteAccount()`.
- `AccountSettingsRepository.deleteAccount()`/`_Impl` → `AccountRemoteDataSource.deleteAccount()` → `ApiClient.delete('account-delete', data: {'confirmation': 'DELETE'})`, success mapped to `Right(unit)` (response body unused).
- `AccountSettingsCubit.deleteAccount()`: guard re-entry via new `isDeletingAccount` (mirrors `isLoggingOut`). `Left` → reset `isDeletingAccount`, set `deleteAccountErrorMessage: failure.message` (inline, `colorError`, below the button — same convention as the biometric toggle's `errorMessage`, announced via the existing `_announce` + `BlocListener` pattern). `Right` → run the same lock+session-logout+cache-clear sequence `logout()` already performs, extracted into a shared private `_finishSession()` called by both (closes spec-8-4-logout.md's own Design Notes directive).
- No navigation code: the existing `app_router.dart` redirect (already watching `VaultStatus`/`SessionStatus`) lands on `/vault` once `_finishSession()` relocks — identical to Story 8.4.

**Ask First:** None.

**Never:** a dedicated "account deleted" screen (none exists; same destination as logout, prototype-extract.md:41,197); an undo/grace-period flow; auto-retrying a failed `DELETE /account`; changing `app_router.dart`; changing `ConfirmationDialog`'s single-overlay guard.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap "Apagar conta" | `isDeletingAccount: false` | destructive dialog opens (red title + "Apagar tudo", outline "Cancelar") | N/A |
| Tap "Cancelar" | dialog open | dialog closes, no network call, screen unchanged | N/A |
| Tap "Apagar tudo" | dialog open | dialog closes immediately; `account-delete` fires; on success vault relocks -> redirect to `/vault`; tokens + both Hive caches clear | N/A |
| `account-delete` fails (offline/expired/...) | any | dialog already closed; inline red error below "Apagar conta"; vault stays unlocked, nothing cleared | `Left.message` shown (unlike logout's swallowed failure) |
| Double-tap "Apagar conta" | `isDeletingAccount: true` | second tap no-ops (button disabled) | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/account/domain/repositories/account_settings_repository.dart:78-86` -- add `deleteAccount()` before `dispose()`
- `lib/features/account/data/repositories/account_settings_repository_impl.dart:211-214` -- implement `deleteAccount()` before `dispose()`
- `lib/features/account/data/datasources/account_remote_data_source.dart:34-48` -- add `deleteAccount()` (`_apiClient.delete('account-delete', data: {'confirmation': 'DELETE'})`)
- `lib/features/account/presentation/cubit/account_settings_cubit.dart:16-192,380-477` -- state fields `isDeletingAccount`/`deleteAccountErrorMessage`; extract `_finishSession()` from `logout()`; add `deleteAccount()`
- `lib/features/account/presentation/screens/account_settings_screen.dart:285-319,623-657` -- dialog builder (`_openDeleteAccountDialog`) + "Apagar conta" trigger/inline error, after "Sair"
- `lib/core/widgets/confirmation_dialog.dart:18-148` -- `confirmButtonColor`/`cancelLabel`/`onCancel` params + second button in `_Card`
- `lib/core/widgets/app_button.dart:18-140` -- `backgroundColor` param, primary variant only
- `docs/input/backend/api/openapi.yaml:1820-1840` (`account-delete`, bearerAuth, `{confirmation: 'DELETE'}`) + `README.md:46`
- `docs/input/prototype/cerne-prototype.html` (`askDelete`/`confirmDelete`/`cancelDelete` spans) + `prototype-extract.md:41,114,116`
- `_bmad-output/implementation-artifacts/spec-8-4-logout.md` Design Notes -- the shared-helper directive this story closes
- Tests: `test/core/widgets/{app_button,confirmation_dialog}_test.dart`, `test/features/account/{data/datasources/account_remote_data_source,data/repositories/account_settings_repository_impl,presentation/cubit/account_settings_cubit,presentation/screens/account_settings_screen}_test.dart`

## Tasks & Acceptance

**Execution:**
- [x] `app_button.dart` -- add `backgroundColor` (primary-only)
- [x] `confirmation_dialog.dart` -- add `confirmButtonColor`/`cancelLabel`/`onCancel`
- [x] `account_remote_data_source.dart` -- `deleteAccount()`
- [x] `account_settings_repository.dart`/`_impl.dart` -- `deleteAccount()`
- [x] `account_settings_cubit.dart` -- `isDeletingAccount`/`deleteAccountErrorMessage`, `_finishSession()` extraction, `deleteAccount()`
- [x] `account_settings_screen.dart` -- "Apagar conta" button, dialog wiring, inline error
- [x] Tests: I/O matrix + new unit coverage; extend `AppButton`/`ConfirmationDialog` fixtures for the new params

**Acceptance Criteria:**
- Given Configurações, when "Apagar conta" is tapped, then the destructive-variant dialog appears with a red title (epics.md Story 8.5 AC).
- Given the dialog, when "Apagar tudo" is confirmed, then `DELETE /account` fires and, on success, the account/data are gone and the user lands on the same destination as logout.
- Given "Cancelar" is tapped, then no network call fires and the screen is unchanged.

## Design Notes

`AppButton`'s primary-variant pressed-state overlay stays `colorPrimaryPressed` even when `backgroundColor` overrides the fill to `colorError` — the prototype's static mockup defines no distinct pressed-red value, and design_tokens.dart has none either; inventing one would violate "never hardcode a visual value outside design_tokens.dart." Accepted as a cosmetic, sub-200ms imperfection, not a blocking gap.

`deleteAccount()`'s success path still calls `_sessionRepository.logout()` (POST `auth-logout`) after the account is already server-side deleted — harmless and intentional: it's the same shared `_finishSession()` Story 8.4 built, and epic-8-context.md explicitly directs reusing it rather than branching.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test test/core/widgets test/features/account test/core/navigation` -- expected: all pass

## Suggested Review Order

**Orchestration (the "Apagar conta" confirm flow, end to end)**

- Entry point — guards re-entry, calls the new `deleteAccount()` on the repository, surfaces a failure's message (unlike `logout()`), runs the shared helper only on success; the whole body is now wrapped in one outer `try`/`finally` (review patch) so any throw still resets `isDeletingAccount`.
  [`account_settings_cubit.dart:455`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L455)
- The shared vault-lock + session-logout + dual-cache-clear sequence, extracted from `logout()` so both it and `deleteAccount()` call the exact same code (closes spec-8-4-logout.md's own Design Notes directive).
  [`account_settings_cubit.dart:405`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L405)
- `logout()` itself, now just a thin re-entry guard around `_finishSession()`.
  [`account_settings_cubit.dart:380`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L380)

**Destructive-dialog UI wiring**

- The dialog builder — red title/confirm, heavier scrim, `Cancelar` outline; `onConfirm` pops synchronously then calls `deleteAccount()`.
  [`account_settings_screen.dart:292`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L292)
- The "Apagar conta" trigger (disabled while in flight) and its inline `colorError` failure text below it.
  [`account_settings_screen.dart:639`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L639)

**Shared widget extensions (reused by the dialog)**

- The `cancelLabel`/`onCancel` pairing guard — review patch, fails loudly instead of silently dropping the cancel button.
  [`confirmation_dialog.dart:32`](../../lib/core/widgets/confirmation_dialog.dart#L32)
- The confirm button's color override plus the new, conditionally-rendered outline cancel button.
  [`confirmation_dialog.dart:245`](../../lib/core/widgets/confirmation_dialog.dart#L245)
- `AppButton`'s `backgroundColor` override — primary variant only, every other call site unaffected.
  [`app_button.dart:78`](../../lib/core/widgets/app_button.dart#L78)

**Network call (`DELETE /account`)**

- The real HTTP call — bearerAuth, exactly `{"confirmation": "DELETE"}`, body discarded on success.
  [`account_remote_data_source.dart:40`](../../lib/features/account/data/datasources/account_remote_data_source.dart#L40)
- The repository interface's new method — no local state to update, unlike `setBiometricEnabled`/`setDisplayName`.
  [`account_settings_repository.dart:84`](../../lib/features/account/domain/repositories/account_settings_repository.dart#L84)
- The plain passthrough implementation.
  [`account_settings_repository_impl.dart:212`](../../lib/features/account/data/repositories/account_settings_repository_impl.dart#L212)

**Tests**

- The cubit's full I/O matrix — re-entry, success running `_finishSession`, failure surfacing the message, the outer `try`/`finally`'s throw-safety.
  [`account_settings_cubit_test.dart:127`](../../test/features/account/presentation/cubit/account_settings_cubit_test.dart#L127)
- The screen's Acceptance Criteria + I/O matrix against the real widget tree (dialog appearance, Cancelar no-op, confirm-then-relock, failure's inline error).
  [`account_settings_screen_test.dart:1478`](../../test/features/account/presentation/screens/account_settings_screen_test.dart#L1478)
- `ConfirmationDialog`'s new cancel-button/assert coverage.
  [`confirmation_dialog_test.dart:280`](../../test/core/widgets/confirmation_dialog_test.dart#L280)
- `AppButton.backgroundColor`'s primary-only scoping.
  [`app_button_test.dart:95`](../../test/core/widgets/app_button_test.dart#L95)
- The real `account-delete` HTTP call, exact endpoint/body, success/failure mapping.
  [`account_remote_data_source_test.dart:232`](../../test/features/account/data/datasources/account_remote_data_source_test.dart#L232)
- The repository's passthrough, proved against a mocked data source.
  [`account_settings_repository_impl_test.dart:619`](../../test/features/account/data/repositories/account_settings_repository_impl_test.dart#L619)
