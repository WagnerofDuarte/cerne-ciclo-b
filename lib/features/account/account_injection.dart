import '../../core/di/injection_container.dart';
import '../auth/domain/repositories/session_repository.dart';
import '../chat/domain/repositories/chat_repository.dart';
import '../entries/domain/repositories/entries_repository.dart';
import '../vault/domain/repositories/vault_repository.dart';
import 'data/datasources/account_remote_data_source.dart';
import 'data/repositories/account_settings_repository_impl.dart';
import 'domain/repositories/account_settings_repository.dart';
import 'presentation/cubit/account_settings_cubit.dart';

/// Registers the `account` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `features/vault/vault_injection.dart`'s
/// pattern. Called from `setupCoreDependencies()` right after
/// `registerVaultFeature()` (Code Map).
void registerAccountFeature() {
  sl.registerLazySingleton<AccountRemoteDataSource>(
    () => AccountRemoteDataSource(sl()),
  );

  // The epic's one new DI-singleton access point for the account's
  // `biometricEnabled` preference — registered as a singleton so every
  // consumer (`main.dart`'s boot fetch; `core/navigation/app_router.dart`'s
  // `/vault` builder; the Configurações screen's own cubit) shares the same
  // `biometricEnabledStream`, not a fresh instance each. `dispose:` wires
  // `AccountSettingsRepository.dispose()` into `get_it`'s own reset
  // lifecycle, so `resetCoreDependencies()` (`sl.reset()`) closes its
  // `StreamController` instead of leaking one on every test teardown.
  sl.registerLazySingleton<AccountSettingsRepository>(
    () => AccountSettingsRepositoryImpl(remoteDataSource: sl()),
    dispose: (repository) => repository.dispose(),
  );

  // Review finding: `AccountSettingsCubit`'s constructor subscribes to
  // `biometricEnabledStream`; only its own `close()` cancels that
  // subscription, which nothing previously called — `dispose:` wires it
  // into `get_it`'s own reset lifecycle, same convention as every other
  // registration in this file.
  //
  // Story 8.4 — widened with the 4 repos `logout()` orchestrates
  // (`SessionRepository`/`VaultRepository`/`EntriesRepository`/
  // `ChatRepository`), all already registered as `lazySingleton`s
  // elsewhere — `sl()`'s own lazy resolution means the registration order
  // across `registerXFeature()` calls in `setupCoreDependencies()` is not
  // load-bearing here (same rationale that file's own comments already
  // give for its sibling calls).
  sl.registerLazySingleton<AccountSettingsCubit>(
    () => AccountSettingsCubit(
      sl<AccountSettingsRepository>(),
      sl<SessionRepository>(),
      sl<VaultRepository>(),
      sl<EntriesRepository>(),
      sl<ChatRepository>(),
    ),
    dispose: (cubit) => cubit.close(),
  );
}
