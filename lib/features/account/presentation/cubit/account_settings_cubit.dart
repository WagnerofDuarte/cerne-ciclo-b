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

  AccountSettingsState copyWith({
    bool? biometricEnabled,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isSaving,
  }) {
    return AccountSettingsState(
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AccountSettingsState &&
          other.biometricEnabled == biometricEnabled &&
          other.errorMessage == errorMessage &&
          other.isSaving == isSaving);

  @override
  int get hashCode => Object.hash(biometricEnabled, errorMessage, isSaving);

  @override
  String toString() =>
      'AccountSettingsState(biometricEnabled: $biometricEnabled, '
      'errorMessage: $errorMessage, isSaving: $isSaving)';
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

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
