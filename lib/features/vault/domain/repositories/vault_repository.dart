import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/vault_status.dart';

/// The epic's ONE new DI-singleton access point for device-level access
/// (AD-14) — `core/navigation/app_router.dart`'s `_redirect` reads
/// [currentStatus] before it reads `SessionRepository.currentStatus`
/// (Boundaries: "`_redirect` checks `VaultStatus` before `SessionStatus`").
/// Mirrors `features/auth/domain/repositories/session_repository.dart`'s
/// shape, except [currentStatus] is never nullable (see [VaultStatus]'s own
/// doc) and there is no `restoreSession`-equivalent boot call — the vault
/// is always [VaultStatus.locked] until a successful [authenticate] call.
abstract class VaultRepository {
  /// Broadcast stream of the current vault status. Unlike
  /// `SessionRepository.statusStream`, this always has a value from the
  /// moment the repository is constructed ([VaultStatus.locked]) — a late
  /// subscriber still immediately replays that cached value, same
  /// `Stream.multi` rationale as the session repository's own stream.
  Stream<VaultStatus> get statusStream;

  /// The last status emitted on [statusStream], read synchronously —
  /// starts at [VaultStatus.locked] (never `null`, see [VaultStatus]'s own
  /// doc) and only a successful [authenticate] call ever flips it to
  /// [VaultStatus.unlocked].
  VaultStatus get currentStatus;

  /// Triggers the OS biometric prompt (`local_auth`, `biometricOnly: true`
  /// — Boundaries: "never set `biometricOnly: false`"). Zero network calls
  /// (Boundaries: "Vault makes zero network calls"); never produces
  /// [Failure.authInvalid] (reserved for password login) — any failure here
  /// (OS declines, cancels, or throws `LocalAuthException`) maps to
  /// [Failure.malformedResponse] instead, and [currentStatus] stays
  /// [VaultStatus.locked]. Only a `true` result flips [currentStatus] to
  /// [VaultStatus.unlocked] and emits it on [statusStream].
  Future<Either<Failure, Unit>> authenticate();

  /// Releases the underlying stream resource. Wired as `get_it`'s
  /// `dispose:` callback on registration, so `resetCoreDependencies()`
  /// (`sl.reset()`) closes it instead of leaking a `StreamController` on
  /// every test teardown.
  Future<void> dispose();
}
