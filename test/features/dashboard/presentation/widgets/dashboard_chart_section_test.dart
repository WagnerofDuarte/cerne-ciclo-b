import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/dashboard/presentation/widgets/dashboard_chart_section.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

/// A plain (non-mocktail) fake — this suite only needs [result] to drive
/// `cubit.load()` through a scriptable `Either`.
class _FakeDashboardRepository implements DashboardRepository {
  Either<Failure, DashboardAggregate> result = right(
    const DashboardAggregate(totalCount: 0, bucketCounts: []),
  );

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async => result;
}

/// A trivial fake `PendingEntryWriteTracker` — this suite drives `load()`
/// directly, never through a `confirmedWrites` event
/// (`dashboard_cubit_test.dart`'s own job).
class _NoOpPendingEntryWriteTracker implements PendingEntryWriteTracker {
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
      const Stream.empty();

  @override
  Future<void> dispose() async {}
}

void main() {
  late _FakeDashboardRepository fakeRepository;
  late DashboardCubit cubit;

  setUp(() {
    fakeRepository = _FakeDashboardRepository();
    cubit = DashboardCubit(fakeRepository, _NoOpPendingEntryWriteTracker());
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<DashboardCubit>.value(
          value: cubit,
          child: const Scaffold(body: DashboardChartSection()),
        ),
      ),
    );
  }

  testWidgets('always shows the "Sua evolução" section title', (tester) async {
    await pumpSection(tester);

    expect(find.text('Sua evolução'), findsOneWidget);
  });

  testWidgets(
    'while loading/idle, shows a spinner, never a bar or either placeholder '
    'message (AC: "never a stale prior value")',
    (tester) async {
      await pumpSection(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(DashboardChartBar), findsNothing);
    },
  );

  testWidgets(
    'I/O matrix: "Zero entries" — count == 0 shows the placeholder icon + '
    '"Comece a registrar..." text, no bar',
    (tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(totalCount: 0, bucketCounts: []),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.byIcon(Icons.show_chart), findsOneWidget);
      expect(
        find.text('Comece a registrar para ver sua evolução aqui'),
        findsOneWidget,
      );
      expect(find.byType(DashboardChartBar), findsNothing);
      // Review finding: the empty-state icon now carries its own
      // `semanticLabel` rather than being silently unlabeled.
      expect(
        find.bySemanticsLabel('Gráfico de evolução vazio'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'I/O matrix: "One entry" — count == 1 shows exactly one full-height bar '
    'plus "Ainda é cedo..." text',
    (tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(totalCount: 1, bucketCounts: [1]),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.byType(DashboardChartBar), findsOneWidget);
      expect(
        find.text('Ainda é cedo pra ver um padrão — volte em alguns dias.'),
        findsOneWidget,
      );
      final bar = tester.widget<DashboardChartBar>(
        find.byType(DashboardChartBar),
      );
      expect(bar.heightFraction, 1.0);
    },
  );

  testWidgets(
    'I/O matrix: "Mid-range" — 1 < count <= 30 renders one bar per bucket '
    'as-is, no text',
    (tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(totalCount: 12, bucketCounts: [3, 0, 4, 5]),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.byType(DashboardChartBar), findsNWidgets(4));
      expect(
        find.text('Comece a registrar para ver sua evolução aqui'),
        findsNothing,
      );
      expect(
        find.text('Ainda é cedo pra ver um padrão — volte em alguns dias.'),
        findsNothing,
      );
      // Review finding: the bar row carries one summarizing `Semantics`
      // label instead of leaving each bare `Container` bar unlabeled.
      expect(
        find.bySemanticsLabel(
          'Gráfico de evolução: 12 registros no período, em 4 barras.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('I/O matrix: ">30 entries" — condenses to exactly 10 bars when '
      'buckets.length is already >= 10, no text', (tester) async {
    final bucketCounts = List<int>.filled(40, 1); // 40 buckets, total 40.
    fakeRepository.result = right(
      DashboardAggregate(totalCount: 40, bucketCounts: bucketCounts),
    );
    await pumpSection(tester);
    await cubit.load();
    await tester.pump();

    expect(find.byType(DashboardChartBar), findsNWidgets(10));
    expect(
      find.text('Comece a registrar para ver sua evolução aqui'),
      findsNothing,
    );
    expect(
      find.text('Ainda é cedo pra ver um padrão — volte em alguns dias.'),
      findsNothing,
    );
  });

  testWidgets(
    'I/O matrix: ">30 entries" — still condenses to exactly 10 bars even '
    'when buckets.length is well under 10 (Boundaries: "any buckets.length"), '
    'left-padded with leading zero bars rather than collapsing into one '
    'giant bar (Spec Change Log: the amended left-pad fix)',
    (tester) async {
      // 3 buckets, each with a high count, totalling > 30.
      fakeRepository.result = right(
        const DashboardAggregate(totalCount: 33, bucketCounts: [11, 11, 11]),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      final bars = tester
          .widgetList<DashboardChartBar>(find.byType(DashboardChartBar))
          .toList();
      expect(bars, hasLength(10));
      // Review finding (round 2): the frozen algorithm's own degenerate
      // reading (no left-pad) would have rendered 9 zero-height bars
      // then 1 bar absorbing the full total — a non-degenerate spread
      // instead puts the 3 real buckets' own full-height bars at the
      // *end*, with 7 leading zero-height bars ahead of them (padded
      // length 10, chunk size 1 -> identity mapping of the padded list).
      for (final bar in bars.take(7)) {
        expect(bar.heightFraction, 0.0);
      }
      for (final bar in bars.skip(7)) {
        expect(bar.heightFraction, 1.0);
      }
    },
  );

  testWidgets(
    'boundary: totalCount == 30 renders one bar per bucket, no condensation '
    '(off-by-one guard against the >30 rule)',
    (tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(
          totalCount: 30,
          bucketCounts: [5, 10, 5, 5, 5],
        ),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.byType(DashboardChartBar), findsNWidgets(5));
    },
  );

  testWidgets(
    'boundary: totalCount == 31 condenses to exactly 10 bars (one more '
    'than the uncondensed boundary immediately above)',
    (tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(
          totalCount: 31,
          bucketCounts: [6, 10, 5, 5, 5],
        ),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.byType(DashboardChartBar), findsNWidgets(10));
    },
  );

  testWidgets('defensive guard: totalCount > 0 with an empty bucketCounts '
      '(contract-inconsistent/malformed data) falls back to a single bar for '
      'the whole totalCount, never an empty bar row', (tester) async {
    fakeRepository.result = right(
      const DashboardAggregate(totalCount: 5, bucketCounts: []),
    );
    await pumpSection(tester);
    await cubit.load();
    await tester.pump();

    expect(find.byType(DashboardChartBar), findsOneWidget);
    final bar = tester.widget<DashboardChartBar>(
      find.byType(DashboardChartBar),
    );
    expect(bar.heightFraction, 1.0);
  });

  testWidgets(
    'I/O matrix: "Fetch fails" — ResourceError shows the Failure\'s message '
    'inline, no crash',
    (tester) async {
      fakeRepository.result = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      expect(find.text('Sem conexão'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a live fetch replaces whatever the section rendered before '
      '(AC: "never a stale prior value")', (tester) async {
    fakeRepository.result = right(
      const DashboardAggregate(totalCount: 0, bucketCounts: []),
    );
    await pumpSection(tester);
    await cubit.load();
    await tester.pump();
    expect(
      find.text('Comece a registrar para ver sua evolução aqui'),
      findsOneWidget,
    );

    fakeRepository.result = right(
      const DashboardAggregate(totalCount: 1, bucketCounts: [1]),
    );
    await cubit.load();
    await tester.pump();

    expect(
      find.text('Comece a registrar para ver sua evolução aqui'),
      findsNothing,
    );
    expect(find.byType(DashboardChartBar), findsOneWidget);
  });
}
