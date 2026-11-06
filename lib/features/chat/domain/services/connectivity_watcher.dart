/// spec-6-3 — the chat feature's own connectivity port. Feature-local
/// (`chat/domain/services/`), mirroring `MicRecorder`'s own domain/data
/// split (`lib/features/capture/domain/services/mic_recorder.dart`): an
/// abstract class in `domain/`, a concrete `connectivity_plus`-backed
/// implementation in `data/` (`ConnectivityPlusWatcher`), injected
/// directly into `ChatCubit`'s constructor — never routed through
/// `ChatRepository` (Boundaries). Lives here rather than in `core/` since
/// no other feature needs connectivity yet (Design Notes); promote it
/// later if one does.
abstract class ConnectivityWatcher {
  /// Emits the device's online/offline status — `true` whenever it
  /// currently has connectivity, `false` whenever it doesn't — every time
  /// it changes. `ChatCubit` folds each emission into
  /// `ChatReady.isOffline` (the logical negation, `!value`).
  ///
  /// This port makes no guarantee about an initial emission on `listen()`
  /// — a caller that needs the device's *current* status right away, not
  /// only future changes, depends on the concrete implementation
  /// providing one (`ConnectivityPlusWatcher`'s own doc).
  Stream<bool> watch();
}
