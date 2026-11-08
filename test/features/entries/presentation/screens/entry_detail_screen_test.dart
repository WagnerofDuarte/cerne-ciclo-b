import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/entry_detail_cubit.dart';
import 'package:cerne/features/entries/presentation/screens/entry_detail_screen.dart';
import 'package:cerne/features/entries/presentation/widgets/sync_badge.dart';

Entry _entry(String id) => Entry(
  id: id,
  content: 'Conteúdo do registro.',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: '2026-01-01T10:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T10:00:00Z',
  updatedAt: '2026-01-01T10:00:00Z',
);

/// A gated fake — [firstCallGate], when set, holds the one `getById()`
/// call unresolved so a test can assert the blank `EntryDetailLoading`
/// render before letting it resolve.
class _FakeEntriesRepository implements EntriesRepository {
  final List<Either<Failure, Entry>> _results = [];
  Completer<void>? firstCallGate;
  int getByIdCallCount = 0;

  void queueGetById(Either<Failure, Entry> result) {
    _results.add(result);
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
  Future<Either<Failure, Entry>> getById(String id) async {
    getByIdCallCount++;
    if (getByIdCallCount == 1 && firstCallGate != null) {
      await firstCallGate!.future;
    }
    if (_results.isEmpty) {
      throw StateError('no queued getById() result');
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

  // Story 8.4 — not exercised by this suite, same trivial rationale
  // this fake's other untouched members already follow.
  @override
  Future<Either<Failure, Unit>> clearLocalCache() async => right(unit);
}

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
  Future<void> retry(String tempId) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<void> dispose() async {}
}

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

  // Story 8.4 — not exercised by this suite, same trivial rationale this
  // fake's other untouched members already follow.
  @override
  Future<Either<Failure, Unit>> logout() async => right(unit);

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(SessionStatus status) {
    _status = status;
    _controller.add(status);
  }
}

EntryDetailCubit _buildCubit(_FakeEntriesRepository fakeRepository) =>
    EntryDetailCubit(
      fakeRepository,
      _FakePendingEntryWriteTracker(),
      _FakeSessionRepository(),
    );

/// Renders each `EntryDetailState` variant (Code Map).
void main() {
  testWidgets(
    'EntryDetailLoading renders a blank screen (no skeleton/spinner — no '
    'prototype precedent for this screen, Intent)',
    (tester) async {
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete();
        }
      });
      final fakeRepository = _FakeEntriesRepository()
        ..firstCallGate = gate
        ..queueGetById(right(_entry('e1')));
      final cubit = _buildCubit(fakeRepository);
      final loadFuture = cubit.load('e1');

      await tester.pumpWidget(
        MaterialApp(home: EntryDetailScreen(cubit: cubit)),
      );

      expect(find.text('Conteúdo do registro.'), findsNothing);
      expect(find.byType(SyncBadge), findsNothing);

      gate.complete();
      await loadFuture;
      await tester.pump();
    },
  );

  testWidgets('EntryDetailData renders content, source, local time, and a Sync '
      'Badge with no onRetryTap — zero edit affordance on the screen '
      '(Acceptance Criteria)', (tester) async {
    final fakeRepository = _FakeEntriesRepository()
      ..queueGetById(right(_entry('e1')));
    final cubit = _buildCubit(fakeRepository);
    final loadFuture = cubit.load('e1');

    await tester.pumpWidget(MaterialApp(home: EntryDetailScreen(cubit: cubit)));
    await loadFuture;
    await tester.pump();

    expect(find.text('Conteúdo do registro.'), findsOneWidget);
    expect(find.text('Texto'), findsOneWidget);
    expect(find.byType(SyncBadge), findsOneWidget);
    final badge = tester.widget<SyncBadge>(find.byType(SyncBadge));
    expect(badge.onRetryTap, isNull);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.textContaining('Editar'), findsNothing);
  });

  testWidgets('EntryDetailNotFound renders the generic not-found treatment', (
    tester,
  ) async {
    final fakeRepository = _FakeEntriesRepository()
      ..queueGetById(left(const Failure.notFound(message: 'Não encontrado')));
    final cubit = _buildCubit(fakeRepository);
    final loadFuture = cubit.load('unknown-id');

    await tester.pumpWidget(MaterialApp(home: EntryDetailScreen(cubit: cubit)));
    await loadFuture;
    await tester.pump();

    expect(find.text('Registro não encontrado'), findsOneWidget);
  });

  testWidgets(
    'EntryDetailError (e.g. an offline cache miss) renders the exact same '
    'generic not-found treatment as EntryDetailNotFound (RNF04: never a '
    'distinguishable failure-reason state)',
    (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueGetById(left(const Failure.networkOffline(message: 'Offline')));
      final cubit = _buildCubit(fakeRepository);
      final loadFuture = cubit.load('e1');

      await tester.pumpWidget(
        MaterialApp(home: EntryDetailScreen(cubit: cubit)),
      );
      await loadFuture;
      await tester.pump();

      expect(find.text('Registro não encontrado'), findsOneWidget);
    },
  );

  testWidgets(
    'the shared BackArrowHeader is present with this screen\'s own title, '
    'regardless of which state is showing below it',
    (tester) async {
      final fakeRepository = _FakeEntriesRepository()
        ..queueGetById(right(_entry('e1')));
      final cubit = _buildCubit(fakeRepository);
      final loadFuture = cubit.load('e1');

      await tester.pumpWidget(
        MaterialApp(home: EntryDetailScreen(cubit: cubit)),
      );
      await loadFuture;
      await tester.pump();

      expect(find.text('Registro'), findsOneWidget);
    },
  );
}
