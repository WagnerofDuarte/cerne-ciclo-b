import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/export_download_format.dart';
import '../models/export_job_status_dto.dart';

/// The export feature's one remote data source — `export-summary-create`/
/// `export-status-get`, called by `x-cerne-function` name only
/// (AGENTS.md), [jobId] appended as [getStatus]'s one trailing path
/// segment. Mirrors `ChatRemoteDataSource`'s own try/catch-to-
/// `malformedResponse` shape for every decode step (RNF09).
class ExportRemoteDataSource {
  ExportRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  /// `includeNarrative` is left unset — its own `openapi.yaml` default is
  /// `true`, and docs/input gives this story no reason to ever request a
  /// narrative-less export.
  ///
  /// Review finding (blind-hunter layer): [periodStart]/[periodEnd] arrive
  /// from `showDateRangePicker` as local-midnight `DateTime`s for the
  /// first/last *day* the user picked — sending [periodEnd] as-is (local
  /// midnight) would silently exclude every entry made later that same day
  /// from the export. Rebuilt here to the full local calendar day
  /// (start-of-day..end-of-day) before the one `.toUtc()` conversion, so
  /// the day boundary the user actually saw is preserved regardless of
  /// device timezone.
  Future<Either<Failure, String>> createJob({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final startOfDay = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final endOfDay = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
      999,
    );
    final result = await _apiClient.post(
      'export-summary-create',
      data: {
        'periodStart': startOfDay.toUtc().toIso8601String(),
        'periodEnd': endOfDay.toUtc().toIso8601String(),
      },
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(data['jobId'] as String);
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  Future<Either<Failure, ExportJobStatusDto>> getStatus(String jobId) async {
    final result = await _apiClient.get(
      'export-status-get',
      pathParams: [jobId],
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(ExportJobStatusDto.fromJson(data));
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }

  /// `export-download-get` — [jobId] trailing, [format] sent as the
  /// `format` query parameter (`.name`, matching the contract's own enum
  /// values verbatim). `ApiClient.getRedirectLocation` already owns the
  /// `302`-vs-error distinction (Code Map) — this is a thin pass-through,
  /// no mapping logic of its own.
  Future<Either<Failure, String>> getDownloadUrl(
    String jobId, {
    required ExportDownloadFormat format,
  }) => _apiClient.getRedirectLocation(
    'export-download-get',
    pathParams: [jobId],
    queryParameters: {'format': format.name},
  );
}
