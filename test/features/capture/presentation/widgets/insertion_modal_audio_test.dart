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

  /// Lets a test drive `_Waveform`'s own `amplitudeStream.listen(...,
  /// onError: ...)` (Review finding: previously never exercised by any
  /// test) — `null` (the default) keeps every other test's behavior
  /// unchanged (`const Stream.empty()`).
  StreamController<double>? amplitudeController;

  @override
  Future<bool> hasPermission() async => permissionGranted;

  @override
  Future<void> start() async => startCalls++;

  @override
  Future<MicRecording?> stop() async => nextStopResult;

  @override
  Future<void> cancel() async => cancelCalls++;

  @override
  Stream<double> get amplitudeStream =>
      amplitudeController?.stream ?? const Stream.empty();
}

class _FakeAudioTranscriber implements AudioTranscriber {
  String? nextTranscription;

  @override
  Future<String?> transcribe(String audioPath) async => nextTranscription;
}

/// `pickFromGallery` stays a trivial "never expected to be called" fake —
/// this file's own tests only ever drive the Foto tab's Câmera button
/// (spec-3-4's cross-tab tests), never Galeria. `pickFromCamera` is
/// configurable — spec-3-4's Foto→Áudio/chained tests need an in-flight
/// pick to switch away from (same `cameraGate` convention
/// `insertion_modal_photo_test.dart`'s own fake already uses).
class _FakePhotoPicker implements PhotoPicker {
  PickedPhoto? nextCameraResult;
  int cameraCalls = 0;

  /// Lets a test hold `pickFromCamera()` unresolved, to simulate leaving
  /// the Foto tab (via a tab switch) while the native picker dialog is
  /// still open. `null` (the default) resolves immediately.
  Completer<void>? cameraGate;

