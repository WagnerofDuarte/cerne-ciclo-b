import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/services/connectivity_watcher.dart';

/// Wraps `package:connectivity_plus`'s `Connectivity` behind the
/// [ConnectivityWatcher] port — a `get_it` lazy singleton
/// (`chat_injection.dart`), mirroring `RecordMicRecorder`'s own
/// "wrap-the-real-plugin" shape.
///
/// [watch] emits the device's *current* status as soon as it's known
/// (via [Connectivity.checkConnectivity]), then every subsequent change
/// (via [Connectivity.onConnectivityChanged]) — so a caller that starts
/// out already offline (e.g. `ChatCubit`'s own constructor-time
/// subscription) learns that right away, not only once the status
/// changes for the first time.
///
/// Review finding: the live [Connectivity.onConnectivityChanged]
/// subscription starts immediately, never gated behind the initial
/// [Connectivity.checkConnectivity] read — a hang (not just a throw) on
/// that one platform-channel call must never block connectivity watching
/// from starting at all for the rest of the session. The initial read is
/// purely a best-effort *seed* value: it's only ever used if it resolves
/// (successfully or not) before the live subscription has already
/// delivered its own first event, and any failure from it (including a
/// never-resolving hang, which simply never seeds anything) is silently
/// ignored rather than ending the stream.
class ConnectivityPlusWatcher implements ConnectivityWatcher {
  ConnectivityPlusWatcher({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> watch() {
    final controller = StreamController<bool>();
    var liveEventDelivered = false;

    final liveSubscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        liveEventDelivered = true;
        controller.add(_isOnline(results));
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = liveSubscription.cancel;

    // Fire-and-forget: never awaited, so a hang here can't delay (let
    // alone block) the live subscription started above — it only ever
    // reaches into the controller if it resolves before any live event
    // already has. Wrapped in its own try/catch (RNF09) rather than
    // relying solely on `Future.then`'s own error channel — a mocked/
    // misbehaving `checkConnectivity()` throwing synchronously, instead
    // of returning a rejected `Future`, must never escape [watch] itself.
    unawaited(_seedFromInitialCheck(controller, () => liveEventDelivered));

    return controller.stream;
  }

  Future<void> _seedFromInitialCheck(
    StreamController<bool> controller,
    bool Function() liveEventAlreadyDelivered,
  ) async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!liveEventAlreadyDelivered() && !controller.isClosed) {
        controller.add(_isOnline(results));
      }
    } catch (_) {
      // Best-effort seed only — see this class's own doc above.
    }
  }

  /// `connectivity_plus`'s own contract: the emitted list is never empty,
  /// and [ConnectivityResult.none] only ever appears alone (the package's
  /// own doc on `Connectivity.onConnectivityChanged`) — so "online" is
  /// simply "not exactly `[none]`", checked the permissive way (`any`
  /// non-`none` entry) rather than relying on that exact shape.
  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
