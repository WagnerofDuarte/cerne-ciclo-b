import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/entry_detail_cubit.dart';
import 'package:cerne/features/entries/presentation/cubit/entry_detail_state.dart';

Entry _entry(String id) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T10:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T10:00:00Z',
  updatedAt: '2026-01-01T10:00:00Z',
);

/// A plain (non-mocktail) fake — queues one `getById()` result per call,
/// same rationale as `meus_registros_cubit_test.dart`'s own fakes.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Either<Failure, Entry>> _results = [];
  int getByIdCallCount = 0;

  void queueGetById(Either<Failure, Entry> result) {
    _results.add(result);
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
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) async {
    getByIdCallCount++;
    if (_results.isEmpty) {
      throw StateError('no queued getById() result for call #$getByIdCallCount');
    }
    return _results.removeAt(0);
  }

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');
}

/// A `Completer`-per-call fake, letting a test resolve `getById()` calls in
/// whatever order it chooses — needed to reproduce the stale-result
/// generation guard, same rationale `meus_registros_cubit_test.dart`'s own
/// `_GatedEntriesRepository` already uses for `list()`.
class _GatedEntriesRepository implements EntriesRepository {
  final List<Completer<Either<Failure, Entry>>> _completers = [];

  void resolve(int callIndex, Either<Failure, Entry> result) {
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
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) {
    final completer = Completer<Either<Failure, Entry>>();
    _completers.add(completer);
    return completer.future;
  }

  @override
  Future<Either<Failure, List<Entry>>> search(
    String query, {
    EntrySource? source,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => throw UnimplementedError('not expected to be called');
}

/// A controllable `PendingEntryWriteTracker` fake — lets a test drive
/// [pendingWrites] directly; `confirmedWrites` is never exercised by this
/// cubit (it only ever reads the tracker's pending snapshot, never
/// reconciles a confirmation the way `MeusRegistrosCubit` does).
class _FakePendingEntryWriteTracker implements PendingEntryWriteTracker {
  final _pendingController =
      StreamController<List<PendingEntryWrite>>.broadcast();

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
  Future<void> retry(String tempId) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> dispose() async {
    await _pendingController.close();
  }
}

/// A plain (non-mocktail) fake `SessionRepository` — same rationale/shape
/// as `app_router_test.dart`'s/`meus_registros_screen_test.dart`'s own
/// `_FakeSessionRepository`.
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

/// Covers spec-4-4's I/O & Edge-Case Matrix for `EntryDetailCubit`, the
/// one place the three sources (Boundaries) are merged.
void main() {
  late _FakeEntriesRepository fakeRepository;
  late _FakePendingEntryWriteTracker fakeTracker;
  late _FakeSessionRepository fakeSessionRepository;
  late EntryDetailCubit cubit;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    fakeTracker = _FakePendingEntryWriteTracker();
    fakeSessionRepository = _FakeSessionRepository();
    cubit = EntryDetailCubit(
      fakeRepository,
      fakeTracker,
      fakeSessionRepository,
    );
  });

  tearDown(() async {
    await cubit.close();
    await fakeTracker.dispose();
    await fakeSessionRepository.dispose();
  });

  test('initial state is EntryDetailLoading', () {
    expect(cubit.state, const EntryDetailLoading());
  });

  group('load() — success', () {
    test(
      'a successful fetch emits EntryDetailData with a Synchronized badge '
      '(Boundaries: a fetched Entry is always server-confirmed)',
      () async {
        fakeRepository.queueGetById(right(_entry('e1')));

        await cubit.load('e1');

        expect(
          cubit.state,
          EntryDetailData(
            entry: _entry('e1'),
            badgeState: const SyncBadgeState.synchronized(),
          ),
        );
      },
    );

    test(
      'a pending write that happens to share this entry\'s id still feeds '
      'the shared deriveSyncBadgeState() (never recomputed inline), rather '
      'than being ignored',
      () async {
        fakeRepository.queueGetById(right(_entry('e1')));
        fakeTracker.emitPendingWrites([
          PendingEntryWrite(
            tempId: 'e1',
            content: 'content-e1',
            source: EntrySource.manual,
            mediaDurationSeconds: null,
            startedAt: DateTime(2026, 1, 1),
            status: const PendingEntryWriteInFlight(),
          ),
        ]);
        // Lets the pending snapshot land before `load()` reads it.
        await Future<void>.delayed(Duration.zero);

        await cubit.load('e1');

        expect(cubit.state, isA<EntryDetailData>());
        final state = cubit.state as EntryDetailData;
        expect(state.badgeState, const SyncBadgeState.synchronizing());
      },
    );
  });

  group('load() — notFound (RNF04)', () {
    test(
      'Failure.notFound emits EntryDetailNotFound',
      () async {
        fakeRepository.queueGetById(
          left(const Failure.notFound(message: 'Não encontrado')),
        );

        await cubit.load('unknown-id');

        expect(cubit.state, const EntryDetailNotFound());
      },
    );

    test(
      'a still-pending placeholder\'s synthetic tempId that 404s at the '
      'backend resolves to the exact same EntryDetailNotFound — no '
      'special-casing in this cubit',
      () async {
        fakeRepository.queueGetById(
          left(const Failure.notFound(message: 'Não encontrado')),
        );

        await cubit.load('pending-123-0');

        expect(cubit.state, const EntryDetailNotFound());
      },
    );
  });