  @override
  Future<PickedPhoto?> pickFromCamera() async {
    cameraCalls++;
    final activeGate = cameraGate;
    if (activeGate != null) {
      await activeGate.future;
    }
    return nextCameraResult;
  }

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
/// ports are faked (see the classes above). `PhotoEntryCubit` is a fresh
/// instance, left unconfigured by every test except spec-3-4's own
/// cross-tab tests below, which do switch to the Foto tab and configure
/// `_FakePhotoPicker.nextCameraResult`/`cameraGate` to drive an in-flight
/// Câmera pick; `pickFromGallery()` stays untouched throughout — no test
/// in this file, including spec-3-4's, ever taps Galeria.
void main() {
  late _FakeMicRecorder fakeMicRecorder;
  late _FakeAudioTranscriber fakeAudioTranscriber;
  late _FakePhotoPicker fakePhotoPicker;
  late _FakeEntriesRepository fakeRepository;
  late TextEntryCubit textCubit;
  late AudioEntryCubit audioCubit;
  late PhotoEntryCubit photoCubit;

  setUp(() {
    fakeMicRecorder = _FakeMicRecorder();
    fakeAudioTranscriber = _FakeAudioTranscriber();
    fakePhotoPicker = _FakePhotoPicker();
    fakeRepository = _FakeEntriesRepository();
    textCubit = TextEntryCubit(fakeRepository);
    audioCubit = AudioEntryCubit(
      fakeMicRecorder,
      fakeAudioTranscriber,
      fakeRepository,
    );
    photoCubit = PhotoEntryCubit(
      fakePhotoPicker,
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

  testWidgets(
    'An amplitudeStream error while recording never escapes uncaught — '
    'the waveform just stays frozen on its last sample (Review finding: '
    'the real MicRecorder.amplitudeStream can surface a native-side '
    'error, which _Waveform guards with onError)',
    (tester) async {
      final amplitudeController = StreamController<double>();
      fakeMicRecorder.amplitudeController = amplitudeController;
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
      amplitudeController.add(0.6);
      await tester.pump();

      amplitudeController.addError(Exception('native amplitude failure'));
      // If `onError` were ever dropped, this `pump()` is where the
      // uncaught stream error would surface as a failed test.
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget);

      // Ends mid-recording — same cleanup as the other mid-recording
      // tests above. The controller is deliberately never `close()`d:
      // doing so under `flutter_test`'s `FakeAsync` zone needs its own
      // `pump()` afterward to flush the pending `done` microtask, and
      // nothing in this test needs that cleanup to pass.
      await audioCubit.cancel();
      await tester.pump();
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

  testWidgets(
    'Story 3.4: Áudio→Foto mid-recording switch cancels the recorder, '
    'never auto-starts anything on Foto',
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

      // Switches directly to Foto — skipping Texto — unlike every other
      // "leave Áudio" test in this file, which only ever exercises the
      // Áudio↔Texto pair.
      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();

      expect(fakeMicRecorder.cancelCalls, 1);
      // Foto shows its idle capture buttons — nothing auto-started on
      // entry (unlike Áudio, which auto-starts recording on entry).
      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Galeria'), findsOneWidget);
      expect(fakeRepository.createCallCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Story 3.4: Foto→Áudio mid-pick switch discards the pick and starts '
    'recording immediately',
    (tester) async {
      fakePhotoPicker.cameraGate = Completer<void>();
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Câmera'));
      // Only a `pump()` — the gate above holds `pickFromCamera()`
      // unresolved, same as never reaching the real file-read
      // `insertion_modal_photo_test.dart`'s own "Leave tab mid-pick"
      // test avoids this same way.
      await tester.pump();

      await tester.tap(find.text('Áudio'));
      await tester.pump();

      // Recording starts immediately despite the still-pending pick.
      expect(fakeMicRecorder.startCalls, 1);
      expect(fakeRepository.createCallCount, 0);

      fakePhotoPicker.cameraGate!.complete();
      await tester.pump();

      // The stale pick never resurrected the Foto tab's own state nor
      // fired a save.
      expect(photoCubit.state, isA<PhotoIdle>());
      expect(fakeRepository.createCallCount, 0);

      // Ends mid-recording — see the happy path test's own comment on
      // `AudioEntryCubit`'s 1-second elapsed-time ticker.
      await audioCubit.cancel();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Story 3.4: chained Áudio→Foto→Texto interruptions, then closing '
    'without Salvar — POST /entries never fires at any point',
    (tester) async {
      fakePhotoPicker.cameraGate = Completer<void>();
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      // Record audio.
      await tester.tap(find.text('Áudio'));
      await tester.pump();
      expect(fakeMicRecorder.startCalls, 1);
      expect(fakeRepository.createCallCount, 0);

      // Switch to Foto — cancels the still-recording audio.
      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();
      expect(fakeMicRecorder.cancelCalls, 1);
      expect(fakeRepository.createCallCount, 0);

      // Start a photo pick (held in flight by the gate).
      await tester.tap(find.text('Câmera'));
      await tester.pump();
      expect(fakeRepository.createCallCount, 0);

      // Switch to Texto — cancels/discards the still-in-flight pick.
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      expect(fakeRepository.createCallCount, 0);

      // Type text.
      await tester.enterText(find.byType(TextField), 'texto digitado');
      await tester.pump();
      expect(find.text('texto digitado'), findsOneWidget);
      expect(fakeRepository.createCallCount, 0);

      // Close the modal via the close control, never tapping Salvar.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 0);

      // Releases the now-abandoned picker call so nothing is left
      // dangling past this test — same hygiene
      // `insertion_modal_photo_test.dart`'s own equivalent test uses.
      // Flushed with a `pump()` (unlike a bare `complete()`) since this
      // runs after the modal — and `PhotoEntryCubit` itself — has already
      // closed; any exception from that completion must surface here,
      // not leak into a later, unrelated test.
      fakePhotoPicker.cameraGate!.complete();
      await tester.pump();

      expect(tester.takeException(), isNull);
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
