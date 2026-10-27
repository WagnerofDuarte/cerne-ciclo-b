import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/session_status.dart';

/// The epic's ONE new DI-singleton access point for session validity (AD) —
/// every later consumer (Story 1.5's overlay, Story 1.6's `go_router`
/// redirect, Epic 4/RF07) listens to [statusStream] rather than re-deriving
/// session validity from a raw 401 or a second stream (RNF09 — still
/// `Either<Failure, T>` for the one-shot [restoreSession] call).
abstract class SessionRepository {
  /// Broadcast stream of the current session status. Emits nothing until
  /// [restoreSession] (or a later story's own trigger) completes at least
  /// once — a `StreamBuilder` with no data yet is the brief-blank boot state
  /// `main.dart` relies on (RNF01's 300ms threshold).
  Stream<SessionStatus> get statusStream;

  /// Boot-time, unconditional refresh: exchanges any stored refresh token
  /// for a fresh pair via `auth-refresh`, persists the result, and emits the
  /// outcome on [statusStream]. No client-side expiry math — the server is
  /// the sole source of truth for validity.
  Future<Either<Failure, Unit>> restoreSession();

  /// Releases the underlying stream resource. Wired as `get_it`'s
  /// `dispose:` callback on registration, so `resetCoreDependencies()`
  /// (`sl.reset()`) closes it instead of leaking a `StreamController` on
  /// every test teardown.
  Future<void> dispose();
}
