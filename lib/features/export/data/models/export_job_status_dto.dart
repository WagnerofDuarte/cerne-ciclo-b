import 'package:json_annotation/json_annotation.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/export_job_state.dart';

part 'export_job_status_dto.g.dart';

/// `export.status.get`'s own response `data` (`openapi.yaml:1495-1539`) —
/// decodes every field the contract declares, even [narrativeErrorCode]/
/// [downloadAvailable] which this story never reads (both belong to
/// Story 7.2's download wiring) — kept here so the DTO always mirrors the
/// full contract shape, not just today's consumer.
@JsonSerializable()
class ExportJobStatusDto {
  const ExportJobStatusDto({
    required this.jobId,
    required this.status,
    required this.narrativeStatus,
    required this.entryCount,
    required this.errorCode,
    required this.narrativeErrorCode,
    required this.downloadAvailable,
  });

  final String jobId;
  final String status;
  final String narrativeStatus;
  final int? entryCount;
  final String? errorCode;
  final String? narrativeErrorCode;
  final bool downloadAvailable;

  factory ExportJobStatusDto.fromJson(Map<String, dynamic> json) =>
      _$ExportJobStatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ExportJobStatusDtoToJson(this);

  /// `docs/input/backend/export-screen-states.md`'s own status×
  /// narrativeStatus×downloadAvailable mapping table, implemented once
  /// here — `ExportRepositoryImpl.getStatus`'s own "thin pass-through"
  /// (Code Map) calls straight through to this method, with no mapping
  /// logic of its own.
  ///
  /// AD-3 ("reuse the existing `Failure.exportEmptyPeriod`... never add a
  /// new `Failure` subtype") is honored by going through the one shared
  /// [Failure.fromCode] for every `status: 'error'` response and then
  /// branching on the *subtype* it returns, rather than re-testing the
  /// literal `'EXPORT_EMPTY_PERIOD'` string a second time here — this
  /// stays correct even if a future taxonomy edit ever changed which code
  /// means "empty period", with no second place to update.
  ExportJobState toState() {
    switch (status) {
      case 'pending':
        return const ExportJobState.preparing();
      case 'processing':
      case 'data_ready':
        // Design Notes — `data_ready` folds into `generating`'s own
        // visual here, no case of its own (lighting it up is Story
        // 7.2's job).
        return const ExportJobState.generating();
      case 'done':
        return ExportJobState.done(
          narrativeStatus == 'done'
              ? ExportOutcome.narrativeReady
              : ExportOutcome.narrativeUnavailable,
        );
      case 'error':
        final failure = Failure.fromCode(
          errorCode ?? '',
          'Não foi possível gerar a exportação.',
        );
        return failure is ExportEmptyPeriod
            ? const ExportJobState.emptyPeriod()
            : ExportJobState.error(failure);
      default:
        // Forward-compatible: an unrecognized `status` (shouldn't happen —
        // the contract's own enum is closed) never crashes the poll loop
        // (RNF09) — surfaces as a terminal error instead.
        return ExportJobState.error(
          Failure.malformedResponse(
            message: 'Unknown export status: $status',
          ),
        );
    }
  }
}
