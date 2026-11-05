import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/date_range_preset.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_state.dart';

Entry _entry(
  String id, {
  String occurredAt = '2026-01-01T00:00:00Z',
  EntrySource source = EntrySource.manual,
}) => Entry(
  id: id,
  content: 'content-$id',
  source: source,
  chatMessageId: null,
  occurredAt: occurredAt,
  serverRevision: 1,
  createdAt: occurredAt,
  updatedAt: occurredAt,
);

/// A plain (non-mocktail) fake — this cubit's own tests need a scriptable
/// `list()` result per call (first page vs. a later `loadMore()` page),
/// which a single static mocktail stub can't express as naturally.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Either<Failure, EntriesPage>> _listResults = [];
  final List<
    ({
      String? cursor,
      int limit,
      EntrySource? source,
      DateTime? dateFrom,
      DateTime? dateTo,
    })
  >
  listCalls = [];

  /// Queues the next `list()` call's result, in order.
  void queueList(Either<Failure, EntriesPage> result) {
    _listResults.add(result);
  }

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    listCalls.add((
      cursor: cursor,
      limit: limit,
      source: source,
      dateFrom: dateFrom,
      dateTo: dateTo,
    ));
    if (_listResults.isEmpty) {
      throw StateError('no queued list() result for call #${listCalls.length}');
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
  }) async => throw UnimplementedError('not expected to be called');
}

/// A `Completer`-per-call fake, letting a test resolve `list()` calls in
/// whatever order it chooses — needed to reproduce the stale-result race
/// (review finding): an older call's result landing after a newer call has
/// already changed the state.
class _GatedEntriesRepository implements EntriesRepository {
  final List<Completer<Either<Failure, EntriesPage>>> _completers = [];

  void resolve(int callIndex, Either<Failure, EntriesPage> result) {
    _completers[callIndex].complete(result);
  }

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    final completer = Completer<Either<Failure, EntriesPage>>();
    _completers.add(completer);
    return completer.future;
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
  }) async => throw UnimplementedError('not expected to be called');
}

/// A controllable `PendingEntryWriteTracker` fake — lets a test drive
/// [pendingWrites]/[confirmedWrites] directly (simulating a capture cubit
/// elsewhere, sharing the same tracker instance in production) and records
/// every [retry] call so `MeusRegistrosCubit.retry()`'s own delegation can
/// be asserted without a real `EntriesRepository` behind it.
class _FakePendingEntryWriteTracker implements PendingEntryWriteTracker {
  final _pendingController =
      StreamController<List<PendingEntryWrite>>.broadcast();
  final _confirmedController =
      StreamController<({String tempId, Entry entry})>.broadcast();
  final List<String> retryCalls = [];

  void emitPendingWrites(List<PendingEntryWrite> writes) =>
      _pendingController.add(writes);

  void emitConfirmed(String tempId, Entry entry) =>
      _confirmedController.add((tempId: tempId, entry: entry));

  @override
  Stream<List<PendingEntryWrite>> get pendingWrites =>
      _pendingController.stream;

  @override
  Stream<({String tempId, Entry entry})> get confirmedWrites =>
      _confirmedController.stream;

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
    await _confirmedController.close();
  }
}

PendingEntryWrite _pendingWrite(
  String tempId, {
  PendingEntryWriteStatus status = const PendingEntryWriteInFlight(),
  String content = 'pending content',
  EntrySource source = EntrySource.manual,
  DateTime? startedAt,
}) => PendingEntryWrite(
  tempId: tempId,
  content: content,
  source: source,
  mediaDurationSeconds: null,
  startedAt: startedAt ?? DateTime(2026, 1, 1),
  status: status,
);

