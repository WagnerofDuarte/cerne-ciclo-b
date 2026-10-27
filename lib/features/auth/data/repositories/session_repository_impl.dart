// The constructor keeps public named params (`remoteDataSource`,
// `accessTokenProvider`) distinct from the private fields they initialize,
// matching `auth_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/access_token_provider.dart';
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
  }) : _remoteDataSource = remoteDataSource,
       _accessTokenProvider = accessTokenProvider;

  final AuthRemoteDataSource _remoteDataSource;
  final AccessTokenProvider _accessTokenProvider;
  final StreamController<SessionStatus> _statusController =
      StreamController<SessionStatus>.broadcast();

  /// The last status emitted, so a consumer that subscribes *after* the
  /// first emission (a later `StreamBuilder`, or Story 1.5/1.6's own
  /// listener) still sees current state immediately rather than nothing
  /// until the next change — see [statusStream].
  SessionStatus? _lastStatus;

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
    _lastStatus = status;
    _statusController.add(status);
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

    if (refreshToken == null) {
      // Fresh install / post-logout: no network call at all.
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
  Future<void> dispose() => _statusController.close();
}
