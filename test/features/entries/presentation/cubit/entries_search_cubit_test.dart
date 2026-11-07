import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/presentation/cubit/entries_search_cubit.dart';

Entry _entry(String id) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// A plain (non-mocktail) fake — same convention
/// `meus_registros_cubit_test.dart`'s own fakes use. Needed here because
/// several tests (debounce coalescing, stale-result discarding) must
/// assert exactly how many times/with what argument `search()` was
/// called, and the stale-result tests need to resolve two calls out of
/// order — a single static mocktail stub can't express that naturally.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Either<Failure, List<Entry>>> _results = [];
  final List<Completer<Either<Failure, List<Entry>>>> _completers = [];
  final List<String> searchCalls = [];

  /// spec-5-3 — every `source`/`dateFrom`/`dateTo` [search] was called
  /// with, in order; `updateFilters()`'s own tests below read this to
  /// assert what the cubit actually forwarded.
  final List<({EntrySource? source, DateTime? dateFrom, DateTime? dateTo})>
  searchFilterCalls = [];

  /// When `true`, [search] returns a `Completer`-backed future the test
  /// resolves explicitly (via [resolve]) rather than immediately returning
  /// a queued result — needed to reproduce a stale in-flight call landing
  /// after a newer one has already superseded it.
  bool gated = false;

  void queueSearch(Either<Failure, List<Entry>> result) {
    _results.add(result);
  }

  void resolve(int callIndex, Either<Failure, List<Entry>> result) {
    _completers[callIndex].complete(result);
  }

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) {
    searchCalls.add(query);
    searchFilterCalls.add((source: source, dateFrom: dateFrom, dateTo: dateTo));
    if (gated) {
      final completer = Completer<Either<Failure, List<Entry>>>();
      _completers.add(completer);
      return completer.future;
    }
    if (_results.isEmpty) {
      throw StateError(
        'no queued search() result for call #${searchCalls.length}',
      );
    }
    return Future.value(_results.removeAt(0));
  }

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
    String? chatMessageId,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');
}

/// Collects every state the cubit emits for the duration of [act] — same
/// helper/rationale `auth_cubit_test.dart` already documents: this stack
/// has no `bloc_test` pin, so this drives [EntriesSearchCubit] through its
/// public API only, the same way any other `flutter_bloc` consumer would.
Future<List<Resource<List<Entry>>>> _emittedDuring(
  EntriesSearchCubit cubit,
  FutureOr<void> Function() act,
) async {
  final emitted = <Resource<List<Entry>>>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  await subscription.cancel();
  return emitted;
}

