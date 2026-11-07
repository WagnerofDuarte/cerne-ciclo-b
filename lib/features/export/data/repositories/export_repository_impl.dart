import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/export_download_format.dart';
import '../../domain/entities/export_job_state.dart';
import '../../domain/repositories/export_repository.dart';
import '../datasources/export_remote_data_source.dart';

/// Thin pass-through over [ExportRemoteDataSource] (Code Map) — no cache
/// (AD-15: export jobs are never persisted locally). [getStatus]'s own
/// DTO→state mapping lives on [ExportJobStatusDto.toState] itself, not
/// here — this class only awaits the data source and relays its result.
class ExportRepositoryImpl implements ExportRepository {
  ExportRepositoryImpl({required this._remoteDataSource});

  final ExportRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, String>> createJob({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) => _remoteDataSource.createJob(
    periodStart: periodStart,
    periodEnd: periodEnd,
  );

  @override
  Future<Either<Failure, ExportJobState>> getStatus(String jobId) async {
    final result = await _remoteDataSource.getStatus(jobId);
    return result.map((dto) => dto.toState());
  }

  @override
  Future<Either<Failure, String>> getDownloadUrl(
    String jobId, {
    required ExportDownloadFormat format,
  }) => _remoteDataSource.getDownloadUrl(jobId, format: format);
}
