// The constructor keeps a public named param (`recorder`) distinct from
// the private field it initializes, matching
// `vault_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'package:path_provider/path_provider.dart';
// Aliased — `record`'s own `AudioRecorder` would otherwise clash with
// nothing in this file today, but the alias keeps every reference to the
// package explicit, per Code Map.
import 'package:record/record.dart' as record_pkg;

import '../../domain/services/mic_recorder.dart';

/// Wraps `package:record`'s `AudioRecorder` behind the [MicRecorder] port.
/// A `get_it` singleton (Code Map/`capture_injection.dart`) — one real
/// recorder for the app's lifetime, reused across every Insertion Modal
/// open, never recreated per "+" tap the way `AudioEntryCubit` itself is.
class RecordMicRecorder implements MicRecorder {
  RecordMicRecorder({
    required record_pkg.AudioRecorder recorder,
    DateTime Function() now = DateTime.now,
  }) : _recorder = recorder,
       _now = now;

  final record_pkg.AudioRecorder _recorder;

  /// Injectable clock (Review finding) — same convention as
  /// `VaultRepositoryImpl`'s own `now` param — so a test can drive
  /// [stop]'s negative-duration clamp without waiting on, or faking, the
  /// real wall clock.
  final DateTime Function() _now;

  /// Set by [start], cleared by [stop]/[cancel] — [stop] has no other way
  /// to learn how long the session ran, since `AudioRecorder.stop()` only
  /// ever returns the output path.
  DateTime? _startedAt;

  /// Set by [start], cleared by [stop]/[cancel] — tracked independently
  /// of `_recorder`'s own "delete on cancel" contract (Review finding:
  /// that contract was asserted in this class's own doc comment but
  /// never independently verified) so [cancel] can delete the file
  /// itself rather than relying solely on the plugin's behavior.
  String? _currentPath;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/cerne_audio_entry_'
        '${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(
      // 16kHz mono matches `whisper_ggml`'s own expected input exactly
      // (its internal ffmpeg conversion step — `WhisperAudioConvert` —
      // falls back to passing the file through unconverted when ffmpeg
      // is unavailable, which only works if it's already in this shape).
      const record_pkg.RecordConfig(
        encoder: record_pkg.AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _startedAt = _now();
    _currentPath = path;
  }

  @override
  Future<MicRecording?> stop() async {
    final path = await _recorder.stop();
    final startedAt = _startedAt;
    _startedAt = null;
    _currentPath = null;
    if (path == null || startedAt == null) {
      return null;
    }
    // Review finding: a backward system-clock adjustment mid-recording
    // (DST/NTP correction) could otherwise make this negative, which the
    // backend's `mediaDurationSeconds: minimum 0` contract rejects —
    // floored at 0 rather than trusting the wall clock never moves back.
    final elapsed = _now().difference(startedAt).inSeconds;
    return MicRecording(path: path, durationSeconds: elapsed < 0 ? 0 : elapsed);
  }

  @override
  Future<void> cancel() async {
    _startedAt = null;
    final path = _currentPath;
    _currentPath = null;
    await _recorder.cancel();
    // Review finding: don't rely solely on the plugin's own "cancel
    // deletes the file" contract — delete it ourselves too, best-effort,
    // so this class's own doc comment stays true regardless of the
    // underlying plugin's actual behavior.
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {
        // Best-effort — the plugin may have already deleted it itself,
        // or it may never have existed (e.g. a very early cancel).
      }
    }
  }

  @override
  Stream<double> get amplitudeStream => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 200))
      .map(_normalize);

  /// `record`'s own `Amplitude.current` is dBFS, roughly -45 (near
  /// silence, in practice — the package's own floor is -160 but normal
  /// mic noise never gets that quiet) to 0 (loudest) — rescaled to a
  /// 0.0–1.0 range the waveform widget can use directly, with no
  /// `package:record` type ever crossing the [MicRecorder] boundary.
  double _normalize(record_pkg.Amplitude amplitude) {
    const floorDb = -45.0;
    final clamped = amplitude.current.clamp(floorDb, 0.0);
    return (clamped - floorDb) / -floorDb;
  }
}
