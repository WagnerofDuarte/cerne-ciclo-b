import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../domain/entities/dashboard_aggregate.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_data_source.dart';

/// Thin pass-through over [DashboardRemoteDataSource] (Code Map) — no
/// cache (Boundaries/Never: "cache the aggregate", AD-15 exclusion).
/// [DashboardAggregateDto.toDomain]'s own DTO->domain mapping lives on the
/// DTO itself, not here — this class only awaits the data source and
/// relays its result, same shape `ExportRepositoryImpl` already uses.
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl({required this._remoteDataSource});

  final DashboardRemoteDataSource _remoteDataSource;

  @override
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  }) async {
    final result = await _remoteDataSource.getAggregate(period: period);
    return result.map((dto) => dto.toDomain());
  }

  /// spec-8-2 — same thin pass-through shape as [getAggregate] above.
  @override
  Future<Either<Failure, String>> getNarrative({
    required String period,
  }) async {
    final result = await _remoteDataSource.getNarrative(period: period);
    return result.map((dto) => dto.toDomain());
  }
}
