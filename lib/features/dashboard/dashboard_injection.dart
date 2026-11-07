import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import '../entries/domain/services/pending_entry_write_tracker.dart';
import 'data/datasources/dashboard_remote_data_source.dart';
import 'data/repositories/dashboard_repository_impl.dart';
import 'domain/repositories/dashboard_repository.dart';
import 'presentation/cubit/dashboard_cubit.dart';

/// Registers the `dashboard` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `export_injection.dart`'s own shape. Must run
/// after `registerEntriesFeature()` (`injection_container.dart`'s own call
/// order, Code Map) since [DashboardCubit] depends on the shared
/// [PendingEntryWriteTracker] that registration provides. No Hive box here
/// (Boundaries/Never: "cache the aggregate", AD-15 exclusion).
void registerDashboardFeature() {
  sl.registerLazySingleton<DashboardRemoteDataSource>(
    () => DashboardRemoteDataSource(sl<ApiClient>()),
  );

  sl.registerLazySingleton<DashboardRepository>(
    () => DashboardRepositoryImpl(
      remoteDataSource: sl<DashboardRemoteDataSource>(),
    ),
  );

  // Boundaries — a `registerLazySingleton`, not a factory: long-lived, so
  // its constructor subscription to `PendingEntryWriteTracker.
  // confirmedWrites` stays live for the app's whole session (same
  // rationale `MeusRegistrosCubit`'s own registration gives). `dispose:`
  // wires `close()` into `get_it`'s own reset lifecycle, same convention
  // every other long-lived cubit in this project already uses.
  sl.registerLazySingleton<DashboardCubit>(
    () => DashboardCubit(
      sl<DashboardRepository>(),
      sl<PendingEntryWriteTracker>(),
    ),
    dispose: (cubit) => cubit.close(),
  );
}
