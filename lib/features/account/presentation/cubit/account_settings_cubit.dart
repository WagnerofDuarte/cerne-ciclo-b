import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/account_settings_repository.dart';

/// Drives [AccountSettingsScreen]: just the one toggle's current value
/// (mirrored straight from [AccountSettingsRepository.biometricEnabledStream]
/// — the repository is the single source of truth, Boundaries) plus an
/// inline error message for a failed toggle.
class AccountSettingsState {
  const AccountSettingsState({
    required this.biometricEnabled,
    this.errorMessage,
    this.isSaving = false,
    this.displayName = '',
    this.email = '',
    this.isEditingName = false,
    this.nameDraft = '',
    this.isSavingName = false,
    this.nameErrorMessage,
  });

  final bool biometricEnabled;

  /// Set only once [AccountSettingsCubit.toggleBiometric]'s own PATCH call
  /// fails — the switch itself has already reverted via the repository's
  /// own stream by the time this is shown (I/O matrix: "Toggle fails ->
  /// switch reverts ... Failure.message shown inline").
  final String? errorMessage;

  /// Review finding: `true` for the duration of one [toggleBiometric] call
  /// — `account_settings_screen.dart` disables the `Switch` while this is
  /// `true`, so a double-tap can never start a second, overlapping
  /// `setBiometricEnabled` call in the first place (the repository's own
  /// generation guard is the backstop for every other overlap this can't
  /// prevent, e.g. a boot fetch racing a toggle).
  final bool isSaving;

  /// spec-8-3 — the profile name shown in display mode, read from
  /// `AccountSettingsRepository.currentDisplayName` at construction
  /// (Boundaries), then kept in sync by [AccountSettingsCubit.
  /// confirmEditingName]'s own success branch — never re-read from the
  /// repository afterwards.
  final String displayName;

  /// spec-8-3 — the account e-mail, read the same way as [displayName] and
  /// never written anywhere (not editable — "email is rejected").
  final String email;

  /// spec-8-3 — `true` while the name is in its inline-editable form (the
  /// pencil icon has become a check). Boundaries: "startEditingName()
  /// (draft = current name)".
  final bool isEditingName;

  /// spec-8-3 — the in-progress edit's own text, separate from
  /// [displayName] until [AccountSettingsCubit.confirmEditingName] commits
  /// it. Kept exactly as typed (not trimmed) so a failed save redisplays
  /// the same text the user left in the field (Boundaries: "draft kept").
  final String nameDraft;

  /// spec-8-3 — `true` for the duration of one
  /// [AccountSettingsCubit.confirmEditingName] PATCH call. Mirrors
  /// [isSaving]'s own role for the biometric toggle, kept as its own field
  /// (Boundaries: "never: merging name-edit into the toggle's own state").
  final bool isSavingName;

  /// spec-8-3 — set only once [AccountSettingsCubit.confirmEditingName]'s
  /// own PATCH call fails; the field stays editable with [nameDraft]
  /// unchanged (I/O matrix: "Failure -> stays editing, inline error, draft
  /// kept").
  final String? nameErrorMessage;

