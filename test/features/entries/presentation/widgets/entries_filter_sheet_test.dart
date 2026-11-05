import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entries_page.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/repositories/entries_repository.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';
import 'package:cerne/features/entries/presentation/cubit/meus_registros_cubit.dart';
import 'package:cerne/features/entries/presentation/widgets/entries_filter_sheet.dart';

/// A plain fake — this suite only ever needs `list()` to resolve so
/// `MeusRegistrosCubit.applyFilters()`/`clearFilters()` don't hang; every
/// other method is unreachable from this sheet's own behavior.
class _FakeEntriesRepository implements EntriesRepository {
  final List<({EntrySource? source, DateTime? dateFrom, DateTime? dateTo})>
  listFilterCalls = [];

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
    listFilterCalls.add((source: source, dateFrom: dateFrom, dateTo: dateTo));
    return right(const EntriesPage(items: [], nextCursor: null));
  }

  @override
  Future<Either<Failure, Entry>> getById(String id) async =>
      throw UnimplementedError('not expected to be called');

  @override
  Future<Either<Failure, List<Entry>>> search(String query) async =>
      throw UnimplementedError('not expected to be called');
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
  Future<void> retry(String tempId) async {}

  @override
  Future<void> dispose() async {}
}

/// Pumps [EntriesFilterSheet] directly (bypassing `.show()`'s own
/// `showModalBottomSheet` ceremony) — its own behavior depends only on
/// [cubit], never on being inside a real modal route; a plain
/// `MaterialApp`/`Scaffold` host is enough, and still gives `Navigator.of
/// (context).pop()` (the "Aplicar" button's own call) a root route to
/// no-op against without throwing. [textScaler] (code-review fix) lets a
/// test verify this sheet's own `SingleChildScrollView` guard against
/// overflowing at a large Dynamic Type accessibility size (epic-5-context
/// .md's own UX note, cited directly in the widget's class doc).
Future<void> _pumpSheet(
  WidgetTester tester,
  MeusRegistrosCubit cubit, {
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: MaterialApp(
        home: Scaffold(body: EntriesFilterSheet(cubit: cubit)),
      ),
    ),
  );
}

