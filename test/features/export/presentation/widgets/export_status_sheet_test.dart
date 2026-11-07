import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/export/domain/entities/export_download_format.dart';
import 'package:cerne/features/export/domain/entities/export_job_state.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/domain/services/download_opener.dart';
import 'package:cerne/features/export/presentation/cubit/export_job_cubit.dart';
import 'package:cerne/features/export/presentation/widgets/export_status_sheet.dart';

/// Review finding (verification-gap layer) — `ExportStatusSheet`'s
/// per-state content mapping (`_contentFor`/`_doneContent`) had no test
/// anywhere. Same hand-written fake convention `export_job_cubit_test.dart`
/// already uses for `ExportRepository`: [getStatusResults] is consumed one
/// entry per `getStatus` call, driving [ExportJobCubit] through whichever
/// state a test wants to assert the sheet's rendering for.
class _FakeExportRepository implements ExportRepository {
  Either<Failure, String> createJobResult = right('job-1');
  final List<Either<Failure, ExportJobState>> getStatusResults = [];

  /// spec-7-2 — queued per-call, same consume-one-entry convention as
  /// [getStatusResults]; defaults to a success URL when nothing is queued.
  final List<Either<Failure, String>> getDownloadUrlResults = [];
  final List<ExportDownloadFormat> getDownloadUrlCalls = [];

  @override
  Future<Either<Failure, String>> createJob({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async => createJobResult;

  @override
  Future<Either<Failure, ExportJobState>> getStatus(String jobId) async =>
      getStatusResults.isEmpty
      ? right(const ExportJobState.generating())
      : getStatusResults.removeAt(0);

  @override
  Future<Either<Failure, String>> getDownloadUrl(
    String jobId, {
    required ExportDownloadFormat format,
  }) async {
    getDownloadUrlCalls.add(format);
    if (getDownloadUrlResults.isEmpty) {
      return right('https://storage.example.com/signed');
    }
    return getDownloadUrlResults.removeAt(0);
  }
}

/// spec-7-2 — [DownloadOpener]'s own hand-written fake for this suite,
/// same convention as [_FakeExportRepository].
class _FakeDownloadOpener implements DownloadOpener {
  bool openResult = true;
  final List<String> openCalls = [];

  @override
  Future<bool> open(String url) async {
    openCalls.add(url);
    return openResult;
  }
}

/// Pumps [ExportStatusSheet] directly (bypassing `.show()`'s own
/// `showModalBottomSheet` ceremony) — same convention
/// `entries_filter_sheet_test.dart`'s own `_pumpSheet` helper uses; the
/// sheet's own rendering depends only on [cubit]'s state, never on being
/// inside a real modal route.
Future<void> _pumpSheet(WidgetTester tester, ExportJobCubit cubit) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ExportStatusSheet(cubit: cubit)),
    ),
  );
}

/// [cubit] already has its job created (`start()`) and one `getStatus`
/// result queued — this advances the cubit's own 2s `Timer.periodic` past
/// its threshold (same `tester.pump(duration)` convention
/// `meus_registros_screen_test.dart` already uses for its 300ms skeleton
/// timers) so the queued result is actually emitted before assertions run.
Future<void> _advancePastOnePoll(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2, milliseconds: 100));

