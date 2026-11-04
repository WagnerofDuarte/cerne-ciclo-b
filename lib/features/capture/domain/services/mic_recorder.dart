/// A finished microphone recording — the on-disk file [path] plus its
/// [durationSeconds], known only once [MicRecorder.stop] returns. Plain
/// Dart, not `package:record`'s own types — keeps this port, and every
/// caller that depends on it (`AudioEntryCubit`), decoupled from that
/// package's shape (Boundaries: "decouple the cubit from both packages").
class MicRecording {
  const MicRecording({required this.path, required this.durationSeconds});

  final String path;
  final int durationSeconds;
}

/// Capture's own mic-recording port — the `record`-backed
/// `RecordMicRecorder` is the only implementation (Code Map), mirroring
/// `EntriesRepository`'s port convention (an abstract class in `domain/`,
/// a concrete `data/` class wrapping the real package, injected via
/// `capture_injection.dart`). `AudioEntryCubit` depends on this interface
/// only, never on `package:record` directly (RNF06-style boundary,
/// extended here to any native package, not just `data/`).
abstract class MicRecorder {
  /// Checks (and, per `record`'s own `AudioRecorder.hasPermission()`
  /// default, requests if not yet granted) microphone permission — the
  /// one permission check this story ever performs (Boundaries: "no
  /// separate `permission_handler`"). `false` means denied/unavailable.
  Future<bool> hasPermission();

  /// Starts a new recording session to a fresh temp file. Callers must
  /// have already confirmed [hasPermission] returns `true` — this method
  /// itself doesn't re-check.
  Future<void> start();

  /// Stops the current recording session, returning its file path and
  /// duration (whole seconds). `null` if no session was in progress.
  Future<MicRecording?> stop();

  /// Stops and discards (deletes) the current recording session, if any —
  /// used only when leaving the Áudio tab mid-recording (I/O matrix:
  /// "Recorder stopped/released", resource safety only, never the full
  /// Story 3.4 cross-tab cancel choreography).
  Future<void> cancel();

  /// A normalized (0.0–1.0) amplitude sample roughly every 200ms while a
  /// recording session is active — drives the waveform animation. No
  /// guaranteed emissions outside an active session.
  Stream<double> get amplitudeStream;
}
