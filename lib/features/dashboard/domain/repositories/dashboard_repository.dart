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

  /// Calls `dashboard-narrative-get` (`ApiClient.get`, [period] sent as the
  /// one required `period` query parameter) — spec-8-2's own independent
  /// second fetch, decoupled from [getAggregate] (Boundaries: "couple the
  /// two `Resource`s into one state object" is explicitly `Never`). A thin
  /// pass-through, no cache, same rationale [getAggregate]'s own doc gives.
  /// `DashboardNarrativeCubit.load()` is this method's one call site,
  /// always with `period: 'all'` (Boundaries: same fixed value as
  /// [getAggregate]).
  Future<Either<Failure, String>> getNarrative({required String period});
}
