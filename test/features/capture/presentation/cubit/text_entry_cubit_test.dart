import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

class MockPendingEntryWriteTracker extends Mock
    implements PendingEntryWriteTracker {}

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

/// Covers spec-3-1's I/O & Edge-Case Matrix at the cubit layer:
/// - "Modal open resets" -> a fresh cubit always starts `TextEntryIdle`
///   on `CaptureTab.texto` with empty text.
/// - "Happy path save" -> `TextEntrySaving` then `TextEntrySaved`, source
///   always `manual`.
/// - "Save fails (incl. offline)" -> `TextEntrySaving` then
///   `TextEntryError` carrying `Failure.message` verbatim.
/// - "Cancel before save" -> covered at the widget layer
///   (`insertion_modal_test.dart`), since this cubit never calls `create`
///   except from `save()`.
void main() {
  late MockPendingEntryWriteTracker mockTracker;
  late TextEntryCubit cubit;

  setUpAll(() {
    registerFallbackValue(EntrySource.manual);
  });

  setUp(() {
    mockTracker = MockPendingEntryWriteTracker();
    cubit = TextEntryCubit(mockTracker);
  });

  tearDown(() => cubit.close());

  test('starts TextEntryIdle on CaptureTab.texto with empty text (Boundaries: '
      '"Opens on Texto, all 3 tabs idle/empty")', () {
    expect(
      cubit.state,
      isA<TextEntryIdle>()
          .having((s) => s.activeTab, 'activeTab', CaptureTab.texto)
          .having((s) => s.text, 'text', ''),
    );
  });

  group('selectTab', () {
    test('switches activeTab, preserving the current text', () {
      cubit.updateText('rascunho');

      cubit.selectTab(CaptureTab.audio);

      expect(
        cubit.state,
        isA<TextEntryIdle>()
            .having((s) => s.activeTab, 'activeTab', CaptureTab.audio)
            .having((s) => s.text, 'text', 'rascunho'),
      );
    });

    test('selecting the already-active tab is a no-op (no new emission)', () {
      final emitted = <TextEntryState>[];
      final subscription = cubit.stream.listen(emitted.add);

      cubit.selectTab(CaptureTab.texto);

      expect(emitted, isEmpty);
      subscription.cancel();
    });
  });

  group('updateText', () {
    test('mirrors the typed text into state while idle', () {
      cubit.updateText('um rascunho');

      expect(cubit.state.text, 'um rascunho');
      expect(cubit.state, isA<TextEntryIdle>());
    });

    test('ignored while a save is already in flight', () async {
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockTracker.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) => completer.future);
      cubit.updateText('texto original');

      final saveFuture = cubit.save();
      cubit.updateText('tentativa de editar durante o save');

      expect(cubit.state.text, 'texto original');

      completer.complete(right(_savedEntry));
      await saveFuture;
    });
  });

  group('save() — happy path', () {
    test('blank/whitespace-only text never calls create()', () async {
      cubit.updateText('   ');

      await cubit.save();

      verifyNever(
        () => mockTracker.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      );
      expect(cubit.state, isA<TextEntryIdle>());
    });

    test('non-empty text -> TextEntrySaving then TextEntrySaved, source '
        'always manual (Boundaries)', () async {
      when(
        () => mockTracker.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        ),
      ).thenAnswer((_) async => right(_savedEntry));
      cubit.updateText('Hoje foi um bom dia.');

      final emitted = <TextEntryState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.save();
      // Cubit's stream delivers via a microtask per emission — this
      // drains the one still pending after `save()`'s own last `emit()`
      // returns, same rationale
      // `account_settings_repository_impl_test.dart`'s own
      // `emittedDuring` helper already documents.
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [isA<TextEntrySaving>(), isA<TextEntrySaved>()]);
      verify(
        () => mockTracker.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        ),
      ).called(1);
    });
  });

  group('save() — failure (incl. offline)', () {
    test('TextEntrySaving then TextEntryError carrying Failure.message '
        'verbatim — modal stays open, no auto-retry', () async {
      when(
        () => mockTracker.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Sem conexão')),
      );
      cubit.updateText('Hoje foi um bom dia.');

      final emitted = <TextEntryState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.save();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [isA<TextEntrySaving>(), isA<TextEntryError>()]);
      final errorState = cubit.state as TextEntryError;
      expect(errorState.message, 'Sem conexão');
      // Re-enabled: the text is preserved so the user can retry Salvar
      // manually.
      expect(errorState.text, 'Hoje foi um bom dia.');
    });
  });

  test(
    'emit() after close() never throws (a save racing a modal dismiss)',
    () async {
      final completer = Completer<Either<Failure, Entry>>();
      when(
        () => mockTracker.create(
          content: any(named: 'content'),
          source: any(named: 'source'),
        ),
      ).thenAnswer((_) => completer.future);
      cubit.updateText('Hoje foi um bom dia.');

      final saveFuture = cubit.save();
      await cubit.close();
      completer.complete(right(_savedEntry));

      await expectLater(saveFuture, completes);
    },
  );
}
