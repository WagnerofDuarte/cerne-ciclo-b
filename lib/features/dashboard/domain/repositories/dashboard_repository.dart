import 'package:fpdart/fpdart.dart';

import '../../../../core/failure/failure.dart';
import '../entities/dashboard_aggregate.dart';

/// The dashboard feature's one port (RNF06) — `features/dashboard/
/// presentation` depends on this abstract class only, never
/// `features/dashboard/data` directly. Returns `Either<Failure, T>`
/// (RNF09).
abstract class DashboardRepository {
  /// Calls `dashboard-aggregate-get` (`ApiClient.get`, [period] sent as the
  /// one required `period` query parameter) — a thin pass-through, no
  /// cache (Boundaries/Never: "cache the aggregate", AD-15 exclusion).
  /// `DashboardCubit.load()` is this method's one call site, always with
  /// `period: 'all'` (Boundaries: "fixed; no period selector exists
  /// anywhere in the product"); [period] stays a plain `String` (the
  /// contract's own `openapi.yaml` enum values) rather than a dedicated
  /// enum, since nothing else in this app will ever pass a different one.
  Future<Either<Failure, DashboardAggregate>> getAggregate({
    required String period,
  });
}
