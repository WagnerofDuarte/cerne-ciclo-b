import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// `TranscribeResult` (`WhisperController.transcribe()`'s own return
// type) isn't re-exported by the package's public `whisper_ggml.dart`
// barrel — this test needs to construct one directly to stub that
// return value, which no public import path allows.
// ignore: implementation_imports
import 'package:whisper_ggml/src/models/whisper_result.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'package:cerne/features/capture/data/services/whisper_audio_transcriber.dart';

class MockWhisperController extends Mock implements WhisperController {}

/// Covers spec-3-2's Code Map wrapper directly — `whisper_ggml`'s own
/// `WhisperController` is mocked (mocktail), never a real on-device
/// model download/transcription (Never: no automated test exercises the
/// real native plugin), same "mock the plugin class directly" convention
/// `record_mic_recorder_test.dart` already applies.
void main() {
  late MockWhisperController mockController;
  late WhisperAudioTranscriber transcriber;

  setUpAll(() {
    registerFallbackValue(WhisperModel.base);
  });

  setUp(() {
    mockController = MockWhisperController();
    transcriber = WhisperAudioTranscriber(controller: mockController);
  });

  test(
    'happy path: downloads the base model, transcribes in Portuguese, '
    'returns the transcribed text',
    () async {
      when(
        () => mockController.downloadModel(WhisperModel.base),
      ).thenAnswer((_) async => '/models/ggml-base.bin');
      when(
        () => mockController.transcribe(
          model: WhisperModel.base,
          audioPath: '/tmp/a.wav',
          lang: 'pt',
        ),
      ).thenAnswer(
        (_) async => TranscribeResult(
          time: const Duration(seconds: 1),
          transcription: const WhisperTranscribeResponse(
            type: 'transcription',
            text: 'Hoje foi um bom dia.',
            segments: null,
          ),
        ),
      );

      final result = await transcriber.transcribe('/tmp/a.wav');

      expect(result, 'Hoje foi um bom dia.');
    },
  );

  test(
    'WhisperController.transcribe returning null (its own internal '
    'failure) -> null, never throws',
    () async {
      when(
        () => mockController.downloadModel(WhisperModel.base),
      ).thenAnswer((_) async => '/models/ggml-base.bin');
      when(
        () => mockController.transcribe(
          model: WhisperModel.base,
          audioPath: '/tmp/a.wav',
          lang: 'pt',
        ),
      ).thenAnswer((_) async => null);

      final result = await transcriber.transcribe('/tmp/a.wav');

      expect(result, isNull);
    },
  );

  test(
    'downloadModel throwing (e.g. no connectivity on first-ever use) -> '
    'null, never lets the exception escape',
    () async {
      when(
        () => mockController.downloadModel(WhisperModel.base),
      ).thenThrow(Exception('no connectivity'));

      final result = await transcriber.transcribe('/tmp/a.wav');

      expect(result, isNull);
      verifyNever(
        () => mockController.transcribe(
          model: any(named: 'model'),
          audioPath: any(named: 'audioPath'),
          lang: any(named: 'lang'),
        ),
      );
    },
  );
}