/// Opens the real `EntriesFilterSheet` through its own `.show()` (unlike
/// [_pumpSheet], which mounts the sheet directly) — needed only for the
/// reduce-motion test below, which exercises `.show()`'s own
/// `disableAnimations` handling. Mirrors `insertion_modal_test.dart`'s own
/// `_openModal` helper/pattern exactly.
Future<void> _openSheet(
  WidgetTester tester,
  MeusRegistrosCubit cubit, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    Builder(
      builder: (outerContext) => MediaQuery(
        data: MediaQuery.of(outerContext)
            .copyWith(disableAnimations: disableAnimations),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => EntriesFilterSheet.show(context, cubit: cubit),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
}

void main() {
  late _FakeEntriesRepository fakeRepository;
  late MeusRegistrosCubit cubit;

  setUp(() {
    fakeRepository = _FakeEntriesRepository();
    cubit = MeusRegistrosCubit(fakeRepository, _FakePendingEntryWriteTracker());
  });

  tearDown(() async {
    await cubit.close();
  });

  testWidgets(
    'renders both groups ("INTERVALO DE DATA"/"TIPO DE ENTRADA") and no '
    '"CATEGORIA" group (Design Notes: the backend has no category filter)',
    (tester) async {
      await _pumpSheet(tester, cubit);

      expect(find.text('INTERVALO DE DATA'), findsOneWidget);
      expect(find.text('Todo o período'), findsOneWidget);
      expect(find.text('Esta semana'), findsOneWidget);
      expect(find.text('Este mês'), findsOneWidget);
      expect(find.text('TIPO DE ENTRADA'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
      expect(find.text('Áudio'), findsOneWidget);
      expect(find.text('Foto'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('CATEGORIA'), findsNothing);
      expect(find.text('Aplicar'), findsOneWidget);
      expect(find.text('Limpar'), findsOneWidget);
    },
  );

  testWidgets('with no filter selected, tapping Aplicar commits an all-null '
      'selection (no source, no date range) to the cubit', (tester) async {
    await _pumpSheet(tester, cubit);

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(cubit.activeSource, isNull);
    expect(cubit.activeDateFrom, isNull);
    expect(cubit.activeDateTo, isNull);
  });

  testWidgets(
    'selecting a source chip then Aplicar commits exactly that source, '
    'with no date bounds',
    (tester) async {
      await _pumpSheet(tester, cubit);

      await tester.tap(find.text('Áudio'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(cubit.activeSource, EntrySource.audio);
      expect(cubit.activeDateFrom, isNull);
      expect(cubit.activeDateTo, isNull);
    },
  );

  testWidgets('single choice: tapping the already-selected source chip again '
      'deselects it back to "no source filter" instead of being a no-op', (
    tester,
  ) async {
    await _pumpSheet(tester, cubit);

    await tester.tap(find.text('Manual'));
    await tester.tap(find.text('Manual'));
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(cubit.activeSource, isNull);
  });

  testWidgets(
    'single choice: selecting a second source chip replaces the first, '
    'never both at once',
    (tester) async {
      await _pumpSheet(tester, cubit);

      await tester.tap(find.text('Manual'));
      await tester.tap(find.text('Foto'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(cubit.activeSource, EntrySource.photo);
    },
  );

  testWidgets('selecting "Esta semana" then Aplicar commits a dateFrom at this '
      'week\'s own Monday local midnight and a dateTo of "now"', (
    tester,
  ) async {
    await _pumpSheet(tester, cubit);

    await tester.tap(find.text('Esta semana'));
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expectedMonday = today.subtract(Duration(days: today.weekday - 1));
    expect(cubit.activeDateFrom, expectedMonday);
    expect(cubit.activeDateTo, isNotNull);
  });

  testWidgets(
    'selecting "Este mês" then Aplicar commits a dateFrom at the 1st of '
    'this calendar month',
    (tester) async {
      await _pumpSheet(tester, cubit);

      await tester.tap(find.text('Este mês'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(cubit.activeDateFrom, DateTime(now.year, now.month));
    },
  );

  testWidgets(
    'Acceptance Criteria: selecting a source and a date range together '
    'sends a single query carrying both (AND narrowing)',
    (tester) async {
      await _pumpSheet(tester, cubit);

      await tester.tap(find.text('Áudio'));
      await tester.tap(find.text('Este mês'));
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(fakeRepository.listFilterCalls, hasLength(1));
      final call = fakeRepository.listFilterCalls.single;
      expect(call.source, EntrySource.audio);
      expect(call.dateFrom, isNotNull);
    },
  );

  testWidgets(
    'Boundaries: "Limpar" resets only the sheet\'s own pending selection '
    '— it never calls applyFilters() on the cubit and never closes the '
    'sheet',
    (tester) async {
      await _pumpSheet(tester, cubit);

      await tester.tap(find.text('Áudio'));
      await tester.tap(find.text('Esta semana'));
      await tester.tap(find.text('Limpar'));
      await tester.pumpAndSettle();

      // No list() call at all yet — "Limpar" never touched the cubit.
      expect(fakeRepository.listFilterCalls, isEmpty);
      // The sheet is still showing (never popped).
      expect(find.text('Aplicar'), findsOneWidget);

      // Confirms the pending selection itself was actually reset, not
      // just left as-is: applying now (with nothing re-selected after
      // Limpar) commits an all-null selection.
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();

      expect(cubit.activeSource, isNull);
      expect(cubit.activeDateFrom, isNull);
    },
  );

  testWidgets('reopening the sheet pre-selects whichever filters are already '
      'active on the cubit — applying immediately (no further taps) '
      'commits that exact same selection back unchanged. The "already '
      'active" state here is itself one of this sheet\'s own 3 date '
      'presets ("Este mês") — the only kind of date range the real UI '
      'could ever have produced in the first place, so pre-selection has '
      'something to actually match against', (tester) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    await cubit.applyFilters(
      source: EntrySource.chat,
      dateFrom: monthStart,
      dateTo: now,
    );
    fakeRepository.listFilterCalls.clear();

    await _pumpSheet(tester, cubit);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    expect(cubit.activeSource, EntrySource.chat);
    expect(cubit.activeDateFrom, monthStart);
    expect(cubit.activeDateTo, isNotNull);
  });

  test('code-review fix: dateRangePresetMatching checks thisMonth before '
      'thisWeek — when a month\'s 1st day is also this week\'s own Monday, '
      'the two presets\' start boundaries collide, and the fix must resolve '
      'the collision as "Este mês", not mislabel it "Esta semana"', () {
    // Finds the next month-start that's also a Monday, starting from a
    // fixed date — deterministic and calendar-fact-free (never depends
    // on knowing a specific real date's weekday up front).
    var now = DateTime(2026, 1, 1);
    while (!(now.day == 1 && now.weekday == DateTime.monday)) {
      now = now.add(const Duration(days: 1));
    }
    final monthStart = DateTime(now.year, now.month);

    expect(dateRangePresetMatching(monthStart, now), DateRangePreset.thisMonth);
  });

  test('dateRangePresetMatching still resolves a plain mid-week Monday (not '
      'also a month start) as thisWeek — the ordering fix above must not '
      'break the common, non-colliding case', () {
    // A Monday that is deliberately *not* the 1st of its month.
    var now = DateTime(2026, 1, 8);
    while (!(now.weekday == DateTime.monday && now.day != 1)) {
      now = now.add(const Duration(days: 1));
    }

    expect(
      dateRangePresetMatching(DateTime(now.year, now.month, now.day), now),
      DateRangePreset.thisWeek,
    );
  });

  testWidgets('code-review fix: renders with no overflow exception at a large '
      'Dynamic Type scale — the SingleChildScrollView guard this widget\'s '
      'own class doc cites (epic-5-context.md\'s "tight-fit area for '
      'Dynamic Type" note) actually holds', (tester) async {
    await _pumpSheet(tester, cubit, textScaler: const TextScaler.linear(3.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(EntriesFilterSheet), findsOneWidget);
    expect(find.text('Aplicar'), findsOneWidget);
  });

  testWidgets('Reduce Motion (MediaQuery.disableAnimations) skips the sheetUp '
      'entrance — the sheet is already fully in place after a single pump', (
    tester,
  ) async {
    await _openSheet(tester, cubit, disableAnimations: true);
    // Exactly one pump (not pumpAndSettle) — if the entrance animation
    // weren't skipped, the sheet would still be mid-transition here,
    // same assertion rationale `insertion_modal_test.dart`'s own
    // equivalent test uses.
    await tester.pump();

    expect(find.text('INTERVALO DE DATA'), findsOneWidget);
    expect(find.text('Aplicar'), findsOneWidget);
  });
}
