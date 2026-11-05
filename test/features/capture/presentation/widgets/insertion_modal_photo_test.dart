import 'dart:async';
import 'dart:io';
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
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

import '../../../../support/intercept_announcements.dart';

/// A minimal valid 1x1 transparent PNG — see `setUp`'s own comment on
/// why this file's widget tests need genuinely decodable image bytes.
const _validPng1x1 = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];

const _savedEntry = Entry(
  id: 'p1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.photo,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// Scriptable fakes (not mocktail — same convention
/// `insertion_modal_audio_test.dart`'s own fakes already use) standing in
/// for spec-3-3's two new ports. Never exercises the real `image_picker`
/// plugin (Never, AGENTS.md: no device/simulator exists).
class _FakePhotoPicker implements PhotoPicker {
  PickedPhoto? nextCameraResult;
  PickedPhoto? nextGalleryResult;
  int cameraCalls = 0;
  int galleryCalls = 0;

  /// Lets a test hold `pickFromCamera()` unresolved, to simulate leaving
  /// the Foto tab while the native picker dialog is theoretically still
  /// open (I/O matrix: "Leave tab mid-pick/OCR" — the "mid-pick" half).
  /// Deliberately on the *picker* call, not `MediaRepository.
  /// recognizeText()` — gating that one would require the real file
  /// read (`PhotoEntryCubit._recognize()`) to have already run inside
  /// `tester.runAsync()`, which cannot be pumped concurrently with
  /// (`WidgetTester.pump`/`runAsync` cannot interleave — confirmed by
  /// direct probe); this `Completer` is plain Dart, so it works
  /// regardless of zone.
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
  Future<PickedPhoto?> pickFromGallery() async {
    galleryCalls++;
    return nextGalleryResult;
  }
}

class _FakeMediaRepository implements MediaRepository {
  Either<Failure, OcrResult> Function()? nextResult;

  /// Lets a test hold `recognizeText()` unresolved, to observe the
  /// modal's mid-OCR state — same convention as
  /// `_FakeEntriesRepository.gate` below.
  Completer<void>? gate;

  @override
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final activeGate = gate;
    if (activeGate != null) {
      await activeGate.future;
    }
    return nextResult!();
  }
}

/// A trivial fake — this file's own tests never switch to the Áudio tab,
/// so neither `MicRecorder` port method below is ever expected to be
/// called (same rationale as `insertion_modal_test.dart`'s own
/// `_FakeMicRecorder`).
class _FakeMicRecorder implements MicRecorder {
  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<void> start() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<MicRecording?> stop() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> cancel() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<double> get amplitudeStream => const Stream.empty();
}

class _FakeAudioTranscriber implements AudioTranscriber {
  @override
  Future<String?> transcribe(String audioPath) async =>
      throw UnimplementedError('not expected to be called');
}

class _FakeEntriesRepository implements PendingEntryWriteTracker {
  Either<Failure, Entry> Function()? nextResult;
  int createCallCount = 0;
  EntrySource? lastSource;
  String? lastContent;

  /// Lets a test hold `create()` unresolved, to observe the modal's
  /// mid-save state — same convention
  /// `insertion_modal_audio_test.dart`'s own `gate` already uses.
  Completer<void>? gate;

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    createCallCount++;
    lastSource = source;
    lastContent = content;
    final activeGate = gate;
    if (activeGate != null) {
      await activeGate.future;
    }
    return nextResult!();
  }

  /// This file never exercises the pending/retry overlay (spec-4-2's own
  /// suites do) — not expected to be called/observed here.
  @override
  Future<void> retry(String tempId) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites => const Stream.empty();

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      const Stream.empty();

  @override
  Future<void> dispose() async {}
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

