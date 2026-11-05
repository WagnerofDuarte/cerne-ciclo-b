import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/expiry_overlay_host.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/core/widgets/back_arrow_header.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/capture/domain/repositories/media_repository.dart';
import 'package:cerne/features/capture/domain/services/audio_transcriber.dart';
import 'package:cerne/features/capture/domain/services/mic_recorder.dart';
import 'package:cerne/features/capture/domain/services/photo_picker.dart';
import 'package:cerne/features/capture/presentation/cubit/audio_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/photo_entry_cubit.dart';
import 'package:cerne/features/capture/presentation/cubit/text_entry_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/entries_search_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/screens/meus_registros_screen.dart';
import 'package:cerne/features/entries/presentation/widgets/entries_search_bar.dart';
import 'package:cerne/features/entries/presentation/widgets/entry_record_card.dart';
import 'package:cerne/features/entries/presentation/widgets/entry_skeleton_card.dart';
import 'package:cerne/features/entries/presentation/widgets/sync_badge.dart';

/// Same tiny fake `expiry_overlay_host_test.dart` uses — gives synchronous
/// control over the `SessionStatus` stream `ExpiryOverlayHost` subscribes
/// to, needed to simulate a mid-visit session expiry over this screen.
class _FakeSessionRepository implements SessionRepository {
  SessionStatus? _status;
  final _controller = StreamController<SessionStatus>.broadcast();

  @override
  SessionStatus? get currentStatus => _status;

  @override
  Stream<SessionStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> restoreSession() async => right(unit);

  @override
  void markAuthenticated() => setStatus(SessionStatus.authenticated);

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(SessionStatus status) {
    _status = status;
    _controller.add(status);
  }
}

Entry _entry(String id, String occurredAt) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: occurredAt,
  serverRevision: 1,
  createdAt: occurredAt,
  updatedAt: occurredAt,
);

/// A plain (non-mocktail) fake — queues one `list()` result per call, same
/// rationale as `meus_registros_cubit_test.dart`'s own fake, plus an
/// optional [firstCallGate] so a test can hold the very first `list()`
/// call unresolved to observe the skeleton's 300ms threshold.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Either<Failure, EntriesPage>> _listResults = [];
  int listCallCount = 0;
  Completer<void>? firstCallGate;

  /// spec-5-1 — queued `search()` results, same per-call-queue convention
  /// as [_listResults] above. This file's own tests never queue one
  /// unless they specifically exercise the new docked search bar.
  final List<Either<Failure, List<Entry>>> _searchResults = [];
  final List<String> searchCalls = [];

  /// spec-5-3 — every `query`/`source`/`dateFrom`/`dateTo` this fake's
  /// `search()` was called with, in order; the combined search+filter
  /// tests below read this to assert what `EntriesSearchCubit` actually
  /// sent, same rationale [listFilterCalls] already gives `list()`.
  final List<
    ({String query, EntrySource? source, DateTime? dateFrom, DateTime? dateTo})
  >
  searchFilterCalls = [];

  /// spec-5-1 — same [firstCallGate] rationale as `list()`'s own gate,
  /// applied to `search()` instead: lets a test hold the search call
  /// unresolved to observe `_searchSkeletonTimer`'s own 300ms threshold
  /// (Matrix: "Slow request"). Every queued test only ever makes one
  /// `search()` call, so gating unconditionally (unlike [firstCallGate]'s
  /// call-count check) is sufficient.
  Completer<void>? searchGate;

  void queueList(Either<Failure, EntriesPage> result) {
    _listResults.add(result);
  }

  void queueSearch(Either<Failure, List<Entry>> result) {
    _searchResults.add(result);
  }

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  /// spec-5-2 — every `source`/`dateFrom`/`dateTo` this fake's `list()`
  /// was called with, in order; this file's own filter tests read it to
  /// assert what `MeusRegistrosCubit`/the filter sheet actually sent.
  final List<({EntrySource? source, DateTime? dateFrom, DateTime? dateTo})>
  listFilterCalls = [];

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    listCallCount++;
    listFilterCalls.add((source: source, dateFrom: dateFrom, dateTo: dateTo));
    if (listCallCount == 1 && firstCallGate != null) {
      await firstCallGate!.future;
    }
    if (_listResults.isEmpty) {
      throw StateError('no queued list() result for call #$listCallCount');
    }
    return _listResults.removeAt(0);
  }

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    searchCalls.add(query);
    searchFilterCalls.add((
      query: query,
      source: source,
      dateFrom: dateFrom,
      dateTo: dateTo,
    ));
    if (searchGate != null) {
      await searchGate!.future;
    }
    if (_searchResults.isEmpty) {
      throw StateError(
        'no queued search() result for call #${searchCalls.length}',
      );
    }
    return _searchResults.removeAt(0);
  }
}

