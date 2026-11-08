// The constructor keeps a public named param (`remoteDataSource`) distinct
// from the private field it initializes, matching `vault_repository_impl.
// dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/repositories/account_settings_repository.dart';
import '../datasources/account_remote_data_source.dart';

/// Owns the one broadcast `biometricEnabled` stream Story 2.4's AD-14-style
/// seam requires. Covers the I/O & Edge-Case Matrix exactly:
/// - boot fetch resolves `false`/`true` -> [currentBiometricEnabled]/
///   [biometricEnabledStream] updated to that value.
/// - boot fetch fails -> swallowed, [currentBiometricEnabled] unchanged.
/// - [setBiometricEnabled] -> flips immediately (optimistic), PATCH fires;
///   success leaves it flipped, failure reverts it and returns `Left`.
class AccountSettingsRepositoryImpl implements AccountSettingsRepository {
  AccountSettingsRepositoryImpl({
    required AccountRemoteDataSource remoteDataSource,
  }) : _remoteDataSource = remoteDataSource;

  final AccountRemoteDataSource _remoteDataSource;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Starts `true` (never `null`, Boundaries) — the single source of truth
  /// for both the vault gate and the Configurações toggle.
  bool _currentValue = true;

  /// spec-8-3 — starts `''` (Boundaries: "default ''"), set only from
  /// [fetchBiometricEnabled]'s own success branch (piggybacking on that
  /// call's response — no new network call) or from a successful
  /// [setDisplayName].
  String _currentDisplayName = '';

  /// spec-8-3 — same "starts `''`, boot-fetch piggyback" shape as
  /// [_currentDisplayName]; never written anywhere else — `PATCH
  /// /account/settings` rejects `email` (contract summary: "email is
  /// rejected").
  String _currentEmail = '';

  /// Review finding: without this, two overlapping calls — a double-tap
  /// toggle, or a boot [fetchBiometricEnabled] resolving while a
  /// [setBiometricEnabled] call is still in flight — let a stale call's
  /// revert/confirm stomp a newer call's already-settled value, because
  /// each call's own PATCH round-trip resolves independently of the
  /// others. Mirrors `VaultRepositoryImpl._submitPinGeneration`'s same
  /// fix for the exact same class of bug: every call captures the
  /// generation current at its OWN start; only the call whose captured
  /// generation still matches this field once its PATCH resolves is
  /// allowed to mutate [_currentValue]/emit — every other (superseded)
  /// call's result is discarded.
  int _generation = 0;

  /// spec-8-3 — [setDisplayName]'s own generation guard, same shape as
  /// [_generation] but kept separate (Boundaries): a name write and a
  /// biometric toggle/fetch are independent calls that must never
  /// supersede each other's in-flight state.
  int _nameGeneration = 0;

  @override
  bool get currentBiometricEnabled => _currentValue;

  @override
  String get currentDisplayName => _currentDisplayName;

  @override
  String get currentEmail => _currentEmail;

