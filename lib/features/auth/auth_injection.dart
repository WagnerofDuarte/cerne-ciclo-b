import '../../core/di/injection_container.dart';
import '../../core/network/access_token_provider.dart';
import 'data/datasources/auth_remote_data_source.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'domain/repositories/auth_repository.dart';
import 'presentation/cubit/auth_cubit.dart';

/// Registers the `auth` feature into the project's single `get_it` instance
/// (`sl`). Called from `setupCoreDependencies()` once core infrastructure is
/// up, since this feature only needs `ApiClient`/`AccessTokenProvider`,
/// already registered there.
void registerAuthFeature() {
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSource(sl()),
  );

  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: sl(),
      accessTokenProvider: sl<AccessTokenProvider>(),
    ),
  );

  sl.registerLazySingleton<AuthCubit>(() => AuthCubit(sl()));
}