/// A trivial `PendingEntryWriteTracker` fake — this file's own tests cover
/// spec-4-1's list/pagination/skeleton behavior, not spec-4-2's pending-
/// write overlay (that's `meus_registros_cubit_test.dart`'s/
/// `entry_record_card_test.dart`'s job), so neither stream here ever emits.
class _FakePendingEntryWriteTracker implements PendingEntryWriteTracker {
  @override
  Stream<List<PendingEntryWrite>> get pendingWrites => const Stream.empty();

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      const Stream.empty();

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<void> retry(String tempId) async {}

  @override
  Future<void> dispose() async {}
}

/// A controllable `PendingEntryWriteTracker` fake — unlike the trivial one
/// above (whose streams never emit), this one lets a test drive
/// [pendingWrites] directly and records every [retry] call, so a test can
/// assert the real screen's own tap-to-retry wiring
/// (`meus_registros_screen.dart`'s `onRetryTap: (entry) =>
/// widget.cubit.retry(entry.id)`) actually reaches the tracker with the
/// right `tempId` — Review finding (round 2): this exact chain (screen tap
/// -> cubit.retry(entry.id) -> tracker.retry(tempId)) had no end-to-end
/// coverage before; every other link in it was only ever exercised in
/// isolation (`entry_record_card_test.dart`, `meus_registros_cubit_test.
/// dart`).
class _ControllablePendingEntryWriteTracker
    implements PendingEntryWriteTracker {
  final _pendingController =
      StreamController<List<PendingEntryWrite>>.broadcast();
  final List<String> retryCalls = [];

  void emitPendingWrites(List<PendingEntryWrite> writes) =>
      _pendingController.add(writes);

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites =>
      _pendingController.stream;

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      const Stream.empty();

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<void> retry(String tempId) async {
    retryCalls.add(tempId);
  }

  @override
  Future<void> dispose() async {
    await _pendingController.close();
  }
}

/// Trivial fakes for the three capture cubits' own ports (the next five
/// classes: tracker, mic recorder, transcriber, photo picker, media
/// repository) — the CTA test below never exercises a real save, just that
/// tapping it opens the Insertion Modal on Texto; same rationale and shape
/// as `placeholder_screens_test.dart`'s own "+ control" test fakes.
class _UnusedPendingEntryWriteTracker implements PendingEntryWriteTracker {
  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

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

class _UnusedMicRecorder implements MicRecorder {
  @override
  Future<bool> hasPermission() async =>
      throw UnimplementedError('not expected to be called');

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

class _UnusedAudioTranscriber implements AudioTranscriber {
  @override
  Future<String?> transcribe(String audioPath) async =>
      throw UnimplementedError('not expected to be called');
}

class _UnusedPhotoPicker implements PhotoPicker {
  @override
  Future<PickedPhoto?> pickFromCamera() async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<PickedPhoto?> pickFromGallery() async =>
      throw UnimplementedError('not expected to be called');
}

class _UnusedMediaRepository implements MediaRepository {
  @override
  Future<Either<Failure, OcrResult>> recognizeText({
    required Uint8List imageBytes,
    required String mimeType,
  }) async => throw UnimplementedError('not expected to be called');
}

/// spec-5-1 — every `MeusRegistrosScreen` construction in this file now
/// also needs its own `EntriesSearchCubit`; this suite's own tests never
/// exercise the search surface itself (that's `entries_search_cubit_test.
/// dart`'s/the new e2e test's job), so a throwaway instance over the same
/// fake repository already in scope is enough to satisfy the screen's
/// required constructor param.
EntriesSearchCubit _searchCubitFor(EntriesRepository repository) {
  final searchCubit = EntriesSearchCubit(repository);
  addTearDown(searchCubit.close);
  return searchCubit;
}

Future<MeusRegistrosCubit> _pumpScreen(
  WidgetTester tester,
  _FakeEntriesRepository fakeRepository,
) async {
  final cubit = MeusRegistrosCubit(
    fakeRepository,
    _FakePendingEntryWriteTracker(),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(
    MaterialApp(
      home: MeusRegistrosScreen(
        cubit: cubit,
        searchCubit: _searchCubitFor(fakeRepository),
      ),
    ),
  );
  return cubit;
}

void main() {
  group('skeleton timing (RNF01: no loading UI below 300ms)', () {
    testWidgets('stays blank below the 300ms threshold while the first load is '
        'still in flight', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete();
        }
      });
      final fakeRepository = _FakeEntriesRepository()
        ..firstCallGate = gate
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

      await _pumpScreen(tester, fakeRepository);
      await tester.pump(const Duration(milliseconds: 299));

      expect(find.byType(EntrySkeletonCard), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Lets the 300ms `Timer` itself fire and the gated call resolve
      // before the test ends, so neither is left dangling at teardown.
      gate.complete();
      await tester.pump(const Duration(milliseconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'shows the skeleton list once past the 300ms threshold, while the '
      'first load is still in flight',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });
        final fakeRepository = _FakeEntriesRepository()
          ..firstCallGate = gate
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pump(const Duration(milliseconds: 301));

        expect(find.byType(EntrySkeletonCard), findsWidgets);

        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a fast resolution (before 300ms) never shows the skeleton at all — '
      'goes straight from blank to the resolved content',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        // Settles the already-unblocked `list()` call well before the
        // 300ms threshold's own Timer would fire.
        await tester.pump();
        await tester.pump();

        expect(find.byType(EntrySkeletonCard), findsNothing);
        expect(find.text('Nenhum registro ainda'), findsOneWidget);

        // Even once the threshold elapses afterwards, the state is already
        // resolved — the skeleton branch never gets a chance to render.
        await tester.pump(const Duration(milliseconds: 301));
        expect(find.byType(EntrySkeletonCard), findsNothing);
      },
    );
  });

