// The constructor keeps a public named param (`localAuthentication`)
// distinct from the private field it initializes, matching
// `session_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/vault_status.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../domain/vault_idle_timeout.dart';

/// Owns the one broadcast [VaultStatus] stream the epic's AD-14 seam
/// requires. Covers the I/O matrix (spec-2-1 + spec-2-2 + spec-2-3):
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
/// - spec-2-3: backgrounded (`AppLifecycleState.paused`) for >= 5 minutes
///   while [VaultStatus.unlocked], then resumed -> [VaultStatus.locked]
///   emitted via [didChangeAppLifecycleState]; below that threshold, or
///   while already locked, no emission at all.
///
/// Zero network calls anywhere in this class (Boundaries: "Vault makes zero
/// network calls") and never produces [Failure.authInvalid] (Boundaries:
/// reserved for password login) — every failure branch below maps only to
/// [Failure.malformedResponse]. The PIN is compared as a plain string
/// (Design Notes: `flutter_secure_storage` already encrypts at rest;
/// `package:crypto` isn't a pinned dependency) stored under [_pinStorageKey]
/// via the same [FlutterSecureStorage] instance
/// `SecureStorageAccessTokenProvider` uses for the access/refresh tokens.
class VaultRepositoryImpl
    with WidgetsBindingObserver
    implements VaultRepository {
  VaultRepositoryImpl({
    required LocalAuthentication localAuthentication,
    required FlutterSecureStorage secureStorage,
    DateTime Function() now = DateTime.now,
  }) : _localAuthentication = localAuthentication,
       _secureStorage = secureStorage,
       _now = now {
    // Story 2.3 — observes app-lifecycle transitions directly so idle
    // re-lock works with zero DI changes and zero new VaultRepository
    // methods. Removed in dispose() below. Safe only because
    // `WidgetsFlutterBinding.ensureInitialized()` (or an equivalent, e.g.
    // `TestWidgetsFlutterBinding.ensureInitialized()` in tests) must
    // already have run before this constructor executes — true today
    // because `get_it` constructs this lazily, well after `main()`'s own
    // binding initialization.
    //
    // Review finding: `WidgetsBinding.instance` itself throws an opaque
    // Flutter-internal assertion if no binding exists yet — caught here and
    // rethrown with a message that names the actual root cause, so any
    // future call site that breaks this ordering fails clearly instead of
    // opaquely.
    try {
      WidgetsBinding.instance.addObserver(this);
    } on FlutterError catch (error) {
      throw StateError(
        'VaultRepositoryImpl requires WidgetsFlutterBinding.ensureInitialized() '
        '(or TestWidgetsFlutterBinding.ensureInitialized() in tests) to run '
        'before construction. Original error: $error',
      );
    }
  }

  static const _pinStorageKey = 'vault_pin';

  final LocalAuthentication _localAuthentication;
  final FlutterSecureStorage _secureStorage;
  final DateTime Function() _now;
  final StreamController<VaultStatus> _statusController =
      StreamController<VaultStatus>.broadcast();

  /// Incremented at the start of every [submitPin] call. Review finding:
  /// the UI's own `.timeout()` only stops it from *waiting* — the call
  /// here keeps running — so a user-triggered retry after that UI timeout
  /// could otherwise race a still-in-flight earlier call against the same
  /// storage key, or let its stale result emit [VaultStatus.unlocked]
  /// behind the newer attempt's back. A call whose captured generation no
  /// longer matches this field by the time its [_secureStorage.read]
  /// resolves is superseded and must not mutate storage or emit.
  int _submitPinGeneration = 0;

  /// Set on `AppLifecycleState.paused`, read and cleared on
  /// `AppLifecycleState.resumed` (Boundaries: `inactive`/`hidden` are not
  /// "backgrounded" on their own — only this pair bounds iOS's actual
  /// background/foreground transition). `null` means either the app has
  /// never been backgrounded, or the last `paused`->`resumed` cycle already
  /// consumed it.
  DateTime? _backgroundedAt;

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
    if (status == VaultStatus.unlocked) {
      // Review finding: without this, a biometric/PIN call that resolves
      // while the app is still backgrounded (persistAcrossBackgrounding:
      // true covers exactly this) leaves the *original* `_backgroundedAt`
      // in place; if `resumed` then arrives >= 5 minutes after that
      // original timestamp, the idle check below immediately re-locks the
      // vault the instant it was unlocked. Any unlock always starts the
      // idle clock fresh instead.
      _backgroundedAt = null;
    }
    _lastStatus = status;
    _statusController.add(status);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Story 2.3's I/O & Edge-Case Matrix, exactly:
    // - `paused` -> record the backgrounded timestamp (only meaningful read
    //   on the next `resumed`).
    // - `resumed` with no prior `paused` recorded -> no-op (e.g. the very
    //   first lifecycle callback ever observed).
    // - `resumed` with elapsed time < 5 minutes -> no-op, `currentStatus`
    //   stays whatever it was.
    // - `resumed` with elapsed time >= 5 minutes AND `currentStatus` is
    //   currently `unlocked` -> emit `locked` exactly once; never
    //   redundantly if already `locked` (no duplicate emission).
    // `inactive`/`hidden` are intentionally ignored (Boundaries) — they
    // don't bound the real background/foreground transition on their own.
    if (state == AppLifecycleState.paused) {
      // Review finding: `??=` (not `=`) — keeps the *earliest* timestamp if
      // `paused` ever fires twice before a `resumed` consumes it, so a
      // lifecycle quirk can't reset the idle clock to a later start and
      // undercount real elapsed background time.
      _backgroundedAt ??= _now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt == null) {
        return;
      }
      final elapsed = _now().difference(backgroundedAt);
      if (elapsed >= vaultIdleTimeout && _lastStatus == VaultStatus.unlocked) {
        _emit(VaultStatus.locked);
      }
    }
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
    final generation = ++_submitPinGeneration;
    try {
      final storedPin = await _secureStorage.read(key: _pinStorageKey);
      if (generation != _submitPinGeneration) {
        // A newer `submitPin` call started while this one was still
        // awaiting `read` (e.g. the caller's own UI timed out and the user
        // retried) — never let this superseded attempt write a possibly
        // stale PIN or emit `unlocked` behind the newer attempt's back.
        return left(
          const Failure.malformedResponse(
            message: 'Superseded by a newer PIN attempt',
          ),
        );
      }
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
    WidgetsBinding.instance.removeObserver(this);
    await _statusController.close();
  }
}
