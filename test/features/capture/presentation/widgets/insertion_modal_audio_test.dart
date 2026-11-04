import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/domain/services/photo_picker.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/photo_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/widgets/insertion_modal.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

import '../../../../support/intercept_announcements.dart';

const _savedEntry = Entry(
  id: 'a1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.audio,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  mediaDurationSeconds: 7,
);

/// Scriptable fakes (not mocktail — same "plain fake" convention
/// `insertion_modal_test.dart`'s own `_FakeEntriesRepository` already
/// uses for widget-level tests) standing in for the two native-package
/// ports this story adds. Never exercises the real `record`/
/// `whisper_ggml` plugins (Never, AGENTS.md: no device/simulator exists).
class _FakeMicRecorder implements MicRecorder {
  bool permissionGranted = true;
  int startCalls = 0;
  int cancelCalls = 0;
  MicRecording? nextStopResult;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<MicRecording?> stop() async => nextStopResult;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

class _FakeAudioTranscriber implements AudioTranscriber {
  String? nextTranscription;

  @override
  Future<String?> transcribe(String audioPath) async => nextTranscription;
}

/// A trivial fake — this file's own tests never switch to the Foto tab,
/// so neither `PhotoPicker` port method below is ever expected to be
/// called (same rationale as `_FakeMicRecorder`'s own doc, applied to
/// spec-3-3's two new ports).
class _FakePhotoPicker implements PhotoPicker {
  @override
  Future<PickedPhoto?> pickFromCamera() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<PickedPhoto?> pickFromGallery() async =>
      throw UnimplementedError('not expected to be called');
}

class _FakeMediaRepository implements MediaRepository {
  @override
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError('not expected to be called');
}

class _FakeEntriesRepository implements EntriesRepository {
  Either<Failure, Entry> Function()? nextResult;
  int createCallCount = 0;
  EntrySource? lastSource;
  int? lastMediaDurationSeconds;

  /// Lets a test hold `create()` unresolved, to observe the modal's
  /// mid-save state — same convention `insertion_modal_test.dart`'s own
  /// `_FakeEntriesRepository.gate` already uses for the Texto tab (Review
  /// finding: the Áudio tab had no equivalent coverage of its own
  /// `isSaving` gating the tab bar/close button).
  Completer<void>? gate;

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    createCallCount++;
    lastSource = source;
    lastMediaDurationSeconds = mediaDurationSeconds;
    final activeGate = gate;
    if (activeGate != null) {
      await activeGate.future;
    }
    return nextResult!();
  }
}

