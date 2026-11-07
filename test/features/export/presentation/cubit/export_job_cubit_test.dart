import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/export/domain/entities/export_job_state.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/presentation/cubit/export_job_cubit.dart';

/// A controllable fake (same hand-written convention `ChatCubit`'s own
/// test suite uses for `ChatRepository`) rather than a mocktail stub —
/// [getStatusResults] is a queue consumed one entry per `getStatus` call,
/// repeating its last entry once exhausted, so a test only has to queue
/// the few stages it cares about.
class _FakeExportRepository implements ExportRepository {
  Either<Failure, String> createJobResult = right('job-1');
  final List<({DateTime periodStart, DateTime periodEnd})> createJobCalls =
      [];

  final List<Either<Failure, ExportJobState>> getStatusResults = [];
  final List<String> getStatusCalls = [];

  @override
  Future<Either<Failure, String>> createJob({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    createJobCalls.add((periodStart: periodStart, periodEnd: periodEnd));
    return createJobResult;
  }

  @override
  Future<Either<Failure, ExportJobState>> getStatus(String jobId) async {
    getStatusCalls.add(jobId);
    if (getStatusResults.isEmpty) {
      return right(const ExportJobState.generating());
    }
    final index = (getStatusCalls.length - 1).clamp(
      0,
      getStatusResults.length - 1,
    );
    return getStatusResults[index];
  }
}

void main() {
  late _FakeExportRepository repository;
  late ExportJobCubit cubit;

  final periodStart = DateTime.utc(2026, 1, 1);
  final periodEnd = DateTime.utc(2026, 1, 31);

  // Slightly over the cubit's own fixed 2s poll cadence (Design Notes) —
  // real-time, same convention `EntriesSearchCubit`'s own debounce tests
  // already use for its 300ms window, just scaled up to this cubit's
  // longer interval.
  const onePoll = Duration(milliseconds: 2100);

  setUp(() {
    repository = _FakeExportRepository();
    cubit = ExportJobCubit(repository);
  });

  tearDown(() async {
    await cubit.close();
  });

  test('initial state is preparing (Pendente) before start() is ever called', () {
    expect(cubit.state, isA<ExportJobPreparing>());
  });

  group('start — Create job', () {
    test(
      'happy path: stores jobId, keeps Pendente, returns true '
      '(sheet may open)',
      () async {
        final started = await cubit.start(
          periodStart: periodStart,
          periodEnd: periodEnd,
        );

        expect(started, isTrue);
        expect(repository.createJobCalls.single.periodStart, periodStart);
        expect(repository.createJobCalls.single.periodEnd, periodEnd);
        expect(cubit.state, isA<ExportJobPreparing>());
      },
    );

    test(
      'Create fails: emits error, returns false (sheet never opens), '
      'and never starts polling',
      () async {
        repository.createJobResult = left(
          const Failure.networkOffline(message: 'offline'),
        );

        final started = await cubit.start(
          periodStart: periodStart,
          periodEnd: periodEnd,
        );

        expect(started, isFalse);
        expect(cubit.state, isA<ExportJobError>());
        expect(
          (cubit.state as ExportJobError).failure,
          isA<NetworkOffline>(),
        );

        // No poll ever fires for a job that was never created.
        await Future<void>.delayed(onePoll);
        expect(repository.getStatusCalls, isEmpty);
      },
    );
  });

  group('polling (I/O matrix rows)', () {
    test(
      'Processando: the first poll tick moves Pendente -> Processando, '
      'and keeps polling (non-terminal)',
      () async {
        repository.getStatusResults.add(
          right(const ExportJobState.generating()),
        );

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);

        expect(cubit.state, isA<ExportJobGenerating>());
        expect(repository.getStatusCalls, hasLength(1));
      },
    );

    test(
      'Concluído: done with narrativeStatus done maps to '
      'ExportOutcome.narrativeReady, and polling stops (terminal)',
      () async {
        repository.getStatusResults.add(
          right(const ExportJobState.done(ExportOutcome.narrativeReady)),
        );

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);

        expect(cubit.state, isA<ExportJobDone>());
        expect(
          (cubit.state as ExportJobDone).outcome,
          ExportOutcome.narrativeReady,
        );

        final callsAtTerminal = repository.getStatusCalls.length;
        await Future<void>.delayed(onePoll);
        expect(repository.getStatusCalls.length, callsAtTerminal);
      },
    );

    test(
      'Narrativa falhou/pulada: done with a failed/skipped narrative maps '
      'to ExportOutcome.narrativeUnavailable',
      () async {
        repository.getStatusResults.add(
          right(const ExportJobState.done(ExportOutcome.narrativeUnavailable)),
        );

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);

        expect(
          (cubit.state as ExportJobDone).outcome,
          ExportOutcome.narrativeUnavailable,
        );
      },
    );

