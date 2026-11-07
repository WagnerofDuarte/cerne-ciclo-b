import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/export/domain/entities/export_download_format.dart';
import 'package:cerne/features/export/domain/entities/export_job_state.dart';
import 'package:cerne/features/export/domain/repositories/export_repository.dart';
import 'package:cerne/features/export/domain/services/download_opener.dart';
import 'package:cerne/features/export/presentation/cubit/export_job_cubit.dart';

/// A controllable fake (same hand-written convention `ChatCubit`'s own
/// test suite uses for `ChatRepository`) rather than a mocktail stub —
/// [getStatusResults] is a queue consumed one entry per `getStatus` call,
/// repeating its last entry once exhausted, so a test only has to queue
/// the few stages it cares about.
class _FakeExportRepository implements ExportRepository {
  Either<Failure, String> createJobResult = right('job-1');
  final List<({DateTime periodStart, DateTime periodEnd})> createJobCalls = [];

  final List<Either<Failure, ExportJobState>> getStatusResults = [];
  final List<String> getStatusCalls = [];

  /// Review finding (verification-gap layer) — when set, the next
  /// `getStatus` call doesn't resolve until this completer completes,
  /// letting a test hold one poll tick's own repository call open across
  /// a second (and third) `Timer.periodic` tick firing underneath it —
  /// the exact overlap `ExportJobCubit._pollInFlight` exists to prevent.
  /// Consumed once, then cleared, so only the call it was set for waits.
  Completer<void>? delayNextGetStatus;

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
    // Recorded before the gate below so a test can observe "the call was
    // made and is still in flight" — not just "the call has resolved".
    getStatusCalls.add(jobId);
    final gate = delayNextGetStatus;
    delayNextGetStatus = null;
    if (gate != null) {
      await gate.future;
    }
    if (getStatusResults.isEmpty) {
      return right(const ExportJobState.generating());
    }
    final index = (getStatusCalls.length - 1).clamp(
      0,
      getStatusResults.length - 1,
    );
    return getStatusResults[index];
  }

  /// spec-7-2 — queued per-call, same consume-one-entry convention as
  /// [getStatusResults]; defaults to a success URL when nothing is queued,
  /// so a test that only cares about the opener side doesn't also have to
  /// stub this.
  final List<Either<Failure, String>> getDownloadUrlResults = [];
  final List<({String jobId, ExportDownloadFormat format})>
  getDownloadUrlCalls = [];

  /// Review finding (code review, patch item 3) — same gate convention as
  /// [delayNextGetStatus], for [ExportJobCubit._downloadInFlight]'s own
  /// overlap test.
  Completer<void>? delayNextGetDownloadUrl;

  @override
  Future<Either<Failure, String>> getDownloadUrl(
    String jobId, {
    required ExportDownloadFormat format,
  }) async {
    getDownloadUrlCalls.add((jobId: jobId, format: format));
    final gate = delayNextGetDownloadUrl;
    delayNextGetDownloadUrl = null;
    if (gate != null) {
      await gate.future;
    }
    if (getDownloadUrlResults.isEmpty) {
      return right('https://storage.example.com/signed');
    }
    return getDownloadUrlResults.removeAt(0);
  }
}

/// spec-7-2 — [DownloadOpener]'s own hand-written fake, same convention as
/// [_FakeExportRepository]: [openResult] configures the next (and every
/// subsequent, until changed) call's return value, [openCalls] records
/// every URL actually passed through. [throwOnOpen], when set, makes
/// [open] throw instead of returning — covering [ExportJobCubit._download]'s
/// own try/catch around this call (review finding, code review patch
/// item 5): the real `UrlLauncherDownloadOpener` already catches
/// internally and never throws, but nothing on the [DownloadOpener]
/// contract itself enforces that for a future implementation.
class _FakeDownloadOpener implements DownloadOpener {
  bool openResult = true;
  Object? throwOnOpen;
  final List<String> openCalls = [];

  @override
  Future<bool> open(String url) async {
    openCalls.add(url);
    final error = throwOnOpen;
    if (error != null) {
      throw error;
    }
    return openResult;
  }
}