  group('zero / error states', () {
    testWidgets(
      'zero entries renders the dedicated empty state — icon, "Nenhum '
      'registro ainda" copy, and the "Criar primeiro registro" CTA (spec-4-3)',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        expect(find.text('Nenhum registro ainda'), findsOneWidget);
        expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
        expect(find.text('Criar primeiro registro'), findsOneWidget);
      },
    );

    testWidgets(
      'tapping the empty-state CTA opens the Insertion Modal on Texto, '
      'identical to the Home/Chat "+" FAB\'s own modal (spec-4-3)',
      (tester) async {
        await resetCoreDependencies();
        sl.registerFactory<TextEntryCubit>(
          () => TextEntryCubit(_UnusedPendingEntryWriteTracker()),
        );
        sl.registerFactory<AudioEntryCubit>(
          () => AudioEntryCubit(
            _UnusedMicRecorder(),
            _UnusedAudioTranscriber(),
            _UnusedPendingEntryWriteTracker(),
          ),
        );
        sl.registerFactory<PhotoEntryCubit>(
          () => PhotoEntryCubit(
            _UnusedPhotoPicker(),
            _UnusedMediaRepository(),
            _UnusedPendingEntryWriteTracker(),
          ),
        );
        addTearDown(resetCoreDependencies);

        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Criar primeiro registro'));
        await tester.pumpAndSettle();

        expect(find.text('Texto'), findsOneWidget);
        expect(find.text('Áudio'), findsOneWidget);
        expect(find.text('Foto'), findsOneWidget);
      },
    );

    testWidgets(
      'entries with every occurredAt malformed render the same dedicated '
      'empty state (icon + CTA), not a blank list (I/O matrix, spec-4-3)',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(
              EntriesPage(
                items: [_entry('e1', 'not-a-date')],
                nextCursor: null,
              ),
            ),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        expect(find.text('Nenhum registro ainda'), findsOneWidget);
        expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
        expect(find.text('Criar primeiro registro'), findsOneWidget);
      },
    );

