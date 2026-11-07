import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import 'data/datasources/export_remote_data_source.dart';
import 'data/repositories/export_repository_impl.dart';
import 'domain/repositories/export_repository.dart';
import 'presentation/cubit/export_job_cubit.dart';

/// Registers the `export` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `capture_injection.dart`'s own shape.
/// [ExportJobCubit] is a `registerFactory`, not a `lazySingleton` (Code
/// Map: "`registerFactory<TextEntryCubit>` one-shot-cubit precedent") — a
/// fresh instance per download-icon tap, closed by the call site itself
/// once its sheet is gone (`ExportStatusSheet.show()`), never by a
/// `get_it` `dispose:` hook. No Hive box here (AD-15: export jobs are
/// never persisted locally).
void registerExportFeature() {
  sl.registerLazySingleton<ExportRemoteDataSource>(
    () => ExportRemoteDataSource(sl<ApiClient>()),
  );

  sl.registerLazySingleton<ExportRepository>(
    () => ExportRepositoryImpl(remoteDataSource: sl<ExportRemoteDataSource>()),
  );

  sl.registerFactory<ExportJobCubit>(
    () => ExportJobCubit(sl<ExportRepository>()),
  );
}
