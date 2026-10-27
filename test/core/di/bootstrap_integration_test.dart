import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/header_interceptor.dart';
import 'package:cerne/core/network/retry_interceptor.dart';

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
    'secure storage read/write round-trips through the DI-resolved instance',
    () async {
      final storage = sl<FlutterSecureStorage>();

      await storage.write(key: 'spike_test_key', value: 'spike_test_value');
      final value = await storage.read(key: 'spike_test_key');

      expect(value, 'spike_test_value');
    },
  );
}
