import '../../core/di/injection_container.dart';
import '../../core/network/access_token_provider.dart';
import '../../core/session/session_expiry_notifier.dart';
import 'data/datasources/auth_remote_data_source.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/repositories/session_repository_impl.dart';
import 'domain/repositories/auth_repository.dart';
import 'domain/repositories/session_repository.dart';
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

  // The epic's ONE new DI-singleton access point for session validity (AD) —
  // registered as a singleton so every consumer (`main.dart` here; Story
  // 1.5's overlay and Story 1.6's `go_router` redirect later) shares the
  // same `statusStream`, not a fresh instance each. `dispose:` wires
  // `SessionRepository.dispose()` into `get_it`'s own reset lifecycle, so
  // `resetCoreDependencies()` (`sl.reset()`) closes its `StreamController`
  // instead of leaking one on every test teardown.
  sl.registerLazySingleton<SessionRepository>(
    () => SessionRepositoryImpl(
      remoteDataSource: sl(),
      accessTokenProvider: sl<AccessTokenProvider>(),
      sessionExpiryNotifier: sl<SessionExpiryNotifier>(),
    ),
    dispose: (repository) => repository.dispose(),
  );

  // Story 1.6 — `AuthCubit` additionally depends on `SessionRepository`
  // (registered above) so its `submit()` success branch can call
  // `markAuthenticated()`.
  sl.registerLazySingleton<AuthCubit>(
    () => AuthCubit(sl(), sl<SessionRepository>()),
  );
}