void main() {
  late _FakeEntriesRepository fakeRepository;
  late _FakePendingEntryWriteTracker fakeTracker;
  late MeusRegistrosCubit cubit;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    fakeTracker = _FakePendingEntryWriteTracker();
    cubit = MeusRegistrosCubit(fakeRepository, fakeTracker);
  });

  tearDown(() async {
    await cubit.close();
    await fakeTracker.dispose();
  });

  group('loadFirstPage()', () {
    test('starts as MeusRegistrosLoading before any load', () {
      expect(cubit.state, isA<MeusRegistrosLoading>());
    });

    test('a successful page with items emits MeusRegistrosLoaded with those '
        'entries and the page\'s own nextCursor', () async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: 'cursor-2')),
      );

      await cubit.loadFirstPage();

      final state = cubit.state;
      expect(state, isA<MeusRegistrosLoaded>());
      expect((state as MeusRegistrosLoaded).entries.map((e) => e.id), ['e1']);
      expect(state.nextCursor, 'cursor-2');
      expect(state.isLoadingMore, isFalse);
      expect(state.loadMoreFailed, isFalse);
    });

    test('a successful page with zero items emits MeusRegistrosEmpty — '
        'Boundaries: "Zero entries"', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );

      await cubit.loadFirstPage();

      expect(cubit.state, isA<MeusRegistrosEmpty>());
    });

    test('a Failure (e.g. authExpired) emits MeusRegistrosError with its '
        'message verbatim', () async {
      fakeRepository.queueList(
        left(const Failure.authExpired(message: 'Sessão expirada')),
      );

      await cubit.loadFirstPage();

      final state = cubit.state;
      expect(state, isA<MeusRegistrosError>());
      expect((state as MeusRegistrosError).message, 'Sessão expirada');
    });

    test('calls list() with no cursor (first page)', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );

      await cubit.loadFirstPage();

      expect(fakeRepository.listCalls.single.cursor, isNull);
    });

    test('review finding: no duplicate ids even within the very first page '
        'itself', () async {
      fakeRepository.queueList(
        right(
          EntriesPage(
            items: [_entry('e1'), _entry('e2'), _entry('e1')],
            nextCursor: null,
          ),
        ),
      );

      await cubit.loadFirstPage();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['e1', 'e2']);
    });
  });

  group('loadMore()', () {
    Future<void> seedLoaded({String? nextCursor = 'cursor-2'}) async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: nextCursor)),
      );
      await cubit.loadFirstPage();
    }

    test(
      'a no-op while not MeusRegistrosLoaded (e.g. still loading)',
      () async {
        await cubit.loadMore();

        expect(fakeRepository.listCalls, isEmpty);
      },
    );

    test('a no-op once nextCursor is already null — no further page to '
        'fetch', () async {
      await seedLoaded(nextCursor: null);

      await cubit.loadMore();

      expect(fakeRepository.listCalls, hasLength(1));
    });

    test('appends the next page\'s entries, keeping the already-loaded ones, '
        'and adopts the new page\'s own nextCursor', () async {
      await seedLoaded();
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e2')], nextCursor: null)),
      );

      await cubit.loadMore();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['e1', 'e2']);
      expect(state.nextCursor, isNull);
      expect(state.isLoadingMore, isFalse);
    });

    test('passes the current nextCursor through to list()', () async {
      await seedLoaded();
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );

      await cubit.loadMore();

      expect(fakeRepository.listCalls.last.cursor, 'cursor-2');
    });

    test(
      'I/O matrix: a fetch failure keeps the current items and flags '
      'loadMoreFailed, for an inline retry — never clears the list',
      () async {
        await seedLoaded();
        fakeRepository.queueList(
          left(const Failure.networkTimeout(message: 'Timed out')),
        );

        await cubit.loadMore();

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.entries.map((e) => e.id), ['e1']);
        expect(state.loadMoreFailed, isTrue);
        expect(state.isLoadingMore, isFalse);
        // The cursor is untouched by a failed attempt — a retry reuses it.
        expect(state.nextCursor, 'cursor-2');
      },
    );

    test('a subsequent loadMore() (e.g. a re-triggered scroll listener) is a '
        'no-op once loadMoreFailed is already true — only retryLoadMore() '
        'tries again. Review finding: without this guard, a failed page\'s '
        'footer changing size (spinner -> button) can shift '
        'maxScrollExtent enough to keep re-firing the scroll listener, '
        'retrying forever', () async {
      await seedLoaded();
      fakeRepository.queueList(
        left(const Failure.networkTimeout(message: 'Timed out')),
      );
      await cubit.loadMore();
      expect(fakeRepository.listCalls, hasLength(2));

      await cubit.loadMore();

      // No second repository call — still a no-op.
      expect(fakeRepository.listCalls, hasLength(2));
      expect((cubit.state as MeusRegistrosLoaded).loadMoreFailed, isTrue);
    });

    test('I/O matrix: no duplicate ids even if the server repeats an item '
        'across a cursor boundary', () async {
      await seedLoaded();
      fakeRepository.queueList(
        right(
          EntriesPage(items: [_entry('e1'), _entry('e2')], nextCursor: null),
        ),
      );

      await cubit.loadMore();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['e1', 'e2']);
    });

    test(
      'review finding: no duplicate ids even when the new page itself '
      'repeats an id internally (not just against already-held ones)',
      () async {
        await seedLoaded();
        fakeRepository.queueList(
          right(
            EntriesPage(
              items: [_entry('e2'), _entry('e3'), _entry('e2')],
              nextCursor: null,
            ),
          ),
        );

        await cubit.loadMore();

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.entries.map((e) => e.id), ['e1', 'e2', 'e3']);
      },
    );

    test('review finding: a page with zero genuinely-new entries (every '
        'returned item already present by id) forces nextCursor to null '
        'even though the server still reports a non-null cursor — otherwise '
        'a stuck server cursor could re-trigger loadMore() forever with no '
        'progress', () async {
      await seedLoaded();
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: 'cursor-3')),
      );

      await cubit.loadMore();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['e1']);
      expect(state.nextCursor, isNull);

      // The scroll listener's own `loadMore()` is now a genuine no-op —
      // confirms the forced null actually stops further calls.
      await cubit.loadMore();
      expect(fakeRepository.listCalls, hasLength(2));
    });

    test(
      'retryLoadMore() after a failed loadMore() succeeds normally, '
      'clearing loadMoreFailed — the one path allowed past that guard',
      () async {
        await seedLoaded();
        fakeRepository.queueList(
          left(const Failure.networkTimeout(message: 'Timed out')),
        );
        await cubit.loadMore();
        expect((cubit.state as MeusRegistrosLoaded).loadMoreFailed, isTrue);

        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e2')], nextCursor: null)),
        );
        await cubit.retryLoadMore();

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.loadMoreFailed, isFalse);
        expect(state.entries.map((e) => e.id), ['e1', 'e2']);
      },
    );
  });

  group('generation guard (review finding: stale in-flight result)', () {
    test('a stale loadFirstPage() result — an older call resolving after a '
        'newer call already changed the state — is discarded rather than '
        'emitted', () async {
      final gatedRepository = _GatedEntriesRepository();
      final gatedTracker = _FakePendingEntryWriteTracker();
      addTearDown(gatedTracker.dispose);
      final gatedCubit = MeusRegistrosCubit(gatedRepository, gatedTracker);
      addTearDown(gatedCubit.close);

      final firstLoad = gatedCubit.loadFirstPage(); // call #0 (stale)
      final secondLoad = gatedCubit.loadFirstPage(); // call #1 (fresh)

      // The newer call resolves first.
      gatedRepository.resolve(
        1,
        right(EntriesPage(items: [_entry('newer')], nextCursor: null)),
      );
      await secondLoad;
      expect(
        (gatedCubit.state as MeusRegistrosLoaded).entries.map((e) => e.id),
        ['newer'],
      );

      // The stale call resolving afterwards must not overwrite it.
      gatedRepository.resolve(
        0,
        right(EntriesPage(items: [_entry('stale')], nextCursor: null)),
      );
      await firstLoad;

      final state = gatedCubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['newer']);
    });

    test('a stale _fetchMore() (loadMore()) result arriving after '
        'loadFirstPage() has already reset the state is discarded rather '
        'than emitted', () async {
      final gatedRepository = _GatedEntriesRepository();
      final gatedTracker = _FakePendingEntryWriteTracker();
      addTearDown(gatedTracker.dispose);
      final gatedCubit = MeusRegistrosCubit(gatedRepository, gatedTracker);
      addTearDown(gatedCubit.close);

      final firstLoad = gatedCubit.loadFirstPage(); // call #0
      gatedRepository.resolve(
        0,
        right(EntriesPage(items: [_entry('e1')], nextCursor: 'cursor-2')),
      );
      await firstLoad;

      final loadMoreCall = gatedCubit.loadMore(); // call #1 (will go stale)
      final reloadCall = gatedCubit.loadFirstPage(); // call #2 (fresh)

      gatedRepository.resolve(
        2,
        right(EntriesPage(items: [_entry('reloaded')], nextCursor: null)),
      );
      await reloadCall;
      expect(
        (gatedCubit.state as MeusRegistrosLoaded).entries.map((e) => e.id),
        ['reloaded'],
      );

      // The stale loadMore() result resolving afterwards must not
      // overwrite the fresher reload.
      gatedRepository.resolve(
        1,
        right(EntriesPage(items: [_entry('e2')], nextCursor: null)),
      );
      await loadMoreCall;

      final state = gatedCubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['reloaded']);
    });
  });

  group('spec-4-2: pending/confirmed write overlay', () {
    test('a pending write arriving while MeusRegistrosLoaded overlays onto '
        'pendingWrites, with its own placeholder card groups.badgeFor() '
        'reporting synchronizing', () async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
      );
      await cubit.loadFirstPage();

      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.pendingWrites.map((p) => p.tempId), ['temp-1']);
      // The placeholder card is always first across every group
      // (Boundaries: "Card appears top-of-today") — `groupEntriesByDate`
      // orders groups by first-encountered entry, and the placeholder is
      // always prepended ahead of every confirmed entry.
      final allIds = state.groups.expand((g) => g.entries).map((e) => e.id);
      expect(allIds.first, 'temp-1');
      final placeholder = state.groups
          .expand((g) => g.entries)
          .firstWhere((e) => e.id == 'temp-1');
      expect(state.badgeFor(placeholder), const SyncBadgeState.synchronizing());
    });

    test('a pending write arriving while MeusRegistrosEmpty transitions to '
        'MeusRegistrosLoaded showing just the placeholder card', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.loadFirstPage();
      expect(cubit.state, isA<MeusRegistrosEmpty>());

      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries, isEmpty);
      expect(state.pendingWrites, hasLength(1));
    });

    test('a confirmed write prepends the real Entry into entries, preserving '
        'nextCursor/pagination, and dedupes against a later duplicate from '
        'list()', () async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: 'cursor-2')),
      );
      await cubit.loadFirstPage();

      fakeTracker.emitConfirmed('temp-1', _entry('new-1'));
      await Future<void>.delayed(Duration.zero);

      var state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['new-1', 'e1']);
      // Pagination state untouched by the prepend.
      expect(state.nextCursor, 'cursor-2');

      // A later loadMore() page happens to repeat the now-confirmed id
      // (e.g. a cursor shifted by the insert) — absorbed by the existing
      // dedup helper, same as any other cursor-boundary repeat.
      fakeRepository.queueList(
        right(
          EntriesPage(items: [_entry('new-1'), _entry('e2')], nextCursor: null),
        ),
      );
      await cubit.loadMore();

      state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['new-1', 'e1', 'e2']);
    });

    test('a confirmed write arriving while MeusRegistrosEmpty transitions to '
        'MeusRegistrosLoaded showing just that entry', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.loadFirstPage();

      fakeTracker.emitConfirmed('temp-1', _entry('new-1'));
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['new-1']);
    });

    test('a pending write already outstanding before the first page resolves '
        'is folded into the very first MeusRegistrosLoaded emission', () async {
      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);

      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.loadFirstPage();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.pendingWrites.map((p) => p.tempId), ['temp-1']);
    });

    test('retry(tempId) delegates to the shared tracker verbatim — no second '
        'retry endpoint', () async {
      await cubit.retry('temp-1');

      expect(fakeTracker.retryCalls, ['temp-1']);
    });

    test('code-review round 1 finding: a confirmed write drops its own '
        'matching pending placeholder in the very same emission that '
        'prepends the real entry — no transient frame where both the stale '
        'placeholder and the real entry are visible at once', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.loadFirstPage();
      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as MeusRegistrosLoaded).pendingWrites, hasLength(1));

      final emitted = <MeusRegistrosState>[];
      final subscription = cubit.stream.listen(emitted.add);

      fakeTracker.emitConfirmed('temp-1', _entry('new-1'));
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      // Exactly one emission for this confirmation — proving the
      // pending-removal and the entry-prepend happen together, not as
      // two separate emissions (one of which would otherwise render
      // both the stale placeholder and the real entry simultaneously).
      expect(emitted, hasLength(1));
      final state = emitted.single as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['new-1']);
      expect(state.pendingWrites, isEmpty);

      // A later, independent pendingWrites emission (the tracker's own,
      // arriving after its `Stream.multi` hop) must not resurrect it.
      fakeTracker.emitPendingWrites([]);
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as MeusRegistrosLoaded).pendingWrites, isEmpty);
    });

    test('code-review round 1 finding: a zero-item first page with a pending '
        'write outstanding still forces nextCursor to null (the degenerate-'
        'cursor guard applies unconditionally)', () async {
      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);

      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: 'cursor-2')),
      );
      await cubit.loadFirstPage();

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries, isEmpty);
      expect(state.pendingWrites, hasLength(1));
      expect(state.nextCursor, isNull);
    });

    test('code-review round 1 finding: a pending write arriving while '
        'MeusRegistrosError transitions to MeusRegistrosLoaded showing the '
        'placeholder, same as the MeusRegistrosEmpty case', () async {
      fakeRepository.queueList(
        left(const Failure.authExpired(message: 'Sessão expirada')),
      );
      await cubit.loadFirstPage();
      expect(cubit.state, isA<MeusRegistrosError>());

      fakeTracker.emitPendingWrites([_pendingWrite('temp-1')]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries, isEmpty);
      expect(state.pendingWrites, hasLength(1));
    });

    test('code-review round 1 finding: a confirmed write arriving while '
        'MeusRegistrosError transitions to MeusRegistrosLoaded showing that '
        'entry, same as the MeusRegistrosEmpty case', () async {
      fakeRepository.queueList(
        left(const Failure.authExpired(message: 'Sessão expirada')),
      );
      await cubit.loadFirstPage();
      expect(cubit.state, isA<MeusRegistrosError>());

      fakeTracker.emitConfirmed('temp-1', _entry('new-1'));
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as MeusRegistrosLoaded;
      expect(state.entries.map((e) => e.id), ['new-1']);
    });
  });

  group('spec-5-2: metadata filters', () {
    test('starts with no active filters', () {
      expect(cubit.hasActiveFilters, isFalse);
      expect(cubit.activeSource, isNull);
      expect(cubit.activeDateFrom, isNull);
      expect(cubit.activeDateTo, isNull);
    });

    test(
      'I/O matrix: "Source filter only" — applyFilters(source: audio) '
      'sends exactly {source: audio} to list(), with no date bounds',
      () async {
        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );

        await cubit.applyFilters(source: EntrySource.audio);

        expect(fakeRepository.listCalls.single.source, EntrySource.audio);
        expect(fakeRepository.listCalls.single.dateFrom, isNull);
        expect(fakeRepository.listCalls.single.dateTo, isNull);
        expect(cubit.hasActiveFilters, isTrue);
        expect(cubit.activeSource, EntrySource.audio);
        expect((cubit.state as MeusRegistrosLoaded).entries.map((e) => e.id), [
          'e1',
        ]);
      },
    );

    test(
      'I/O matrix: "Date range filter only" (round-2 review fix) — '
      'applyFilters(dateFrom/dateTo) with no source sends exactly that '
      'date range to list(), with no source param — the symmetric '
      'counterpart to "Source filter only" above, applied from a clean '
      'start rather than reached by removing an already-applied chip',
      () async {
        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );
        final dateFrom = DateTime(2026, 1, 1);
        final dateTo = DateTime(2026, 1, 31);

        await cubit.applyFilters(
          dateFrom: dateFrom,
          dateTo: dateTo,
          dateRangePreset: DateRangePreset.thisMonth,
        );

        expect(fakeRepository.listCalls.single.source, isNull);
        expect(fakeRepository.listCalls.single.dateFrom, dateFrom);
        expect(fakeRepository.listCalls.single.dateTo, dateTo);
        expect(cubit.hasActiveFilters, isTrue);
        expect(cubit.activeSource, isNull);
        expect(cubit.activeDateRangePreset, DateRangePreset.thisMonth);
      },
    );

    test('I/O matrix: "Source + date range together" — a single query '
        'carries both params at once (AND narrowing)', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);

      await cubit.applyFilters(
        source: EntrySource.photo,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      expect(fakeRepository.listCalls, hasLength(1));
      final call = fakeRepository.listCalls.single;
      expect(call.source, EntrySource.photo);
      expect(call.dateFrom, dateFrom);
      expect(call.dateTo, dateTo);
    });

    test('I/O matrix: "Remove one of two active chips" — re-applying with '
        'only the date range re-queries with source omitted', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);
      await cubit.applyFilters(
        source: EntrySource.chat,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.applyFilters(dateFrom: dateFrom, dateTo: dateTo);

      final call = fakeRepository.listCalls.last;
      expect(call.source, isNull);
      expect(call.dateFrom, dateFrom);
      expect(call.dateTo, dateTo);
      expect(cubit.activeSource, isNull);
    });

    test('I/O matrix: "Remove one of two active chips" (round-2 review fix, '
        'reverse direction) — re-applying with only the source re-queries '
        'with the date range omitted, at the cubit level (previously only '
        'covered at the screen widget-test level)', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      final dateFrom = DateTime(2026, 1, 1);
      final dateTo = DateTime(2026, 1, 31);
      await cubit.applyFilters(
        source: EntrySource.chat,
        dateFrom: dateFrom,
        dateTo: dateTo,
        dateRangePreset: DateRangePreset.thisMonth,
      );

      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.applyFilters(source: EntrySource.chat);

      final call = fakeRepository.listCalls.last;
      expect(call.source, EntrySource.chat);
      expect(call.dateFrom, isNull);
      expect(call.dateTo, isNull);
      expect(cubit.activeDateFrom, isNull);
      expect(cubit.activeDateRangePreset, DateRangePreset.allTime);
    });

    test('I/O matrix: "Clear all filters" — clearFilters() restores the full '
        'unfiltered list in place, with no filter params on the next list() '
        'call', () async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('filtered-1')], nextCursor: null)),
      );
      await cubit.applyFilters(source: EntrySource.manual);
      expect(cubit.hasActiveFilters, isTrue);

      fakeRepository.queueList(
        right(
          EntriesPage(
            items: [_entry('all-1'), _entry('all-2')],
            nextCursor: null,
          ),
        ),
      );
      await cubit.clearFilters();

      expect(cubit.hasActiveFilters, isFalse);
      final call = fakeRepository.listCalls.last;
      expect(call.source, isNull);
      expect(call.dateFrom, isNull);
      expect(call.dateTo, isNull);
      expect((cubit.state as MeusRegistrosLoaded).entries.map((e) => e.id), [
        'all-1',
        'all-2',
      ]);
    });

    test('I/O matrix: "Load more with filters active" — _fetchMore sends '
        'cursor plus the same active filters', () async {
      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: 'cursor-2')),
      );
      final dateFrom = DateTime(2026, 1, 1);
      await cubit.applyFilters(source: EntrySource.audio, dateFrom: dateFrom);

      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e2')], nextCursor: null)),
      );
      await cubit.loadMore();

      final call = fakeRepository.listCalls.last;
      expect(call.cursor, 'cursor-2');
      expect(call.source, EntrySource.audio);
      expect(call.dateFrom, dateFrom);
    });

    test('loadFirstPage() resets any previously active filters — a fresh '
        'mount always starts from the full unfiltered timeline', () async {
      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.applyFilters(source: EntrySource.manual);
      expect(cubit.hasActiveFilters, isTrue);

      fakeRepository.queueList(
        right(const EntriesPage(items: [], nextCursor: null)),
      );
      await cubit.loadFirstPage();

      expect(cubit.hasActiveFilters, isFalse);
      final call = fakeRepository.listCalls.last;
      expect(call.source, isNull);
      expect(call.dateFrom, isNull);
      expect(call.dateTo, isNull);
    });

    test('a Failure while filters are active still emits MeusRegistrosError '
        '(same as an unfiltered loadFirstPage() failure)', () async {
      fakeRepository.queueList(
        left(const Failure.authExpired(message: 'Sessão expirada')),
      );

      await cubit.applyFilters(source: EntrySource.manual);

      expect(cubit.state, isA<MeusRegistrosError>());
    });

    test('code-review fix: retryCurrentPage() keeps the active filter intact '
        '— unlike loadFirstPage(), a failed filtered query retries with the '
        'same filter rather than silently succeeding unfiltered', () async {
      fakeRepository.queueList(
        left(const Failure.networkTimeout(message: 'Timed out')),
      );
      await cubit.applyFilters(source: EntrySource.audio);
      expect(cubit.state, isA<MeusRegistrosError>());

      fakeRepository.queueList(
        right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
      );
      await cubit.retryCurrentPage();

      expect(cubit.hasActiveFilters, isTrue);
      expect(cubit.activeSource, EntrySource.audio);
      final call = fakeRepository.listCalls.last;
      expect(call.source, EntrySource.audio);
    });

    group('code-review fix: a new entry/pending write must never visibly '
        'violate the active filter', () {
      test('a confirmed entry matching the active source filter is still '
          'prepended normally (control case)', () async {
        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);

        fakeTracker.emitConfirmed(
          'temp-1',
          _entry('new-1', source: EntrySource.audio),
        );
        await Future<void>.delayed(Duration.zero);

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.entries.map((e) => e.id), ['new-1', 'e1']);
      });

      test('a confirmed entry whose source does not match the active source '
          'filter is never prepended into entries', () async {
        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);

        fakeTracker.emitConfirmed(
          'temp-1',
          _entry('new-1', source: EntrySource.manual),
        );
        await Future<void>.delayed(Duration.zero);

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.entries.map((e) => e.id), ['e1']);
      });

      test('a confirmed entry before the active dateFrom is never prepended '
          'into entries', () async {
        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await cubit.applyFilters(
          dateFrom: DateTime(2026, 1, 1),
          dateTo: DateTime(2026, 1, 31),
        );
        expect(cubit.state, isA<MeusRegistrosEmpty>());

        fakeTracker.emitConfirmed(
          'temp-1',
          _entry('new-1', occurredAt: '2025-12-31T00:00:00Z'),
        );
        await Future<void>.delayed(Duration.zero);

        // Still MeusRegistrosEmpty — nothing new matched the filter, so
        // there was nothing to transition into MeusRegistrosLoaded for.
        expect(cubit.state, isA<MeusRegistrosEmpty>());
      });

      test(
        'round-2 review fix: a confirmed entry created after the active '
        'dateTo still shows live — dateTo only narrows the server list() '
        'query (Design Notes: it\'s frozen to "now" at apply-time), so a '
        'brand-new entry written moments later while "Esta semana"/"Este '
        'mês" is still active must not be permanently hidden by it',
        () async {
          fakeRepository.queueList(
            right(const EntriesPage(items: [], nextCursor: null)),
          );
          final dateTo = DateTime(2026, 1, 1);
          await cubit.applyFilters(
            dateFrom: DateTime(2025, 12, 1),
            dateTo: dateTo,
          );
          expect(cubit.state, isA<MeusRegistrosEmpty>());

          fakeTracker.emitConfirmed(
            'temp-1',
            _entry(
              'new-1',
              occurredAt: dateTo.add(const Duration(days: 1)).toIso8601String(),
            ),
          );
          await Future<void>.delayed(Duration.zero);

          final state = cubit.state as MeusRegistrosLoaded;
          expect(state.entries.map((e) => e.id), ['new-1']);
        },
      );

      test('round-2 review fix: a pending write started after the active '
          'dateTo still shows its own placeholder card, same rationale as '
          'the confirmed-entry case above', () async {
        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        final dateTo = DateTime(2026, 1, 1);
        await cubit.applyFilters(
          dateFrom: DateTime(2025, 12, 1),
          dateTo: dateTo,
        );
        expect(cubit.state, isA<MeusRegistrosEmpty>());

        fakeTracker.emitPendingWrites([
          _pendingWrite(
            'temp-1',
            startedAt: dateTo.add(const Duration(days: 1)),
          ),
        ]);
        await Future<void>.delayed(Duration.zero);

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.pendingWrites, hasLength(1));
      });

      test('round-2 review fix: an item already visible under "no active '
          'filter" correctly drops out of view once applyFilters() makes it '
          'no longer match — the reverse of every other case in this group, '
          'which all apply the filter first', () async {
        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );
        await cubit.loadFirstPage();
        fakeTracker.emitConfirmed(
          'temp-1',
          _entry('new-1', source: EntrySource.manual),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          (cubit.state as MeusRegistrosLoaded).entries.map((e) => e.id),
          containsAll(['e1', 'new-1']),
        );

        fakeRepository.queueList(
          right(EntriesPage(items: [_entry('e1')], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);

        // The fresh server-filtered page excludes 'new-1' entirely —
        // _loadFiltered() fully replaces state rather than filtering
        // the previous entries list incrementally, so there's no
        // separate path that could leave a stale, now-non-matching
        // entry behind.
        expect((cubit.state as MeusRegistrosLoaded).entries.map((e) => e.id), [
          'e1',
        ]);
      });

      test('a confirmed entry that doesn\'t match a MeusRegistrosEmpty '
          'screen\'s active filter leaves it unchanged (no spurious '
          'MeusRegistrosLoaded with zero entries)', () async {
        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);
        expect(cubit.state, isA<MeusRegistrosEmpty>());

        fakeTracker.emitConfirmed(
          'temp-1',
          _entry('new-1', source: EntrySource.manual),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state, isA<MeusRegistrosEmpty>());
      });

      test('a pending write matching the active source filter still shows '
          'its own placeholder card (control case)', () async {
        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);
        expect(cubit.state, isA<MeusRegistrosEmpty>());

        fakeTracker.emitPendingWrites([
          _pendingWrite('temp-1', source: EntrySource.audio),
        ]);
        await Future<void>.delayed(Duration.zero);

        final state = cubit.state as MeusRegistrosLoaded;
        expect(state.pendingWrites, hasLength(1));
      });

      test('a pending write whose source doesn\'t match the active filter '
          'never shows its own placeholder card', () async {
        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);
        expect(cubit.state, isA<MeusRegistrosEmpty>());

        fakeTracker.emitPendingWrites([
          _pendingWrite('temp-1', source: EntrySource.manual),
        ]);
        await Future<void>.delayed(Duration.zero);

        // Stays MeusRegistrosEmpty — the one pending write in flight
        // doesn't match the active filter, so it has nothing to show.
        expect(cubit.state, isA<MeusRegistrosEmpty>());
      });

      test('a non-matching pending write already outstanding is excluded '
          'from the very first filtered MeusRegistrosLoaded/Empty emission '
          'too, not just from a later pendingWrites update', () async {
        fakeTracker.emitPendingWrites([
          _pendingWrite('temp-1', source: EntrySource.manual),
        ]);
        await Future<void>.delayed(Duration.zero);

        fakeRepository.queueList(
          right(const EntriesPage(items: [], nextCursor: null)),
        );
        await cubit.applyFilters(source: EntrySource.audio);

        expect(cubit.state, isA<MeusRegistrosEmpty>());
      });
    });
  });
}