void main() {
  late _FakeEntriesRepository fakeRepository;
  late EntriesSearchCubit cubit;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    cubit = EntriesSearchCubit(fakeRepository);
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
  });

  test('starts as ResourceIdle', () {
    expect(cubit.state, const ResourceIdle<List<Entry>>());
  });

  test('I/O matrix: "Semantic match" — a successful search emits '
      'ResourceLoading then ResourceData with the repository\'s results, '
      '300ms after the triggering call', () async {
    fakeRepository.queueSearch(right([_entry('e1')]));

    final emitted = await _emittedDuring(cubit, () async {
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });

    expect(emitted, [
      // Not a `const` comparison (Review finding) — `_search()`
      // deliberately emits a fresh, non-canonicalized `ResourceLoading`
      // each time, so only its runtime type is asserted here.
      isA<ResourceLoading<List<Entry>>>(),
      isA<ResourceData<List<Entry>>>().having(
        (s) => s.data.map((e) => e.id),
        'data ids',
        ['e1'],
      ),
    ]);
  });

  test('onQueryChanged trims the raw input before calling search()', () async {
    fakeRepository.queueSearch(right([_entry('e1')]));

    cubit.onQueryChanged('  ansiedade  ');
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(fakeRepository.searchCalls, ['ansiedade']);
  });

  test('I/O matrix: "Rapid typing" — 5 keystrokes within 300ms fire exactly '
      'one entries-search call, for the final value', () async {
    fakeRepository.queueSearch(right([_entry('e1')]));

    cubit.onQueryChanged('a');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cubit.onQueryChanged('an');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cubit.onQueryChanged('ans');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cubit.onQueryChanged('ansi');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cubit.onQueryChanged('ansiedade');

    // Still well within the 300ms window since the last keystroke — no
    // call should have fired yet.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fakeRepository.searchCalls, isEmpty);

    // Past the 300ms debounce window from the final keystroke.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(fakeRepository.searchCalls, ['ansiedade']);
  });

  test('I/O matrix: "Query cleared" — a non-empty query followed by an empty/'
      'whitespace one cancels the pending timer and emits ResourceIdle, '
      'with no request ever firing', () async {
    final emitted = await _emittedDuring(cubit, () async {
      cubit.onQueryChanged('ansiedade');
      cubit.onQueryChanged('   ');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });

    expect(emitted, [const ResourceIdle<List<Entry>>()]);
    expect(fakeRepository.searchCalls, isEmpty);
  });

  test('I/O matrix: "Offline" — a Failure.networkOffline from the repository '
      'emits ResourceError(networkOffline), never a cache fallback', () async {
    fakeRepository.queueSearch(
      left(const Failure.networkOffline(message: 'Sem conexão')),
    );

    final emitted = await _emittedDuring(cubit, () async {
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });

    expect(emitted, [
      isA<ResourceLoading<List<Entry>>>(),
      isA<ResourceError<List<Entry>>>().having(
        (s) => s.failure,
        'failure',
        isA<NetworkOffline>(),
      ),
    ]);
  });

  test('Review finding: recovers from ResourceError — a failed search '
      'followed by a new query re-arms the debounce and reaches '
      'ResourceData normally, rather than getting stuck in error', () async {
    fakeRepository.queueSearch(
      left(const Failure.networkOffline(message: 'Sem conexão')),
    );
    fakeRepository.queueSearch(right([_entry('e1')]));

    final emitted = await _emittedDuring(cubit, () async {
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      cubit.onQueryChanged('nervosismo');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });

    expect(emitted, [
      isA<ResourceLoading<List<Entry>>>(),
      isA<ResourceError<List<Entry>>>(),
      isA<ResourceLoading<List<Entry>>>(),
      isA<ResourceData<List<Entry>>>().having(
        (s) => s.data.map((e) => e.id),
        'data ids',
        ['e1'],
      ),
    ]);
    expect(fakeRepository.searchCalls, ['ansiedade', 'nervosismo']);
  });

  test(
    'I/O matrix: "Stale response" — query A in flight, query B supersedes '
    'it; A\'s result is discarded on arrival (generation mismatch)',
    () async {
      fakeRepository.gated = true;

      cubit.onQueryChanged('query-a');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(fakeRepository.searchCalls, ['query-a']);
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      cubit.onQueryChanged('query-b');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(fakeRepository.searchCalls, ['query-a', 'query-b']);

      // Query A's (stale) result resolves after query B has already
      // started — must never land.
      fakeRepository.resolve(0, right([_entry('stale')]));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      // Query B's own result still lands normally.
      fakeRepository.resolve(1, right([_entry('fresh')]));
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as ResourceData<List<Entry>>).data.map((e) => e.id), [
        'fresh',
      ]);
    },
  );

  test('Review finding: two back-to-back in-flight searches each emit their '
      'own distinct ResourceLoading on the stream — a canonicalized const '
      'instance would make the second transition a no-op (Cubit.emit skips '
      're-emitting a state == the current one), which would in turn leave '
      'MeusRegistrosScreen\'s own skeleton timer un-reset for the second '
      'query', () async {
    fakeRepository.gated = true;

    final emitted = await _emittedDuring(cubit, () async {
      cubit.onQueryChanged('query-a');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      cubit.onQueryChanged('query-b');
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });

    // Two separate ResourceLoading events on the stream — not collapsed
    // into one no-op by `Cubit.emit`'s own `==`-based skip.
    expect(emitted.whereType<ResourceLoading<List<Entry>>>(), hasLength(2));
  });

  test(
    'I/O matrix: "Stale response" variant — an in-flight query discarded '
    'by clearing the field back to empty must never land once resolved',
    () async {
      fakeRepository.gated = true;

      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      cubit.onQueryChanged('');
      expect(cubit.state, const ResourceIdle<List<Entry>>());

      fakeRepository.resolve(0, right([_entry('stale')]));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, const ResourceIdle<List<Entry>>());
    },
  );

  test('close() while a search is in flight never throws (emit-after-close '
      'guard, mirrors MeusRegistrosCubit.loadFirstPage)', () async {
    fakeRepository.gated = true;

    cubit.onQueryChanged('ansiedade');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await cubit.close();

    fakeRepository.resolve(0, right([_entry('e1')]));
    await Future<void>.delayed(Duration.zero);
    // No exception means the generation/isClosed guard held.
  });

  group('spec-5-3: updateFilters()', () {
    test('Boundaries: "While idle: silent storage, no call" — updateFilters() '
        'with no active query stores the fields but never calls search()', () {
      cubit.updateFilters(source: EntrySource.audio);

      expect(fakeRepository.searchCalls, isEmpty);
    });

    test(
      'review finding: calling updateFilters() with the exact same '
      'source/dateFrom/dateTo already stored is a no-op during an active '
      'search — no redundant entries-search call, since nothing actually '
      'changed (e.g. MeusRegistrosScreen.initState()\'s own unconditional '
      'reset-to-null on every mount, when no filter was ever active)',
      () async {
        fakeRepository.queueSearch(right([_entry('e1')]));
        cubit.onQueryChanged('ansiedade');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(fakeRepository.searchCalls, ['ansiedade']);

        // Same values already stored (both default to null) — must not
        // fire a second search() call.
        cubit.updateFilters();
        await Future<void>.delayed(Duration.zero);

        expect(fakeRepository.searchCalls, ['ansiedade']);
      },
    );

    test('review finding: updateFilters() retries even with no filter change '
        'when the last search landed in ResourceError — the no-op-when-'
        'unchanged guard must not strand the user with no way to recover '
        'other than editing the search text', () async {
      fakeRepository.queueSearch(
        left(const Failure.networkOffline(message: 'offline')),
      );
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.state, isA<ResourceError<List<Entry>>>());
      expect(fakeRepository.searchCalls, ['ansiedade']);

      // Same values already stored (both default to null) — must still
      // retry, since the prior attempt failed.
      fakeRepository.queueSearch(right([_entry('e1')]));
      cubit.updateFilters();
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepository.searchCalls, ['ansiedade', 'ansiedade']);
      expect(cubit.state, isA<ResourceData<List<Entry>>>());
    });

    test('review finding: updateFilters() during an active search never '
        'throws after close() — same emit-after-close guard '
        'onQueryChanged()\'s own empty-query branch already has', () async {
      fakeRepository.gated = true;
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      await cubit.close();

      // A genuinely different filter value, so the no-op-when-unchanged
      // guard above doesn't mask this one — only the isClosed guard
      // should prevent the emit.
      expect(
        () => cubit.updateFilters(source: EntrySource.audio),
        returnsNormally,
      );
    });

    test('I/O matrix: "Apply filter during active search" — updateFilters() '
        'while a search is active cancels any pending debounce and '
        'immediately re-runs the same term with the new filter — no 300ms '
        'wait', () async {
      fakeRepository.queueSearch(right([_entry('e1')]));
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(fakeRepository.searchCalls, ['ansiedade']);

      fakeRepository.queueSearch(right([_entry('e2')]));
      cubit.updateFilters(source: EntrySource.audio);
      // No delay at all — the re-search must fire immediately, not
      // wait out another debounce window.
      await Future<void>.delayed(Duration.zero);

      expect(fakeRepository.searchCalls, ['ansiedade', 'ansiedade']);
      expect(fakeRepository.searchFilterCalls.last.source, EntrySource.audio);
    });

    test('a filter applied, then a brand-new query typed, carries that same '
        'filter forward to the new query too (the filter selection outlives '
        'any single search term)', () async {
      cubit.updateFilters(source: EntrySource.audio);
      fakeRepository.queueSearch(right([_entry('e1')]));

      cubit.onQueryChanged('nervosismo');
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(fakeRepository.searchFilterCalls.single.source, EntrySource.audio);
    });

    test('I/O matrix: "Clear filters during active search" — updateFilters() '
        'with no args while active re-queries the same term with every '
        'field null', () async {
      cubit.updateFilters(
        source: EntrySource.audio,
        dateFrom: DateTime(2026, 1, 1),
        dateTo: DateTime(2026, 1, 31),
      );
      fakeRepository.queueSearch(right([_entry('e1')]));
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(fakeRepository.searchFilterCalls.last.source, EntrySource.audio);

      fakeRepository.queueSearch(right([_entry('e2')]));
      cubit.updateFilters();
      await Future<void>.delayed(Duration.zero);

      final call = fakeRepository.searchFilterCalls.last;
      expect(call.source, isNull);
      expect(call.dateFrom, isNull);
      expect(call.dateTo, isNull);
    });

    test(
      'cancels a pending (not-yet-fired) debounce — updateFilters() during '
      'the 300ms window fires the re-search with the already-typed term '
      'immediately, and the original debounced call never also fires',
      () async {
        fakeRepository.queueSearch(right([_entry('e1')]));

        cubit.onQueryChanged('ansiedade');
        // Still well inside the 300ms debounce window — no call yet.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(fakeRepository.searchCalls, isEmpty);

        cubit.updateFilters(source: EntrySource.audio);
        await Future<void>.delayed(Duration.zero);

        expect(fakeRepository.searchCalls, ['ansiedade']);

        // The original debounce timer, had it fired, would have called
        // search() a second time — confirm it never does.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(fakeRepository.searchCalls, ['ansiedade']);
      },
    );

    test('updateFilters() bumps the generation, discarding a stale in-flight '
        'call the same way a new query does', () async {
      fakeRepository.gated = true;
      cubit.onQueryChanged('ansiedade');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      cubit.updateFilters(source: EntrySource.audio);
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.searchCalls, ['ansiedade', 'ansiedade']);

      // Call #0 (the stale, pre-filter one) resolving must never land.
      fakeRepository.resolve(0, right([_entry('stale')]));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ResourceLoading<List<Entry>>>());

      fakeRepository.resolve(1, right([_entry('fresh')]));
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as ResourceData<List<Entry>>).data.map((e) => e.id), [
        'fresh',
      ]);
    });
  });
}