  AccountSettingsState copyWith({
    bool? biometricEnabled,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isSaving,
    String? displayName,
    String? email,
    bool? isEditingName,
    String? nameDraft,
    bool? isSavingName,
    String? nameErrorMessage,
    bool clearNameErrorMessage = false,
  }) {
    return AccountSettingsState(
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      isEditingName: isEditingName ?? this.isEditingName,
      nameDraft: nameDraft ?? this.nameDraft,
      isSavingName: isSavingName ?? this.isSavingName,
      nameErrorMessage: clearNameErrorMessage
          ? null
          : (nameErrorMessage ?? this.nameErrorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountSettingsState &&
          other.biometricEnabled == biometricEnabled &&
          other.errorMessage == errorMessage &&
          other.isSaving == isSaving &&
          other.displayName == displayName &&
          other.email == email &&
          other.isEditingName == isEditingName &&
          other.nameDraft == nameDraft &&
          other.isSavingName == isSavingName &&
          other.nameErrorMessage == nameErrorMessage);

  @override
  int get hashCode => Object.hash(
    biometricEnabled,
    errorMessage,
    isSaving,
    displayName,
    email,
    isEditingName,
    nameDraft,
    isSavingName,
    nameErrorMessage,
  );

  @override
  String toString() =>
      'AccountSettingsState(biometricEnabled: $biometricEnabled, '
      'errorMessage: $errorMessage, isSaving: $isSaving, '
      'displayName: $displayName, email: $email, '
      'isEditingName: $isEditingName, nameDraft: $nameDraft, '
      'isSavingName: $isSavingName, nameErrorMessage: $nameErrorMessage)';
}

/// Calls [AccountSettingsRepository] directly (no use-case — same small-
/// scope rationale `AuthCubit`'s own doc gives). [toggleBiometric] is the
/// I/O matrix's optimistic flip/revert, end to end: the repository itself
/// flips [AccountSettingsRepository.currentBiometricEnabled] immediately
/// and emits it on [AccountSettingsRepository.biometricEnabledStream] —
/// this cubit only mirrors that stream into its own [AccountSettingsState]
/// (subscribed once, at construction) and separately layers the
/// toggle-failure error message on top.
class AccountSettingsCubit extends Cubit<AccountSettingsState> {
  AccountSettingsCubit(this._repository)
    : super(
        AccountSettingsState(
          biometricEnabled: _repository.currentBiometricEnabled,
          // spec-8-3 — read once, at construction (Boundaries); never
          // re-read from the repository afterwards.
          displayName: _repository.currentDisplayName,
          email: _repository.currentEmail,
        ),
      ) {
    _subscription = _repository.biometricEnabledStream.listen((value) {
      // Review finding: `biometricEnabledStream`'s first delivery always
      // replays the exact same value the constructor above just read
      // synchronously — without this check, that replay was a redundant
      // duplicate emission (not skipped by `Cubit`'s own equal-state dedup,
      // which only applies once something has already been emitted),
      // forcing one pointless extra rebuild right after every screen mount.
      if (value == state.biometricEnabled) {
        return;
      }
      emit(state.copyWith(biometricEnabled: value));
    });
  }

  final AccountSettingsRepository _repository;
  late final StreamSubscription<bool> _subscription;

  Future<void> toggleBiometric(bool value) async {
    emit(state.copyWith(clearErrorMessage: true, isSaving: true));
    final result = await _repository.setBiometricEnabled(value);
    // Review finding: this cubit is a `get_it` lazy singleton with
    // `dispose: (cubit) => cubit.close()` — if `close()` runs while the
    // `await` above is still pending (e.g. `resetCoreDependencies()`
    // during a logout, once Epic 8 implements one), `emit()` below would
    // otherwise throw a `StateError` ("Cannot emit new states after
    // calling close"), unlike the repository-layer `_emit` methods in this
    // codebase, which already guard against the equivalent race.
    if (isClosed) {
      return;
    }
    result.match((failure) {
      // Review finding: a superseded call's `Left` is an internal
      // control-flow signal (`AccountSettingsRepository.
      // supersededMessage`), not a real error — the winning call already
      // settled the value correctly, so nothing should be shown; showing
      // `failure.message` unconditionally leaked that raw, English,
      // internal string into this otherwise fully Portuguese screen.
      if (failure.message == AccountSettingsRepository.supersededMessage) {
        emit(state.copyWith(isSaving: false));
        return;
      }
      emit(state.copyWith(errorMessage: failure.message, isSaving: false));
    }, (_) => emit(state.copyWith(isSaving: false)));
  }

  /// Review finding: [errorMessage] previously cleared only at the start of
  /// the *next* [toggleBiometric] call — since this cubit is a DI
  /// singleton that outlives any single Configurações visit, a failed
  /// toggle's error text would otherwise still be showing if the user
  /// left the screen and came back later with no new attempt made.
  /// `account_settings_screen.dart` calls this once, on mount, same
  /// "stale message must not linger unchanged" fix already applied to
  /// `vault_lock_screen.dart`'s own PIN-mismatch error, just anchored to
  /// screen-entry instead of attempt-start.
  void clearStaleError() {
    if (state.errorMessage != null) {
      emit(state.copyWith(clearErrorMessage: true));
    }
  }

  /// spec-8-3 — tapping the pencil icon (I/O matrix: "Tap pencil ->
  /// `isEditingName: false` -> Field replaces name, draft = current, icon
  /// -> check"). Also clears any leftover [AccountSettingsState.
  /// nameErrorMessage] from a previous failed attempt.
  void startEditingName() {
    emit(
      state.copyWith(
        isEditingName: true,
        nameDraft: state.displayName,
        clearNameErrorMessage: true,
      ),
    );
  }

  /// spec-8-3 — mirrors the field's own `onChanged`, kept as the single
  /// source [confirmEditingName] reads from.
  void updateNameDraft(String value) {
    emit(state.copyWith(nameDraft: value));
  }

  /// spec-8-3 — I/O matrix: "Tap away, not saving -> Reverts, draft
  /// discarded, no PATCH" / "Tap away, saving -> No-op, save completes".
  /// A no-op while [AccountSettingsState.isSavingName] (Boundaries) — the
  /// in-flight [confirmEditingName] call owns the eventual transition back
  /// to display mode.
  void cancelEditingName() {
    if (state.isSavingName) {
      return;
    }
    emit(state.copyWith(isEditingName: false, clearNameErrorMessage: true));
  }

  /// spec-8-3 — tapping the check icon. Trims [AccountSettingsState.
  /// nameDraft] only for the empty/unchanged comparison and the PATCH
  /// payload itself; an empty or unchanged draft reverts immediately with
  /// no PATCH (I/O matrix). Otherwise awaits
  /// `AccountSettingsRepository.setDisplayName` (not optimistic,
  /// Boundaries) — success reverts to display mode showing the new name;
  /// failure stays in edit mode with the draft kept and an inline error.
  Future<void> confirmEditingName() async {
    final trimmed = state.nameDraft.trim();
    if (trimmed.isEmpty || trimmed == state.displayName) {
      emit(state.copyWith(isEditingName: false, clearNameErrorMessage: true));
      return;
    }
    emit(state.copyWith(isSavingName: true, clearNameErrorMessage: true));
    final result = await _repository.setDisplayName(trimmed);
    // Same close()-race guard as toggleBiometric's own.
    if (isClosed) {
      return;
    }
    result.match(
      (failure) {
        // Same superseded-message filtering convention as toggleBiometric's
        // own failure branch — an internal control-flow signal, not a real
        // error to show.
        if (failure.message == AccountSettingsRepository.supersededMessage) {
          emit(state.copyWith(isSavingName: false));
          return;
        }
        emit(
          state.copyWith(
            isSavingName: false,
            nameErrorMessage: failure.message,
          ),
        );
      },
      (_) {
        emit(
          state.copyWith(
            isEditingName: false,
            isSavingName: false,
            displayName: trimmed,
            clearNameErrorMessage: true,
          ),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
