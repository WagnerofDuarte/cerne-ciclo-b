// The constructor keeps a public named param (`localAuthentication`)
// distinct from the private field it initializes, matching
// `session_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/vault_status.dart';
import '../../domain/repositories/vault_repository.dart';

/// Owns the one broadcast [VaultStatus] stream the epic's AD-14 seam
/// requires. Covers the I/O matrix (spec-2-1 + spec-2-2):
/// - biometrics succeed -> [VaultStatus.unlocked] emitted, `Right(unit)`.
/// - biometrics fail/cancelled/unavailable (`authenticate()` returns
///   `false`, or throws `LocalAuthException`, including any OS lockout) ->
///   status stays [VaultStatus.locked], `Left(Failure.
///   malformedResponse(...))` — every one of those cases routes the caller
///   to [submitPin] next (spec-2-2), with no code-specific branch needed
///   here since the generic catches below already cover lockout.
/// - [submitPin], no PIN stored yet -> stores it, [VaultStatus.unlocked]
///   emitted, `Right(unit)`.
/// - [submitPin], stored PIN matches -> [VaultStatus.unlocked] emitted,
///   `Right(unit)`.
/// - [submitPin], stored PIN mismatch -> status stays locked, `Left(Failure.
///   malformedResponse(...))`, always retryable (no attempt cap).
///
/// Zero network calls anywhere in this class (Boundaries: "Vault makes zero
/// network calls") and never produces [Failure.authInvalid] (Boundaries:
/// reserved for password login) — every failure branch below maps only to
/// [Failure.malformedResponse]. The PIN is compared as a plain string
/// (Design Notes: `flutter_secure_storage` already encrypts at rest;
/// `package:crypto` isn't a pinned dependency) stored under [_pinStorageKey]
/// via the same [FlutterSecureStorage] instance
/// `SecureStorageAccessTokenProvider` uses for the access/refresh tokens.
class VaultRepositoryImpl implements VaultRepository {
  VaultRepositoryImpl({
    required LocalAuthentication localAuthentication,
    required FlutterSecureStorage secureStorage,
  }) : _localAuthentication = localAuthentication,
       _secureStorage = secureStorage;

  static const _pinStorageKey = 'vault_pin';

  final LocalAuthentication _localAuthentication;
  final FlutterSecureStorage _secureStorage;
  final StreamController<VaultStatus> _statusController =
      StreamController<VaultStatus>.broadcast();

  /// The last status emitted. Starts at [VaultStatus.locked] — not
  /// nullable, see [VaultStatus]'s own doc — so [currentStatus] is correct
  /// synchronously from construction, with no async warm-up step.
  VaultStatus _lastStatus = VaultStatus.locked;

  @override
  VaultStatus get currentStatus => _lastStatus;

  @override
  Stream<VaultStatus> get statusStream {
    // Same `Stream.multi` replay-to-late-listeners rationale as
    // `SessionRepositoryImpl.statusStream`: a listener that subscribes
    // after construction (but before any [authenticate] call) still
    // immediately sees the cached [_lastStatus] ([VaultStatus.locked])
    // rather than nothing until the next emission.
    return Stream<VaultStatus>.multi((controller) {
      controller.add(_lastStatus);
      final subscription = _statusController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  void _emit(VaultStatus status) {
    // Guards against `dispose()` (wired to `get_it`'s `sl.reset()`) racing
    // an in-flight `authenticate()` call — mirrors
    // `SessionRepositoryImpl._emit`'s own guard.
    if (_statusController.isClosed) {
      return;
    }
    _lastStatus = status;
    _statusController.add(status);
  }

  @override
  Future<Either<Failure, Unit>> authenticate() async {
    try {
      // `biometricOnly: true` (Boundaries/Design Notes) — never lets the
      // OS's own device-passcode UI satisfy this call, which would bypass
      // Cerne's own PIN screen (Story 2.2) entirely.
      // `persistAcrossBackgrounding: true` so a backgrounding mid-prompt
      // (e.g. an incoming call) retries on foreground instead of failing
      // outright.
      final success = await _localAuthentication.authenticate(
        localizedReason: 'Autentique-se para acessar o Cerne',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (success) {
        _emit(VaultStatus.unlocked);
        return right(unit);
      }
      // A `false` result (declined/unavailable, no exception) — status
      // stays `locked`; never `Failure.authInvalid` (Boundaries: reserved
      // for password login).
      return left(
        const Failure.malformedResponse(
          message: 'Biometric authentication was not successful',
        ),
      );
    } on LocalAuthException catch (error) {
      // Covers cancellation, no enrolled biometrics, hardware unavailable,
      // etc. (RNF09: never let a platform exception escape unmapped).
      return left(Failure.malformedResponse(message: error.toString()));
    } catch (error) {
      // Any other thrown platform exception (e.g. the plugin's channel
      // itself failing) must never escape unmapped either (RNF09) — fail
      // closed, same as the documented `LocalAuthException` branch above,
      // mirroring `SessionRepositoryImpl.restoreSession()`'s own plain
      // `catch`.
      return left(Failure.malformedResponse(message: error.toString()));
    }
  }

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async {
    try {
      final storedPin = await _secureStorage.read(key: _pinStorageKey);
      // No PIN-creation screen exists anywhere in `docs/input/` (Design
      // Notes) — the first ever `submitPin` call sets the stored PIN
      // instead of comparing against one.
      if (storedPin == null) {
        await _secureStorage.write(key: _pinStorageKey, value: pin);
        _emit(VaultStatus.unlocked);
        return right(unit);
      }
      if (storedPin == pin) {
        _emit(VaultStatus.unlocked);
        return right(unit);
      }
      // Mismatch — status stays `locked`, no attempt cap (Boundaries: "PIN
      // has no attempt cap — always retryable"); never `Failure.authInvalid`
      // (reserved for password login), same rationale as `authenticate()`.
      return left(
        const Failure.malformedResponse(
          message: 'PIN did not match the stored PIN',
        ),
      );
    } catch (error) {
      // A thrown platform exception from the secure-storage channel must
      // never escape unmapped either (RNF09) — fail closed, same as
      // `authenticate()`'s own plain `catch`.
      return left(Failure.malformedResponse(message: error.toString()));
    }
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
  }
}
