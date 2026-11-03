import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/header_interceptor.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';

/// AC4 — proves the `dio` + `flutter_secure_storage` + `get_it` integration
/// spike works together in one bootstrap, before anything else is built on
/// top of it (architecture spine's Deferred note).
///
/// No device/simulator/CI exists yet to run a true platform-channel
/// integration test (AGENTS.md's "Running and verifying" TODO), so the
/// native secure-storage channel is faked with an in-memory store here —
/// the test still exercises the *real* `FlutterSecureStorage` instance
/// resolved from the single DI container, round-tripping a write/read
/// through it exactly as AC4 requires.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeNativeStorage = <String, String>{};

  Future<dynamic> handleSecureStorageCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>;
    switch (call.method) {
      case 'write':
        fakeNativeStorage[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return fakeNativeStorage[args['key'] as String];
      case 'delete':
        fakeNativeStorage.remove(args['key'] as String);
        return null;
      case 'containsKey':
        return fakeNativeStorage.containsKey(args['key'] as String);
      default:
        return null;
    }
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, handleSecureStorageCall);

    await resetCoreDependencies();
    await setupCoreDependencies();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await resetCoreDependencies();
  });

  test(
    'exactly one get_it instance resolves Dio + FlutterSecureStorage + ApiClient',
    () {
      expect(sl.isRegistered<Dio>(), isTrue);
      expect(sl.isRegistered<FlutterSecureStorage>(), isTrue);
      expect(sl.isRegistered<ApiClient>(), isTrue);

      // `dio` is configured through the container: both interceptors
      // (header + retry, AD-4/AD-5) are attached to the resolved instance,
      // alongside dio's own built-in default interceptor.
      final dio = sl<Dio>();
      expect(dio.interceptors.whereType<HeaderInterceptor>(), hasLength(1));
      expect(dio.interceptors.whereType<RetryInterceptor>(), hasLength(1));

      // Resolving twice returns the same singleton — one container, one Dio.
      expect(sl<Dio>(), same(dio));
    },
  );

  test(
    'setupCoreDependencies also wires the auth feature (Story 1.3) — a '
    'broken registration/dependency cycle must surface here, not only at '
    'real app launch (no device/CI exists yet to catch that otherwise)',
    () {
      expect(sl.isRegistered<AuthRemoteDataSource>(), isTrue);
      expect(sl.isRegistered<AuthRepository>(), isTrue);
      expect(sl.isRegistered<AuthCubit>(), isTrue);

      // Actually resolves the whole chain (AuthCubit -> AuthRepository ->
      // AuthRemoteDataSource/AccessTokenProvider -> ApiClient/Dio) rather
      // than just checking the registration exists — `get_it`'s
      // `registerLazySingleton` only evaluates its factory on first
      // resolution.
      expect(() => sl<AuthCubit>(), returnsNormally);
    },
  );

  test(
    'setupCoreDependencies also wires the vault feature (spec-2-1, AD-14) — '
    'a broken registration (bad factory, missing LocalAuthentication '
    "dependency, broken dispose:) must surface here, not only at real app "
    'launch (no device/CI exists yet to catch that otherwise)',
    () {
      expect(sl.isRegistered<VaultRepository>(), isTrue);

      // Actually resolves VaultRepository -> VaultRepositoryImpl(
      // localAuthentication: sl<LocalAuthentication>()) rather than just
      // checking the registration exists. This only constructs the
      // LocalAuthentication() instance and stores it — it never calls any
      // of its methods, so no platform-channel mock is needed here (same
      // reasoning that already applies to AuthCubit's forced resolution
      // above).
      expect(() => sl<VaultRepository>(), returnsNormally);
    },
  );

  test(
    'setupCoreDependencies also wires the account feature (spec-2-4) — a '
    'broken registration/dependency cycle must surface here, not only at '
    'real app launch (no device/CI exists yet to catch that otherwise)',
    () {
      expect(sl.isRegistered<AccountSettingsRepository>(), isTrue);
      expect(sl.isRegistered<AccountSettingsCubit>(), isTrue);

      // Actually resolves the whole chain (AccountSettingsCubit ->
      // AccountSettingsRepository -> AccountRemoteDataSource -> ApiClient/
      // Dio) rather than just checking the registration exists — same
      // rationale as `AuthCubit`'s own forced resolution above.
      expect(() => sl<AccountSettingsCubit>(), returnsNormally);
    },
  );

  test(
    'secure storage read/write round-trips through the DI-resolved instance',
    () async {
      final storage = sl<FlutterSecureStorage>();

      await storage.write(key: 'spike_test_key', value: 'spike_test_value');
      final value = await storage.read(key: 'spike_test_key');

      expect(value, 'spike_test_value');
    },
  );
}
