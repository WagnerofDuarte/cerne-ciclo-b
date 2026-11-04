// The constructor keeps a public named param (`controller`) distinct from
// the private field it initializes, matching
// `vault_repository_impl.dart`'s documented convention.
// ignore_for_file: prefer_initializing_formals
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../domain/services/audio_transcriber.dart';

/// Wraps `whisper_ggml`'s `WhisperController` behind the [AudioTranscriber]
/// port — 100% on-device (FR-12), `lang: 'pt'`, `WhisperModel.base`
/// (Design Notes: balances accuracy/size). A `get_it` singleton (Code Map/
/// `capture_injection.dart`), same "one real instance for the app's
/// lifetime" convention as [RecordMicRecorder].
class WhisperAudioTranscriber implements AudioTranscriber {
  WhisperAudioTranscriber({required WhisperController controller})
    : _controller = controller;

  final WhisperController _controller;

  static const _model = WhisperModel.base;

  @override
  Future<String?> transcribe(String audioPath) async {
    try {
      // Lazy download, inside transcribe() (Design Notes) — a missing
      // model + no connectivity just surfaces through the catch below,
      // same generic error/retry path as any other transcription
      // failure.
      await _controller.downloadModel(_model);
      final result = await _controller.transcribe(
        model: _model,
        audioPath: audioPath,
        lang: 'pt',
      );
      // `WhisperController.transcribe` already swallows its own internal
      // exceptions into a `null` return (never throws) — the outer `try`
      // here exists for `downloadModel`'s own exceptions (e.g. no
      // connectivity on first-ever use), not this call.
      return result?.transcription.text;
    } catch (_) {
      return null;
    }
  }
}
