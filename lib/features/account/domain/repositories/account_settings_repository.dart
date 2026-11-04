import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';

/// Story 2.4's one DI-singleton access point for the account's
/// `biometricEnabled` preference — mirrors `features/vault/domain/
/// repositories/vault_repository.dart`'s stream-plus-sync-getter shape
/// (AD-14), except the underlying source of truth is server-side (`PATCH
/// /account/settings`), not on-device.
///
/// [currentBiometricEnabled] is the single source both
/// `core/navigation/app_router.dart` (feeding `VaultLockScreen`'s
/// `attemptBiometricFirst`) and the Configurações toggle read — never a
/// second, independently-tracked copy of the same boolean.
abstract class AccountSettingsRepository {
  /// The exact [Failure.message] [setBiometricEnabled] returns when a call
  /// is discarded for being superseded by a newer one (the generation
  /// guard, `AccountSettingsRepositoryImpl._generation`) — an internal
  /// control-flow signal, not a real error, since the winning call already
  /// settled the value correctly by the time this one resolves.
  /// `AccountSettingsCubit` recognizes this exact string to suppress it
  /// from the UI rather than showing a raw, English, internal message.
  static const supersededMessage = 'Superseded by a newer preference update';

  /// Broadcast stream of the current `biometricEnabled` preference. Like
  /// `VaultRepository.statusStream`, this always has a value from the
  /// moment the repository is constructed (`true`) — a late subscriber
  /// still immediately replays that cached value.
  Stream<bool> get biometricEnabledStream;

  /// The last value emitted on [biometricEnabledStream], read
  /// synchronously — starts `true` (never `null`) so a cold boot before
  /// [fetchBiometricEnabled] resolves still degrades to "try biometric
  /// first" (Design Notes), never silent PIN-only.
  bool get currentBiometricEnabled;

  /// Boot-time read: `PATCH /account/settings` called with `{}` — no GET
  /// endpoint exists for this resource (Boundaries). A successful response
  /// updates [currentBiometricEnabled]/[biometricEnabledStream] to the
  /// server's value; any [Failure] is swallowed (fire-and-forget, like
  /// `SessionRepository.restoreSession()`) and leaves
  /// [currentBiometricEnabled] exactly as it was.
  Future<Either<Failure, Unit>> fetchBiometricEnabled();

  /// Story 2.4's optimistic toggle: [currentBiometricEnabled]/
  /// [biometricEnabledStream] flip to [enabled] immediately, before the
  /// `PATCH {"biometricEnabled": enabled}` call even starts (RNF01,
  /// <100ms) — then, on failure, revert back to the prior value and
  /// return `Left` so the caller can surface the `Failure`'s message. A
  /// successful PATCH leaves the optimistic value in place and returns
  /// `Right(unit)`.
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled);

  /// Releases the underlying stream resource. Wired as `get_it`'s
  /// `dispose:` callback on registration, same rationale as
  /// `VaultRepository.dispose()`/`SessionRepository.dispose()`.
  Future<void> dispose();
}