void main() {
  late _FakeExportRepository repository;
  late _FakeDownloadOpener downloadOpener;
  late ExportJobCubit cubit;

  final periodStart = DateTime.utc(2026, 1, 1);
  final periodEnd = DateTime.utc(2026, 1, 31);

  // Slightly over the cubit's own fixed 2s poll cadence (Design Notes).
  // Review finding (blind-hunter layer) — every test below runs inside
  // `fakeAsync` (`async.elapse(...)`), so this is virtual time, not real
  // wall-clock delay: the whole suite no longer takes ~48s to run.
  const onePoll = Duration(milliseconds: 2100);

  setUp(() {
    repository = _FakeExportRepository();
    downloadOpener = _FakeDownloadOpener();
    cubit = ExportJobCubit(repository, downloadOpener);
  });

  tearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
  });

  test(
    'initial state is preparing (Pendente) before start() is ever called',
    () {
      expect(cubit.state, isA<ExportJobPreparing>());
    },
  );

  group('start — Create job', () {
    test('happy path: stores jobId, keeps Pendente, returns true '
        '(sheet may open)', () {
      fakeAsync((async) {
        bool? started;
        unawaited(
          cubit
              .start(periodStart: periodStart, periodEnd: periodEnd)
              .then((value) => started = value),
        );
        async.flushMicrotasks();

        expect(started, isTrue);
        expect(repository.createJobCalls.single.periodStart, periodStart);
        expect(repository.createJobCalls.single.periodEnd, periodEnd);
        expect(cubit.state, isA<ExportJobPreparing>());
      });
    });

    test('Create fails: emits error, returns false (sheet never opens), '
        'and never starts polling', () {
      fakeAsync((async) {
        repository.createJobResult = left(
          const Failure.networkOffline(message: 'offline'),
        );

        bool? started;
        unawaited(
          cubit
              .start(periodStart: periodStart, periodEnd: periodEnd)
              .then((value) => started = value),
        );
        async.flushMicrotasks();

        expect(started, isFalse);
        expect(cubit.state, isA<ExportJobError>());
        expect((cubit.state as ExportJobError).failure, isA<NetworkOffline>());

        // No poll ever fires for a job that was never created.
        async.elapse(onePoll);
        expect(repository.getStatusCalls, isEmpty);
      });
    });
  });

  group('polling (I/O matrix rows)', () {
    test('Processando: the first poll tick moves Pendente -> Processando, '
        'and keeps polling (non-terminal)', () {
      fakeAsync((async) {
        repository.getStatusResults.add(
          right(const ExportJobState.generating()),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);

        expect(cubit.state, isA<ExportJobGenerating>());
        expect(repository.getStatusCalls, hasLength(1));
      });
    });

    test('Dados prontos: data_ready maps to ExportJobDataReady and keeps '
        'polling (non-terminal — the narrative may still be processing '
        'underneath it, spec-7-2)', () {
      fakeAsync((async) {
        repository.getStatusResults.add(
          right(const ExportJobState.dataReady()),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);

        expect(cubit.state, isA<ExportJobDataReady>());

        final callsAtDataReady = repository.getStatusCalls.length;
        async.elapse(onePoll);
        expect(repository.getStatusCalls.length, greaterThan(callsAtDataReady));
      });
    });

    test('Concluído: done with narrativeStatus done maps to '
        'ExportOutcome.narrativeReady, and polling stops (terminal)', () {
      fakeAsync((async) {
        repository.getStatusResults.add(
          right(const ExportJobState.done(ExportOutcome.narrativeReady)),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);

        expect(cubit.state, isA<ExportJobDone>());
        expect(
          (cubit.state as ExportJobDone).outcome,
          ExportOutcome.narrativeReady,
        );

        final callsAtTerminal = repository.getStatusCalls.length;
        async.elapse(onePoll);
        expect(repository.getStatusCalls.length, callsAtTerminal);
      });
    });

    test('Narrativa falhou/pulada: done with a failed/skipped narrative maps '
        'to ExportOutcome.narrativeUnavailable', () {
      fakeAsync((async) {
        repository.getStatusResults.add(
          right(const ExportJobState.done(ExportOutcome.narrativeUnavailable)),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);

        expect(
          (cubit.state as ExportJobDone).outcome,
          ExportOutcome.narrativeUnavailable,
        );
      });
    });

    test(
      'Erro: a job-level error is terminal/non-retryable — polling stops',
      () {
        fakeAsync((async) {
          repository.getStatusResults.add(
            right(
              const ExportJobState.error(
                Failure.aiGenerationTimeout(message: 'boom'),
              ),
            ),
          );

          unawaited(
            cubit.start(periodStart: periodStart, periodEnd: periodEnd),
          );
          async.flushMicrotasks();
          async.elapse(onePoll);

          expect(cubit.state, isA<ExportJobError>());

          final callsAtTerminal = repository.getStatusCalls.length;
          async.elapse(onePoll);
          expect(repository.getStatusCalls.length, callsAtTerminal);
        });
      },
    );

    test('Período vazio: emptyPeriod is terminal — polling stops, maps to '
        'the adjust-period copy rather than a generic error', () {
      fakeAsync((async) {
        repository.getStatusResults.add(
          right(const ExportJobState.emptyPeriod()),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);

        expect(cubit.state, isA<ExportJobEmptyPeriod>());

        final callsAtTerminal = repository.getStatusCalls.length;
        async.elapse(onePoll);
        expect(repository.getStatusCalls.length, callsAtTerminal);
      });
    });

    test('a transient poll failure (Left) is swallowed, never surfaced — '
        'the next tick simply tries again', () {
      fakeAsync((async) {
        repository.getStatusResults
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(right(const ExportJobState.generating()));

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll);
        // First tick failed transiently — state is unchanged (still
        // Pendente), not flipped to a false terminal error.
        expect(cubit.state, isA<ExportJobPreparing>());

        async.elapse(onePoll);
        expect(cubit.state, isA<ExportJobGenerating>());
      });
    });

    test('a persistent poll failure gives up after 5 consecutive Lefts — '
        'emits the generic Erro state and stops polling, rather than '
        'retrying forever', () {
      fakeAsync((async) {
        for (var i = 0; i < 5; i++) {
          repository.getStatusResults.add(
            left(const Failure.networkTimeout(message: 'timeout')),
          );
        }

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        // 5 consecutive failing polls.
        async.elapse(onePoll * 5);

        expect(cubit.state, isA<ExportJobError>());
        expect((cubit.state as ExportJobError).failure, isA<NetworkTimeout>());

        final callsAtGiveUp = repository.getStatusCalls.length;
        async.elapse(onePoll);
        expect(repository.getStatusCalls.length, callsAtGiveUp);
      });
    });

    test('a success tick resets the consecutive-failure counter — 4 '
        'failures then a success never trips the give-up cap', () {
      fakeAsync((async) {
        repository.getStatusResults
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(left(const Failure.networkTimeout(message: 'timeout')))
          ..add(right(const ExportJobState.generating()));

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        async.elapse(onePoll * 5);

        expect(cubit.state, isA<ExportJobGenerating>());
      });
    });

    test('a slow getStatus call blocks every timer tick that fires while it '
        'is still in flight — _pollInFlight stops an overlapping second '
        'call, and the stale response cannot un-terminate a later state '
        '(review finding: verification-gap layer — this guard previously '
        'had no test that ever produced an actual overlap, since every '
        'fake getStatus call resolved instantly)', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        repository.delayNextGetStatus = gate;
        repository.getStatusResults.add(
          right(const ExportJobState.done(ExportOutcome.narrativeReady)),
        );

        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        // Two more ticks fire while the first getStatus call is still
        // gated open. Without `_pollInFlight`, each would start its own
        // overlapping `getStatus` call; with it, only the first call
        // ever reaches the repository.
        async.elapse(onePoll * 2);
        expect(repository.getStatusCalls, hasLength(1));
        expect(cubit.state, isA<ExportJobPreparing>());

        // Release the first (and only) call — it resolves to a
        // terminal state.
        gate.complete();
        async.flushMicrotasks();
        expect(cubit.state, isA<ExportJobDone>());

        // A further tick must never fire again now that the job is
        // terminal, and no stale/overlapping call ever got the chance
        // to "un-terminate" it back to a non-terminal state.
        async.elapse(onePoll);
        expect(repository.getStatusCalls, hasLength(1));
        expect(cubit.state, isA<ExportJobDone>());
      });
    });
  });

  group('downloadPdf/downloadRawData (spec-7-2)', () {
    test('downloadPdf resolves the signed URL for the stored jobId with '
        'format=pdf and hands it to the DownloadOpener; resolves to null '
        '(no failure) on success', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        Failure? result;
        unawaited(cubit.downloadPdf().then((value) => result = value));
        async.flushMicrotasks();

        expect(repository.getDownloadUrlCalls.single.jobId, 'job-1');
        expect(
          repository.getDownloadUrlCalls.single.format,
          ExportDownloadFormat.pdf,
        );
        expect(
          downloadOpener.openCalls.single,
          'https://storage.example.com/signed',
        );
        expect(result, isNull);
      });
    });

    test('downloadRawData calls through with format=raw', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        unawaited(cubit.downloadRawData());
        async.flushMicrotasks();

        expect(
          repository.getDownloadUrlCalls.single.format,
          ExportDownloadFormat.raw,
        );
      });
    });

    test('a repository failure (Left) is returned directly, never emitted '
        'as a new ExportJobState', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();
        final stateBefore = cubit.state;

        repository.getDownloadUrlResults.add(
          left(const Failure.notFound(message: 'gone')),
        );
        Failure? result;
        unawaited(cubit.downloadPdf().then((value) => result = value));
        async.flushMicrotasks();

        expect(result, isA<NotFound>());
        expect(cubit.state, stateBefore);
        expect(downloadOpener.openCalls, isEmpty);
      });
    });

    test('the DownloadOpener reporting it could not open the URL (false) '
        'also returns a Failure, even though the repository call itself '
        'succeeded', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        downloadOpener.openResult = false;
        Failure? result;
        unawaited(cubit.downloadRawData().then((value) => result = value));
        async.flushMicrotasks();

        expect(result, isA<MalformedResponse>());
      });
    });

    test('review finding (patch item 5): the DownloadOpener throwing (instead '
        'of returning false) is caught — resolves to a Failure rather than '
        'the exception escaping _download uncaught', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        downloadOpener.throwOnOpen = Exception('platform channel died');
        Failure? result;
        unawaited(cubit.downloadPdf().then((value) => result = value));
        async.flushMicrotasks();

        expect(result, isA<MalformedResponse>());
      });
    });

    test('review finding (patch item 4): calling a download method before '
        'start() has ever stored a jobId resolves to a Failure rather than '
        'silently no-op-ing (indistinguishable from success)', () {
      fakeAsync((async) {
        Failure? result;
        unawaited(cubit.downloadPdf().then((value) => result = value));
        async.flushMicrotasks();

        expect(result, isA<MalformedResponse>());
        expect(repository.getDownloadUrlCalls, isEmpty);
        expect(downloadOpener.openCalls, isEmpty);
      });
    });

    test('review finding (patch item 3): a second download call arriving '
        'while the first is still in flight is a no-op — _downloadInFlight '
        'stops it from ever reaching the repository/opener, mirroring '
        '_pollInFlight\'s own overlap guard', () {
      fakeAsync((async) {
        unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
        async.flushMicrotasks();

        final gate = Completer<void>();
        repository.delayNextGetDownloadUrl = gate;

        Failure? firstResult;
        Failure? secondResult;
        var secondCompleted = false;
        unawaited(cubit.downloadPdf().then((value) => firstResult = value));
        async.flushMicrotasks();
        // The first call is now in flight, gated open on the repository
        // call. A second call arriving now must never reach the
        // repository or the opener at all.
        unawaited(
          cubit.downloadRawData().then((value) {
            secondResult = value;
            secondCompleted = true;
          }),
        );
        async.flushMicrotasks();

        expect(repository.getDownloadUrlCalls, hasLength(1));
        expect(secondCompleted, isTrue);
        expect(secondResult, isNull);

        // Releasing the first call lets it resolve normally.
        gate.complete();
        async.flushMicrotasks();
        expect(firstResult, isNull);
        expect(downloadOpener.openCalls, hasLength(1));
      });
    });
  });

  test('close() cancels the poll Timer — no getStatus call ever fires after '
      'close, even past what would have been the next tick', () {
    fakeAsync((async) {
      unawaited(cubit.start(periodStart: periodStart, periodEnd: periodEnd));
      async.flushMicrotasks();

      // `tearDown` above also calls `cubit.close()`, but the guard this
      // test is about only matters if it has already happened by the
      // time the next tick would fire — so it's called here too,
      // directly inside the elapsed window.
      unawaited(cubit.close());
      async.flushMicrotasks();

      async.elapse(onePoll);
      expect(repository.getStatusCalls, isEmpty);
    });
  });
}