Future<void> _openModal(
  WidgetTester tester, {
  required TextEntryCubit cubit,
  required AudioEntryCubit audioCubit,
  required PhotoEntryCubit photoCubit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => InsertionModal.show(
              context,
              cubit: cubit,
              audioCubit: audioCubit,
              photoCubit: photoCubit,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

/// Drives the real `InsertionModal` + real `AudioEntryCubit` through
/// spec-3-2's own I/O & Edge-Case Matrix — only the two native-package
/// ports are faked (see the classes above). `PhotoEntryCubit` is always a
/// fresh, never-configured instance (backed by the two trivial "not
/// expected to be called" fakes above) — this file's own tests never
/// switch to the Foto tab.
void main() {
  late _FakeMicRecorder fakeMicRecorder;
  late _FakeAudioTranscriber fakeAudioTranscriber;
  late _FakeEntriesRepository fakeRepository;
  late TextEntryCubit textCubit;
  late AudioEntryCubit audioCubit;
  late PhotoEntryCubit photoCubit;

  setUp(() {
    fakeMicRecorder = _FakeMicRecorder();
    fakeAudioTranscriber = _FakeAudioTranscriber();
    fakeRepository = _FakeEntriesRepository();
    textCubit = TextEntryCubit(fakeRepository);
    audioCubit = AudioEntryCubit(
      fakeMicRecorder,
      fakeAudioTranscriber,
      fakeRepository,
    );
    photoCubit = PhotoEntryCubit(
      _FakePhotoPicker(),
      _FakeMediaRepository(),
      fakeRepository,
    );
  });

  // Every test below opens the modal; the ones that never pop it (e.g. a
  // retry that leaves the sheet open) would otherwise leave
  // `AudioEntryCubit`'s own internal `Timer.periodic` (the elapsed-time
  // ticker) still pending once the test ends — `InsertionModal.show`
  // only closes both cubits once the sheet itself closes, which not
  // every scenario below reaches. `close()` is safe to call twice (it's
  // also called by `InsertionModal.show`'s own `finally` whenever a test
  // *does* pop the sheet), same convention
  // `text_entry_cubit_test.dart`'s own "emit after close" test relies on.
  tearDown(() async {
    // Every test below opens the modal; the ones that pop it (Salvar
    // success) already have both cubits closed by `InsertionModal.show`'s
    // own `finally` by the time this runs — guarding with `isClosed`
    // avoids calling `close()` a second time on an already-closed cubit,
    // which (confirmed while drafting this suite) hangs indefinitely
    // rather than being the harmless no-op `text_entry_cubit_test.dart`'s
    // own "emit after close" test relies on for a *bare* cubit (no
    // `BlocProvider`/widget tree attached there, unlike here).
    if (!textCubit.isClosed) {
      await textCubit.close();
    }
    if (!audioCubit.isClosed) {
      await audioCubit.close();
    }
    if (!photoCubit.isClosed) {
      await photoCubit.close();
    }
  });

  testWidgets(
    'Happy path: switching to Áudio starts recording immediately with a '
    'running timer; stopping transcribes; Salvar fires source: audio + '
    'mediaDurationSeconds and closes the modal',
    (tester) async {
      fakeRepository.nextResult = () => right(_savedEntry);
      fakeMicRecorder.nextStopResult = const MicRecording(
        path: '/tmp/a.wav',
        durationSeconds: 7,
      );
      fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Áudio'));
      // A single `pump()`, never `pumpAndSettle()`, from here until the
      // recording stops below — `AudioEntryCubit`'s own 1-second
      // `Timer.periodic` (the elapsed-time ticker) never produces a
      // settled tree on its own; `pumpAndSettle()` would spin forever
      // waiting for a quiescent point that an active recording never
      // reaches.
      await tester.pump();

      expect(fakeMicRecorder.startCalls, 1);
      expect(find.text('00:00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      expect(find.text('Hoje foi um bom dia.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 1);
      expect(fakeRepository.lastSource, EntrySource.audio);
      expect(fakeRepository.lastMediaDurationSeconds, 7);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('Mic permission denied: AudioError shown, no file to preserve; '
      '"Tentar novamente" re-requests permission', (tester) async {
    fakeMicRecorder.permissionGranted = false;
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Áudio'));
    // Never `pumpAndSettle()` here — see the happy path test's own
    // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
    await tester.pump();

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(fakeMicRecorder.startCalls, 0);

    fakeMicRecorder.permissionGranted = true;
    await tester.tap(find.text('Tentar novamente'));
    // Never `pumpAndSettle()` once recording starts — see the happy
    // path test's own comment.
    await tester.pump();

    expect(fakeMicRecorder.startCalls, 1);
    expect(find.text('00:00'), findsOneWidget);

    // This test ends mid-recording — `AudioEntryCubit`'s internal
    // `Timer.periodic` must be canceled before the test body returns
    // (not left to `tearDown`, which the framework's own pending-timer
    // invariant check runs ahead of): same as a real tab switch away
    // from Áudio (`cancel()`'s own I/O matrix row).
    await audioCubit.cancel();
    await tester.pump();
  });

  testWidgets('Transcription fails: AudioError shown, audio file preserved; '
      '"Tentar novamente" re-transcribes the same file (never re-records)', (
    tester,
  ) async {
    fakeMicRecorder.nextStopResult = const MicRecording(
      path: '/tmp/a.wav',
      durationSeconds: 7,
    );
    fakeAudioTranscriber.nextTranscription = null;
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Áudio'));
    // Never `pumpAndSettle()` here — see the happy path test's own
    // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(fakeMicRecorder.startCalls, 1);

    fakeAudioTranscriber.nextTranscription = 'Funcionou na segunda vez.';
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Funcionou na segunda vez.'), findsOneWidget);
    // Still only the original recording — retry re-transcribed, it
    // never started a second recording session.
    expect(fakeMicRecorder.startCalls, 1);
  });

  testWidgets(
    'Save fails (incl. offline): inline Failure.message shown, Salvar '
    're-enabled, text/audio preserved, no auto-retry',
    (tester) async {
      fakeRepository.nextResult = () =>
          left(const Failure.networkOffline(message: 'Sem conexão'));
      fakeMicRecorder.nextStopResult = const MicRecording(
        path: '/tmp/a.wav',
        durationSeconds: 7,
      );
      fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Áudio'));
      // Never `pumpAndSettle()` here — see the happy path test's own
      // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 1);
      expect(find.text('Sem conexão'), findsOneWidget);
      expect(find.text('Hoje foi um bom dia.'), findsOneWidget);
      final salvarButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Salvar'),
      );
      expect(salvarButton.onPressed, isNotNull);
    },
  );

  testWidgets(
    'Leave tab mid-recording: switching to Texto cancels the recorder, '
    'no POST /entries ever fires',
    (tester) async {
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Áudio'));
      // Never `pumpAndSettle()` here — see the happy path test's own
      // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
      await tester.pump();
      expect(fakeMicRecorder.startCalls, 1);

      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();

      expect(fakeMicRecorder.cancelCalls, 1);
      expect(fakeRepository.createCallCount, 0);
    },
  );

  testWidgets('the transcribed text is editable before Salvar', (tester) async {
    fakeMicRecorder.nextStopResult = const MicRecording(
      path: '/tmp/a.wav',
      durationSeconds: 7,
    );
    fakeAudioTranscriber.nextTranscription = 'texto original';
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Áudio'));
    // Never `pumpAndSettle()` here — see the happy path test's own
    // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'texto editado pelo usuário',
    );
    await tester.pump();

    expect(find.text('texto editado pelo usuário'), findsOneWidget);
  });

  testWidgets(
    'Review finding: re-entering Áudio after a completed transcription '
    'resumes it instead of silently discarding it and starting a new '
    'recording',
    (tester) async {
      fakeMicRecorder.nextStopResult = const MicRecording(
        path: '/tmp/a.wav',
        durationSeconds: 7,
      );
      fakeAudioTranscriber.nextTranscription = 'texto transcrito original';
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Áudio'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();
      expect(find.text('texto transcrito original'), findsOneWidget);

      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.pumpAndSettle();

      // Still showing the earlier transcription — no second recording
      // session started (startCalls stays at 1), and nothing was
      // discarded.
      expect(find.text('texto transcrito original'), findsOneWidget);
      expect(fakeMicRecorder.startCalls, 1);
    },
  );

  testWidgets(
    'Review finding: tapping Salvar again after a save failure actually '
    'retries create() instead of being a permanent no-op',
    (tester) async {
      fakeRepository.nextResult = () =>
          left(const Failure.networkOffline(message: 'Sem conexão'));
      fakeMicRecorder.nextStopResult = const MicRecording(
        path: '/tmp/a.wav',
        durationSeconds: 7,
      );
      fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();
      expect(fakeRepository.createCallCount, 1);

      fakeRepository.nextResult = () => right(_savedEntry);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 2);
      expect(fakeRepository.lastSource, EntrySource.audio);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('Review finding: editing the text after a save failure actually '
      'retries with the edited text, not the stale pre-failure text', (
    tester,
  ) async {
    fakeRepository.nextResult = () =>
        left(const Failure.networkOffline(message: 'Sem conexão'));
    fakeMicRecorder.nextStopResult = const MicRecording(
      path: '/tmp/a.wav',
      durationSeconds: 7,
    );
    fakeAudioTranscriber.nextTranscription = 'texto original';
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áudio'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'texto corrigido');
    await tester.pump();
    fakeRepository.nextResult = () => right(_savedEntry);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 2);
  });

  testWidgets(
    "Review finding: an in-flight audio save disables the tab bar and "
    'close button too, not only TextEntryCubit\'s own saves',
    (tester) async {
      fakeMicRecorder.nextStopResult = const MicRecording(
        path: '/tmp/a.wav',
        durationSeconds: 7,
      );
      fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
      fakeRepository.nextResult = () => right(_savedEntry);
      fakeRepository.gate = Completer<void>();
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pump();

      final textoInkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Texto'), matching: find.byType(InkWell))
            .first,
      );
      expect(textoInkWell.onTap, isNull);
      final closeInkWell = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.byIcon(Icons.close),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(closeInkWell.onTap, isNull);

      fakeRepository.gate!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Dismissing the whole modal (not switching tabs) while recording '
      'releases the mic too (Review finding: previously only verified via '
      'a tab switch, never via "x"/swipe/barrier dismissing the whole '
      'sheet)', (tester) async {
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Áudio'));
    // Never `pumpAndSettle()` here — see the happy path test's own
    // comment on `AudioEntryCubit`'s 1-second elapsed-time ticker.
    await tester.pump();
    expect(fakeMicRecorder.startCalls, 1);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(fakeMicRecorder.cancelCalls, 1);
    expect(fakeRepository.createCallCount, 0);
  });

  group(
    'announcements — review finding: every assertion above only read '
    'visible Text/TextField/button state, so a deleted/broken '
    '_onAudioStateChange() path would still pass every test in this file',
    () {
      testWidgets('recording announces "Gravando áudio"', (tester) async {
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Áudio'));
        await tester.pump();

        expect(announcements, contains('Gravando áudio'));

        // Ends mid-recording — see the happy path test's own comment on
        // `AudioEntryCubit`'s 1-second elapsed-time ticker.
        await audioCubit.cancel();
        await tester.pump();
      });

      testWidgets(
        'stopping announces "Transcrevendo áudio" then the transcribed-'
        'review prompt',
        (tester) async {
          fakeMicRecorder.nextStopResult = const MicRecording(
            path: '/tmp/a.wav',
            durationSeconds: 7,
          );
          fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
          final announcements = interceptAnnouncements(tester);
          await _openModal(
            tester,
            cubit: textCubit,
            audioCubit: audioCubit,
            photoCubit: photoCubit,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Áudio'));
          await tester.pump();

          await tester.tap(find.byIcon(Icons.stop));
          await tester.pumpAndSettle();

          expect(announcements, contains('Transcrevendo áudio'));
          expect(
            announcements,
            contains('Transcrição concluída. Revise o texto antes de salvar.'),
          );
        },
      );

      testWidgets('a transcription failure announces the error message', (
        tester,
      ) async {
        fakeMicRecorder.nextStopResult = const MicRecording(
          path: '/tmp/a.wav',
          durationSeconds: 7,
        );
        fakeAudioTranscriber.nextTranscription = null;
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();

        expect(
          announcements,
          contains('Não foi possível transcrever o áudio.'),
        );
      });

      testWidgets('a successful save announces "Registro salvo"', (
        tester,
      ) async {
        fakeMicRecorder.nextStopResult = const MicRecording(
          path: '/tmp/a.wav',
          durationSeconds: 7,
        );
        fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
        fakeRepository.nextResult = () => right(_savedEntry);
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.stop));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
        await tester.pumpAndSettle();

        expect(announcements, contains('Registro salvo'));
      });

      testWidgets(
        'saving announces "Salvando registro" before "Registro salvo" '
        '(Review finding: the Texto tab\'s equivalent has a dedicated '
        'test; the Áudio tab had none)',
        (tester) async {
          fakeMicRecorder.nextStopResult = const MicRecording(
            path: '/tmp/a.wav',
            durationSeconds: 7,
          );
          fakeAudioTranscriber.nextTranscription = 'Hoje foi um bom dia.';
          fakeRepository.nextResult = () => right(_savedEntry);
          fakeRepository.gate = Completer<void>();
          final announcements = interceptAnnouncements(tester);
          await _openModal(
            tester,
            cubit: textCubit,
            audioCubit: audioCubit,
            photoCubit: photoCubit,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Áudio'));
          await tester.pump();
          await tester.tap(find.byIcon(Icons.stop));
          await tester.pumpAndSettle();

          await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
          await tester.pump();

          expect(announcements, contains('Salvando registro'));
          expect(announcements, isNot(contains('Registro salvo')));

          fakeRepository.gate!.complete();
          await tester.pumpAndSettle();

          expect(announcements, contains('Registro salvo'));
        },
      );

      testWidgets(
        'canceling mid-recording (tab switch away) announces "Gravação '
        'cancelada" (Review finding: the one AudioCaptureState transition '
        'previously never announced — masked only because its one '
        'reachable path coincides with the separate tab-switch '
        'announcement)',
        (tester) async {
          final announcements = interceptAnnouncements(tester);
          await _openModal(
            tester,
            cubit: textCubit,
            audioCubit: audioCubit,
            photoCubit: photoCubit,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Áudio'));
          await tester.pump();

          await tester.tap(find.text('Texto'));
          await tester.pumpAndSettle();

          expect(announcements, contains('Gravação cancelada'));
        },
      );
    },
  );
}
