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
  id: 'e1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// A plain (non-mocktail) fake — same convention
/// `account_settings_cubit_test.dart` already uses — so a test can both
/// script the next `create()` result and count how many times it was
/// called (I/O matrix: "Cancel before save ... no `POST /entries` fires").
class _FakeEntriesRepository implements EntriesRepository {
  Either<Failure, Entry> Function()? nextResult;
  int createCallCount = 0;

  /// Lets a test hold `create()` unresolved, to observe the modal's
  /// mid-save state (review finding: the tab bar/close button must
  /// disable themselves while a save is in flight).
  Completer<void>? gate;

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async {
    createCallCount++;
    final activeGate = gate;
    if (activeGate != null) {
      await activeGate.future;
    }
    return nextResult!();
  }
}

/// A trivial fake — this file's own tests never switch to the Áudio tab,
/// so neither `MicRecorder` port method below is ever expected to be
/// called (same rationale as `_FakeEntriesRepository`'s own doc, applied
/// to spec-3-2's two new ports).
class _FakeMicRecorder implements MicRecorder {
  // This file's generic tab-switch tests (`_openModal`'s own default)
  // *do* switch into the Áudio tab (Code Map: tab-switch starts
  // recording), so `hasPermission()` must return something rather than
  // throw — `false` keeps the flow harmless (an `AudioError` state,
  // never touching `start`/`stop`/`cancel` below) for every test that
  // doesn't care about the audio pipeline's own details
  // (`audio_entry_cubit_test.dart` covers those with scriptable mocks).
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

/// A trivial fake — same rationale as `_FakeMicRecorder`'s own doc, for
/// spec-3-3's two new ports. This file's one Foto-tab test only checks
/// that the tab itself now renders real capture buttons (never actually
/// taps Câmera/Galeria), so neither method below is ever expected to be
/// called (`photo_entry_cubit_test.dart`/`insertion_modal_photo_test.dart`
/// cover the full pipeline with scriptable fakes/mocks).
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

/// Opens the real `InsertionModal` from a minimal host screen with an
/// "open" button — `InsertionModal.show` just needs a `BuildContext` with
/// a `Navigator` ancestor, same as `showModalBottomSheet` itself.
Future<void> _openModal(
  WidgetTester tester,
  TextEntryCubit cubit, {
  bool disableAnimations = false,
}) async {
  // Only `cubit` is scripted per test (`fakeRepository.nextResult`/`gate`)
  // — none of this file's tests ever switch to the Áudio/Foto tabs to do
  // anything beyond proving they render, so a fresh, never-configured
  // `AudioEntryCubit`/`PhotoEntryCubit` (backed by the trivial "not
  // expected to be called" fakes above) is always enough here.
  final audioCubit = AudioEntryCubit(
    _FakeMicRecorder(),
    _FakeAudioTranscriber(),
    _FakeEntriesRepository(),
  );
  final photoCubit = PhotoEntryCubit(
    _FakePhotoPicker(),
    _FakeMediaRepository(),
    _FakeEntriesRepository(),
  );
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MaterialApp(
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
    ),
  );
  await tester.tap(find.text('open'));
}

