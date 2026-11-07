import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

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
/// `entries_search_cubit_test.dart`'s own `_FakeEntriesRepository` fake
/// uses: several tests here need to resolve two calls out of order (the
/// stale-in-flight-call generation guard), which a single static mocktail
/// stub can't express as naturally.
class _FakeDashboardRepository implements DashboardRepository {
  final List<Either<Failure, DashboardAggregate>> _results = [];
  final List<Completer<Either<Failure, DashboardAggregate>>> _completers = [];
  final List<String> calls = [];

  /// When `true`, [getAggregate] returns a `Completer`-backed future the
  /// test resolves explicitly (via [resolve]) rather than immediately
  /// returning a queued result.
  bool gated = false;

  void queue(Either<Failure, DashboardAggregate> result) {
    _results.add(result);
  }

  void resolve(int callIndex, Either<Failure, DashboardAggregate> result) {
    _completers[callIndex].complete(result);
  }

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) {
    calls.add(period);
    if (gated) {
      final completer = Completer<Either<Failure, DashboardAggregate>>();
      _completers.add(completer);
      return completer.future;
    }
    if (_results.isEmpty) {
      throw StateError(
        'no queued getAggregate() result for call #${calls.length}',
      );
    }
    return Future.value(_results.removeAt(0));
  }
}

/// A plain (non-mocktail) fake [PendingEntryWriteTracker] — [emitConfirmed]
/// lets a test drive the Boundaries' own "recomputing on each event"
/// requirement directly, without any capture cubit actually in play.
class _FakePendingEntryWriteTracker implements PendingEntryWriteTracker {
  final _confirmedController =
      StreamController<({String tempId, Entry entry})>.broadcast();

  void emitConfirmed() {
    _confirmedController.add((tempId: 'temp-1', entry: _entry('e1')));
  }

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
      _confirmedController.stream;

  @override
  Future<void> dispose() => _confirmedController.close();
}

/// Collects every state the cubit emits for the duration of [act] — same
/// helper `entries_search_cubit_test.dart` already documents.
Future<List<Resource<DashboardAggregate>>> _emittedDuring(
  DashboardCubit cubit,
  FutureOr<void> Function() act,
) async {
  final emitted = <Resource<DashboardAggregate>>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  // Flushes any state the broadcast `StreamController` has already queued
  // for delivery but not yet dispatched to this listener (`Cubit.emit`'s
  // underlying controller is not `sync`) — without this, a `load()` whose
  // own awaited repository call resolves synchronously can have its final
  // `emit()` still pending delivery at the exact microtask `act()`'s
  // returned Future completes on.
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  return emitted;
}

void main() {
  late _FakeDashboardRepository fakeRepository;
  late _FakePendingEntryWriteTracker fakeTracker;
  late DashboardCubit cubit;

  setUp(() {
    fakeRepository = _FakeDashboardRepository();
    fakeTracker = _FakePendingEntryWriteTracker();
    cubit = DashboardCubit(fakeRepository, fakeTracker);
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await fakeTracker.dispose();
  });

  test('starts as ResourceIdle', () {
    expect(cubit.state, const ResourceIdle<DashboardAggregate>());
  });

  test('load() always passes period: \'all\' (Boundaries: fixed, no period '
      'selector anywhere in the product)', () async {
    fakeRepository.queue(
      right(const DashboardAggregate(totalCount: 0, bucketCounts: [])),
    );

    await cubit.load();

    expect(fakeRepository.calls, ['all']);
  });

  test('a successful load() emits ResourceLoading then ResourceData with '
      'the repository\'s aggregate', () async {
    fakeRepository.queue(
      right(const DashboardAggregate(totalCount: 3, bucketCounts: [1, 2])),
    );

    final emitted = await _emittedDuring(cubit, cubit.load);

    expect(emitted, [
      // Not a `const` comparison (same rationale `EntriesSearchCubit`'s
      // own test gives) — `load()` deliberately emits a fresh,
      // non-canonicalized `ResourceLoading` every time.
      isA<ResourceLoading<DashboardAggregate>>(),
      isA<ResourceData<DashboardAggregate>>().having(
        (s) => s.data.totalCount,
        'totalCount',
        3,
      ),
    ]);
  });

  test('I/O matrix: "Fetch fails" — a Failure from the repository emits '
      'ResourceError, never a crash', () async {
    fakeRepository.queue(
      left(const Failure.networkOffline(message: 'Sem conexão')),
    );

    final emitted = await _emittedDuring(cubit, cubit.load);

    expect(emitted, [
      isA<ResourceLoading<DashboardAggregate>>(),
      isA<ResourceError<DashboardAggregate>>().having(
        (s) => s.failure,
        'failure',
        isA<NetworkOffline>(),
      ),
    ]);
  });

  test('Acceptance Criteria: "entry created elsewhere while mounted ... chart '
      'recomputes" — a confirmedWrites event triggers a brand-new load() '
      'with no explicit call from a screen', () async {
    fakeRepository.queue(
      right(const DashboardAggregate(totalCount: 0, bucketCounts: [])),
    );
    fakeRepository.queue(
      right(const DashboardAggregate(totalCount: 1, bucketCounts: [1])),
    );

    final emitted = await _emittedDuring(cubit, () async {
      await cubit.load();
      fakeTracker.emitConfirmed();
      await Future<void>.delayed(Duration.zero);
    });

    expect(fakeRepository.calls, ['all', 'all']);
    expect(emitted.last, isA<ResourceData<DashboardAggregate>>());
    expect(
      (emitted.last as ResourceData<DashboardAggregate>).data.totalCount,
      1,
    );
  });

  test(
    'generation guard: a stale in-flight load() call is discarded once a '
    'newer one (triggered by confirmedWrites) has already superseded it',
    () async {
      fakeRepository.gated = true;

      // First load() starts and never resolves yet.
      // ignore: unawaited_futures
      cubit.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ResourceLoading<DashboardAggregate>>());

      // A confirmedWrites event starts a second, superseding load().
      fakeTracker.emitConfirmed();
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.calls, ['all', 'all']);

      // The first (stale) call resolving must never land.
      fakeRepository.resolve(
        0,
        right(const DashboardAggregate(totalCount: 99, bucketCounts: [99])),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ResourceLoading<DashboardAggregate>>());

      // The second (fresh) call's own result still lands normally.
      fakeRepository.resolve(
        1,
        right(const DashboardAggregate(totalCount: 1, bucketCounts: [1])),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        (cubit.state as ResourceData<DashboardAggregate>).data.totalCount,
        1,
      );
    },
  );

  test('close() while a load() is in flight never throws (emit-after-close '
      'guard, mirrors EntriesSearchCubit)', () async {
    fakeRepository.gated = true;

    // ignore: unawaited_futures
    cubit.load();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();

    fakeRepository.resolve(
      0,
      right(const DashboardAggregate(totalCount: 1, bucketCounts: [1])),
    );
    await Future<void>.delayed(Duration.zero);
    // No exception means the generation/isClosed guard held.
  });
}
