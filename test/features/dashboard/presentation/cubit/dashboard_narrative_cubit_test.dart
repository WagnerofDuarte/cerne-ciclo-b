import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
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

/// A plain (non-mocktail) fake — same convention `dashboard_cubit_test.
/// dart`'s own `_FakeDashboardRepository` uses: several tests here need to
/// resolve two calls out of order (the stale-in-flight-call generation
/// guard), which a single static mocktail stub can't express as naturally.
/// [getAggregate] is never called by this cubit (`DashboardNarrativeCubit`
/// only ever calls [getNarrative]) — throws if reached.
class _FakeDashboardRepository implements DashboardRepository {
  final List<Either<Failure, String>> _results = [];
  final List<Completer<Either<Failure, String>>> _completers = [];
  final List<String> calls = [];

  /// When `true`, [getNarrative] returns a `Completer`-backed future the
  /// test resolves explicitly (via [resolve]) rather than immediately
  /// returning a queued result.
  bool gated = false;

  void queue(Either<Failure, String> result) {
    _results.add(result);
  }

  void resolve(int callIndex, Either<Failure, String> result) {
    _completers[callIndex].complete(result);
  }

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, String>> getNarrative({required String period}) {
    calls.add(period);
    if (gated) {
      final completer = Completer<Either<Failure, String>>();
      _completers.add(completer);
      return completer.future;
    }
    if (_results.isEmpty) {
      throw StateError(
        'no queued getNarrative() result for call #${calls.length}',
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
/// helper `dashboard_cubit_test.dart` already documents.
Future<List<Resource<String>>> _emittedDuring(
  DashboardNarrativeCubit cubit,
  FutureOr<void> Function() act,
) async {
  final emitted = <Resource<String>>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  // Flushes any state the broadcast `StreamController` has already queued
  // for delivery but not yet dispatched to this listener — same rationale
  // `dashboard_cubit_test.dart`'s own `_emittedDuring` gives.
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  return emitted;
}

void main() {
  late _FakeDashboardRepository fakeRepository;
  late _FakePendingEntryWriteTracker fakeTracker;
  late DashboardNarrativeCubit cubit;

  setUp(() {
    fakeRepository = _FakeDashboardRepository();
    fakeTracker = _FakePendingEntryWriteTracker();
    cubit = DashboardNarrativeCubit(fakeRepository, fakeTracker);
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await fakeTracker.dispose();
  });

  test('starts as ResourceIdle', () {
    expect(cubit.state, const ResourceIdle<String>());
  });

  test('load() always passes period: \'all\' (Boundaries: same fixed value '
      'as dashboard-aggregate-get)', () async {
    fakeRepository.queue(right('narrative text'));

    await cubit.load();

    expect(fakeRepository.calls, ['all']);
  });

  test('a successful load() emits ResourceLoading then ResourceData with '
      'the repository\'s own text', () async {
    fakeRepository.queue(right('Seu balanço do período.'));

    final emitted = await _emittedDuring(cubit, cubit.load);

    expect(emitted, [
      // Not a `const` comparison (same rationale `DashboardCubit`'s own
      // test gives) — `load()` deliberately emits a fresh,
      // non-canonicalized `ResourceLoading` every time.
      isA<ResourceLoading<String>>(),
      isA<ResourceData<String>>().having(
        (s) => s.data,
        'data',
        'Seu balanço do período.',
      ),
    ]);
  });

  test('I/O matrix: "narrative fails" — a Failure from the repository emits '
      'ResourceError, never a crash', () async {
    fakeRepository.queue(
      left(const Failure.networkOffline(message: 'Sem conexão')),
    );

    final emitted = await _emittedDuring(cubit, cubit.load);

    expect(emitted, [
      isA<ResourceLoading<String>>(),
      isA<ResourceError<String>>().having(
        (s) => s.failure,
        'failure',
        isA<NetworkOffline>(),
      ),
    ]);
  });

  test('Boundaries: "constructor-subscribes to confirmedWrites, recompute '
      'on every entry write, same as the aggregate" — a confirmedWrites '
      'event triggers a brand-new load() with no explicit call from a '
      'screen', () async {
    fakeRepository.queue(right('first'));
    fakeRepository.queue(right('second'));

    final emitted = await _emittedDuring(cubit, () async {
      await cubit.load();
      fakeTracker.emitConfirmed();
      await Future<void>.delayed(Duration.zero);
    });

    expect(fakeRepository.calls, ['all', 'all']);
    expect(emitted.last, isA<ResourceData<String>>());
    expect((emitted.last as ResourceData<String>).data, 'second');
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
      expect(cubit.state, isA<ResourceLoading<String>>());

      // A confirmedWrites event starts a second, superseding load().
      fakeTracker.emitConfirmed();
      await Future<void>.delayed(Duration.zero);
      expect(fakeRepository.calls, ['all', 'all']);

      // The first (stale) call resolving must never land.
      fakeRepository.resolve(0, right('stale'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ResourceLoading<String>>());

      // The second (fresh) call's own result still lands normally.
      fakeRepository.resolve(1, right('fresh'));
      await Future<void>.delayed(Duration.zero);
      expect((cubit.state as ResourceData<String>).data, 'fresh');
    },
  );

  test(
    'a retry tap (AccountSettingsScreen/DashboardChartSection\'s own '
    'narrativeCubit.load() re-call) behaves like any other load() — '
    'ResourceError followed by a fresh ResourceData, no crash',
    () async {
      fakeRepository.queue(
        left(const Failure.networkOffline(message: 'Sem conexão')),
      );
      await cubit.load();
      expect(cubit.state, isA<ResourceError<String>>());

      fakeRepository.queue(right('Recuperado com sucesso.'));
      await cubit.load();

      expect(
        (cubit.state as ResourceData<String>).data,
        'Recuperado com sucesso.',
      );
    },
  );
}
