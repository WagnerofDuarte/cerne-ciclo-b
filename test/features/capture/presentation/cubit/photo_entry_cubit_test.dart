import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';
import 'package:cerne/features/capture/domain/services/photo_picker.dart';
import 'package:cerne/features/capture/presentation/cubit/photo_entry_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';

/// `_deletePickedFile`/`_pick`'s own replace-on-fresh-pick cleanup are
/// both fire-and-forget (`unawaited`) by design — a single microtask
/// tick isn't a reliable enough wait for a real `dart:io` file-delete to
/// land under full-suite load, so assertions on the resulting file poll
/// instead, bounded to avoid hanging if the delete genuinely never
/// happens. Mirrors `audio_entry_cubit_test.dart`'s own helper.
Future<void> _waitUntilDeleted(File file) async {
  for (var i = 0; i < 50 && file.existsSync(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class MockPhotoPicker extends Mock implements PhotoPicker {}

class MockMediaRepository extends Mock implements MediaRepository {}

class MockEntriesRepository extends Mock implements EntriesRepository {}

const _savedEntry = Entry(
  id: 'p1',
  content: 'Texto da foto.',
  source: EntrySource.photo,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// Covers spec-3-3's I/O & Edge-Case Matrix at the cubit layer — both
/// `PhotoPicker`/`MediaRepository` are mocked (mocktail), same
/// convention as `audio_entry_cubit_test.dart` (Never: no automated test
/// exercises the real `image_picker` native plugin).
void main() {
  late MockPhotoPicker mockPhotoPicker;
  late MockMediaRepository mockMediaRepository;
  late MockEntriesRepository mockRepository;
  late PhotoEntryCubit cubit;
  late Directory tempDir;
  late File photoFile;

  setUpAll(() {
    registerFallbackValue(EntrySource.photo);
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cerne_test_photo_cubit_');
    photoFile = File('${tempDir.path}/foto.jpg')..writeAsBytesSync([1, 2, 3]);
    mockPhotoPicker = MockPhotoPicker();
    mockMediaRepository = MockMediaRepository();
    mockRepository = MockEntriesRepository();
    cubit = PhotoEntryCubit(
      mockPhotoPicker,
      mockMediaRepository,
      mockRepository,
    );
  });

  tearDown(() async {
    await cubit.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('starts PhotoIdle', () {
    expect(cubit.state, isA<PhotoIdle>());
  });

  group('pickFromCamera()', () {
    test('happy path: PhotoProcessing then PhotoRecognized carrying the '
        'recognized text', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => right(
          const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
        ),
      );

      final emitted = <PhotoCaptureState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.pickFromCamera();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [isA<PhotoProcessing>(), isA<PhotoRecognized>()]);
      final recognized = cubit.state as PhotoRecognized;
      expect(recognized.text, 'Hoje foi um bom dia.');
      expect(recognized.path, photoFile.path);
      expect(recognized.mimeType, 'image/jpeg');
      expect(recognized.saving, isFalse);
      // `Uint8List`/`List` use identity equality, not content equality,
      // so the actual bytes read from disk are captured and compared
      // via `equals` (deep) rather than matched directly in `verify`.
      final captured = verify(
        () => mockMediaRepository.recognizeText(
          imageBytes: captureAny(named: 'imageBytes'),
          mimeType: 'image/jpeg',
        ),
      ).captured;
      expect(captured.single, equals([1, 2, 3]));
    });

    test('user cancels (null) -> stays PhotoIdle, OCR never called', () async {
      when(() => mockPhotoPicker.pickFromCamera())
          .thenAnswer((_) async => null);

      await cubit.pickFromCamera();

      expect(cubit.state, isA<PhotoIdle>());
      verifyNever(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      );
    });

    test(
      'the picker throwing (native PlatformException) -> stays PhotoIdle, '
      'never escapes uncaught (mirrors AudioEntryCubit\'s own catch)',
      () async {
        when(() => mockPhotoPicker.pickFromCamera())
            .thenThrow(Exception('native failure'));

        await cubit.pickFromCamera();

        expect(cubit.state, isA<PhotoIdle>());
      },
    );

    test('ignored while already picking/processing', () async {
      final pickCompleter = Completer<PickedPhoto?>();
      when(() => mockPhotoPicker.pickFromCamera())
          .thenAnswer((_) => pickCompleter.future);

      final firstPick = cubit.pickFromCamera();
      await cubit.pickFromCamera();

      verify(() => mockPhotoPicker.pickFromCamera()).called(1);
      pickCompleter.complete(null);
      await firstPick;
    });
  });

  group('pickFromGallery()', () {
    test('calls PhotoPicker.pickFromGallery()', () async {
      when(() => mockPhotoPicker.pickFromGallery())
          .thenAnswer((_) async => null);

      await cubit.pickFromGallery();

      verify(() => mockPhotoPicker.pickFromGallery()).called(1);
      verifyNever(() => mockPhotoPicker.pickFromCamera());
    });
  });

  group('OCR failures', () {
    Future<void> pick() async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
    }

    test('OCR_NO_TEXT -> PhotoError(kind: ocrNoText), text null', () async {
      await pick();
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.ocrNoText(message: 'Nenhum texto.')),
      );

      await cubit.pickFromCamera();

      expect(
        cubit.state,
        isA<PhotoError>()
            .having((s) => s.kind, 'kind', PhotoErrorKind.ocrNoText)
            .having((s) => s.text, 'text', isNull)
            .having((s) => s.message, 'message', 'Nenhum texto.'),
      );
    });

    test(
      'PAYLOAD_TOO_LARGE -> PhotoError(kind: payloadTooLarge), text null',
      () async {
        await pick();
        when(
          () => mockMediaRepository.recognizeText(
            imageBytes: any(named: 'imageBytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer(
          (_) async => left(
            const Failure.payloadTooLarge(message: 'Imagem muito grande.'),
          ),
        );

        await cubit.pickFromCamera();

        expect(
          cubit.state,
          isA<PhotoError>()
              .having((s) => s.kind, 'kind', PhotoErrorKind.payloadTooLarge)
              .having((s) => s.text, 'text', isNull),
        );
      },
    );

    test('any other Failure (e.g. offline) -> PhotoError(kind: generic), '
        'text null', () async {
      await pick();
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
      );

      await cubit.pickFromCamera();

      expect(
        cubit.state,
        isA<PhotoError>()
            .having((s) => s.kind, 'kind', PhotoErrorKind.generic)
            .having((s) => s.text, 'text', isNull)
            .having((s) => s.message, 'message', 'Sem conexão'),
      );
    });

    test('an unreadable picked file -> PhotoError(kind: generic), never '
        'escapes uncaught', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => const PickedPhoto(
          path: '/nonexistent/path.jpg',
          mimeType: 'image/jpeg',
        ),
      );

      await cubit.pickFromCamera();

      expect(
        cubit.state,
        isA<PhotoError>().having((s) => s.kind, 'kind', PhotoErrorKind.generic),
      );
      verifyNever(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      );
    });
  });

  group('retry()', () {
    Future<void> reachError(Failure failure) async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) async => left(failure));
      await cubit.pickFromCamera();
    }

    test('ocrNoText -> re-OCRs the same image', () async {
      await reachError(const Failure.ocrNoText(message: 'Nenhum texto.'));
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const OcrResult(text: 'Funcionou.', confidence: 'high')),
      );

      await cubit.retry();

      expect(
        cubit.state,
        isA<PhotoRecognized>().having((s) => s.text, 'text', 'Funcionou.'),
      );
      verify(() => mockPhotoPicker.pickFromCamera()).called(1);
    });

    test(
      'generic OCR-call failure (text null) -> re-OCRs the same image',
      () async {
        await reachError(const Failure.networkOffline(message: 'Sem conexão'));
        when(
          () => mockMediaRepository.recognizeText(
            imageBytes: any(named: 'imageBytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer(
          (_) async =>
              right(const OcrResult(text: 'Funcionou.', confidence: 'high')),
        );

        await cubit.retry();

        expect(cubit.state, isA<PhotoRecognized>());
      },
    );

    test('payloadTooLarge -> a no-op (no retry offered)', () async {
      await reachError(
        const Failure.payloadTooLarge(message: 'Imagem muito grande.'),
      );

      await cubit.retry();

      expect(cubit.state, isA<PhotoError>());
      verify(() => mockPhotoPicker.pickFromCamera()).called(1);
    });

    test('a no-op for a save failure (generic, text non-null) — Salvar, not '
        'retry, is that case\'s own recovery path', () async {
      await reachError(const Failure.ocrNoText(message: 'Nenhum texto.'));
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
      );
      await cubit.saveWithoutText();
      final errorState = cubit.state as PhotoError;
      expect(errorState.text, isNotNull);

      await cubit.retry();

      expect(cubit.state, same(errorState));
    });

    test('a no-op outside PhotoError', () async {
      await cubit.retry();

      expect(cubit.state, isA<PhotoIdle>());
    });
  });

  group('saveWithoutText()', () {
    test('only valid from an ocrNoText error — saves the fixed placeholder '
        'content with source: photo', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.ocrNoText(message: 'Nenhum texto.')),
      );
      await cubit.pickFromCamera();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_savedEntry));

      await cubit.saveWithoutText();

      expect(cubit.state, isA<PhotoSaved>());
      verify(
        () => mockRepository.create(
          content: 'Registro fotográfico (sem texto reconhecido)',
          source: EntrySource.photo,
        ),
      ).called(1);
    });

    test('a no-op from PhotoIdle', () async {
      await cubit.saveWithoutText();

      expect(cubit.state, isA<PhotoIdle>());
      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      );
    });

    test('a no-op from a payloadTooLarge error', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => left(
          const Failure.payloadTooLarge(message: 'Imagem muito grande.'),
        ),
      );
      await cubit.pickFromCamera();

      await cubit.saveWithoutText();

      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      );
    });
  });

  group('updateText()', () {
    Future<PhotoRecognized> recognizedState() async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const OcrResult(text: 'texto original', confidence: 'high')),
      );
      await cubit.pickFromCamera();
      return cubit.state as PhotoRecognized;
    }

    test('mirrors the typed text into state while recognized', () async {
      await recognizedState();

      cubit.updateText('texto editado');

      expect(
        cubit.state,
        isA<PhotoRecognized>().having((s) => s.text, 'text', 'texto editado'),
      );
    });

    test('ignored outside PhotoRecognized/a save-failure PhotoError', () {
      cubit.updateText('nada deveria acontecer');

      expect(cubit.state, isA<PhotoIdle>());
    });

    test('ignored while a save is already in flight', () async {
      await recognizedState();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) => completer.future);

      final saveFuture = cubit.save();
      cubit.updateText('tentativa de editar durante o save');

      expect(
        cubit.state,
        isA<PhotoRecognized>().having((s) => s.text, 'text', 'texto original'),
      );

      completer.complete(right(_savedEntry));
      await saveFuture;
    });
  });

  group('save()', () {
    Future<void> reachRecognized() async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => right(
          const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
        ),
      );
      await cubit.pickFromCamera();
    }

    test('happy path -> saving then PhotoSaved, source always photo', () async {
      await reachRecognized();
      when(
        () => mockRepository.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.photo,
        ),
      ).thenAnswer((_) async => right(_savedEntry));

      final emitted = <PhotoCaptureState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.save();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [
        isA<PhotoRecognized>().having((s) => s.saving, 'saving', true),
        isA<PhotoSaved>(),
      ]);
      verify(
        () => mockRepository.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.photo,
        ),
      ).called(1);
    });

    test('failure (incl. offline) -> PhotoError(kind: generic, text non-null), '
        'Salvar re-enabled, no auto-retry', () async {
      await reachRecognized();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
      );

      await cubit.save();

      expect(
        cubit.state,
        isA<PhotoError>()
            .having((s) => s.kind, 'kind', PhotoErrorKind.generic)
            .having((s) => s.message, 'message', 'Sem conexão')
            .having((s) => s.text, 'text', 'Hoje foi um bom dia.')
            .having((s) => s.path, 'path', photoFile.path),
      );
    });

    test('tapping Salvar again after a save failure retries create() with '
        'the (possibly edited) text', () async {
      await reachRecognized();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
      );
      await cubit.save();
      cubit.updateText('texto corrigido');
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_savedEntry));

      await cubit.save();

      expect(cubit.state, isA<PhotoSaved>());
      verify(
        () => mockRepository.create(
          content: 'texto corrigido',
          source: EntrySource.photo,
        ),
      ).called(1);
    });

    test('blank/whitespace-only text never calls create()', () async {
      await reachRecognized();
      cubit.updateText('   ');

      await cubit.save();

      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      );
    });

    test('ignored outside PhotoRecognized/an eligible PhotoError', () async {
      await cubit.save();

      verifyNever(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      );
      expect(cubit.state, isA<PhotoIdle>());
    });

    test('ignored while already saving (no double-submit)', () async {
      await reachRecognized();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) => completer.future);

      final firstSave = cubit.save();
      await cubit.save();

      verify(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).called(1);

      completer.complete(right(_savedEntry));
      await firstSave;
    });

    test('happy path deletes the picked photo\'s real temp file after a '
        'successful save (Review finding: the picked file was never '
        'cleaned up at all before this fix)', () async {
      await reachRecognized();
      expect(photoFile.existsSync(), isTrue);
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) async => right(_savedEntry));

      await cubit.save();
      await _waitUntilDeleted(photoFile);

      expect(photoFile.existsSync(), isFalse);
    });
  });

  group('cancel() — leaving the Foto tab mid-pick/mid-OCR', () {
    test('while processing -> resets to PhotoIdle, drops the stale OCR '
        'result instead of resurrecting the flow', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      final recognizeCompleter = Completer<Either<Failure, OcrResult>>();
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer((_) => recognizeCompleter.future);

      final pickFuture = cubit.pickFromCamera();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<PhotoProcessing>());

      await cubit.cancel();
      expect(cubit.state, isA<PhotoIdle>());

      recognizeCompleter.complete(
        right(const OcrResult(text: 'chegou tarde demais', confidence: 'high')),
      );
      await pickFuture;

      expect(cubit.state, isA<PhotoIdle>());
    });

    test('a no-op outside PhotoProcessing — PhotoRecognized/PhotoError are '
        'preserved for a tab switch back', () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => right(const OcrResult(text: 'texto', confidence: 'high')),
      );
      await cubit.pickFromCamera();
      final recognized = cubit.state;

      await cubit.cancel();

      expect(cubit.state, same(recognized));
    });

    test('a no-op from PhotoIdle', () async {
      await cubit.cancel();

      expect(cubit.state, isA<PhotoIdle>());
    });

    test('resets _picking even when called before PhotoProcessing is '
        'reached (Review finding: otherwise a pick abandoned mid-native-'
        'call left a later pick attempt silently dropped by the !_picking '
        'guard, forever)', () async {
      final pickCompleter = Completer<PickedPhoto?>();
      when(() => mockPhotoPicker.pickFromCamera())
          .thenAnswer((_) => pickCompleter.future);
      final firstPick = cubit.pickFromCamera();

      await cubit.cancel();
      // Lets the now-generation-mismatched first pick's completion
      // (once the native call eventually resolves) land harmlessly.
      pickCompleter.complete(null);
      await firstPick;

      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => right(const OcrResult(text: 'texto', confidence: 'high')),
      );

      await cubit.pickFromCamera();

      expect(cubit.state, isA<PhotoRecognized>());
    });

    test(
      'a photo picked just as the user left the tab (generation mismatch) '
      'is deleted instead of leaking its temp file forever (Review '
      'finding)',
      () async {
        final abandonedFile = File('${tempDir.path}/abandonada.jpg')
          ..writeAsBytesSync([7, 8, 9]);
        final pickCompleter = Completer<PickedPhoto?>();
        when(
          () => mockPhotoPicker.pickFromCamera(),
        ).thenAnswer((_) => pickCompleter.future);
        final firstPick = cubit.pickFromCamera();

        await cubit.cancel();
        // The native picker call finally resolves with a real photo after
        // the user already left the tab — must not leak this file.
        pickCompleter.complete(
          PickedPhoto(path: abandonedFile.path, mimeType: 'image/jpeg'),
        );
        await firstPick;

        await _waitUntilDeleted(abandonedFile);
        expect(abandonedFile.existsSync(), isFalse);
        expect(cubit.state, isA<PhotoIdle>());
      },
    );

    group('discardPreserved', () {
      test(
        'false (default) — a no-op for PhotoRecognized, preserving both '
        'the state and its picked file for a later tab switch back',
        () async {
          when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
            (_) async =>
                PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
          );
          when(
            () => mockMediaRepository.recognizeText(
              imageBytes: any(named: 'imageBytes'),
              mimeType: any(named: 'mimeType'),
            ),
          ).thenAnswer(
            (_) async =>
                right(const OcrResult(text: 'texto', confidence: 'high')),
          );
          await cubit.pickFromCamera();
          final recognized = cubit.state;

          await cubit.cancel();

          expect(cubit.state, same(recognized));
          expect(photoFile.existsSync(), isTrue);
        },
      );

      test('true — deletes the preserved picked file for PhotoRecognized '
          '(Review finding: InsertionModal.show()\'s full-modal-dismiss '
          'path, which never switches back to the tab, so the file would '
          'otherwise leak forever once close() follows)', () async {
        when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
          (_) async =>
              PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
        );
        when(
          () => mockMediaRepository.recognizeText(
            imageBytes: any(named: 'imageBytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer(
          (_) async =>
              right(const OcrResult(text: 'texto', confidence: 'high')),
        );
        await cubit.pickFromCamera();
        expect(photoFile.existsSync(), isTrue);

        await cubit.cancel(discardPreserved: true);
        await _waitUntilDeleted(photoFile);

        expect(photoFile.existsSync(), isFalse);
      });

      test('true — also deletes the preserved file for a file-carrying '
          'PhotoError (e.g. a failed OCR awaiting retry)', () async {
        when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
          (_) async =>
              PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
        );
        when(
          () => mockMediaRepository.recognizeText(
            imageBytes: any(named: 'imageBytes'),
            mimeType: any(named: 'mimeType'),
          ),
        ).thenAnswer(
          (_) async => left(const Failure.ocrNoText(message: 'Nenhum texto.')),
        );
        await cubit.pickFromCamera();
        expect(cubit.state, isA<PhotoError>());
        expect(photoFile.existsSync(), isTrue);

        await cubit.cancel(discardPreserved: true);
        await _waitUntilDeleted(photoFile);

        expect(photoFile.existsSync(), isFalse);
      });

      test('true — a no-op from PhotoIdle (no file to delete)', () async {
        await cubit.cancel(discardPreserved: true);

        expect(cubit.state, isA<PhotoIdle>());
      });
    });
  });

  test('cancel() mid-retry-re-recognition resets to PhotoIdle and drops the '
      'eventual stale result instead of resurrecting the flow', () async {
    when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
      (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
    );
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer(
      (_) async => left(const Failure.ocrNoText(message: 'Nenhum texto.')),
    );
    await cubit.pickFromCamera();
    expect(cubit.state, isA<PhotoError>());

    final retryCompleter = Completer<Either<Failure, OcrResult>>();
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) => retryCompleter.future);

    final retryFuture = cubit.retry();
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, isA<PhotoProcessing>());

    await cubit.cancel();
    expect(cubit.state, isA<PhotoIdle>());

    retryCompleter.complete(
      right(const OcrResult(text: 'chegou tarde demais', confidence: 'high')),
    );
    await retryFuture;

    expect(cubit.state, isA<PhotoIdle>());
  });

  test('picking again from a payloadTooLarge error (the only error that '
      'offers it) re-OCRs a newly picked photo', () async {
    // A genuinely distinct second file — `image_picker` always returns a
    // fresh temp path per pick, and the cubit now deletes the abandoned
    // first file once the second pick lands (Review finding), so
    // reusing `photoFile`'s own path for both would make the second
    // `File.readAsBytes()` fail against a file this same test just had
    // deleted out from under it.
    final secondPhotoFile = File('${tempDir.path}/foto2.jpg')
      ..writeAsBytesSync([4, 5, 6]);
    when(() => mockPhotoPicker.pickFromGallery()).thenAnswer(
      (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
    );
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer(
      (_) async =>
          left(const Failure.payloadTooLarge(message: 'Imagem muito grande.')),
    );
    await cubit.pickFromGallery();
    expect(cubit.state, isA<PhotoError>());

    when(() => mockPhotoPicker.pickFromGallery()).thenAnswer(
      (_) async =>
          PickedPhoto(path: secondPhotoFile.path, mimeType: 'image/jpeg'),
    );
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer(
      (_) async => right(const OcrResult(text: 'texto', confidence: 'high')),
    );

    await cubit.pickFromGallery();

    expect(cubit.state, isA<PhotoRecognized>());
    verify(() => mockPhotoPicker.pickFromGallery()).called(2);
  });

  test('picking again from a payloadTooLarge error deletes the abandoned '
      'first file (Review finding: a fresh pick replacing a previous '
      'error\'s file must not leak it)', () async {
    when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
      (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
    );
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer(
      (_) async =>
          left(const Failure.payloadTooLarge(message: 'Imagem muito grande.')),
    );
    await cubit.pickFromCamera();
    expect(cubit.state, isA<PhotoError>());
    expect(photoFile.existsSync(), isTrue);

    final secondPhotoFile = File('${tempDir.path}/foto2.jpg')
      ..writeAsBytesSync([4, 5, 6]);
    when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
      (_) async =>
          PickedPhoto(path: secondPhotoFile.path, mimeType: 'image/jpeg'),
    );
    when(
      () => mockMediaRepository.recognizeText(
        imageBytes: any(named: 'imageBytes'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer(
      (_) async => right(const OcrResult(text: 'texto', confidence: 'high')),
    );

    await cubit.pickFromCamera();
    await _waitUntilDeleted(photoFile);

    expect(photoFile.existsSync(), isFalse);
    expect(secondPhotoFile.existsSync(), isTrue);
  });

  test(
    'picking again from a payloadTooLarge error still deletes the '
    'abandoned first file even when the re-pick is itself canceled '
    '(Review finding: the fix deletes the old file unconditionally as '
    'soon as a new pick starts, independent of how that new pick ends — '
    'the happy-path test above only exercises the re-pick-succeeds case)',
    () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => left(
          const Failure.payloadTooLarge(message: 'Imagem muito grande.'),
        ),
      );
      await cubit.pickFromCamera();
      expect(cubit.state, isA<PhotoError>());
      expect(photoFile.existsSync(), isTrue);

      // The re-pick is canceled (user dismisses the picker with no file
      // chosen) — the old abandoned file must still be gone.
      when(
        () => mockPhotoPicker.pickFromCamera(),
      ).thenAnswer((_) async => null);

      await cubit.pickFromCamera();
      await _waitUntilDeleted(photoFile);

      expect(photoFile.existsSync(), isFalse);
      expect(cubit.state, isA<PhotoIdle>());
    },
  );

  test(
    'emit() after close() never throws (a save racing a modal dismiss)',
    () async {
      when(() => mockPhotoPicker.pickFromCamera()).thenAnswer(
        (_) async => PickedPhoto(path: photoFile.path, mimeType: 'image/jpeg'),
      );
      when(
        () => mockMediaRepository.recognizeText(
          imageBytes: any(named: 'imageBytes'),
          mimeType: any(named: 'mimeType'),
        ),
      ).thenAnswer(
        (_) async => right(
          const OcrResult(text: 'Hoje foi um bom dia.', confidence: 'high'),
        ),
      );
      await cubit.pickFromCamera();
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockRepository.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) => completer.future);

      final saveFuture = cubit.save();
      await cubit.close();
      completer.complete(right(_savedEntry));

      await expectLater(saveFuture, completes);
    },
  );
}
