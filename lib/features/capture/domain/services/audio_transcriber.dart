/// Capture's on-device speech-to-text port — the `whisper_ggml`-backed
/// `WhisperAudioTranscriber` is the only implementation (Code Map),
/// mirroring [MicRecorder]'s same port convention.
abstract class AudioTranscriber {
  /// Transcribes the audio file at [audioPath] entirely on-device
  /// (FR-12) — never sends audio bytes anywhere. `null` means failure (a
  /// local-only outcome, never wrapped in `Failure` — RNF09 scopes
  /// `Failure` to repository/backend calls); a non-null result is the
  /// transcribed text, which may itself be empty if nothing was said.
  Future<String?> transcribe(String audioPath);
}