    testWidgets(
      'a load failure renders the Failure\'s own message plus an inline '
      'retry that calls loadFirstPage() again',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            left(const Failure.authExpired(message: 'Sessão expirada')),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
        expect(find.text('Tentar novamente'), findsOneWidget);

        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();

        expect(find.text('Nenhum registro ainda'), findsOneWidget);
        expect(fakeRepository.listCallCount, 2);
      },
    );

    testWidgets(
      'round-2 review fix: with a filter active, a load failure\'s inline '
      '"Tentar novamente" retries with that same filter intact — the '
      'actual UI wiring this story\'s retryCurrentPage() fix was for, '
      'unlike the cubit-level test which calls retryCurrentPage() '
      'directly and the widget test above which never has a filter '
      'active (where loadFirstPage()/retryCurrentPage() are identical)',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        fakeRepository.queueList(
          left(const Failure.authExpired(message: 'Sessão expirada')),
        );
        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
        expect(find.text('Tentar novamente'), findsOneWidget);

        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();

        // The retried call still carries the filter that was active when
        // it failed — reverting `onRetry` to `loadFirstPage` would show
        // isNull here instead.
        expect(fakeRepository.listFilterCalls.last.source, EntrySource.audio);
      },
    );

    testWidgets('a loaded page groups entries by day, with each card\'s spine '
        'present (origin marking) — Acceptance Criteria\'s first bullet', (
      tester,
    ) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(
          right(
            EntriesPage(
              items: [
                _entry('e1', '2026-01-02T10:00:00'),
                _entry('e2', '2026-01-01T10:00:00'),
              ],
              nextCursor: null,
            ),
          ),
        );

      await _pumpScreen(tester, fakeRepository);
      await tester.pumpAndSettle();

      expect(find.byType(EntryRecordCard), findsNWidgets(2));
      expect(find.byType(BackArrowHeader), findsOneWidget);
      expect(find.text('Meus Registros'), findsOneWidget);
    });

    testWidgets(
      'day-group labels: today -> "Hoje", yesterday -> "Ontem", older -> '
      'the dd/mm/yyyy fallback',
      (tester) async {
        final now = DateTime.now();
        String isoAt(DateTime day) =>
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}T10:00:00';
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        // Far enough back that it can never collide with "Hoje"/"Ontem".
        final older = today.subtract(const Duration(days: 10));

        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(
              EntriesPage(
                items: [
                  _entry('e1', isoAt(today)),
                  _entry('e2', isoAt(yesterday)),
                  _entry('e3', isoAt(older)),
                ],
                nextCursor: null,
              ),
            ),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        final olderLabel =
            '${older.day.toString().padLeft(2, '0')}/'
            '${older.month.toString().padLeft(2, '0')}/'
            '${older.year}';
        expect(find.text('Hoje'), findsOneWidget);
        expect(find.text('Ontem'), findsOneWidget);
        expect(find.text(olderLabel), findsOneWidget);
      },
    );

    testWidgets('the back arrow navigates to / (Boundaries: "back arrow always '
        'targets /"), mirroring the deleted MeusRegistrosPlaceholderScreen '
        'test of the same thing', (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)));
      final cubit = MeusRegistrosCubit(
        fakeRepository,
        _FakePendingEntryWriteTracker(),
      );
      addTearDown(cubit.close);
      final router = GoRouter(
        initialLocation: '/meus-registros',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Text('Home')),
          GoRoute(
            path: '/meus-registros',
            builder: (context, state) => MeusRegistrosScreen(
              cubit: cubit,
              searchCubit: _searchCubitFor(fakeRepository),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/');
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('scroll pagination', () {
    testWidgets('scrolling to the end triggers loadMore() and appends the next '
        'page\'s entries, with no duplicate ids', (tester) async {
      // Enough entries across enough distinct days to make the list
      // overflow the test viewport and actually become scrollable.
      final firstPageItems = [
        for (var i = 0; i < 20; i++)
          _entry(
            'e$i',
            '2026-01-${(i + 1).toString().padLeft(2, '0')}T10:00:00',
          ),
      ];
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(
          right(EntriesPage(items: firstPageItems, nextCursor: 'cursor-2')),
        );

      await _pumpScreen(tester, fakeRepository);
      await tester.pumpAndSettle();

      fakeRepository.queueList(
        right(
          EntriesPage(
            items: [_entry('e20', '2026-02-01T10:00:00')],
            nextCursor: null,
          ),
        ),
      );

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // `ListView.builder` only keeps on-screen (plus a small cache
      // extent) items mounted — after jumping to the very end, most of
      // the original 20 entries have scrolled out and are no longer in
      // the tree, so this asserts the newly-appended entry rendered and
      // the call count, not a total on-screen card count.
      expect(fakeRepository.listCallCount, 2);
      expect(find.textContaining('content-e20'), findsOneWidget);
    });

    testWidgets(
      'I/O matrix: a pagination fetch failure keeps the current items '
      'visible, with an inline retry in the footer',
      (tester) async {
        final firstPageItems = [
          for (var i = 0; i < 20; i++)
            _entry(
              'e$i',
              '2026-01-${(i + 1).toString().padLeft(2, '0')}T10:00:00',
            ),
        ];
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(EntriesPage(items: firstPageItems, nextCursor: 'cursor-2')),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        fakeRepository.queueList(
          left(const Failure.networkTimeout(message: 'Timed out')),
        );

        final listView = tester.widget<ListView>(find.byType(ListView));
        final controller = listView.controller!;
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();

        // I/O matrix: "keeps current items" — the list is still showing
        // (not replaced by a full-screen error), with an inline retry.
        // Exactly one `list()` call — `MeusRegistrosCubit.loadMore()`'s own
        // `loadMoreFailed` guard (review finding) stops the scroll
        // listener from re-triggering a retry storm on its own; only an
        // explicit tap on "Tentar novamente" would try again.
        expect(fakeRepository.listCallCount, 2);
        expect(find.byType(EntryRecordCard), findsWidgets);
        expect(find.text('Tentar novamente'), findsOneWidget);
      },
    );
  });

  group('AC3: session expiry preserves scroll position (spec Acceptance '
      'Criteria, third bullet)', () {
    testWidgets('the global ExpiryOverlayHost appearing over this screen while '
        'scrolled does not throw and leaves the scroll position untouched', (
      tester,
    ) async {
      ConfirmationDialog.isOpen = false;
      final firstPageItems = [
        for (var i = 0; i < 20; i++)
          _entry(
            'e$i',
            '2026-01-${(i + 1).toString().padLeft(2, '0')}T10:00:00',
          ),
      ];
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(
          right(EntriesPage(items: firstPageItems, nextCursor: null)),
        );
      final cubit = MeusRegistrosCubit(
        fakeRepository,
        _FakePendingEntryWriteTracker(),
      );
      addTearDown(cubit.close);
      final fakeSessionRepository = _FakeSessionRepository();
      addTearDown(fakeSessionRepository.dispose);
      final navigatorKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ExpiryOverlayHost(
            sessionRepository: fakeSessionRepository,
            router: router,
            navigatorKey: navigatorKey,
            child: Navigator(
              key: navigatorKey,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (context) => MeusRegistrosScreen(
                  cubit: cubit,
                  searchCubit: _searchCubitFor(fakeRepository),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listView = tester.widget<ListView>(find.byType(ListView));
      final controller = listView.controller!;
      expect(controller.position.maxScrollExtent, greaterThan(0));
      controller.jumpTo(100);
      await tester.pump();
      final scrollOffsetBeforeExpiry = controller.offset;

      fakeSessionRepository.setStatus(SessionStatus.expired);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sessão expirada'), findsOneWidget);
      expect(controller.offset, scrollOffsetBeforeExpiry);
    });
  });

  group('spec-4-4: card tap navigates to entry detail', () {
    testWidgets('tapping a card\'s body pushes /meus-registros/:id with that '
        'entry\'s own id', (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(
          right(
            EntriesPage(
              items: [_entry('e1', '2026-01-01T10:00:00')],
              nextCursor: null,
            ),
          ),
        );
      final cubit = MeusRegistrosCubit(
        fakeRepository,
        _FakePendingEntryWriteTracker(),
      );
      addTearDown(cubit.close);
      final router = GoRouter(
        initialLocation: '/meus-registros',
        routes: [
          GoRoute(
            path: '/meus-registros',
            builder: (context, state) => MeusRegistrosScreen(
              cubit: cubit,
              searchCubit: _searchCubitFor(fakeRepository),
            ),
          ),
          GoRoute(
            path: '/meus-registros/:id',
            builder: (context, state) =>
                Text('Detail: ${state.pathParameters['id']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('content-e1'));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/meus-registros/e1');
      expect(find.text('Detail: e1'), findsOneWidget);
    });

    testWidgets(
      'a rapid double-tap on a card pushes the detail route only once '
      '(review fix, round 2 — no debounce guard previously)',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(
              EntriesPage(
                items: [_entry('e1', '2026-01-01T10:00:00')],
                nextCursor: null,
              ),
            ),
          );
        final cubit = MeusRegistrosCubit(
          fakeRepository,
          _FakePendingEntryWriteTracker(),
        );
        addTearDown(cubit.close);
        var pushCount = 0;
        final router = GoRouter(
          initialLocation: '/meus-registros',
          routes: [
            GoRoute(
              path: '/meus-registros',
              builder: (context, state) => MeusRegistrosScreen(
                cubit: cubit,
                searchCubit: _searchCubitFor(fakeRepository),
              ),
            ),
            GoRoute(
              path: '/meus-registros/:id',
              builder: (context, state) {
                pushCount++;
                return Text('Detail: ${state.pathParameters['id']}');
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        // Two taps before the first transition settles — `tester.tap`
        // alone doesn't pump, so both land while `_navigatingToDetail`
        // is still true from the first.
        await tester.tap(find.textContaining('content-e1'));
        await tester.tap(find.textContaining('content-e1'));
        await tester.pumpAndSettle();

        expect(pushCount, 1);
      },
    );
  });

  group('retry wiring (spec-4-2, screen-level — Review finding, round 2)', () {
    testWidgets(
      "tapping a rendered retryable error SyncBadge calls the cubit's "
      'retry() with that write\'s own tempId, exercising the full chain '
      'from the real screen widget tree down to the tracker',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));
        final fakeTracker = _ControllablePendingEntryWriteTracker();
        final cubit = MeusRegistrosCubit(fakeRepository, fakeTracker);
        addTearDown(cubit.close);

        await tester.pumpWidget(
          MaterialApp(
            home: MeusRegistrosScreen(
              cubit: cubit,
              searchCubit: _searchCubitFor(fakeRepository),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nenhum registro ainda'), findsOneWidget);

        fakeTracker.emitPendingWrites([
          PendingEntryWrite(
            tempId: 'temp-1',
            content: 'failed content',
            source: EntrySource.manual,
            mediaDurationSeconds: null,
            startedAt: DateTime(2026, 1, 1),
            status: const PendingEntryWriteFailed(
              failure: Failure.networkTimeout(message: 'Timed out'),
            ),
          ),
        ]);
        await tester.pumpAndSettle();

        expect(find.byType(SyncBadge), findsOneWidget);
        await tester.tap(find.byType(SyncBadge));
        await tester.pumpAndSettle();

        expect(fakeTracker.retryCalls, ['temp-1']);
      },
    );
  });

  group('spec-5-1: docked search bar', () {
    testWidgets(
      'Acceptance Criteria: the search bar renders above the timeline on '
      'first load',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        expect(find.byType(EntriesSearchBar), findsOneWidget);
        expect(find.text('Nenhum registro ainda'), findsOneWidget);
      },
    );

    testWidgets(
      'typing a query shows the search results in place of the timeline, '
      ' 300ms after the debounce window',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(
              EntriesPage(
                items: [_entry('timeline-1', '2026-01-01T10:00:00')],
                nextCursor: null,
              ),
            ),
          )
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();
        expect(find.textContaining('content-timeline-1'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(fakeRepository.searchCalls, ['ansiedade']);
        expect(find.textContaining('content-search-1'), findsOneWidget);
        expect(find.textContaining('content-timeline-1'), findsNothing);
      },
    );

    testWidgets(
      'I/O matrix: "Query cleared" — clearing the field back to empty '
      'reverts to the normal timeline, with the search results gone',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(
            right(
              EntriesPage(
                items: [_entry('timeline-1', '2026-01-01T10:00:00')],
                nextCursor: null,
              ),
            ),
          )
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.textContaining('content-search-1'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();

        expect(find.textContaining('content-timeline-1'), findsOneWidget);
        expect(find.textContaining('content-search-1'), findsNothing);
      },
    );

    testWidgets(
      'I/O matrix: "Offline" — a search Failure.networkOffline renders its '
      'message, never a cache fallback',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueSearch(
            left(const Failure.networkOffline(message: 'Sem conexão')),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.text('Sem conexão'), findsOneWidget);
      },
    );

    testWidgets(
      'I/O matrix: "Slow request" — the search skeleton stays blank below '
      'the 300ms threshold while a search is still in flight',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..searchGate = gate
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        // Debounce window elapses — EntriesSearchCubit emits
        // ResourceLoading and calls the gated search(), starting the
        // screen's own _searchSkeletonTimer.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 299));

        expect(find.byType(EntrySkeletonCard), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'I/O matrix: "Slow request" — the search skeleton shows once past '
      'the 300ms threshold while still in flight',
      (tester) async {
        final gate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..searchGate = gate
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 301));

        expect(find.byType(EntrySkeletonCard), findsWidgets);

        gate.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Review fix (round 2): remounting while a search is already '
        'ResourceLoading arms the search skeleton fresh, instead of staying '
        'blank forever — e.g. the user navigates away to another tab and '
        'back while EntriesSearchCubit (a DI singleton) is still mid-search; '
        'BlocConsumer\'s listener never fires for a state already current at '
        'subscription time, so only initState inspecting the cubit\'s state '
        'up front catches this. spec-5-3: initState now also calls '
        'searchCubit.updateFilters(source: null, dateFrom: null, dateTo: '
        'null) unconditionally on every mount (Boundaries: "no stale '
        'filter carried forward") — neither mount here ever had an active '
        'filter to begin with, so updateFilters()\'s own no-op-when-'
        'unchanged guard (review finding) keeps this a single search() '
        'call, not two', (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete();
        }
      });
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..searchGate = gate
        ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

      final cubit = MeusRegistrosCubit(
        fakeRepository,
        _FakePendingEntryWriteTracker(),
      );
      addTearDown(cubit.close);
      final searchCubit = _searchCubitFor(fakeRepository);

      Widget buildScreen() => MaterialApp(
        home: MeusRegistrosScreen(cubit: cubit, searchCubit: searchCubit),
      );

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // Start a search and let it debounce into ResourceLoading — the
      // repository's own gate holds it there indefinitely, so this
      // state is still current when the screen below is torn down.
      await tester.enterText(find.byType(TextField), 'ansiedade');
      await tester.pump(const Duration(milliseconds: 350));
      expect(searchCubit.state, isA<ResourceLoading<List<Entry>>>());

      // Tear this screen down (simulating navigating away to another
      // tab) — `cubit`/`searchCubit` are DI singletons the screen never
      // closes, so both keep running underneath.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Remount: a brand-new State subscribes to the still-loading
      // searchCubit. Flush the fresh (ungated) loadFirstPage() call
      // initState also fires, so only the search branch below is live.
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      // Below the 300ms threshold since remounting — no skeleton yet.
      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byType(EntrySkeletonCard), findsNothing);

      // Past the threshold, re-armed by the new State's own initState.
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(EntrySkeletonCard), findsWidgets);

      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('spec-5-2: metadata filters', () {
    testWidgets(
      'Boundaries: "fills the funnel icon" — colorPrimary once a filter is '
      'applied, reverting to colorTextSecondary once cleared',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        Icon funnelIcon() =>
            tester.widget<Icon>(find.byIcon(Icons.filter_list));
        expect(funnelIcon().color, DesignTokens.colorTextSecondary);

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manual'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        expect(funnelIcon().color, DesignTokens.colorPrimary);

        await tester.tap(find.text('Limpar filtros'));
        await tester.pumpAndSettle();

        expect(funnelIcon().color, DesignTokens.colorTextSecondary);
      },
    );

    testWidgets(
      'tapping the funnel icon opens the filter sheet with both groups, '
      'and no CATEGORIA group (Design Notes: the backend has no category '
      'filter)',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();

        expect(find.text('INTERVALO DE DATA'), findsOneWidget);
        expect(find.text('TIPO DE ENTRADA'), findsOneWidget);
        expect(find.text('CATEGORIA'), findsNothing);
      },
    );

    testWidgets(
      'Acceptance Criteria: applying a source filter sends it to list(), '
      'renders a removable active-filter chip, and its "x" re-queries '
      'without that filter',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        expect(fakeRepository.listFilterCalls.last.source, EntrySource.audio);
        expect(find.text('Áudio'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        expect(fakeRepository.listFilterCalls.last.source, isNull);
        expect(find.text('Áudio'), findsNothing);
      },
    );

    testWidgets(
      'I/O matrix: "Clear all filters" — "Limpar filtros" restores the '
      'full list in place without a screen reload/re-mount',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(
            right(
              EntriesPage(
                items: [_entry('e1', '2026-01-01T10:00:00')],
                nextCursor: null,
              ),
            ),
          );

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Manual'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();
        expect(find.text('Limpar filtros'), findsOneWidget);

        await tester.tap(find.text('Limpar filtros'));
        await tester.pumpAndSettle();

        expect(find.text('Limpar filtros'), findsNothing);
        expect(find.textContaining('content-e1'), findsOneWidget);
        expect(fakeRepository.listFilterCalls.last.source, isNull);
      },
    );

    testWidgets('spec-5-3: reverses 5.2\'s own "must not read as filled while '
        'searching" behavior — the funnel now stays filled (colorPrimary) '
        'while a search is active too, since a filter now narrows that '
        'search as well, rather than reading as misleadingly "filled" next '
        'to results that were never actually filtered', (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]));

      await _pumpScreen(tester, fakeRepository);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      Icon funnelIcon() => tester.widget<Icon>(find.byIcon(Icons.filter_list));
      expect(funnelIcon().color, DesignTokens.colorPrimary);

      await tester.enterText(find.byType(TextField), 'ansiedade');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // A search is now on screen — the filter applied above was also
      // forwarded to this search (spec-5-3), so the funnel still reads
      // as "filled" here.
      expect(funnelIcon().color, DesignTokens.colorPrimary);
      expect(fakeRepository.searchFilterCalls.last.source, EntrySource.manual);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Back to the plain filtered timeline — still "filled".
      expect(funnelIcon().color, DesignTokens.colorPrimary);
    });

    testWidgets(
      'code-review fix: two active filters render as two separate chips '
      '— tapping the date-range chip\'s own "x" drops only the date '
      'range, keeping the source filter intact',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.tap(find.text('Este mês'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        expect(find.text('Áudio'), findsOneWidget);
        expect(find.text('Este mês'), findsOneWidget);
        expect(fakeRepository.listFilterCalls.last.source, EntrySource.audio);
        expect(fakeRepository.listFilterCalls.last.dateFrom, isNotNull);
        expect(fakeRepository.listFilterCalls.last.dateTo, isNotNull);

        // Two removable chips now, each with its own "x" — the date-
        // range chip is the second one rendered (_ActiveFiltersRow: the
        // source chip always comes first).
        expect(find.byIcon(Icons.close), findsNWidgets(2));
        await tester.tap(find.byIcon(Icons.close).last);
        await tester.pumpAndSettle();

        expect(fakeRepository.listFilterCalls.last.source, EntrySource.audio);
        expect(fakeRepository.listFilterCalls.last.dateFrom, isNull);
        expect(fakeRepository.listFilterCalls.last.dateTo, isNull);
        expect(find.text('Áudio'), findsOneWidget);
        expect(find.text('Este mês'), findsNothing);
      },
    );
  });

  group('spec-5-3: combined search + filter & non-disruptive clearing', () {
    testWidgets(
      'I/O matrix: "Apply filter during active search" — Aplicar fires one '
      'entries-search call carrying both the already-typed term and the '
      'new filter, and the chip row/funnel both reflect it over the '
      'search results',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]))
          ..queueSearch(right([_entry('search-2', '2026-01-01T10:00:00')]));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(fakeRepository.searchFilterCalls, hasLength(1));

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        expect(fakeRepository.searchFilterCalls, hasLength(2));
        final call = fakeRepository.searchFilterCalls.last;
        expect(call.query, 'ansiedade');
        expect(call.source, EntrySource.audio);
        // The chip row now renders above the search results, and the
        // funnel reads as "filled".
        expect(find.text('Áudio'), findsOneWidget);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.filter_list)).color,
          DesignTokens.colorPrimary,
        );
      },
    );

    testWidgets('I/O matrix: "Clear filters during active search" — "Limpar '
        'filtros" re-queries entries-search with only q, no search-box/'
        'screen disruption', (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]))
        ..queueSearch(right([_entry('search-2', '2026-01-01T10:00:00')]));

      await _pumpScreen(tester, fakeRepository);
      await tester.pumpAndSettle();

      // Filter applied first, while idle.
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.tap(find.text('Este mês'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(fakeRepository.searchFilterCalls, isEmpty);

      // Now a search starts, carrying that same filter selection.
      await tester.enterText(find.byType(TextField), 'ansiedade');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(fakeRepository.searchFilterCalls, hasLength(1));
      expect(fakeRepository.searchFilterCalls.single.source, EntrySource.audio);

      await tester.tap(find.text('Limpar filtros'));
      await tester.pumpAndSettle();

      expect(fakeRepository.searchFilterCalls, hasLength(2));
      final call = fakeRepository.searchFilterCalls.last;
      expect(call.query, 'ansiedade');
      expect(call.source, isNull);
      expect(call.dateFrom, isNull);
      // The search box itself was never touched/cleared.
      expect(find.text('ansiedade'), findsOneWidget);
      expect(find.text('Limpar filtros'), findsNothing);
    });

    testWidgets('I/O matrix: "Remove one of two active chips mid-search" — the '
        'date-range chip\'s own "x" re-queries entries-search with q plus '
        'only the still-active source filter', (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
        ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]))
        ..queueSearch(right([_entry('search-2', '2026-01-01T10:00:00')]));

      await _pumpScreen(tester, fakeRepository);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Áudio'));
      await tester.tap(find.text('Este mês'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ansiedade');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(fakeRepository.searchFilterCalls, hasLength(1));

      // Two chips above the search results — the date-range one is the
      // second, same ordering `_ActiveFiltersRow` always uses.
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      expect(fakeRepository.searchFilterCalls, hasLength(2));
      final call = fakeRepository.searchFilterCalls.last;
      expect(call.query, 'ansiedade');
      expect(call.source, EntrySource.audio);
      expect(call.dateFrom, isNull);
      expect(find.text('Áudio'), findsOneWidget);
      expect(find.text('Este mês'), findsNothing);
    });

    testWidgets(
      'Boundaries: "Re-enter screen after a prior combined session" — '
      'leaving with search+filter active and returning resets both '
      'cubits\' filters, with no stale filter carried into the still-'
      'active search',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)))
          ..queueSearch(right([_entry('search-1', '2026-01-01T10:00:00')]))
          ..queueSearch(right([_entry('search-2', '2026-01-01T10:00:00')]));

        final cubit = MeusRegistrosCubit(
          fakeRepository,
          _FakePendingEntryWriteTracker(),
        );
        addTearDown(cubit.close);
        final searchCubit = _searchCubitFor(fakeRepository);

        Widget buildScreen() => MaterialApp(
          home: MeusRegistrosScreen(cubit: cubit, searchCubit: searchCubit),
        );

        await tester.pumpWidget(buildScreen());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Áudio'));
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'ansiedade');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(fakeRepository.searchFilterCalls.last.source, EntrySource.audio);
        expect(cubit.hasActiveFilters, isTrue);

        // Leave (tear down the screen's own State) and come back — both
        // cubits are DI singletons that keep running underneath.
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpWidget(buildScreen());
        await tester.pumpAndSettle();

        expect(cubit.hasActiveFilters, isFalse);
        // The still-active search (never cleared by the remount) is now
        // re-queried without the stale filter.
        expect(fakeRepository.searchFilterCalls, hasLength(2));
        final call = fakeRepository.searchFilterCalls.last;
        expect(call.query, 'ansiedade');
        expect(call.source, isNull);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.filter_list)).color,
          DesignTokens.colorTextSecondary,
        );
      },
    );
  });
}
