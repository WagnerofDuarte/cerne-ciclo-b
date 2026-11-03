// The constructor keeps public named params (`remoteDataSource`,
// `accessTokenProvider`) distinct from the private fields they initialize,
// matching `auth_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/access_token_provider.dart';
import '../../../../core/session/session_expiry_notifier.dart';
import '../../domain/entities/session_status.dart';
import '../../domain/repositories/session_repository.dart';
import '../datasources/auth_remote_data_source.dart';

/// Owns the one broadcast [SessionStatus] stream the epic's AD requires.
/// [restoreSession] is unconditional — no client-side expiry math — and
/// covers the I/O matrix (spec-1-4):
/// - no stored refresh token -> no network call, emits `unauthenticated`
///   immediately.
/// - stored token, backend accepts -> new pair persisted via `saveSession`,
///   emits `authenticated`.
/// - stored token, backend reports `AUTH_EXPIRED`/`AUTH_INVALID` (dead
///   token) -> `clearSession`, emits `unauthenticated`.
/// - stored token, any other failure (offline/timeout/...) -> fail-closed:
///   emits `unauthenticated` WITHOUT clearing storage, so the next boot
///   retries naturally.
class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl({
    required AuthRemoteDataSource remoteDataSource,
    required AccessTokenProvider accessTokenProvider,
    required SessionExpiryNotifier sessionExpiryNotifier,
  }) : _remoteDataSource = remoteDataSource,
       _accessTokenProvider = accessTokenProvider,
       _sessionExpiryNotifier = sessionExpiryNotifier {
    // Story 1.5 — the one bridge from `core`'s expiry signal onto this
    // feature's own `SessionStatus` stream (Design Notes). Subscribed for
    // this repository's whole lifetime; cancelled in [dispose].
    _expirySubscription = _sessionExpiryNotifier.expiredEvents.listen(
      (_) => _onSessionExpired(),
      // Mirrors `statusStream`'s own internal subscription a few lines
      // below: no current `SessionExpiryNotifier` implementation ever
      // errors, but without this, a future one that did would surface as
      // an unhandled zone exception instead of just being dropped here.
      onError: (_, _) {},
    );
  }

  final AuthRemoteDataSource _remoteDataSource;
  final AccessTokenProvider _accessTokenProvider;
  final SessionExpiryNotifier _sessionExpiryNotifier;
  late final StreamSubscription<void> _expirySubscription;
  final StreamController<SessionStatus> _statusController =
      StreamController<SessionStatus>.broadcast();

  /// The last status emitted, so a consumer that subscribes *after* the
  /// first emission (a later `StreamBuilder`, or Story 1.5/1.6's own
  /// listener) still sees current state immediately rather than nothing
  /// until the next change — see [statusStream].
  SessionStatus? _lastStatus;

  @override
  SessionStatus? get currentStatus => _lastStatus;

  @override
  void markAuthenticated() => _emit(SessionStatus.authenticated);

  @override
  Stream<SessionStatus> get statusStream {
    // `Stream.multi` runs this callback once per listener (and, with
    // `isBroadcast: true`, supports more than one simultaneously) — each
    // new listener synchronously gets the cached last status (if any)
    // before being attached to the live broadcast controller for whatever
    // comes next. This is this story's whole reason to not just expose
    // `_statusController.stream` directly: a plain broadcast stream only
    // ever delivers *future* events to a listener that joins late.
    return Stream<SessionStatus>.multi((controller) {
      final last = _lastStatus;
      if (last != null) {
        controller.add(last);
      }
      final subscription = _statusController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  void _emit(SessionStatus status) {
    // Guards against `dispose()` (wired to `get_it`'s `sl.reset()`) racing
    // an in-flight `restoreSession()` call — without this, a late `.add()`
    // after `.close()` would throw an unhandled `StateError` instead of
    // just being a no-op on an already-torn-down repository.
    if (_statusController.isClosed) {
      return;
    }
    _lastStatus = status;
    _statusController.add(status);
  }

  /// "Always" boundary — a mid-session expiry only ever matters while the
  /// user is currently [SessionStatus.authenticated]; any other current
  /// status (not yet decided at boot, already unauthenticated/logged out,
  /// or already [SessionStatus.expired] from an earlier event) is a
  /// silent no-op — covers both the "expiry while not authenticated"
  /// post-logout race and the "already-open overlay" double-event case in
  /// the I/O matrix (a second event here never re-emits once [_lastStatus]
  /// is already [SessionStatus.expired]).
  void _onSessionExpired() {
    if (_lastStatus == SessionStatus.authenticated) {
      _emit(SessionStatus.expired);
    }
  }

  @override
  Future<Either<Failure, Unit>> restoreSession() async {
    String? refreshToken;
    try {
      refreshToken = await _accessTokenProvider.readRefreshToken();
    } catch (error) {
      // A thrown platform exception from the native secure-storage channel
      // must never escape unmapped (RNF09) — fail closed, same as any other
      // unreadable session.
      _emit(SessionStatus.unauthenticated);
      return left(Failure.malformedResponse(message: error.toString()));
    }

    if (refreshToken == null || refreshToken.isEmpty) {
      // Fresh install / post-logout (null), or a stored-but-empty token
      // (the backend response schema has no `minLength` on `refreshToken`,
      // so an empty string is a theoretically valid stored value) — either
      // way, no network call: `auth-refresh`'s own request schema requires
      // `minLength: 1`, so an empty token would only fail server-side.
      _emit(SessionStatus.unauthenticated);
      return left(
        const Failure.authExpired(message: 'No stored session to restore'),
      );
    }

    final result = await _remoteDataSource.refresh(refreshToken);
    return result.match(
      (failure) async {
        // Only a backend-confirmed dead token clears storage; any other
        // failure (offline, timeout, malformed response, ...) leaves it
        // untouched so the next boot retries naturally.
        if (failure is AuthExpired || failure is AuthInvalid) {
          try {
            await _accessTokenProvider.clearSession();
          } catch (_) {
            // Best-effort clear — the session is already being treated as
            // unauthenticated below regardless of whether this succeeds.
          }
        }
        _emit(SessionStatus.unauthenticated);
        return left(failure);
      },
      (session) async {
        try {
          await _accessTokenProvider.saveSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
          );
        } catch (error) {
          _emit(SessionStatus.unauthenticated);
          return left(Failure.malformedResponse(message: error.toString()));
        }
        _emit(SessionStatus.authenticated);
        return right(unit);
      },
    );
  }

  @override
  Future<void> dispose() async {
    await _expirySubscription.cancel();
    await _statusController.close();
  }
}
