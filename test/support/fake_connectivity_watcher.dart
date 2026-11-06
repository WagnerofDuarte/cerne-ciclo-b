import 'dart:async';

import 'package:cerne/features/chat/domain/services/connectivity_watcher.dart';

/// A controllable fake `ConnectivityWatcher` — shared across every test
/// that constructs a `ChatCubit` directly (never through real DI), mirroring
/// every other hand-rolled fake domain service in this suite (no mocktail
/// stub needed: every caller just wants to push `true`/`false` and assert
/// the cubit's reaction). Emits nothing until [emit] is called — a test
/// that never exercises offline/online behavior never has to drive it at
/// all, and `ChatCubit`'s own `_isOffline` simply stays at its `false`
/// default.
class FakeConnectivityWatcher implements ConnectivityWatcher {
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> watch() => _controller.stream;

  /// Pushes a new online ([isOnline] `true`) / offline (`false`) reading.
  void emit(bool isOnline) => _controller.add(isOnline);

  /// Pushes a stream-level error — exercises a caller's RNF09 "never
  /// crashes" handling of a connectivity-watch failure (e.g. the real
  /// `connectivity_plus` platform channel being unavailable).
  void emitError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();
}