  @override
  Stream<bool> get biometricEnabledStream {
    // Same `Stream.multi` replay-to-late-listeners rationale as
    // `VaultRepositoryImpl.statusStream`/`SessionRepositoryImpl.
    // statusStream`: a listener that subscribes after construction still
    // immediately sees the cached current value rather than nothing until
    // the next emission.
    return Stream<bool>.multi((controller) {
      controller.add(_currentValue);
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  void _emit(bool value) {
    // Guards against `dispose()` (wired to `get_it`'s `sl.reset()`) racing
    // an in-flight `fetchBiometricEnabled()`/`setBiometricEnabled()` call —
    // mirrors `VaultRepositoryImpl._emit`'s own guard.
    if (_controller.isClosed) {
      return;
    }
    _currentValue = value;
    _controller.add(value);
  }

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async {
    final generation = ++_generation;
    // Code-review patch (spec-8-3): captured so the piggybacked
    // `displayName`/`email` write below can detect a `setDisplayName`
    // call that started *after* this fetch — without this, a stale fetch
    // resolving after a concurrent name save already succeeded would
    // silently overwrite the just-saved name/email back to this fetch's
    // own (older) values, the same class of bug `_generation` already
    // guards against for `currentBiometricEnabled`.
    final nameGeneration = _nameGeneration;
    final result = await _remoteDataSource.fetchSettings();
    return result.match(
      (failure) {
        // Swallowed, fire-and-forget like `SessionRepository.
        // restoreSession()` — `currentBiometricEnabled` stays exactly as it
        // was (I/O matrix: "Boot fetch fails").
        return left(failure);
      },
      (dto) {
        // spec-8-3 — same response, no new network call (Boundaries):
        // `_currentDisplayName`/`_currentEmail` piggyback on this already
        // in-flight fetch's own DTO. Code-review patch: only applied if no
        // `setDisplayName` call has started since this fetch began — a
        // concurrent name save that already resolved owns the name/email
        // fields from here on, and this now-stale piggyback must not
        // clobber it. Review finding: evaluated independently of (and
        // before) the `_generation` check below — a fetch superseded only
        // on its *biometric-toggle* generation (e.g. the double boot-time
        // call in `main.dart`/`CerneApp.initState()`) still carries a
        // perfectly valid, non-conflicting `displayName`/`email` that must
        // not be thrown away along with the discarded `biometricEnabled`
        // result.
        if (nameGeneration == _nameGeneration) {
          _currentDisplayName = dto.displayName;
          _currentEmail = dto.email;
        }
        // Review finding: a `setBiometricEnabled` call that started after
        // this fetch (and has therefore already bumped `_generation`) has
        // superseded it — this fetch's now-stale read must not clobber
        // whatever that newer call already settled on, and must not report
        // success either, since its result was discarded (mirrors
        // `setBiometricEnabled`'s own stale-generation branch).
        if (generation != _generation) {
          return left(
            const Failure.malformedResponse(
              message: AccountSettingsRepository.supersededMessage,
            ),
          );
        }
        _emit(dto.biometricEnabled);
        return right(unit);
      },
    );
  }

  @override
  Future<Either<Failure, Unit>> setDisplayName(String name) async {
    final generation = ++_nameGeneration;
    // spec-8-3 — not optimistic (Boundaries): unlike
    // `setBiometricEnabled`, `_currentDisplayName` only changes once the
    // PATCH below actually succeeds.
    final result = await _remoteDataSource.updateDisplayName(name);
    if (generation != _nameGeneration) {
      // Superseded by a newer overlapping `setDisplayName` call — same
      // "discard, don't clobber" rationale as `setBiometricEnabled`'s own
      // stale-generation branch, just on its own, separate counter.
      return left(
        const Failure.malformedResponse(
          message: AccountSettingsRepository.supersededMessage,
        ),
      );
    }
    return result.match((failure) => left(failure), (dto) {
      // Code-review patch: the response's own echoed `displayName` is the
      // source of truth, not the local `name` parameter — any backend-side
      // normalization (trimming, casing, etc.) must be reflected locally
      // rather than assuming the server stored exactly what was sent.
      _currentDisplayName = dto.displayName;
      return right(unit);
    });
  }

  @override
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled) async {
    final generation = ++_generation;
    final previous = _currentValue;
    // Optimistic flip — switches immediately, before the PATCH call below
    // even starts (RNF01, <100ms; Boundaries). Always applied: this call
    // is, by construction, the newest one at the moment it starts.
    _emit(enabled);
    final result = await _remoteDataSource.updateBiometricEnabled(enabled);
    if (generation != _generation) {
      // Review finding: superseded by a newer call (another toggle, or a
      // fetch) that started while this PATCH was still in flight — this
      // call's own confirm/revert must never run at this point; the
      // superseding call owns `_currentValue` from here on.
      return left(
        const Failure.malformedResponse(
          message: AccountSettingsRepository.supersededMessage,
        ),
      );
    }
    return result.match((failure) {
      // Revert on failure — the caller surfaces `failure.message` inline.
      _emit(previous);
      return left(failure);
    }, (_) => right(unit));
  }

  @override
  Future<Either<Failure, Unit>> deleteAccount() =>
      _remoteDataSource.deleteAccount();

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
