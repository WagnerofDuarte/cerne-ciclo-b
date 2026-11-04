import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

class MockMicRecorder extends Mock implements MicRecorder {}

class MockAudioTranscriber extends Mock implements AudioTranscriber {}

class MockEntriesRepository extends Mock implements EntriesRepository {}

const _savedEntry = Entry(
  id: 'e1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.audio,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  mediaDurationSeconds: 7,
);

/// Covers spec-3-2's I/O & Edge-Case Matrix at the cubit layer — both
/// `MicRecorder`/`AudioTranscriber` are mocked (mocktail), same
/// convention as `EntriesRepository` in `text_entry_cubit_test.dart`
/// (Never: no automated test exercises the real `record`/`whisper_ggml`
/// native plugins).
void main() {
  late MockMicRecorder mockMicRecorder;
  late MockAudioTranscriber mockAudioTranscriber;
  late MockEntriesRepository mockRepository;
  late AudioEntryCubit cubit;

  setUpAll(() {
    registerFallbackValue(EntrySource.audio);
  });

  setUp(() {
    mockMicRecorder = MockMicRecorder();
    mockAudioTranscriber = MockAudioTranscriber();
    mockRepository = MockEntriesRepository();
    cubit = AudioEntryCubit(
      mockMicRecorder,
      mockAudioTranscriber,
      mockRepository,
    );
  });

  tearDown(() => cubit.close());

  test('starts AudioIdle', () {
    expect(cubit.state, isA<AudioIdle>());
  });

  test(
    'amplitudeStream forwards MicRecorder.amplitudeStream verbatim — no '
    'package:record type ever crosses the cubit boundary',
    () {
      final stream = Stream<double>.empty();
      when(() => mockMicRecorder.amplitudeStream).thenAnswer((_) => stream);

      expect(cubit.amplitudeStream, same(stream));
    },
  );

  group('startRecording()', () {
    test(
      'permission granted -> starts the recorder, emits AudioRecording '
      '(elapsedSeconds: 0)',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});

        await cubit.startRecording();

        expect(
          cubit.state,
          isA<AudioRecording>().having((s) => s.elapsedSeconds, 'elapsedSeconds', 0),
        );
        verify(() => mockMicRecorder.start()).called(1);
      },
    );

    test(
      'permission denied -> AudioError with no file ("no file to '
      'preserve"), start() never called',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => false);

        await cubit.startRecording();

        expect(
          cubit.state,
          isA<AudioError>()
              .having((s) => s.path, 'path', isNull)
              .having((s) => s.durationSeconds, 'durationSeconds', isNull),
        );
        verifyNever(() => mockMicRecorder.start());
      },
    );

    test('ignored while already recording (no second overlapping start)', () async {
      when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockMicRecorder.start()).thenAnswer((_) async {});
      await cubit.startRecording();

      await cubit.startRecording();

      verify(() => mockMicRecorder.start()).called(1);
    });
  });

  group('stopRecording()', () {
    test(
      'happy path: stops the recorder, AudioProcessing then AudioTranscribed '
      'carrying the transcribed text',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});
        await cubit.startRecording();
        when(() => mockMicRecorder.stop()).thenAnswer(
          (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
        );
        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) async => 'Hoje foi um bom dia.');

        final emitted = <AudioCaptureState>[];
        final subscription = cubit.stream.listen(emitted.add);

        await cubit.stopRecording();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(emitted, [isA<AudioProcessing>(), isA<AudioTranscribed>()]);
        final transcribed = cubit.state as AudioTranscribed;
        expect(transcribed.text, 'Hoje foi um bom dia.');
        expect(transcribed.durationSeconds, 7);
        expect(transcribed.saving, isFalse);
      },
    );

    test(
      'transcription fails (null) -> AudioError, file preserved (path/'
      'duration still set), no auto-retry',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});
        await cubit.startRecording();
        when(() => mockMicRecorder.stop()).thenAnswer(
          (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
        );
        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) async => null);

        await cubit.stopRecording();

        expect(
          cubit.state,
          isA<AudioError>()
              .having((s) => s.path, 'path', '/tmp/a.wav')
              .having((s) => s.durationSeconds, 'durationSeconds', 7)
              .having((s) => s.text, 'text', isNull),
        );
      },
    );

    test('ignored outside AudioRecording (e.g. a stray second tap)', () async {
      await cubit.stopRecording();

      verifyNever(() => mockMicRecorder.stop());
      expect(cubit.state, isA<AudioIdle>());
    });
  });

  group('retry()', () {
    test(
      'no file (permission denied) -> re-requests permission via '
      'startRecording, never re-transcribes',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => false);
        await cubit.startRecording();
        expect(cubit.state, isA<AudioError>());

        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});

        await cubit.retry();

        expect(cubit.state, isA<AudioRecording>());
        verify(() => mockMicRecorder.start()).called(1);
        verifyNever(() => mockAudioTranscriber.transcribe(any()));
      },
    );

    test(
      'a preserved file whose transcription failed -> re-transcribes the '
      'same file in place, never re-records',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});
        await cubit.startRecording();
        when(() => mockMicRecorder.stop()).thenAnswer(
          (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
        );
        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) async => null);
        await cubit.stopRecording();
        expect(cubit.state, isA<AudioError>());

        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) async => 'Transcrito na segunda tentativa.');

        await cubit.retry();

        expect(
          cubit.state,
          isA<AudioTranscribed>().having(
            (s) => s.text,
            'text',
            'Transcrito na segunda tentativa.',
          ),
        );
        // Called exactly once — the original recording above, never a
        // second time for this retry (it re-transcribes, not re-records).
        verify(() => mockMicRecorder.start()).called(1);
      },
    );

    test(
      'a no-op for a save failure (AudioError.text != null) — Salvar, not '
      'retry, is that case\'s own recovery path',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});
        await cubit.startRecording();
        when(() => mockMicRecorder.stop()).thenAnswer(
          (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
        );
        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) async => 'texto');
        await cubit.stopRecording();
        when(
          () => mockRepository.create(
            content: any(named: 'content'),
            source: any(named: 'source'),
            mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
          ),
        ).thenAnswer(
          (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
        );
        await cubit.save();
        final errorState = cubit.state as AudioError;
        expect(errorState.text, isNotNull);

        await cubit.retry();

        expect(cubit.state, same(errorState));
      },
    );

    test('a no-op outside AudioError', () async {
      await cubit.retry();

      expect(cubit.state, isA<AudioIdle>());
      verifyNever(() => mockMicRecorder.hasPermission());
    });
  });

  group('updateText()', () {
    Future<AudioTranscribed> transcribedState() async {
      when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockMicRecorder.start()).thenAnswer((_) async {});
      await cubit.startRecording();
      when(() => mockMicRecorder.stop()).thenAnswer(
        (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
      );
      when(
        () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
      ).thenAnswer((_) async => 'texto original');
      await cubit.stopRecording();
      return cubit.state as AudioTranscribed;
    }

    test('mirrors the typed text into state while transcribed', () async {
      await transcribedState();

      cubit.updateText('texto editado');

      expect(cubit.state, isA<AudioTranscribed>().having((s) => s.text, 'text', 'texto editado'));
    });

    test('ignored outside AudioTranscribed', () {
      cubit.updateText('nada deveria acontecer');

      expect(cubit.state, isA<AudioIdle>());
    });

    test('ignored while a save is already in flight', () async {
      await transcribedState();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      ).thenAnswer((_) => completer.future);

      final saveFuture = cubit.save();
      cubit.updateText('tentativa de editar durante o save');

      expect(
        cubit.state,
        isA<AudioTranscribed>().having((s) => s.text, 'text', 'texto original'),
      );

      completer.complete(right(_savedEntry));
      await saveFuture;
    });
  });

  group('cancel() — leaving the Áudio tab mid-recording/mid-processing', () {
    test('while recording -> cancels the recorder, resets to AudioIdle', () async {
      when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockMicRecorder.start()).thenAnswer((_) async {});
      await cubit.startRecording();
      when(() => mockMicRecorder.cancel()).thenAnswer((_) async {});

      await cubit.cancel();

      expect(cubit.state, isA<AudioIdle>());
      verify(() => mockMicRecorder.cancel()).called(1);
    });

    test(
      'while processing -> resets to AudioIdle without touching the '
      'recorder (already stopped) and drops the eventual transcription '
      'result instead of resurrecting the flow',
      () async {
        when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
        when(() => mockMicRecorder.start()).thenAnswer((_) async {});
        await cubit.startRecording();
        when(() => mockMicRecorder.stop()).thenAnswer(
          (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
        );
        final transcribeCompleter = Completer<String?>();
        when(
          () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
        ).thenAnswer((_) => transcribeCompleter.future);

        final stopFuture = cubit.stopRecording();
        // Let `stopRecording()` reach `AudioProcessing` before leaving.
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state, isA<AudioProcessing>());

        await cubit.cancel();
        expect(cubit.state, isA<AudioIdle>());

        transcribeCompleter.complete('chegou tarde demais');
        await stopFuture;

        expect(cubit.state, isA<AudioIdle>());
        verifyNever(() => mockMicRecorder.cancel());
      },
    );

    test('a no-op outside AudioRecording/AudioProcessing', () async {
      await cubit.cancel();

      expect(cubit.state, isA<AudioIdle>());
      verifyNever(() => mockMicRecorder.cancel());
    });
  });

  group('save()', () {
    Future<void> reachTranscribed() async {
      when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockMicRecorder.start()).thenAnswer((_) async {});
      await cubit.startRecording();
      when(() => mockMicRecorder.stop()).thenAnswer(
        (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
      );
      when(
        () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
      ).thenAnswer((_) async => 'Hoje foi um bom dia.');
      await cubit.stopRecording();
    }

    test(
      'happy path -> saving then AudioSaved, source always audio, '
      'mediaDurationSeconds carried through',
      () async {
        await reachTranscribed();
        when(
          () => mockRepository.create(
            content: 'Hoje foi um bom dia.',
            source: EntrySource.audio,
            mediaDurationSeconds: 7,
          ),
        ).thenAnswer((_) async => right(_savedEntry));

        final emitted = <AudioCaptureState>[];
        final subscription = cubit.stream.listen(emitted.add);

        await cubit.save();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();

        expect(
          emitted,
          [
            isA<AudioTranscribed>().having((s) => s.saving, 'saving', true),
            isA<AudioSaved>(),
          ],
        );
        verify(
          () => mockRepository.create(
            content: 'Hoje foi um bom dia.',
            source: EntrySource.audio,
            mediaDurationSeconds: 7,
          ),
        ).called(1);
      },
    );

    test(
      'failure (incl. offline) -> AudioError carrying Failure.message, '
      'text/file preserved, Salvar re-enabled (no auto-retry)',
      () async {
        await reachTranscribed();
        when(
          () => mockRepository.create(
            content: any(named: 'content'),
            source: any(named: 'source'),
            mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
          ),
        ).thenAnswer(
          (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
        );

        await cubit.save();

        expect(
          cubit.state,
          isA<AudioError>()
              .having((s) => s.message, 'message', 'Sem conexão')
              .having((s) => s.text, 'text', 'Hoje foi um bom dia.')
              .having((s) => s.path, 'path', '/tmp/a.wav'),
        );
      },
    );

    test('blank/whitespace-only text never calls create()', () async {
      await reachTranscribed();
      cubit.updateText('   ');

      await cubit.save();

      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      );
    });

    test('ignored outside AudioTranscribed', () async {
      await cubit.save();

      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      );
      expect(cubit.state, isA<AudioIdle>());
    });

    test('ignored while already saving (no double-submit)', () async {
      await reachTranscribed();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      ).thenAnswer((_) => completer.future);

      final firstSave = cubit.save();
      await cubit.save();

      verify(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      ).called(1);

      completer.complete(right(_savedEntry));
      await firstSave;
    });
  });

  test(
    'emit() after close() never throws (a save racing a modal dismiss)',
    () async {
      when(() => mockMicRecorder.hasPermission()).thenAnswer((_) async => true);
      when(() => mockMicRecorder.start()).thenAnswer((_) async {});
      await cubit.startRecording();
      when(() => mockMicRecorder.stop()).thenAnswer(
        (_) async => const MicRecording(path: '/tmp/a.wav', durationSeconds: 7),
      );
      when(
        () => mockAudioTranscriber.transcribe('/tmp/a.wav'),
      ).thenAnswer((_) async => 'Hoje foi um bom dia.');
      await cubit.stopRecording();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
          mediaDurationSeconds: any(named: 'mediaDurationSeconds'),
        ),
      ).thenAnswer((_) => completer.future);

      final saveFuture = cubit.save();
      await cubit.close();
      completer.complete(right(_savedEntry));

      await expectLater(saveFuture, completes);
    },
  );
}
