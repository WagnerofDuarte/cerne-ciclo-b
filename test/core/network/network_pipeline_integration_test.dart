import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/header_interceptor.dart';
import 'package:cerne/core/network/retry_interceptor.dart';
import 'package:cerne/core/network/url_builder.dart';

/// Every other network test (`api_client_test.dart`, `header_interceptor_test.dart`,
/// `retry_interceptor_test.dart`) mocks `Dio` itself or drives one interceptor
/// in isolation — neither proves the pieces work *wired together* the way
/// `setupCoreDependencies` actually wires them (AD-5), nor that a retry
/// genuinely goes back out over the wire.
///
/// Like `bootstrap_integration_test.dart` fakes the native secure-storage
/// channel (no device/CI exists yet to do otherwise), this fakes only the
/// transport boundary (`HttpClientAdapter`) — everything above it (URL
/// building, both real interceptors, `ApiClient`'s mapping) is the genuine
/// production wiring.
class _FakeHttpClientAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  final List<({int statusCode, Map<String, dynamic> body})> _queue = [];

  void queueJsonResponse(int statusCode, Map<String, dynamic> body) {
    _queue.add((statusCode: statusCode, body: body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (_queue.isEmpty) {
      throw StateError(
        'No queued response for ${options.method} ${options.path}',
      );
    }
    final next = _queue.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(next.body),
      next.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A minimal, real (non-mocked) in-memory implementation — this suite is
/// about proving the wiring, not re-verifying token-storage behavior
/// (already covered by `access_token_provider_test.dart`).
class _InMemoryAccessTokenProvider implements AccessTokenProvider {
  String? _token;
  String? _refreshToken;

  @override
  Future<String?> readAccessToken() async => _token;

  @override
  Future<void> saveAccessToken(String token) async => _token = token;

  @override
  Future<void> clearAccessToken() async => _token = null;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    _token = accessToken;
    _refreshToken = refreshToken;
  }

  @override
  Future<void> clearSession() async {
    _token = null;
    _refreshToken = null;
  }
}

void main() {
  const baseUrl = 'https://host.example.com';
  const anonKey = 'anon-key-value';

  late _FakeHttpClientAdapter adapter;
  late _InMemoryAccessTokenProvider tokenProvider;
  late ApiClient apiClient;

  setUp(() {
    adapter = _FakeHttpClientAdapter();
    tokenProvider = _InMemoryAccessTokenProvider();

    // Mirrors `setupCoreDependencies`'s wiring exactly: real Dio, both real
    // interceptors attached in the same order, header interceptor fed the
    // same anon key + token provider contract.
    final dio = Dio(BaseOptions())..httpClientAdapter = adapter;
    dio.interceptors.add(
      HeaderInterceptor(anonKey: anonKey, accessTokenProvider: tokenProvider),
    );
    dio.interceptors.add(RetryInterceptor(dio));

    apiClient = ApiClient(dio: dio, urlBuilder: const UrlBuilder(baseUrl));
  });

  group('network pipeline — real Dio + real interceptors, faked transport', () {
    test('an anon-only operation (auth-login) goes out at the x-cerne-function '
        'URL with apikey + anon Authorization, and the success body maps to '
        'Right', () async {
      adapter.queueJsonResponse(200, {'accessToken': 'tok-1'});

      final result = await apiClient.post(
        'auth-login',
        data: {'email': 'a@b.com', 'password': 'secret'},
      );

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (data) => expect(data, {'accessToken': 'tok-1'}),
      );

      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.path, '$baseUrl/auth-login');
      expect(sent.headers['apikey'], anonKey);
      expect(sent.headers['Authorization'], 'Bearer $anonKey');
    });

    test('auth-refresh goes out with the anon-key bearer even when a '
        '(possibly dead) user access token is already stored — refresh must '
        'never need it (Story 1.4)', () async {
      await tokenProvider.saveAccessToken('stale-access-token');
      adapter.queueJsonResponse(200, {
        'session': {
          'accessToken': 'new-access-token',
          'refreshToken': 'new-refresh-token',
          'expiresIn': 3600,
          'expiresAt': 1999999999,
          'tokenType': 'bearer',
        },
      });

      final result = await apiClient.post(
        'auth-refresh',
        data: {'refreshToken': 'stored-refresh-token'},
      );

      expect(result.isRight(), isTrue);
      final sent = adapter.requests.single;
      expect(sent.path, '$baseUrl/auth-refresh');
      expect(sent.headers['apikey'], anonKey);
      expect(sent.headers['Authorization'], 'Bearer $anonKey');
    });

    test('a bearer operation with a stored user token sends that token, not '
        'the anon key — and trailing path params are appended as real URL '
        'segments, never the literal openapi.yaml path (AD-5)', () async {
      await tokenProvider.saveAccessToken('user-token-1');
      adapter.queueJsonResponse(200, {'id': 'message-1', 'status': 'queued'});

      final result = await apiClient.post(
        'chat-messages-retry',
        pathParams: ['session-1', 'message-1'],
      );

      expect(result.isRight(), isTrue);
      final sent = adapter.requests.single;
      expect(sent.path, '$baseUrl/chat-messages-retry/session-1/message-1');
      expect(sent.headers['apikey'], anonKey);
      expect(sent.headers['Authorization'], 'Bearer user-token-1');
    });

    test('a retryable server error (RATE_LIMITED) is genuinely retried over '
        'the wire and the eventual success maps to Right', () async {
      adapter.queueJsonResponse(429, {
        'code': 'RATE_LIMITED',
        'message': 'slow down',
        'retryable': true,
      });
      adapter.queueJsonResponse(200, {'items': <dynamic>[]});

      final result = await apiClient.get('entries-list');

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (data) => expect(data, {'items': <dynamic>[]}),
      );
      // Two real requests actually left through the adapter: the retry
      // policy (AD-4) isn't just deciding to retry, it's re-driving the
      // same Dio pipeline end to end.
      expect(adapter.requests, hasLength(2));
    });

    test('a retryable error that never recovers is retried exactly '
        'maxRetries times and then surfaces as the matching Left', () async {
      for (var i = 0; i <= RetryInterceptor.maxRetries; i++) {
        adapter.queueJsonResponse(504, {
          'code': 'NETWORK_TIMEOUT',
          'message': 'gateway timeout',
          'retryable': true,
        });
      }

      final result = await apiClient.get('entries-list');

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<NetworkTimeout>());
        expect(failure.retryable, isTrue);
      }, (_) => fail('expected Left'));
      // Initial attempt + maxRetries retries, all real requests.
      expect(adapter.requests, hasLength(1 + RetryInterceptor.maxRetries));
    });

    test('a non-retryable error (AUTH_INVALID) surfaces immediately as the '
        'matching Left, with no retry request ever sent', () async {
      adapter.queueJsonResponse(401, {
        'code': 'AUTH_INVALID',
        'message': 'bad credentials',
        'retryable': false,
      });

      final result = await apiClient.post(
        'auth-login',
        data: {'email': 'a@b.com', 'password': 'wrong'},
      );

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<AuthInvalid>());
        expect(failure.retryable, isFalse);
      }, (_) => fail('expected Left'));
      expect(adapter.requests, hasLength(1));
    });
  });
}
