import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/export/data/models/export_job_status_dto.dart';
import 'package:cerne/features/export/domain/entities/export_job_state.dart';

ExportJobStatusDto _dto({
  required String status,
  String narrativeStatus = 'pending',
  String? errorCode,
}) => ExportJobStatusDto(
  jobId: 'job-1',
  status: status,
  narrativeStatus: narrativeStatus,
  entryCount: null,
  errorCode: errorCode,
  narrativeErrorCode: null,
  downloadAvailable: false,
);

void main() {
  group('ExportJobStatusDto.toState (export-screen-states.md table)', () {
    test('pending -> preparing (Pendente)', () {
      expect(_dto(status: 'pending').toState(), isA<ExportJobPreparing>());
    });

    test('processing -> generating (Processando)', () {
      expect(
        _dto(status: 'processing', narrativeStatus: 'processing').toState(),
        isA<ExportJobGenerating>(),
      );
    });

    test(
      'data_ready folds into generating too — no case of its own '
      '(Design Notes, Story 7.2)',
      () {
        expect(
          _dto(status: 'data_ready', narrativeStatus: 'processing').toState(),
          isA<ExportJobGenerating>(),
        );
      },
    );

    test('done + narrativeStatus done -> done(narrativeReady) (Concluído)', () {
      final state = _dto(status: 'done', narrativeStatus: 'done').toState();
      expect(state, isA<ExportJobDone>());
      expect((state as ExportJobDone).outcome, ExportOutcome.narrativeReady);
    });

    test(
      'done + narrativeStatus failed -> done(narrativeUnavailable) '
      '(Narrativa falhou)',
      () {
        final state = _dto(
          status: 'done',
          narrativeStatus: 'failed',
        ).toState();
        expect(state, isA<ExportJobDone>());
        expect(
          (state as ExportJobDone).outcome,
          ExportOutcome.narrativeUnavailable,
        );
      },
    );

    test(
      'done + narrativeStatus skipped -> done(narrativeUnavailable) too '
      '(Narrativa pulada)',
      () {
        final state = _dto(
          status: 'done',
          narrativeStatus: 'skipped',
        ).toState();
        expect(state, isA<ExportJobDone>());
        expect(
          (state as ExportJobDone).outcome,
          ExportOutcome.narrativeUnavailable,
        );
      },
    );

    test(
      'error + EXPORT_EMPTY_PERIOD -> emptyPeriod, never a plain '
      'error(Failure) (AD-3: reuses Failure.exportEmptyPeriod to detect '
      'this, rather than re-testing the literal code string)',
      () {
        final state = _dto(
          status: 'error',
          errorCode: 'EXPORT_EMPTY_PERIOD',
        ).toState();
        expect(state, isA<ExportJobEmptyPeriod>());
      },
    );

    test(
      'error + any other taxonomy code -> error(Failure), mapped via the '
      'one shared Failure.fromCode (Erro)',
      () {
        final state = _dto(
          status: 'error',
          errorCode: 'AI_GENERATION_TIMEOUT',
        ).toState();
        expect(state, isA<ExportJobError>());
        expect(
          (state as ExportJobError).failure,
          isA<AiGenerationTimeout>(),
        );
      },
    );

    test(
      'error + null errorCode -> error(Failure.malformedResponse), never '
      'throws (RNF09)',
      () {
        final state = _dto(status: 'error').toState();
        expect(state, isA<ExportJobError>());
        expect((state as ExportJobError).failure, isA<MalformedResponse>());
      },
    );

    test(
      'an unrecognized status -> error(Failure.malformedResponse), never '
      'throws (RNF09) — the contract enum is closed, should never happen',
      () {
        final state = _dto(status: 'not-a-real-status').toState();
        expect(state, isA<ExportJobError>());
        expect((state as ExportJobError).failure, isA<MalformedResponse>());
      },
    );
  });
}
