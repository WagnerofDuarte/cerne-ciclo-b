import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

const _entry = Entry(
  id: 'server-1',
  content: 'Hoje foi um bom dia.',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T00:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// A scriptable fake `EntriesRepository` — same plain-fake convention
/// every other repository-backed cubit test in this codebase already
/// uses, needed here because a single test drives several distinct
/// `create()` calls (the initial attempt, then a `retry()`) with
/// different queued results.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Completer<Either<Failure, Entry>>> _completers = [];
  int createCallCount = 0;
  final List<String> createdContents = [];

  @override
  Future<Either<Failure, Entry>> create({
    required String content,
    required EntrySource source,
    int? mediaDurationSeconds,
  }) {
    createCallCount++;
    createdContents.add(content);
    final completer = Completer<Either<Failure, Entry>>();
    _completers.add(completer);
    return completer.future;
  }

  void resolve(int callIndex, Either<Failure, Entry> result) {
    _completers[callIndex].complete(result);
  }

  @override
  Future<Either<Failure, EntriesPage>> list({
    String? cursor,
    int limit = 20,
  }) async => throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<Entry>>> search(String query) async =>
      throw UnimplementedError('not expected to be called');
}

void main() {
  late _FakeEntriesRepository fakeRepository;
  late PendingEntryWriteTrackerImpl tracker;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    tracker = PendingEntryWriteTrackerImpl(repository: fakeRepository);
  });

  group('create()', () {
    test(
      'records an optimistic inFlight PendingEntryWrite before the '
      'repository call resolves, visible on pendingWrites immediately',
      () async {
        final snapshots = <List<PendingEntryWrite>>[];
        final subscription = tracker.pendingWrites.listen(snapshots.add);

        final createFuture = tracker.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        );
        await Future<void>.delayed(Duration.zero);

        expect(snapshots, isNotEmpty);
        final latest = snapshots.last;
        expect(latest, hasLength(1));
        expect(latest.single.content, 'Hoje foi um bom dia.');
        expect(latest.single.status, isA<PendingEntryWriteInFlight>());

        fakeRepository.resolve(0, right(_entry));
        await createFuture;
        await subscription.cancel();
      },
    );

    test(
      'identical contract to EntriesRepository.create() — forwards '
      'content/source/mediaDurationSeconds verbatim and returns the '
      'repository\'s own result',
      () async {
        final createFuture = tracker.create(
          content: 'Áudio transcrito.',
          source: EntrySource.audio,
          mediaDurationSeconds: 7,
        );

        fakeRepository.resolve(0, right(_entry));
        final result = await createFuture;

        expect(result, right(_entry));
        expect(fakeRepository.createdContents, ['Áudio transcrito.']);
      },
    );

    test(
      'on success: drops the pending record and broadcasts the confirmed '
      'Entry paired with its own tempId on confirmedWrites',
      () async {
        final confirmed = <({String tempId, Entry entry})>[];
        final confirmedSubscription = tracker.confirmedWrites.listen(
          confirmed.add,
        );
        final pendingSnapshots = <List<PendingEntryWrite>>[];
        final pendingSubscription = tracker.pendingWrites.listen(
          pendingSnapshots.add,
        );

        final createFuture = tracker.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        );
        await Future<void>.delayed(Duration.zero);
        expect(pendingSnapshots.last, hasLength(1));
        final tempId = pendingSnapshots.last.single.tempId;

        fakeRepository.resolve(0, right(_entry));
        await createFuture;
        await Future<void>.delayed(Duration.zero);

        expect(confirmed, hasLength(1));
        expect(confirmed.single.tempId, tempId);
        expect(confirmed.single.entry, _entry);
        expect(pendingSnapshots.last, isEmpty);

        await confirmedSubscription.cancel();
        await pendingSubscription.cancel();
      },
    );

    test(
      'on failure: flips the record to PendingEntryWriteFailed carrying '
      'the Failure verbatim, never broadcasts on confirmedWrites',
      () async {
        final confirmed = <({String tempId, Entry entry})>[];
        final confirmedSubscription = tracker.confirmedWrites.listen(
          confirmed.add,
        );

        const failure = Failure.networkOffline(message: 'Sem conexão');
        final createFuture = tracker.create(
          content: 'Hoje foi um bom dia.',
          source: EntrySource.manual,
        );
        fakeRepository.resolve(0, left(failure));
        final result = await createFuture;
        await Future<void>.delayed(Duration.zero);

        expect(result, left(failure));
        expect(confirmed, isEmpty);

        final snapshot = await tracker.pendingWrites.first;
        expect(snapshot, hasLength(1));
        expect(
          snapshot.single.status,
          const PendingEntryWriteFailed(failure: failure),
        );

        await confirmedSubscription.cancel();
      },
    );
  });

  group('pendingWrites — replay-capable', () {
    test(
      'a late subscriber sees the current snapshot immediately, not just '
      'future changes (mirrors SessionRepositoryImpl.statusStream)',
      () async {
        unawaited(
          tracker.create(content: 'conteúdo', source: EntrySource.manual),
        );
        await Future<void>.delayed(Duration.zero);

        final lateSnapshot = await tracker.pendingWrites.first;

        expect(lateSnapshot, hasLength(1));
      },
    );

    test('a late subscriber before any create() sees an empty snapshot', () async {
      final snapshot = await tracker.pendingWrites.first;

      expect(snapshot, isEmpty);
    });
  });

  group('retry()', () {
    test(
      'replays the exact same payload (content/source/'
      'mediaDurationSeconds) a failed write was created with',
      () async {
        const failure = Failure.networkTimeout(message: 'Timed out');
        final createFuture = tracker.create(
          content: 'Áudio transcrito.',
          source: EntrySource.audio,
          mediaDurationSeconds: 9,
        );
        fakeRepository.resolve(0, left(failure));
        await createFuture;
        final tempId = (await tracker.pendingWrites.first).single.tempId;

        final retryFuture = tracker.retry(tempId);
        fakeRepository.resolve(1, right(_entry));
        await retryFuture;

        expect(fakeRepository.createCallCount, 2);
        expect(fakeRepository.createdContents, [
          'Áudio transcrito.',
          'Áudio transcrito.',
        ]);
      },
    );

    test('on success: drops the record and broadcasts confirmedWrites', () async {
      const failure = Failure.networkOffline(message: 'Sem conexão');
      final createFuture = tracker.create(
        content: 'Hoje foi um bom dia.',
        source: EntrySource.manual,
      );
      fakeRepository.resolve(0, left(failure));
      await createFuture;
      final tempId = (await tracker.pendingWrites.first).single.tempId;

      final confirmed = <({String tempId, Entry entry})>[];
      final confirmedSubscription = tracker.confirmedWrites.listen(
        confirmed.add,
      );

      final retryFuture = tracker.retry(tempId);
      fakeRepository.resolve(1, right(_entry));
      await retryFuture;
      await Future<void>.delayed(Duration.zero);

      expect(confirmed, hasLength(1));
      expect(confirmed.single.tempId, tempId);
      expect(confirmed.single.entry, _entry);
      final snapshot = await tracker.pendingWrites.first;
      expect(snapshot, isEmpty);

      await confirmedSubscription.cancel();
    });

    test(
      'a no-op for an unknown tempId — no repository call',
      () async {
        await tracker.retry('does-not-exist');

        expect(fakeRepository.createCallCount, 0);
      },
    );

    test(
      'a no-op while the write is still in flight (not yet failed)',
      () async {
        final createFuture = tracker.create(
          content: 'conteúdo',
          source: EntrySource.manual,
        );
        final tempId = (await tracker.pendingWrites.first).single.tempId;

        await tracker.retry(tempId);

        expect(fakeRepository.createCallCount, 1);

        fakeRepository.resolve(0, right(_entry));
        await createFuture;
      },
    );

    test(
      'a no-op once the write has already resolved successfully',
      () async {
        final createFuture = tracker.create(
          content: 'conteúdo',
          source: EntrySource.manual,
        );
        final tempId = (await tracker.pendingWrites.first).single.tempId;
        fakeRepository.resolve(0, right(_entry));
        await createFuture;

        await tracker.retry(tempId);

        expect(fakeRepository.createCallCount, 1);
      },
    );
  });

  group(
    'spec amendment (code-review round 1): create() drops a superseded '
    'failed record',
    () {
      test(
        'a second create() call after an earlier one failed leaves exactly '
        'one record — the new one — not two',
        () async {
          const failure = Failure.networkOffline(message: 'Sem conexão');
          final firstCreate = tracker.create(
            content: 'primeira tentativa',
            source: EntrySource.manual,
          );
          fakeRepository.resolve(0, left(failure));
          await firstCreate;
          final firstTempId = (await tracker.pendingWrites.first).single.tempId;

          // The same still-open Insertion Modal's "Salvar" is tapped again
          // (not the badge's own retry) — this is a brand-new `create()`
          // call, not a `retry()` of the first one.
          final secondCreate = tracker.create(
            content: 'segunda tentativa',
            source: EntrySource.manual,
          );
          await Future<void>.delayed(Duration.zero);

          final snapshot = await tracker.pendingWrites.first;
          expect(snapshot, hasLength(1));
          expect(snapshot.single.content, 'segunda tentativa');
          expect(snapshot.single.tempId, isNot(firstTempId));
          expect(snapshot.single.status, isA<PendingEntryWriteInFlight>());

          fakeRepository.resolve(1, right(_entry));
          await secondCreate;
        },
      );

      test(
        'only one combined snapshot is emitted for the drop+add — never a '
        'transient "failed just removed, new one not yet added" one',
        () async {
          const failure = Failure.networkOffline(message: 'Sem conexão');
          final firstCreate = tracker.create(
            content: 'primeira tentativa',
            source: EntrySource.manual,
          );
          fakeRepository.resolve(0, left(failure));
          await firstCreate;

          final snapshots = <List<PendingEntryWrite>>[];
          final subscription = tracker.pendingWrites.listen(snapshots.add);
          // The replay-capable initial snapshot (`Stream.multi`'s own
          // synchronous `controller.add()`, delivered on the next
          // microtask) must be allowed to land *before* clearing — not
          // yet triggering the second `create()` below — or it would
          // otherwise still be in flight and land folded in among the
          // assertions below, double-counting as part of "the" one
          // combined emission this test is pinning.
          await Future<void>.delayed(Duration.zero);
          snapshots.clear();

          final secondCreate = tracker.create(
            content: 'segunda tentativa',
            source: EntrySource.manual,
          );
          await Future<void>.delayed(Duration.zero);

          expect(snapshots, hasLength(1));
          expect(snapshots.single, hasLength(1));
          expect(snapshots.single.single.content, 'segunda tentativa');

          fakeRepository.resolve(1, right(_entry));
          await secondCreate;
          await subscription.cancel();
        },
      );

      test(
        'a failed write from a different lineage is also dropped — the '
        'invariant is "never more than one failed record at a time", not '
        'scoped to the same tempId',
        () async {
          const failure = Failure.networkOffline(message: 'Sem conexão');
          final firstCreate = tracker.create(
            content: 'áudio que falhou',
            source: EntrySource.audio,
            mediaDurationSeconds: 5,
          );
          fakeRepository.resolve(0, left(failure));
          await firstCreate;

          final secondCreate = tracker.create(
            content: 'texto novo',
            source: EntrySource.manual,
          );
          await Future<void>.delayed(Duration.zero);

          final snapshot = await tracker.pendingWrites.first;
          expect(snapshot, hasLength(1));
          expect(snapshot.single.source, EntrySource.manual);

          fakeRepository.resolve(1, right(_entry));
          await secondCreate;
        },
      );
    },
  );

  group('dispose()', () {
    test(
      'a create() call after dispose() still completes without throwing, '
      'even though its own pendingWrites/confirmedWrites emissions are '
      'now guarded no-ops against the closed controllers',
      () async {
        await tracker.dispose();

        final createFuture = tracker.create(
          content: 'conteúdo',
          source: EntrySource.manual,
        );
        fakeRepository.resolve(0, right(_entry));

        await expectLater(createFuture, completes);
      },
    );
  });
}