/// Covers spec-3-1's I/O & Edge-Case Matrix directly against the real
/// `InsertionModal` widget.
void main() {
  late _FakeEntriesRepository fakeRepository;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
  });

  testWidgets(
    'opens on Texto, all 3 tabs idle/empty — Salvar disabled with no text '
    '(Boundaries: "Opens on Texto, all 3 tabs idle/empty")',
    (tester) async {
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      expect(find.text('Texto'), findsOneWidget);
      expect(find.text('Áudio'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      final salvarButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Salvar'),
      );
      expect(salvarButton.onPressed, isNull);
    },
  );

  testWidgets('tapping Áudio switches to its own functional capture pipeline '
      '(spec-3-2 — superseding Story 3.1\'s idle placeholder for this tab); '
      'tapping Foto switches to its own functional capture buttons '
      '(spec-3-3 — superseding Story 3.1\'s idle placeholder for this tab '
      'too)', (tester) async {
    await _openModal(tester, TextEntryCubit(fakeRepository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Áudio'));
    await tester.pumpAndSettle();

    // This file's own `_FakeMicRecorder.hasPermission()` always denies
    // — `audio_entry_cubit_test.dart` covers the full pipeline with
    // scriptable mocks; this just proves the tab is real UI now, not
    // Story 3.1's old idle placeholder.
    expect(find.text('Áudio chega em breve'), findsNothing);
    expect(find.text('Tentar novamente'), findsOneWidget);

    await tester.tap(find.text('Foto'));
    await tester.pumpAndSettle();

    // Same rationale, for Foto: `photo_entry_cubit_test.dart`/
    // `insertion_modal_photo_test.dart` cover the full pipeline with
    // scriptable fakes/mocks; this just proves the tab is real UI now.
    expect(find.text('Foto chega em breve'), findsNothing);
    expect(find.text('Câmera'), findsOneWidget);
    expect(find.text('Galeria'), findsOneWidget);
  });

  testWidgets('typing non-empty text enables Salvar', (tester) async {
    await _openModal(tester, TextEntryCubit(fakeRepository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
    await tester.pump();

    final salvarButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Salvar'),
    );
    expect(salvarButton.onPressed, isNotNull);
  });

  testWidgets('Happy path save: POST fires, success closes the modal', (
    tester,
  ) async {
    fakeRepository.nextResult = () => right(_savedEntry);
    await _openModal(tester, TextEntryCubit(fakeRepository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Salvar'), findsNothing);
  });

  testWidgets(
    'Save fails (incl. offline): inline Failure.message shown, Salvar '
    're-enabled, modal stays open, no auto-retry',
    (tester) async {
      fakeRepository.nextResult = () =>
          left(const Failure.networkOffline(message: 'Sem conexão'));
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.createCallCount, 1);
      expect(find.text('Sem conexão'), findsOneWidget);
      // Still open, and Salvar is enabled again (text is still present).
      final salvarButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Salvar'),
      );
      expect(salvarButton.onPressed, isNotNull);
    },
  );

  testWidgets('Cancel before save: "x" closes/resets the modal without ever '
      'calling create()', (tester) async {
    await _openModal(tester, TextEntryCubit(fakeRepository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'texto não salvo');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(fakeRepository.createCallCount, 0);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Reduce Motion (MediaQuery.disableAnimations) skips the sheetUp '
      'entrance — the sheet is already fully in place after a single pump', (
    tester,
  ) async {
    await _openModal(
      tester,
      TextEntryCubit(fakeRepository),
      disableAnimations: true,
    );
    // Exactly one pump (not pumpAndSettle) — if the entrance animation
    // weren't skipped, the sheet would still be mid-transition here.
    await tester.pump();

    expect(find.text('Texto'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  group('announcements — review finding: every assertion above only read '
      'visible Text/TextField/button state, so a deleted/broken _announce() '
      'call would still pass every test in this file', () {
    testWidgets('a tab switch announces the newly active tab', (tester) async {
      final announcements = interceptAnnouncements(tester);
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Áudio'));
      await tester.pumpAndSettle();

      expect(announcements, contains('Aba Áudio selecionada'));
    });

    testWidgets(
      'typing (which also re-emits TextEntryIdle, same as a tab switch) '
      'never re-announces the already-active tab',
      (tester) async {
        final announcements = interceptAnnouncements(tester);
        await _openModal(tester, TextEntryCubit(fakeRepository));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'texto');
        await tester.pump();

        expect(announcements, isNot(contains('Aba Texto selecionada')));
      },
    );

    testWidgets('Salvar tapped announces "Salvando registro"', (tester) async {
      fakeRepository.nextResult = () => right(_savedEntry);
      fakeRepository.gate = Completer<void>();
      final announcements = interceptAnnouncements(tester);
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pump();

      expect(announcements, contains('Salvando registro'));

      fakeRepository.gate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a successful save announces "Registro salvo"', (tester) async {
      fakeRepository.nextResult = () => right(_savedEntry);
      final announcements = interceptAnnouncements(tester);
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(announcements, contains('Registro salvo'));
    });

    testWidgets('a failed save announces the Failure.message verbatim', (
      tester,
    ) async {
      fakeRepository.nextResult = () =>
          left(const Failure.networkOffline(message: 'Sem conexão'));
      final announcements = interceptAnnouncements(tester);
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pumpAndSettle();

      expect(announcements, contains('Sem conexão'));
    });
  });

  group('in-flight save disables the tab bar and close button (review '
      'finding: a race where switching tabs or tapping "x" mid-save let a '
      'stale save() call land its result against a tab/text the user had '
      'already left)', () {
    testWidgets('the tab bar and "x" are disabled while Salvar is in flight, '
        're-enabled once it resolves', (tester) async {
      fakeRepository.nextResult = () => right(_savedEntry);
      fakeRepository.gate = Completer<void>();
      await _openModal(tester, TextEntryCubit(fakeRepository));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hoje foi um bom dia.');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salvar'));
      await tester.pump();

      // Tapping "Áudio" or "x" while saving must not do anything —
      // both InkWells are disabled (onTap: null).
      final audioInkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('Áudio'), matching: find.byType(InkWell))
            .first,
      );
      expect(audioInkWell.onTap, isNull);

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
    });
  });
}