void main() {
  late _FakeExportRepository repository;
  late _FakeDownloadOpener downloadOpener;
  late ExportJobCubit cubit;

  setUp(() {
    repository = _FakeExportRepository();
    downloadOpener = _FakeDownloadOpener();
    cubit = ExportJobCubit(repository, downloadOpener);
  });

  tearDown(() async {
    // Review finding (self — debugging a hang): calling `BlocBase.close()`
    // a *second* time on an already-closed cubit never resolves its
    // returned `Future` inside a `testWidgets` fake-async zone (confirmed
    // via isolated repro — a single close(), even with a mounted
    // `BlocBuilder` and a live poll `Timer`, always resolves instantly;
    // only the second call on the same instance hangs). Tests below that
    // already close their own cubit (the live-Timer "Processando" case,
    // and `.show()`'s own `finally` block when "Fechar" is tapped) would
    // otherwise be double-closed by this blanket teardown.
    if (!cubit.isClosed) {
      await cubit.close();
    }
  });

  testWidgets('Pendente: spinner + "Preparando exportação..." + Fechar', (
    tester,
  ) async {
    await _pumpSheet(tester, cubit);

    expect(find.text('Preparando exportação...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
  });

  testWidgets('Processando: progress bar + "Gerando resumo com IA..."', (
    tester,
  ) async {
    repository.getStatusResults.add(right(const ExportJobState.generating()));
    await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );
    await _pumpSheet(tester, cubit);
    await _advancePastOnePoll(tester);

    expect(find.text('Gerando resumo com IA...'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Non-terminal state: the cubit's own poll Timer is still live at
    // this point (unlike every other state above, each already
    // terminal, which cancels it on arrival) — flutter_test's own
    // "no pending timers" invariant is checked at the end of the test
    // body itself, before the outer `tearDown` block ever runs, so it
    // must be closed here. A single `close()` call is safe even with a
    // mounted `BlocBuilder` and a live `Timer`; the outer `tearDown`'s
    // own `isClosed` guard (above) stops it from being closed twice.
    await cubit.close();
  });

  testWidgets(
    'Concluído (narrativeReady): "Resumo pronto" + both PDF/raw buttons, '
    'enabled and each wired through to its own download (spec-7-2)',
    (tester) async {
      repository.getStatusResults.add(
        right(const ExportJobState.done(ExportOutcome.narrativeReady)),
      );
      await cubit.start(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );
      await _pumpSheet(tester, cubit);
      await _advancePastOnePoll(tester);

      expect(find.text('Resumo pronto'), findsOneWidget);
      expect(find.text('Baixar PDF'), findsOneWidget);
      expect(find.text('Baixar dados brutos'), findsOneWidget);

      final pdfButton = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Baixar PDF'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(pdfButton.onPressed, isNotNull);

      await tester.tap(find.text('Baixar PDF'));
      await tester.pumpAndSettle();
      expect(repository.getDownloadUrlCalls, [ExportDownloadFormat.pdf]);
      expect(downloadOpener.openCalls, ['https://storage.example.com/signed']);

      await tester.tap(find.text('Baixar dados brutos'));
      await tester.pumpAndSettle();
      expect(repository.getDownloadUrlCalls, [
        ExportDownloadFormat.pdf,
        ExportDownloadFormat.raw,
      ]);
    },
  );

  testWidgets(
    'Dados prontos (data_ready): progress bar/text stay visible, "Baixar '
    'dados brutos" already enabled underneath — no PDF button yet '
    '(spec-7-2 hybrid state)',
    (tester) async {
      repository.getStatusResults.add(right(const ExportJobState.dataReady()));
      await cubit.start(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );
      await _pumpSheet(tester, cubit);
      await _advancePastOnePoll(tester);

      expect(find.text('Gerando resumo com IA...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Baixar PDF'), findsNothing);
      expect(find.text('Baixar dados brutos'), findsOneWidget);

      final rawButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Baixar dados brutos'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(rawButton.onPressed, isNotNull);

      await tester.tap(find.text('Baixar dados brutos'));
      await tester.pump();
      expect(repository.getDownloadUrlCalls, [ExportDownloadFormat.raw]);

      // Non-terminal state: the cubit's own poll Timer is still live.
      await cubit.close();
    },
  );

  testWidgets(
    'a download failure shows an inline SnackBar and never mutates the '
    "sheet's own job-status content (Boundaries)",
    (tester) async {
      repository.getStatusResults.add(
        right(const ExportJobState.done(ExportOutcome.narrativeReady)),
      );
      repository.getDownloadUrlResults.add(
        left(const Failure.notFound(message: 'Arquivo não encontrado.')),
      );
      await cubit.start(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );
      await _pumpSheet(tester, cubit);
      await _advancePastOnePoll(tester);

      await tester.tap(find.text('Baixar PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Arquivo não encontrado.'), findsOneWidget);
      // The sheet's own job-status content is untouched — still "Resumo
      // pronto", not replaced by any error copy.
      expect(find.text('Resumo pronto'), findsOneWidget);
      expect(cubit.state, isA<ExportJobDone>());
    },
  );

  testWidgets(
    'Narrativa falhou/pulada: only the raw-data button, copy scoped to '
    'the narrative, never the whole job — and that one button is enabled '
    'and wired through to a real download (I/O matrix: "Narrative failed/'
    'skipped ... only raw button, now enabled", mirrors the narrativeReady '
    'test above)',
    (tester) async {
      repository.getStatusResults.add(
        right(const ExportJobState.done(ExportOutcome.narrativeUnavailable)),
      );
      await cubit.start(
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 31),
      );
      await _pumpSheet(tester, cubit);
      await _advancePastOnePoll(tester);

      expect(find.text('Baixar PDF'), findsNothing);
      expect(find.text('Baixar dados brutos'), findsOneWidget);
      expect(find.textContaining('a narrativa falhou'), findsOneWidget);

      final rawButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Baixar dados brutos'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(rawButton.onPressed, isNotNull);

      await tester.tap(find.text('Baixar dados brutos'));
      await tester.pumpAndSettle();
      expect(repository.getDownloadUrlCalls, [ExportDownloadFormat.raw]);
      expect(downloadOpener.openCalls, ['https://storage.example.com/signed']);
    },
  );

  testWidgets('Erro: generic error copy, no download button offered', (
    tester,
  ) async {
    repository.getStatusResults.add(
      right(
        const ExportJobState.error(
          Failure.aiGenerationTimeout(message: 'boom'),
        ),
      ),
    );
    await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );
    await _pumpSheet(tester, cubit);
    await _advancePastOnePoll(tester);

    expect(find.text('Não foi possível gerar a exportação.'), findsOneWidget);
    expect(find.text('Baixar PDF'), findsNothing);
    expect(find.text('Baixar dados brutos'), findsNothing);
  });

  testWidgets('Período vazio: adjust-period copy, no download button offered', (
    tester,
  ) async {
    repository.getStatusResults.add(right(const ExportJobState.emptyPeriod()));
    await cubit.start(
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 31),
    );
    await _pumpSheet(tester, cubit);
    await _advancePastOnePoll(tester);

    expect(find.text('Nenhum registro nesse período.'), findsOneWidget);
    expect(
      find.text('Ajuste o filtro de período e tente de novo.'),
      findsOneWidget,
    );
    expect(find.text('Baixar dados brutos'), findsNothing);
  });

  testWidgets(
    '.show() opens the sheet (radiusLg/elevation2 shell) and "Fechar" '
    'closes it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ExportStatusSheet.show(context, cubit: cubit),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      // Bounded pumps, not `pumpAndSettle()` — the Pendente state's own
      // `CircularProgressIndicator` animates indefinitely, so waiting for
      // every animation to settle would never return. One frame plus the
      // sheet's own entrance duration (`durationSheetUp`, 200ms) is enough
      // for the sheet itself to finish rising into place.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Preparando exportação...'), findsOneWidget);

      await tester.tap(find.text('Fechar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Preparando exportação...'), findsNothing);
    },
  );
}
