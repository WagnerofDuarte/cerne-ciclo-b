import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/network/access_token_provider.dart';

/// `SecureStorageAccessTokenProvider` itself (as opposed to the raw
/// `FlutterSecureStorage` instance) was previously only exercised
/// indirectly — this proves save/read/clear on the provider's own API,
/// the same native-channel-faking approach as
/// `bootstrap_integration_test.dart`.
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

  late SecureStorageAccessTokenProvider provider;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    fakeNativeStorage.clear();
    provider = SecureStorageAccessTokenProvider(const FlutterSecureStorage());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  group('SecureStorageAccessTokenProvider', () {
    test('readAccessToken returns null when nothing is stored', () async {
      expect(await provider.readAccessToken(), isNull);
    });

    test(
      'saveAccessToken then readAccessToken round-trips the token',
      () async {
        await provider.saveAccessToken('token-123');

        expect(await provider.readAccessToken(), 'token-123');
      },
    );

    test('clearAccessToken removes the stored token', () async {
      await provider.saveAccessToken('token-123');
      await provider.clearAccessToken();

      expect(await provider.readAccessToken(), isNull);
    });

    test('readRefreshToken returns null when nothing is stored', () async {
      expect(await provider.readRefreshToken(), isNull);
    });

    test('saveSession persists both halves of the pair, independently of '
        'readAccessToken/readRefreshToken', () async {
      await provider.saveSession(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
      );

      expect(await provider.readAccessToken(), 'access-123');
      expect(await provider.readRefreshToken(), 'refresh-456');
    });

    test(
      'a later saveSession overwrites both tokens of an earlier one',
      () async {
        await provider.saveSession(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        );
        await provider.saveSession(
          accessToken: 'access-2',
          refreshToken: 'refresh-2',
        );

        expect(await provider.readAccessToken(), 'access-2');
        expect(await provider.readRefreshToken(), 'refresh-2');
      },
    );

    test('clearSession removes both the access and refresh tokens', () async {
      await provider.saveSession(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
      );
      await provider.clearSession();

      expect(await provider.readAccessToken(), isNull);
      expect(await provider.readRefreshToken(), isNull);
    });
  });
}
