import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../../../../core/network/api_client.dart';
import '../models/dashboard_aggregate_dto.dart';

/// The dashboard feature's one remote data source — `dashboard-aggregate-
/// get`, called by `x-cerne-function` name only (AGENTS.md), [period] sent
/// as the one required `period` query parameter. Mirrors
/// `ExportRemoteDataSource`'s own try/catch-to-`malformedResponse` shape
/// for its decode step (RNF09).
class DashboardRemoteDataSource {
  DashboardRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Either<Failure, DashboardAggregateDto>> getAggregate({
    required String period,
  }) async {
    final result = await _apiClient.get(
      'dashboard-aggregate-get',
      queryParameters: {'period': period},
    );
    return result.flatMap((json) {
      try {
        final data = json['data'] as Map<String, dynamic>;
        return right(DashboardAggregateDto.fromJson(data));
      } catch (error) {
        return left(Failure.malformedResponse(message: error.toString()));
      }
    });
  }
}
