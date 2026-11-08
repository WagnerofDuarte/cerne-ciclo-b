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

### Review Findings

- [x] [Review][Patch] `confirmEditingName()`'s success branch emits `displayName: trimmed` (the locally-sent, merely-trimmed string) instead of re-reading `_repository.currentDisplayName` — defeats the repository's own code-review patch that sets `_currentDisplayName` from the response's echoed `dto.displayName` so any backend-side normalization is reflected locally. The cubit never re-reads the repository after construction, so a divergence persists for the rest of the singleton's session. [account_settings_cubit.dart:291] — fixed: emits `_repository.currentDisplayName` instead; both fakes' `setDisplayName` now set `currentDisplayName` on success (configurable echo override), with a new cubit test proving the echoed value wins over the locally-sent one.
- [x] [Review][Patch] The new sibling `BlocListener<DashboardCubit, Resource<DashboardAggregate>>` added to catch the narrative-errors-before-aggregate-resolves race has no `listenWhen` — it re-announces "narrativa indisponível" on every subsequent `DashboardCubit` emission with `totalCount > 30` (e.g. each further entry save via `confirmedWrites`) for as long as the narrative stays in `ResourceError`, not just once for the missed transition the fix was written for. [account_settings_screen.dart:485-504] — fixed: added a `listenWhen` that only fires on the transition into `totalCount > 30`.
- [x] [Review][Patch] `_nameController` is created empty in `initState()` on every mount; the only sync (`BlocListener` on the `!previous.isEditingName && current.isEditingName` transition) fires on state *transitions*, not on initial build. Leaving Configurações mid-edit (e.g. via the back arrow, which never calls `cancelEditingName`) and reopening it shows a blank field while the cubit's singleton state still holds `isEditingName: true` with the old `nameDraft` — tapping the check icon in that state silently saves the stale, invisible draft rather than the (empty) field the user sees. [account_settings_screen.dart:52-57] — fixed: `initState` seeds the controller (text + cursor position) from the cubit's current state when already mid-edit.
- [x] [Review][Patch] `fetchBiometricEnabled()` checks `generation != _generation` and returns early *before* ever checking `nameGeneration == _nameGeneration` — a fetch superseded only on its biometric-toggle generation (e.g. the double boot-time call in `main.dart`/`CerneApp.initState()` racing past the 2s `main()` timeout) discards its own still-valid `displayName`/`email` piggyback too, even though no `setDisplayName` call happened in between. [account_settings_repository_impl.dart:111-144] — fixed: the `nameGeneration` piggyback now applies before the `generation` check, independent of whether the biometric-toggle generation was superseded.
- [x] [Review][Patch] No test uses `interceptAnnouncements` for the name-save-failure path — the sibling toggle-failure and narrative-failure tests in the same file all assert the accessibility channel receives the announcement, but the new "a failed save keeps the field editable..." test only checks `TextField`/error text, so a dropped or inverted `_announce` call on name-save failure would pass the full suite. [test/features/account/presentation/screens/account_settings_screen_test.dart (profile header group)] — fixed: added a dedicated test asserting the announcement via `interceptAnnouncements`.
- [x] [Review][Patch] `_FakeAccountSettingsRepository.setDisplayNameGate` is wired into the fake's `setDisplayName` but no test ever sets it — the saving-indicator (`CircularProgressIndicator`) and the "tap away while saving is a no-op" I/O-matrix row are proven only at the cubit level, never against the real screen widget, unlike every other row/AC in the matrix. [test/features/account/presentation/screens/account_settings_screen_test.dart:68-80] — fixed: added a widget test using the gate to prove the saving indicator shows and tap-away is a no-op mid-save.
- [x] [Review][Patch] The profile e-mail `Text` has no `maxLines`/`overflow` handling, unlike the adjacent name `Text` which was patched for exactly this (backend allows up to 80 chars) — a long e-mail can still wrap to multiple lines and misalign the row. [account_settings_screen.dart:220-224] — fixed: added matching `maxLines: 1`/`TextOverflow.ellipsis`.
- [x] [Review][Defer] `confirmEditingName()`'s `if (isClosed) return;` guard (same close()-race shape as `toggleBiometric`'s own) has no dedicated test — mirrors `toggleBiometric`'s own identical, also-untested guard, not a gap newly introduced for this feature. [account_settings_cubit.dart:267]
- [x] [Review][Defer] `_nameGeneration` only orders this client's own local state; it can't prevent the backend itself from processing two overlapping `setDisplayName` PATCH requests out of order, so a locally-"superseded" call's name could still be the one actually persisted server-side. Same residual risk class the existing `_generation` guard already carries for the biometric toggle, not fixable from the client given the frozen contract. [account_settings_repository_impl.dart:152-176]
- [x] [Review][Defer] The `DashboardNarrativeCubit.confirmedWrites` "no `onError` handler" observation is recorded nearly verbatim in both `deferred-work.md` and spec-8-2's own Review Findings, with no cross-reference between the two — a future fix to one is likely to leave the other stale. [_bmad-output/implementation-artifacts/deferred-work.md]
- [x] [Review][Defer] `tests/test-summary.md`'s hand-maintained pass-count tally has now drifted from the real `flutter test` count more than once (this diff's own edit corrects a prior miscounted baseline); nothing automated stops a future story's tally from drifting the same way again. [_bmad-output/implementation-artifacts/tests/test-summary.md]

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
