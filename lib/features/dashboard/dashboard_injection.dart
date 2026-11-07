import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import '../entries/domain/services/pending_entry_write_tracker.dart';
import 'data/datasources/dashboard_remote_data_source.dart';
import 'data/repositories/dashboard_repository_impl.dart';
import 'domain/repositories/dashboard_repository.dart';
import 'presentation/cubit/dashboard_cubit.dart';
import 'presentation/cubit/dashboard_narrative_cubit.dart';

/// Registers the `dashboard` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `export_injection.dart`'s own shape. Called
/// after `registerEntriesFeature()` (`injection_container.dart`'s own call
/// order, Code Map), since [DashboardCubit] depends on the shared
/// [PendingEntryWriteTracker] that registration provides — but since every
/// registration here is `registerLazySingleton`, this *call* order isn't
/// itself load-bearing (review finding): [DashboardCubit]'s factory only
/// resolves [PendingEntryWriteTracker] lazily, the first time something
/// resolves `sl<DashboardCubit>()`, which happens well after every
/// `register*Feature()` call in `setupCoreDependencies()` has already run.
/// No Hive box here (Boundaries/Never: "cache the aggregate", AD-15
/// exclusion).
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

  // spec-8-2 — a second, independent `registerLazySingleton` alongside
  // [DashboardCubit] above, same dependencies and long-lived rationale
  // (Boundaries: "mirroring DashboardCubit's exact shape").
  sl.registerLazySingleton<DashboardNarrativeCubit>(
    () => DashboardNarrativeCubit(
      sl<DashboardRepository>(),
      sl<PendingEntryWriteTracker>(),
    ),
    dispose: (cubit) => cubit.close(),
  );
}
