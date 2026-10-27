import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/header_interceptor.dart';

class MockAccessTokenProvider extends Mock implements AccessTokenProvider {}

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/fallback'));
  });

  const anonKey = 'anon-key-value';

  late MockAccessTokenProvider mockAccessTokenProvider;
  late HeaderInterceptor interceptor;

  setUp(() {
    mockAccessTokenProvider = MockAccessTokenProvider();
    interceptor = HeaderInterceptor(
      anonKey: anonKey,
      accessTokenProvider: mockAccessTokenProvider,
    );
  });

  group('HeaderInterceptor.onRequest — AD-5 header policy', () {
    test('anon-only function (auth-login) sends apikey + anon bearer', () {
      final options = RequestOptions(path: 'https://host/auth-login');
      final handler = MockRequestInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      interceptor.onRequest(options, handler);

      expect(options.headers['apikey'], anonKey);
      expect(options.headers['Authorization'], 'Bearer $anonKey');
      verify(() => handler.next(options)).called(1);
      verifyNever(() => mockAccessTokenProvider.readAccessToken());
    });

    test('other function with a stored token sends apikey + user bearer',
        () async {
      const userToken = 'user-token-value';
      when(() => mockAccessTokenProvider.readAccessToken())
          .thenAnswer((_) async => userToken);

      final options = RequestOptions(path: 'https://host/entries-create');
      final handler = MockRequestInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(options.headers['apikey'], anonKey);
      expect(options.headers['Authorization'], 'Bearer $userToken');
      verify(() => handler.next(options)).called(1);
    });

    test('other function with no stored token sends apikey, no Authorization',
        () async {
      when(() => mockAccessTokenProvider.readAccessToken())
          .thenAnswer((_) async => null);

      final options = RequestOptions(path: 'https://host/entries-list');
      final handler = MockRequestInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(options.headers['apikey'], anonKey);
      expect(options.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(options)).called(1);
    });

    test(
        'a thrown PlatformException from readAccessToken never crashes the '
        'pipeline — proceeds with no Authorization header', () async {
      when(() => mockAccessTokenProvider.readAccessToken())
          .thenThrow(Exception('secure storage unavailable'));

      final options = RequestOptions(path: 'https://host/entries-list');
      final handler = MockRequestInterceptorHandler();
      when(() => handler.next(any())).thenReturn(null);

      interceptor.onRequest(options, handler);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(options.headers['apikey'], anonKey);
      expect(options.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(options)).called(1);
    });
  });

  group('HeaderInterceptor.functionNameOf', () {
    test('a bare function path with no path params', () {
      expect(
        HeaderInterceptor.functionNameOf('https://host/auth-login'),
        'auth-login',
      );
    });

    test('a function path with trailing path params', () {
      expect(
        HeaderInterceptor.functionNameOf(
          'https://host/chat-messages-retry/session-1/message-1',
        ),
        'chat-messages-retry',
      );
    });

    test('a bare relative path (no scheme/host)', () {
      expect(HeaderInterceptor.functionNameOf('/auth-signup'), 'auth-signup');
    });
  });
}
