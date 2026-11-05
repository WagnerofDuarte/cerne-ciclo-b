import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_state.dart';

Entry _entry(String id, {String occurredAt = '2026-01-01T00:00:00Z'}) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
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
  final List<({String? cursor, int limit})> listCalls = [];

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
  }) async {
    listCalls.add((cursor: cursor, limit: limit));
    if (_listResults.isEmpty) {
      throw StateError('no queued list() result for call #${listCalls.length}');
    }
    return _listResults.removeAt(0);
  }
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
  }) {
    final completer = Completer<Either<Failure, EntriesPage>>();
    _completers.add(completer);
    return completer.future;
  }
}

void main() {
  late _FakeEntriesRepository fakeRepository;
  late MeusRegistrosCubit cubit;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    cubit = MeusRegistrosCubit(fakeRepository);
  });

  tearDown(() => cubit.close());

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
      'review finding: a page with zero genuinely-new entries (every '
      'returned item already present by id) forces nextCursor to null '
      'even though the server still reports a non-null cursor — otherwise '
      'a stuck server cursor could re-trigger loadMore() forever with no '
      'progress',
      () async {
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
      },
    );

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
    test(
      'a stale loadFirstPage() result — an older call resolving after a '
      'newer call already changed the state — is discarded rather than '
      'emitted',
      () async {
        final gatedRepository = _GatedEntriesRepository();
        final gatedCubit = MeusRegistrosCubit(gatedRepository);
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
      },
    );

    test(
      'a stale _fetchMore() (loadMore()) result arriving after '
      'loadFirstPage() has already reset the state is discarded rather '
      'than emitted',
      () async {
        final gatedRepository = _GatedEntriesRepository();
        final gatedCubit = MeusRegistrosCubit(gatedRepository);
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
      },
    );
  });
}