  group('load() — every other non-absorbed Failure', () {
    test(
      'a networkOffline failure (e.g. cache miss, already resolved by the '
      'repository) emits EntryDetailError, never a permission-denied-'
      'specific state',
      () async {
        fakeRepository.queueGetById(
          left(const Failure.networkOffline(message: 'Offline')),
        );

        await cubit.load('e1');

        expect(cubit.state, const EntryDetailError(message: 'Offline'));
      },
    );

    test('authExpired also emits EntryDetailError', () async {
      fakeRepository.queueGetById(
        left(const Failure.authExpired(message: 'Sessão expirada')),
      );

      await cubit.load('e1');

      expect(
        cubit.state,
        const EntryDetailError(message: 'Sessão expirada'),
      );
    });
  });

  group('session expiry while viewing detail', () {
    test(
      'SessionRepository.statusStream emitting expired is folded into the '
      'sealed EntryDetailState itself (round-2 review fix) without '
      'disturbing the already-resolved entry/badge data — no crash, no '
      'new overlay built by this cubit itself',
      () async {
        fakeRepository.queueGetById(right(_entry('e1')));
        await cubit.load('e1');
        final dataState = cubit.state;

        fakeSessionRepository.setStatus(SessionStatus.expired);
        await Future<void>.delayed(Duration.zero);

        expect(cubit.state.sessionStatus, SessionStatus.expired);
        expect(cubit.state, isA<EntryDetailData>());
        // The resolved entry/badge data itself is unchanged — only
        // sessionStatus differs from dataState (equality intentionally
        // includes it, entry_detail_state.dart's own doc, so this cubit's
        // re-stamp actually reaches a new emit rather than being
        // short-circuited by Cubit.emit's own equality check).
        expect(
          (cubit.state as EntryDetailData).entry,
          (dataState as EntryDetailData).entry,
        );
        expect(
          (cubit.state as EntryDetailData).badgeState,
          dataState.badgeState,
        );
      },
    );

    test(
      'a status already known before load() resolves is stamped onto the '
      'very first emitted state too, not only onto a later re-emit',
      () async {
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await Future<void>.delayed(Duration.zero);
        fakeRepository.queueGetById(right(_entry('e1')));

        await cubit.load('e1');

        expect(cubit.state.sessionStatus, SessionStatus.authenticated);
      },
    );

    test(
      'the session expiring while a load() fetch is still in flight is '
      'reflected on the EntryDetailLoading state it arrives during, then '
      'carried over onto the resolved EntryDetailData once the fetch '
      'completes (review finding: previously only the already-resolved '
      'ordering was covered)',
      () async {
        final gatedRepository = _GatedEntriesRepository();
        final gatedCubit = EntryDetailCubit(
          gatedRepository,
          fakeTracker,
          fakeSessionRepository,
        );
        addTearDown(gatedCubit.close);

        final load = gatedCubit.load('e1');
        expect(gatedCubit.state, isA<EntryDetailLoading>());

        fakeSessionRepository.setStatus(SessionStatus.expired);
        await Future<void>.delayed(Duration.zero);
        expect(gatedCubit.state, isA<EntryDetailLoading>());
        expect(gatedCubit.state.sessionStatus, SessionStatus.expired);

        gatedRepository.resolve(0, right(_entry('e1')));
        await load;

        expect(gatedCubit.state, isA<EntryDetailData>());
        expect(gatedCubit.state.sessionStatus, SessionStatus.expired);
      },
    );
  });

  group('stale in-flight load() guard', () {
    test(
      'a stale call\'s result landing after a newer load() is discarded — '
      'the newer call\'s own result wins',
      () async {
        final gatedRepository = _GatedEntriesRepository();
        final gatedCubit = EntryDetailCubit(
          gatedRepository,
          fakeTracker,
          fakeSessionRepository,
        );
        addTearDown(gatedCubit.close);

        final firstLoad = gatedCubit.load('e1');
        final secondLoad = gatedCubit.load('e2');

        // Resolves the stale first call *after* the second has already
        // started — its result must never land.
        gatedRepository.resolve(0, right(_entry('e1')));
        gatedRepository.resolve(1, right(_entry('e2')));
        await Future.wait([firstLoad, secondLoad]);

        expect(gatedCubit.state, isA<EntryDetailData>());
        expect(
          (gatedCubit.state as EntryDetailData).entry.id,
          'e2',
        );
      },
    );

    test(
      'a load() result landing after the cubit is already closed is '
      'discarded too — no throw, no emit-after-close (review finding: '
      'only the other half of this guard, concurrent load() calls, was '
      'covered before)',
      () async {
        final gatedRepository = _GatedEntriesRepository();
        final gatedCubit = EntryDetailCubit(
          gatedRepository,
          fakeTracker,
          fakeSessionRepository,
        );

        final load = gatedCubit.load('e1');
        await gatedCubit.close();
        gatedRepository.resolve(0, right(_entry('e1')));

        await expectLater(load, completes);
      },
    );
  });
}
