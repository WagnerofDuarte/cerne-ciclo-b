---
title: 'Story 8.3: Profile Name Editing'
type: 'feature'
created: '2026-11-07'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'dd59fc845883a9e56ace167dadcdb435744ecf50'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Configurações shows no avatar/name/email (still the Story 2.4 toggle-only stub) and has no way to edit the display name (epic-8-context.md's Story 8.3 scope).

**Approach:** Add a profile header (52dp avatar + name/email) above the biometric toggle. A pencil icon switches the name to an inline `AppTextField`; it becomes a check that saves via the existing `account-settings-update` PATCH and reverts to display mode. Tapping away unconfirmed reverts without saving.

## Boundaries & Constraints

**Always:**
- `AccountSettingsDto` decodes `displayName`/`email` too (required strings), full-contract-decode precedent as `DashboardNarrativeDto`.
- No new network call: `fetchBiometricEnabled()`'s success branch also sets new `_currentDisplayName`/`_currentEmail` (default `''`) from that response.
- New `setDisplayName(String)`: own `_nameGeneration` guard (shape of `setBiometricEnabled`'s `_generation`, kept separate), **not optimistic** — await `AccountRemoteDataSource.updateDisplayName` (`{'displayName': name}`), set `_currentDisplayName` only on success.
- Cubit reads `displayName`/`email` from the repository at construction. New state: `isEditingName`, `nameDraft`, `isSavingName`, `nameErrorMessage`. New methods: `startEditingName()` (draft = current name), `updateNameDraft()`, `cancelEditingName()` (no-op while saving), `confirmEditingName()` — trims draft; empty/unchanged reverts with no PATCH; otherwise saves, staying in edit mode with the error on failure (draft kept) or reverting with the new name on success.
- Screen: header is the first scroll-`Column` child, above the toggle. `Avatar(size: AvatarSize.large)`, caller derives initials (first letter of first + last word). Name: `textTitleSm`+`colorTextPrimary`. Email: `dashboardNarrativeTextStyle`+`colorTextSecondary`. Icon: `Icons.edit`/`Icons.check`, `dialogIconSize`, `colorPrimary`, in `InkWell`+`ConstrainedBox(minHeight/minWidth: insertionModalTapTargetMin)` (tap-target fix, same as spec-8-2's retry link). Field + check icon in one `TapRegion(onTapOutside: cancelEditingName)`. Field: `AppTextField(controller, errorText: nameErrorMessage)`, no label/hint.
- `_announce` fires on a save failure, same `BlocListener` convention as the toggle's error.
- Keep `fetchBiometricEnabled()`'s name even though it now also sets `displayName`/`email` — renaming ripples into `main.dart`/`vault_lock_screen.dart` for no functional gain.

**Ask First:** None.

**Never:** a second fetch for displayName/email; an optimistic flip for the name; persona/logout/delete UI (Stories 8.4/8.5); merging name-edit into the toggle's own state.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap pencil | `isEditingName: false` | Field replaces name, draft = current, icon -> check | N/A |
| Confirm, changed non-empty name | tap check | PATCH, saving indicator, success -> display mode, new name | Failure -> stays editing, inline error, draft kept |
| Confirm, empty/unchanged draft | tap check | Reverts immediately, no PATCH | N/A |
| Tap away, not saving | outside tap | Reverts, draft discarded, no PATCH | N/A |
| Tap away, saving | outside tap | No-op, save completes | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/account/data/models/account_settings_dto.dart` (+ `.g.dart`) -- add `displayName`/`email`
- `lib/features/account/data/datasources/account_remote_data_source.dart:11-47` -- add `updateDisplayName`, mirrors `updateBiometricEnabled`
- `lib/features/account/domain/repositories/account_settings_repository.dart:15-58` -- add `currentDisplayName`/`currentEmail`/`setDisplayName`
- `lib/features/account/data/repositories/account_settings_repository_impl.dart:20-139` -- fields + boot-fetch piggyback + `setDisplayName`
- `lib/features/account/presentation/cubit/account_settings_cubit.dart` -- state/methods per Boundaries
- `lib/features/account/presentation/screens/account_settings_screen.dart:104-120` -- header, `TapRegion`, initials helper, `_announce`
- `lib/core/widgets/avatar.dart` / `app_text_field.dart` -- reused as-is (first real `AvatarSize.large` consumer)
- `docs/input/backend/api/openapi.yaml:1737-1819` -- `PATCH /account/settings` (frozen), `displayName` optional, `minLength:1`/`maxLength:80`; `README.md:45` maps it to `account-settings-update`
- `docs/input/prototype/prototype-extract.md:116` + raw prototype `toggleEditProfile`/`saveProfile`/`editIcon` -- pencil/check UX source
- `_bmad-output/implementation-artifacts/epic-8-context.md` -- authoritative AC source (no FR in `requirements.md` covers this)
- `test/features/account/**` -- extend `_FakeAccountSettingsRepository` + new coverage

## Tasks & Acceptance

**Execution:**
- [x] `account_settings_dto.dart` (+ `.g.dart`) -- decode `displayName`/`email`
- [x] `account_remote_data_source.dart` -- `updateDisplayName`
- [x] `account_settings_repository.dart`/`_impl.dart` -- getters + `setDisplayName`, boot-fetch piggyback
- [x] `account_settings_cubit.dart` -- edit/draft/save/cancel state machine
- [x] `account_settings_screen.dart` -- header, inline edit, `TapRegion`, tap-target fix, announcement
- [x] Tests: I/O matrix + the 3 RNF09 failure types for `updateDisplayName`; update existing fakes for the widened interface

**Acceptance Criteria:**
- Given display mode, when the pencil is tapped, then the name becomes editable (pre-filled) and the icon becomes a check.
- Given a changed non-empty draft, when the check is tapped and save succeeds, then the screen shows the new name in display mode.
- Given a save fails, then the field stays editable with the typed text and an inline error.
- Given an unconfirmed edit, when the user taps outside the field/icon, then the screen reverts with no change sent.

## Verification

**Commands:**
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- expected: DTO regenerated, no conflicts
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test test/features/account` -- expected: all pass

**Manual checks (if no CLI):**
- Open Configurações; edit through success/failure/tap-away/empty-draft paths per the I/O matrix — widget tests stand in for no device/simulator.

## Suggested Review Order

**Edit/draft/save/cancel state machine**

- Entry point — the check-icon tap: trims the draft, skips the PATCH for an empty/unchanged name, otherwise saves and resolves to the new name or an inline error.
  [`account_settings_cubit.dart:258`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L258)
- Pencil-tap: seeds the draft from the current name, clears any leftover error.
  [`account_settings_cubit.dart:223`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L223)
- Tap-away/cancel: reverts with no PATCH, but is a no-op while a save is already in flight.
  [`account_settings_cubit.dart:244`](../../lib/features/account/presentation/cubit/account_settings_cubit.dart#L244)

**Repository write path & generation guards (code-review patch)**

- `setDisplayName`'s own, separate generation counter — not optimistic, and now sets `_currentDisplayName` from the response's own echoed value rather than the locally-sent one.
  [`account_settings_repository_impl.dart:152`](../../lib/features/account/data/repositories/account_settings_repository_impl.dart#L152)
- The boot-fetch piggyback — captures `_nameGeneration` at its own start so a concurrent, already-succeeded `setDisplayName` can never be clobbered by a stale fetch resolving afterward.
  [`account_settings_repository_impl.dart:102`](../../lib/features/account/data/repositories/account_settings_repository_impl.dart#L102)

**Contract widening**

- `AccountSettingsDto` now decodes `displayName`/`email` as required strings, same full-contract-decode precedent as `DashboardNarrativeDto`.
  [`account_settings_dto.dart:16`](../../lib/features/account/data/models/account_settings_dto.dart#L16)
- The new write call, mirroring `updateBiometricEnabled`'s own shape.
  [`account_remote_data_source.dart:31`](../../lib/features/account/data/datasources/account_remote_data_source.dart#L31)

**Inline-edit UI**

- The profile header: avatar + name/email, inserted as the scroll column's first child above the toggle.
  [`account_settings_screen.dart:204`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L204)
- The pencil/field-and-check row, including the `TapRegion` that scopes tap-away-to-revert to exactly the field+icon pair.
  [`account_settings_screen.dart:109`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L109)
- Initials extraction — grapheme-cluster aware (`.characters.first`), a code-review patch over the original surrogate-pair-unsafe `substring(0,1)`.
  [`account_settings_screen.dart:88`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L88)

**Tests**

- The full inline-edit I/O & Edge-Case Matrix against the real cubit.
  [`account_settings_cubit_test.dart`](../../test/features/account/presentation/cubit/account_settings_cubit_test.dart)
- The four Acceptance Criteria proved against the real screen widget, via a profile-aware pump helper.
  [`account_settings_screen_test.dart`](../../test/features/account/presentation/screens/account_settings_screen_test.dart)
- The stale-fetch-vs-saved-name race and response-echo-wins regressions added during code review.
  [`account_settings_repository_impl_test.dart`](../../test/features/account/data/repositories/account_settings_repository_impl_test.dart)