    test(
      'Erro: a job-level error is terminal/non-retryable — polling stops',
      () async {
        repository.getStatusResults.add(
          right(
            const ExportJobState.error(
              Failure.aiGenerationTimeout(message: 'boom'),
            ),
          ),
        );

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);

        expect(cubit.state, isA<ExportJobError>());

        final callsAtTerminal = repository.getStatusCalls.length;
        await Future<void>.delayed(onePoll);
        expect(repository.getStatusCalls.length, callsAtTerminal);
      },
    );

    test(
      'Período vazio: emptyPeriod is terminal — polling stops, maps to '
      'the adjust-period copy rather than a generic error',
      () async {
        repository.getStatusResults.add(
          right(const ExportJobState.emptyPeriod()),
        );

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);

        expect(cubit.state, isA<ExportJobEmptyPeriod>());

        final callsAtTerminal = repository.getStatusCalls.length;
        await Future<void>.delayed(onePoll);
        expect(repository.getStatusCalls.length, callsAtTerminal);
      },
    );

    test(
      'a transient poll failure (Left) is swallowed, never surfaced — '
      'the next tick simply tries again',
      () async {
        repository.getStatusResults
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(right(const ExportJobState.generating()));

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll);
        // First tick failed transiently — state is unchanged (still
        // Pendente), not flipped to a false terminal error.
        expect(cubit.state, isA<ExportJobPreparing>());

        await Future<void>.delayed(onePoll);
        expect(cubit.state, isA<ExportJobGenerating>());
      },
    );

    test(
      'a persistent poll failure gives up after 5 consecutive Lefts — '
      'emits the generic Erro state and stops polling, rather than '
      'retrying forever',
      () async {
        for (var i = 0; i < 5; i++) {
          repository.getStatusResults.add(
            left(const Failure.networkTimeout(message: 'timeout')),
          );
        }

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        // 5 consecutive failing polls.
        await Future<void>.delayed(onePoll * 5);

        expect(cubit.state, isA<ExportJobError>());
        expect(
          (cubit.state as ExportJobError).failure,
          isA<NetworkTimeout>(),
        );

        final callsAtGiveUp = repository.getStatusCalls.length;
        await Future<void>.delayed(onePoll);
        expect(repository.getStatusCalls.length, callsAtGiveUp);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'a success tick resets the consecutive-failure counter — 4 '
      'failures then a success never trips the give-up cap',
      () async {
        repository.getStatusResults
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(right(const ExportJobState.generating()));

        await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
        await Future<void>.delayed(onePoll * 5);

        expect(cubit.state, isA<ExportJobGenerating>());
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });

  test(
    'close() cancels the poll Timer — no getStatus call ever fires after '
    'close, even past what would have been the next tick',
    () async {
      await cubit.start(periodStart: periodStart, periodEnd: periodEnd);
      await cubit.close();

      await Future<void>.delayed(onePoll);
      expect(repository.getStatusCalls, isEmpty);
    },
  );
}
