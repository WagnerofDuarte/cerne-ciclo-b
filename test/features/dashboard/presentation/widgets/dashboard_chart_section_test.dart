import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/dashboard/domain/entities/dashboard_aggregate.dart';
import 'package:cerne/features/dashboard/domain/repositories/dashboard_repository.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:cerne/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
import 'package:cerne/features/dashboard/presentation/widgets/dashboard_chart_section.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/pending_entry_write.dart';
import 'package:cerne/features/entries/domain/services/pending_entry_write_tracker.dart';

/// A plain (non-mocktail) fake — this suite only needs [result]/
/// [narrativeResult] to drive `cubit.load()`/`narrativeCubit.load()`
/// through a scriptable `Either` each (spec-8-2: the two fetches are
/// independent, never coupled into one state object).
class _FakeDashboardRepository implements DashboardRepository {
  Either<Failure, DashboardAggregate> result = right(
    const DashboardAggregate(totalCount: 0, bucketCounts: []),
  );

  Either<Failure, String> narrativeResult = right('narrative text');

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async => result;

  @override
  Future<Either<Failure, String>> getNarrative({
    required String period,
  }) async => narrativeResult;
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
  late DashboardNarrativeCubit narrativeCubit;

  setUp(() {
    fakeRepository = _FakeDashboardRepository();
    cubit = DashboardCubit(fakeRepository, _NoOpPendingEntryWriteTracker());
    narrativeCubit = DashboardNarrativeCubit(
      fakeRepository,
      _NoOpPendingEntryWriteTracker(),
    );
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    if (!narrativeCubit.isClosed) {
      await narrativeCubit.close();
    }
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<DashboardCubit>.value(value: cubit),
            BlocProvider<DashboardNarrativeCubit>.value(value: narrativeCubit),
          ],
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
    // Review finding: the two existing ">30 entries" tests above use
    // padded lengths (40 and 10) that are exact multiples of 10, so
    // `chunkSize * 9 == padded.length` for both — the last bar's
    // remainder-absorbing `_sum(padded, index, padded.length)` produces
    // the identical result a naive, regressed `_sum(padded, index, index
    // + chunkSize)` (no remainder absorption) would. Neither test can
    // distinguish correct remainder absorption from that regression. A
    // length not divisible by 10 (23, already >= 10 so no padding is
    // involved either) is the only input shape that can.
    'I/O matrix: ">30 entries" — the final bar absorbs the real remainder '
    'left over by floor-division chunking, not just another fixed-width '
    'chunk (round-2 fix: "remainder in the last chunk")',
    (tester) async {
      // 23 buckets of count 2 each (total 46, > 30). chunkSize = 23 ~/ 10
      // == 2: the first 9 bars each sum 2 buckets (count 4), the 10th
      // absorbs the 5-bucket remainder (count 10) — not another
      // 2-bucket chunk (which would be count 4 and silently drop the
      // last 3 buckets' counts from the chart).
      final bucketCounts = List<int>.filled(23, 2);
      fakeRepository.result = right(
        DashboardAggregate(totalCount: 46, bucketCounts: bucketCounts),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      final bars = tester
          .widgetList<DashboardChartBar>(find.byType(DashboardChartBar))
          .toList();
      expect(bars, hasLength(10));
      for (final bar in bars.take(9)) {
        expect(bar.heightFraction, closeTo(0.4, 1e-9)); // 4 / 10
      }
      expect(bars.last.heightFraction, 1.0); // 10 / 10
    },
  );

  testWidgets(
    // Review finding: only buckets.length >= 10 (40) and < 10 (3,
    // padded) were tested — the exact length-10 boundary where `_pad`
    // transitions from padding to a no-op pass-through was never pinned.
    'I/O matrix: ">30 entries" — bucketCounts.length == 10 exactly is '
    'passed straight through unpadded, one bar per original bucket',
    (tester) async {
      final bucketCounts = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      fakeRepository.result = right(
        DashboardAggregate(totalCount: 55, bucketCounts: bucketCounts),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();

      final bars = tester
          .widgetList<DashboardChartBar>(find.byType(DashboardChartBar))
          .toList();
      expect(bars, hasLength(10));
      for (var i = 0; i < bars.length; i++) {
        expect(bars[i].heightFraction, closeTo(bucketCounts[i] / 10, 1e-9));
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

  group('spec-8-2: the AI narrative paragraph, >30-only', () {
    Future<void> pumpOver30(WidgetTester tester) async {
      fakeRepository.result = right(
        const DashboardAggregate(totalCount: 40, bucketCounts: [40]),
      );
      await pumpSection(tester);
      await cubit.load();
      await tester.pump();
    }

    testWidgets(
      'I/O matrix: ">30 entries, narrative resolves" — the narrative text '
      'renders below the chart',
      (tester) async {
        fakeRepository.narrativeResult = right('Seu balanço do período.');
        await pumpOver30(tester);
        await narrativeCubit.load();
        await tester.pump();

        expect(find.text('Seu balanço do período.'), findsOneWidget);
        expect(find.byType(DashboardChartBar), findsNWidgets(10));
      },
    );

    testWidgets(
      'I/O matrix: ">30 entries, narrative fails" — the chart still renders '
      'normally, plus a distinct "narrativa indisponível" message with a '
      'working retry, never the 0/1-entry wording',
      (tester) async {
        fakeRepository.narrativeResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );
        await pumpOver30(tester);
        await narrativeCubit.load();
        await tester.pump();

        expect(find.byType(DashboardChartBar), findsNWidgets(10));
        expect(
          find.text('Não foi possível gerar o balanço agora'),
          findsOneWidget,
        );
        expect(find.text('tentar novamente'), findsOneWidget);
        expect(
          find.text('Comece a registrar para ver sua evolução aqui'),
          findsNothing,
        );
        expect(
          find.text('Ainda é cedo pra ver um padrão — volte em alguns dias.'),
          findsNothing,
        );

        // Tapping "tentar novamente" re-calls narrativeCubit.load(), no
        // crash (Boundaries: "re-calls narrativeCubit.load()").
        fakeRepository.narrativeResult = right('Recuperado com sucesso.');
        await tester.tap(find.text('tentar novamente'));
        await tester.pump();

        expect(find.text('Recuperado com sucesso.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'I/O matrix: "Narrative fetch pending" — Idle/Loading renders no '
      'narrative section, so the chart never waits on it',
      (tester) async {
        await pumpOver30(tester);
        // Deliberately never calls narrativeCubit.load() — stays Idle.

        expect(find.byType(DashboardChartBar), findsNWidgets(10));
        expect(
          find.text('Não foi possível gerar o balanço agora'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'I/O matrix: "0 or 1 entries" — the narrative fetch result is never '
      'rendered, regardless of its own outcome, and the existing hardcoded '
      'messages stay unchanged',
      (tester) async {
        fakeRepository.result = right(
          const DashboardAggregate(totalCount: 0, bucketCounts: []),
        );
        fakeRepository.narrativeResult = right('Should never show.');
        await pumpSection(tester);
        await cubit.load();
        await narrativeCubit.load();
        await tester.pump();

        expect(
          find.text('Comece a registrar para ver sua evolução aqui'),
          findsOneWidget,
        );
        expect(find.text('Should never show.'), findsNothing);
        expect(
          find.text('Não foi possível gerar o balanço agora'),
          findsNothing,
        );

        fakeRepository.result = right(
          const DashboardAggregate(totalCount: 1, bucketCounts: [1]),
        );
        fakeRepository.narrativeResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );
        await cubit.load();
        await narrativeCubit.load();
        await tester.pump();

        expect(
          find.text('Ainda é cedo pra ver um padrão — volte em alguns dias.'),
          findsOneWidget,
        );
        expect(
          find.text('Não foi possível gerar o balanço agora'),
          findsNothing,
        );
        expect(find.text('tentar novamente'), findsNothing);
      },
    );
  });
}
