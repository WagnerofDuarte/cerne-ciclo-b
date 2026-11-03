import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/di/injection_container.dart';
import 'data/repositories/vault_repository_impl.dart';
import 'domain/repositories/vault_repository.dart';

/// Registers the `vault` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `features/auth/auth_injection.dart`'s pattern.
/// Called from `setupCoreDependencies()` right after `registerAuthFeature()`
/// (Code Map).
void registerVaultFeature() {
  sl.registerLazySingleton<LocalAuthentication>(() => LocalAuthentication());

  // The epic's ONE new DI-singleton access point for device-level access
  // (AD-14) — registered as a singleton so every consumer (the `/vault`
  // lock screen; `core/navigation/app_router.dart`'s redirect; `main.dart`)
  // shares the same `statusStream`, not a fresh instance each. `dispose:`
  // wires `VaultRepository.dispose()` into `get_it`'s own reset lifecycle,
  // so `resetCoreDependencies()` (`sl.reset()`) closes its
  // `StreamController` instead of leaking one on every test teardown.
  sl.registerLazySingleton<VaultRepository>(
    () => VaultRepositoryImpl(
      localAuthentication: sl<LocalAuthentication>(),
      // Already registered by `setupCoreDependencies()` (Code Map) — the
      // same singleton `SecureStorageAccessTokenProvider` uses for the
      // access/refresh tokens, now also holding the vault PIN (Story 2.2)
      // under its own distinct key.
      secureStorage: sl<FlutterSecureStorage>(),
    ),
    dispose: (repository) => repository.dispose(),
  );
}
