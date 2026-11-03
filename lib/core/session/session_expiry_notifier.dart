import 'dart:async';

/// Story 1.5 — lets `core/network`'s `ApiClient` signal a mid-session
/// `AUTH_EXPIRED` without importing anything from `features/auth` (RNF06:
/// the domain/data layers of a feature are the only things allowed to know
/// about each other across that boundary, never the other way from core).
/// `SessionRepositoryImpl` is the one bridge that turns an event on
/// [expiredEvents] into the epic's single `SessionStatus.expired` value on
/// its own `statusStream` (Design Notes).
///
/// Pure Dart, no Flutter import — same constraint `ApiClient`/`Failure`
/// already hold in `core/`.
abstract class SessionExpiryNotifier {
  /// Broadcast stream of expiry events. Unlike `SessionRepository
  /// .statusStream`, this carries no replay semantics: it is a one-shot
  /// signal per expiry, not a status a late subscriber needs to catch up
  /// on — only `SessionRepositoryImpl`'s single long-lived subscription
  /// (wired at construction) is expected to listen.
  Stream<void> get expiredEvents;

  /// Signals that the current session just expired mid-use (a non-boot
  /// `AUTH_EXPIRED` response). Never throws.
  void notifyExpired();

  /// Releases the underlying stream resource.
  Future<void> dispose();
}

/// Default implementation — a broadcast `StreamController` wrapped behind
/// the port above.
class SessionExpiryNotifierImpl implements SessionExpiryNotifier {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get expiredEvents => _controller.stream;

  @override
  void notifyExpired() {
    // Guards against a call racing `dispose()` (wired to `get_it`'s
    // `sl.reset()`) — without this, a late `.add()` after `.close()` would
    // throw an unhandled `StateError` instead of just being a no-op on an
    // already-torn-down notifier (same rationale as `SessionRepositoryImpl
    // ._emit`).
    if (_controller.isClosed) {
      return;
    }
    _controller.add(null);
  }

  @override
  Future<void> dispose() => _controller.close();
}
