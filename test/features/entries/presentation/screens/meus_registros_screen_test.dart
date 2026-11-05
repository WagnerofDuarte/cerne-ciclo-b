import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/expiry_overlay_host.dart';
import 'package:cerne/core/widgets/back_arrow_header.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/screens/meus_registros_screen.dart';
import 'package:cerne/features/entries/presentation/widgets/entry_record_card.dart';
import 'package:cerne/features/entries/presentation/widgets/entry_skeleton_card.dart';

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
    listCallCount++;
    if (listCallCount == 1 && firstCallGate != null) {
      await firstCallGate!.future;
    }
    if (_listResults.isEmpty) {
      throw StateError('no queued list() result for call #$listCallCount');
    }
    return _listResults.removeAt(0);
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

Future<MeusRegistrosCubit> _pumpScreen(
  WidgetTester tester,
  _FakeEntriesRepository fakeRepository,
) async {
  final cubit = MeusRegistrosCubit(
    fakeRepository,
    _FakePendingEntryWriteTracker(),
  );
  addTearDown(cubit.close);
  await tester.pumpWidget(MaterialApp(home: MeusRegistrosScreen(cubit: cubit)));
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
        expect(find.text('Nenhum registro ainda.'), findsOneWidget);

        // Even once the threshold elapses afterwards, the state is already
        // resolved — the skeleton branch never gets a chance to render.
        await tester.pump(const Duration(milliseconds: 301));
        expect(find.byType(EntrySkeletonCard), findsNothing);
      },
    );
  });

  group('zero / error states', () {
    testWidgets(
      'zero entries renders the plain "no entries yet" text — Boundaries: '
      'no polished CTA this story',
      (tester) async {
        final fakeRepository = _FakeEntriesRepository()
          ..queueList(right(const EntriesPage(items: [], nextCursor: null)));

        await _pumpScreen(tester, fakeRepository);
        await tester.pumpAndSettle();

        expect(find.text('Nenhum registro ainda.'), findsOneWidget);
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

        expect(find.text('Nenhum registro ainda.'), findsOneWidget);
        expect(fakeRepository.listCallCount, 2);
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

    testWidgets(
      'the back arrow navigates to / (Boundaries: "back arrow always '
      'targets /"), mirroring the deleted MeusRegistrosPlaceholderScreen '
      'test of the same thing',
      (tester) async {
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
            GoRoute(
              path: '/',
              builder: (context, state) => const Text('Home'),
            ),
            GoRoute(
              path: '/meus-registros',
              builder: (context, state) => MeusRegistrosScreen(cubit: cubit),
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
      },
    );
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
    testWidgets(
      'the global ExpiryOverlayHost appearing over this screen while '
      'scrolled does not throw and leaves the scroll position untouched',
      (tester) async {
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
                  builder: (context) => MeusRegistrosScreen(cubit: cubit),
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
      },
    );
  });
}