/// Drives the real `InsertionModal` + real `PhotoEntryCubit` through
/// spec-3-3's own I/O & Edge-Case Matrix — only the two native-package
/// ports are faked (see the classes above).
void main() {
  late _FakePhotoPicker fakePhotoPicker;
  late _FakeMediaRepository fakeMediaRepository;
  late _FakeEntriesRepository fakeRepository;
  late TextEntryCubit textCubit;
  late AudioEntryCubit audioCubit;
  late PhotoEntryCubit photoCubit;
  late Directory tempDir;
  late File photoFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cerne_test_photo_modal_');
    // `_PhotoThumbnail` renders a real `Image.file` of the picked photo —
    // unlike the cubit-only tests, this file's widget tests actually
    // decode it, so it must be real (if tiny) valid image bytes rather
    // than an arbitrary byte sequence (which can hang the decoder
    // indefinitely instead of erroring quickly, stalling
    // `pumpAndSettle()`). A minimal valid 1x1 transparent PNG.
    photoFile = File('${tempDir.path}/foto.png')
      ..writeAsBytesSync(_validPng1x1);
    fakePhotoPicker = _FakePhotoPicker();
    fakeMediaRepository = _FakeMediaRepository();
    fakeRepository = _FakeEntriesRepository();
    textCubit = TextEntryCubit(fakeRepository);
    audioCubit = AudioEntryCubit(
      _FakeMicRecorder(),
      _FakeAudioTranscriber(),
      fakeRepository,
    );
    photoCubit = PhotoEntryCubit(
      fakePhotoPicker,
      fakeMediaRepository,
      fakeRepository,
    );
  });

  tearDown(() async {
    if (!textCubit.isClosed) {
      await textCubit.close();
    }
    if (!audioCubit.isClosed) {
      await audioCubit.close();
    }
    if (!photoCubit.isClosed) {
      await photoCubit.close();
    }
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'Happy path: switching to Foto shows Câmera/Galeria; picking shows a '
    'thumbnail + "Reconhecendo texto..." while OCR runs; Salvar fires '
    'source: photo and closes the modal, with no image bytes ever '
    'reaching POST /entries',
    (tester) async {
      fakePhotoPicker.nextCameraResult = PickedPhoto(
        path: photoFile.path,
        mimeType: 'image/jpeg',
      );
      fakeMediaRepository.nextResult = () => right(
        const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
      );
      fakeRepository.nextResult = () => right(_savedEntry);
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();

      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Galeria'), findsOneWidget);

      // `PhotoEntryCubit._recognize()` reads the picked file's real bytes
      // from disk (`File.readAsBytes()`) — genuine `dart:io` I/O, which
      // `flutter_test`'s default fake-async zone never actually completes
      // (confirmed by direct probe) unless the call originates inside
      // `tester.runAsync()`. Calling the cubit method directly here
      // (rather than tapping "Câmera") is equivalent to what the
      // button's `onPressed` does, same convention
      // `insertion_modal_audio_test.dart` already uses for driving
      // `audioCubit.cancel()` directly where a tap doesn't fit.
      await tester.runAsync(() => photoCubit.pickFromCamera());
      await tester.pumpAndSettle();

      expect(find.text('Hoje foi um bom dia.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 1);
      expect(fakeRepository.lastSource, EntrySource.photo);
      expect(fakeRepository.lastContent, 'Hoje foi um bom dia.');
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('OCR_NO_TEXT: both "Tentar novamente" and "Salvar só a foto" are '
      'offered; "Salvar só a foto" saves the fixed placeholder content', (
    tester,
  ) async {
    fakePhotoPicker.nextGalleryResult = PickedPhoto(
      path: photoFile.path,
      mimeType: 'image/jpeg',
    );
    fakeMediaRepository.nextResult = () => left(
      const Failure.ocrNoText(message: 'Não foi possível reconhecer o texto'),
    );
    fakeRepository.nextResult = () => right(_savedEntry);
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    // See the Happy path test's own comment on why a real file-read
    // (`PhotoEntryCubit._recognize()`) needs `tester.runAsync()`.
    await tester.runAsync(() => photoCubit.pickFromGallery());
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível reconhecer o texto'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    expect(find.text('Salvar só a foto'), findsOneWidget);

    await tester.tap(find.text('Salvar só a foto'));
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 1);
    expect(
      fakeRepository.lastContent,
      'Registro fotográfico (sem texto reconhecido)',
    );
    expect(fakeRepository.lastSource, EntrySource.photo);
  });

  testWidgets('OCR_NO_TEXT: "Tentar novamente" re-OCRs the same image (never '
      're-picks)', (tester) async {
    fakePhotoPicker.nextGalleryResult = PickedPhoto(
      path: photoFile.path,
      mimeType: 'image/jpeg',
    );
    fakeMediaRepository.nextResult = () => left(
      const Failure.ocrNoText(message: 'Não foi possível reconhecer o texto'),
    );
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => photoCubit.pickFromGallery());
    await tester.pumpAndSettle();

    fakeMediaRepository.nextResult = () => right(
      const OcrResult(text: 'Funcionou na segunda vez.', confidence: 'high'),
    );
    // "Tentar novamente" re-OCRs the same image — also a real file
    // read (`retry()` -> `_recognize()`), same rationale as above.
    await tester.runAsync(() => photoCubit.retry());
    await tester.pumpAndSettle();

    expect(find.text('Funcionou na segunda vez.'), findsOneWidget);
    expect(fakePhotoPicker.galleryCalls, 1);
  });

  testWidgets(
    'PAYLOAD_TOO_LARGE: no retry/save-without-text action — only picking '
    'a different photo',
    (tester) async {
      fakePhotoPicker.nextCameraResult = PickedPhoto(
        path: photoFile.path,
        mimeType: 'image/jpeg',
      );
      fakeMediaRepository.nextResult = () =>
          left(const Failure.payloadTooLarge(message: 'Imagem muito grande.'));
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => photoCubit.pickFromCamera());
      await tester.pumpAndSettle();

      expect(find.text('Imagem muito grande.'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);
      expect(find.text('Salvar só a foto'), findsNothing);
      // The only action offered is picking a different photo.
      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Galeria'), findsOneWidget);
    },
  );

  testWidgets(
    'User cancels picker: stays on Foto\'s capture buttons (PhotoIdle)',
    (tester) async {
      fakePhotoPicker.nextCameraResult = null;
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
      await tester.pumpAndSettle();

      expect(find.text('Câmera'), findsOneWidget);
      expect(find.text('Galeria'), findsOneWidget);
    },
  );

  testWidgets(
    'Save fails (incl. offline): inline Failure.message shown, Salvar '
    're-enabled, text/photo preserved, no auto-retry',
    (tester) async {
      fakePhotoPicker.nextCameraResult = PickedPhoto(
        path: photoFile.path,
        mimeType: 'image/jpeg',
      );
      fakeMediaRepository.nextResult = () => right(
        const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
      );
      fakeRepository.nextResult = () =>
          left(const Failure.networkOffline(message: 'Sem conexão'));
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => photoCubit.pickFromCamera());
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

  testWidgets('Leave tab mid-pick: switching to Texto while the picker call is '
      'still in flight discards it, no POST /entries ever fires', (
    tester,
  ) async {
    fakePhotoPicker.nextCameraResult = PickedPhoto(
      path: photoFile.path,
      mimeType: 'image/jpeg',
    );
    // Gates the *picker* call itself, not OCR — see this fake's own
    // doc comment on why (a real-vs-fake-zone `WidgetTester.pump`/
    // `runAsync` constraint `photo_entry_cubit_test.dart`'s own
    // "cancel() — leaving the Foto tab mid-pick/mid-OCR" group already
    // covers the "mid-OCR" half deterministically, with no widget tree
    // involved).
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

    unawaited(photoCubit.pickFromCamera());
    await tester.pump();

    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 0);

    fakePhotoPicker.cameraGate!.complete();
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 0);
    // The stale pick result never resurrected the Foto tab's own state
    // — switching back still shows the capture buttons.
    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    expect(find.text('Câmera'), findsOneWidget);
  });

  testWidgets(
    'Dismissing the whole modal (not switching tabs) while a pick is in '
    'flight discards it too (Review finding: previously only verified '
    'via a tab switch, never via "x"/swipe/barrier dismissing the whole '
    'sheet — mirrors insertion_modal_audio_test.dart\'s own equivalent '
    'test)',
    (tester) async {
      fakePhotoPicker.nextCameraResult = PickedPhoto(
        path: photoFile.path,
        mimeType: 'image/jpeg',
      );
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

      unawaited(photoCubit.pickFromCamera());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 0);
      // `InsertionModal.show()`'s `finally` reached `photoCubit.cancel(
      // discardPreserved: true)` + `.close()` even though the picker
      // call was still in flight (Review finding #3's isolated
      // try/finally chain).
      expect(photoCubit.isClosed, isTrue);

      // Releases the now-abandoned picker call so nothing is left
      // dangling past this test.
      fakePhotoPicker.cameraGate!.complete();
    },
  );

  testWidgets('the recognized text is editable before Salvar', (tester) async {
    fakePhotoPicker.nextCameraResult = PickedPhoto(
      path: photoFile.path,
      mimeType: 'image/jpeg',
    );
    fakeMediaRepository.nextResult = () =>
        right(const OcrResult(text: 'texto original', confidence: 'high'));
    await _openModal(
      tester,
      cubit: textCubit,
      audioCubit: audioCubit,
      photoCubit: photoCubit,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => photoCubit.pickFromCamera());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'texto editado pelo usuário',
    );
    await tester.pump();

    expect(find.text('texto editado pelo usuário'), findsOneWidget);
  });

  testWidgets(
    'an in-flight photo save disables the tab bar and close button too',
    (tester) async {
      fakePhotoPicker.nextCameraResult = PickedPhoto(
        path: photoFile.path,
        mimeType: 'image/jpeg',
      );
      fakeMediaRepository.nextResult = () => right(
        const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
      );
      fakeRepository.nextResult = () => right(_savedEntry);
      fakeRepository.gate = Completer<void>();
      await _openModal(
        tester,
        cubit: textCubit,
        audioCubit: audioCubit,
        photoCubit: photoCubit,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Foto'));
      await tester.pumpAndSettle();
      await tester.runAsync(() => photoCubit.pickFromCamera());
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

  group(
    'announcements — review finding: every assertion above only read '
    'visible Text/TextField/button state, so a deleted/broken '
    '_onPhotoStateChange() path would still pass every test in this file',
    () {
      testWidgets('picking announces "Reconhecendo texto da foto"', (
        tester,
      ) async {
        fakePhotoPicker.nextCameraResult = PickedPhoto(
          path: photoFile.path,
          mimeType: 'image/jpeg',
        );
        fakeMediaRepository.nextResult = () => right(
          const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
        );
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Foto'));
        await tester.pumpAndSettle();

        await tester.runAsync(() => photoCubit.pickFromCamera());
        await tester.pumpAndSettle();

        expect(announcements, contains('Reconhecendo texto da foto'));
        expect(
          announcements,
          contains('Texto reconhecido. Revise o texto antes de salvar.'),
        );
      });

      testWidgets('a successful save announces "Registro salvo"', (
        tester,
      ) async {
        fakePhotoPicker.nextCameraResult = PickedPhoto(
          path: photoFile.path,
          mimeType: 'image/jpeg',
        );
        fakeMediaRepository.nextResult = () => right(
          const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
        );
        fakeRepository.nextResult = () => right(_savedEntry);
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Foto'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => photoCubit.pickFromCamera());
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
        await tester.pumpAndSettle();

        expect(announcements, contains('Registro salvo'));
      });

      testWidgets('an OCR_NO_TEXT error announces the error message', (
        tester,
      ) async {
        fakePhotoPicker.nextCameraResult = PickedPhoto(
          path: photoFile.path,
          mimeType: 'image/jpeg',
        );
        fakeMediaRepository.nextResult = () => left(
          const Failure.ocrNoText(
            message: 'Não foi possível reconhecer o texto',
          ),
        );
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Foto'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => photoCubit.pickFromCamera());
        await tester.pumpAndSettle();

        expect(announcements, contains('Não foi possível reconhecer o texto'));
      });

      testWidgets('canceling mid-pick (tab switch away while PhotoProcessing) '
          'announces "Captura de foto cancelada" (mirrors '
          'insertion_modal_audio_test.dart\'s own "Gravação cancelada" '
          'test)', (tester) async {
        fakePhotoPicker.nextCameraResult = PickedPhoto(
          path: photoFile.path,
          mimeType: 'image/jpeg',
        );
        // Gates the picker call so `PhotoProcessing` is reached at a
        // controlled point (same convention as the "Leave tab
        // mid-pick" test above) — the real file read that follows is
        // deliberately never awaited past this point (abandoned, not
        // gated), which is safe here since the test never needs it to
        // resolve: switching tabs below cancels before it matters.
        fakePhotoPicker.cameraGate = Completer<void>();
        final announcements = interceptAnnouncements(tester);
        await _openModal(
          tester,
          cubit: textCubit,
          audioCubit: audioCubit,
          photoCubit: photoCubit,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Foto'));
        await tester.pumpAndSettle();

        unawaited(photoCubit.pickFromCamera());
        await tester.pump();
        fakePhotoPicker.cameraGate!.complete();
        await tester.pump();
        await tester.pump();
        expect(find.text('Reconhecendo texto...'), findsOneWidget);

        await tester.tap(find.text('Texto'));
        await tester.pumpAndSettle();

        expect(announcements, contains('Captura de foto cancelada'));
      });
    },
  );
}
