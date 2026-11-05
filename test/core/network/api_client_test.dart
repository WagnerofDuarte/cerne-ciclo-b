import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/core/network/url_builder.dart';

import '../../support/mock_session_expiry_notifier.dart';

class MockDio extends Mock implements Dio {}

void main() {
  const baseUrl = 'https://host.example.com';

  late MockDio mockDio;
  late MockSessionExpiryNotifier mockSessionExpiryNotifier;
  late ApiClient apiClient;
  late RequestOptions requestOptions;

  setUp(() {
    mockDio = MockDio();
    mockSessionExpiryNotifier = MockSessionExpiryNotifier();
    apiClient = ApiClient(
      dio: mockDio,
      urlBuilder: const UrlBuilder(baseUrl),
      sessionExpiryNotifier: mockSessionExpiryNotifier,
    );
    requestOptions = RequestOptions(path: '$baseUrl/auth-signup');
  });

  group('ApiClient — real send/mapping logic, mocked Dio', () {
    test('success response -> Right(data)', () async {
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
        data: {'id': 'abc123'},
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => response);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (data) => expect(data, {'id': 'abc123'}),
      );
    });

    test('DioException with a {code, message} body maps to the matching '
        'Failure', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 429,
          data: {
            'code': 'RATE_LIMITED',
            'message': 'Too many requests',
            'retryable': true,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<RateLimited>());
        expect(failure.retryable, isTrue);
      }, (_) => fail('expected Left'));
    });

    test('a {code, message} body where message is not a String still maps '
        'without throwing (patch item 1)', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 400,
          data: {
            'code': 'VALIDATION_ERROR',
            // Malformed on purpose: the contract says `message` is a
            // String, but nothing stops a backend bug from sending an int.
            'message': 12345,
            'retryable': false,
          },
        ),
        type: DioExceptionType.badResponse,
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<Validation>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'DioException with no response at all -> Left(NetworkOffline)',
      () async {
        final dioError = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionError,
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
          ),
        ).thenThrow(dioError);

        final result = await apiClient.post('auth-signup', data: {'a': 1});

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<NetworkOffline>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test('a non-DioException thrown by dio -> Left(MalformedResponse), never '
        'a crash', () async {
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(StateError('unexpected native failure'));

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('a null response body -> Left(MalformedResponse)', () async {
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => response);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('a client-side connect timeout maps to Left(NetworkTimeout), not '
        'NetworkOffline (patch item 1)', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<NetworkTimeout>());
        expect(failure.retryable, isTrue);
      }, (_) => fail('expected Left'));
    });

    test('a cancelled request maps to Left(MalformedResponse), never '
        'NetworkOffline — it must never be retried (patch item 2)', () async {
      final dioError = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.cancel,
      );
      when(
        () =>
            mockDio.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(dioError);

      final result = await apiClient.post('auth-signup', data: {'a': 1});

      expect(result.isLeft(), isTrue);
      result.match((failure) {
        expect(failure, isA<MalformedResponse>());
        expect(failure.retryable, isFalse);
      }, (_) => fail('expected Left'));
    });

    test(
      'get sends queryParameters through and maps a success response',
      () async {
        final response = Response<Map<String, dynamic>>(
          requestOptions: requestOptions,
          statusCode: 200,
          data: {'items': <dynamic>[]},
        );
        when(
          () => mockDio.get<Map<String, dynamic>>(
            any(),
            queryParameters: any(named: 'queryParameters'),
          ),
        ).thenAnswer((_) async => response);

        final result = await apiClient.get(
          'entries-list',
          queryParameters: {'cursor': 'abc'},
        );

        expect(result.isRight(), isTrue);
        final captured = verify(
          () => mockDio.get<Map<String, dynamic>>(
            captureAny(),
            queryParameters: captureAny(named: 'queryParameters'),
          ),
        ).captured;
        expect(captured[0], '$baseUrl/entries-list');
        expect(captured[1], {'cursor': 'abc'});
      },
    );

    test('patch sends data through and maps a success response', () async {
      final response = Response<Map<String, dynamic>>(
        requestOptions: requestOptions,
        statusCode: 200,
        data: {'updated': true},
      );
      when(
        () => mockDio.patch<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => response);

      final result = await apiClient.patch(
        'account-settings-update',
        data: {'name': 'x'},
      );

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (data) => expect(data, {'updated': true}),
      );
    });

    test('delete maps errors the same way the other verbs do', () async {
      when(
        () => mockDio.delete<Map<String, dynamic>>(
          any(),
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await apiClient.delete('account');

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group(
    'Story 1.5 — mid-session AUTH_EXPIRED notifies SessionExpiryNotifier',
    () {
      test(
        'AUTH_EXPIRED on a bearer (non-anon-key) function notifies the expiry '
        'listener exactly once (AD-2/AD-5)',
        () async {
          final bearerRequestOptions = RequestOptions(
            path: '$baseUrl/entries-list',
          );
          final dioError = DioException(
            requestOptions: bearerRequestOptions,
            response: Response(
              requestOptions: bearerRequestOptions,
              statusCode: 401,
              data: {
                'code': 'AUTH_EXPIRED',
                'message': 'Session expired',
                'retryable': false,
              },
            ),
            type: DioExceptionType.badResponse,
          );
          when(
            () => mockDio.get<Map<String, dynamic>>(
              any(),
              queryParameters: any(named: 'queryParameters'),
            ),
          ).thenThrow(dioError);

          final result = await apiClient.get('entries-list');

          expect(result.isLeft(), isTrue);
          result.match(
            (failure) => expect(failure, isA<AuthExpired>()),
            (_) => fail('expected Left'),
          );
          verify(() => mockSessionExpiryNotifier.notifyExpired()).called(1);
        },
      );

      test('AUTH_EXPIRED on one of the three anon-key-only functions '
          '(auth-refresh) never notifies — Story 1.4\'s boot-time '
          'restoreSession() path stays untouched', () async {
        final refreshRequestOptions = RequestOptions(
          path: '$baseUrl/auth-refresh',
        );
        final dioError = DioException(
          requestOptions: refreshRequestOptions,
          response: Response(
            requestOptions: refreshRequestOptions,
            statusCode: 401,
            data: {
              'code': 'AUTH_EXPIRED',
              'message': 'Refresh token dead',
              'retryable': false,
            },
          ),
          type: DioExceptionType.badResponse,
        );
        when(
          () => mockDio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
          ),
        ).thenThrow(dioError);

        final result = await apiClient.post(
          'auth-refresh',
          data: {'refreshToken': 'stored-refresh-token'},
        );

        expect(result.isLeft(), isTrue);
        result.match(
          (failure) => expect(failure, isA<AuthExpired>()),
          (_) => fail('expected Left'),
        );
        verifyNever(() => mockSessionExpiryNotifier.notifyExpired());
      });

      test(
        'a non-AUTH_EXPIRED failure never notifies, even on a bearer function',
        () async {
          final bearerRequestOptions = RequestOptions(
            path: '$baseUrl/entries-create',
          );
          when(
            () => mockDio.post<Map<String, dynamic>>(
              any(),
              data: any(named: 'data'),
            ),
          ).thenThrow(
            DioException(
              requestOptions: bearerRequestOptions,
              type: DioExceptionType.connectionError,
            ),
          );

          final result = await apiClient.post('entries-create', data: {});

          expect(result.isLeft(), isTrue);
          result.match(
            (failure) => expect(failure, isA<NetworkOffline>()),
            (_) => fail('expected Left'),
          );
          verifyNever(() => mockSessionExpiryNotifier.notifyExpired());
        },
      );
    },
  );

  group('spec-6-1 — postStream', () {
    test(
      'yields each decoded chunk as Right, in the order received',
      () async {
        final bodyStream = Stream<Uint8List>.fromIterable([
          Uint8List.fromList(utf8.encode('event: token\n')),
          Uint8List.fromList(utf8.encode('data: {"delta":"Hi"}\n\n')),
        ]);
        final response = Response<ResponseBody>(
          requestOptions: requestOptions,
          statusCode: 200,
          data: ResponseBody(bodyStream, 200),
        );
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => response);

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        expect(chunks, hasLength(2));
        expect(chunks[0].isRight(), isTrue);
        expect(chunks[1].isRight(), isTrue);
        final combined = chunks
            .map((either) => either.getRight().toNullable())
            .join();
        expect(combined, 'event: token\ndata: {"delta":"Hi"}\n\n');
      },
    );

    test(
      'review finding: a multi-byte UTF-8 character split across two raw '
      'chunk boundaries decodes correctly, not as replacement characters '
      '— this app\'s primary language (pt-BR) uses multi-byte characters '
      '(e.g. "ã") constantly, and dio\'s own chunk boundaries split on '
      'byte count, not on character boundaries',
      () async {
        // 'ã' is the 2-byte UTF-8 sequence 0xC3 0xA3 — split with the
        // first byte ending chunk 1 and the second byte starting chunk 2,
        // deliberately severing the character across the boundary.
        final part1 = Uint8List.fromList([
          ...utf8.encode('data: {"delta":"am'),
          0xC3,
        ]);
        final part2 = Uint8List.fromList([0xA3, ...utf8.encode('"}\n\n')]);
        final bodyStream = Stream<Uint8List>.fromIterable([part1, part2]);
        final response = Response<ResponseBody>(
          requestOptions: requestOptions,
          statusCode: 200,
          data: ResponseBody(bodyStream, 200),
        );
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async => response);

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        final combined = chunks
            .map((either) => either.getRight().toNullable() ?? '')
            .join();
        expect(combined, 'data: {"delta":"amã"}\n\n');
        expect(combined, isNot(contains('�')));
      },
    );

    test('a null response.data -> a single Left(MalformedResponse)', () async {
      final response = Response<ResponseBody>(
        requestOptions: requestOptions,
        statusCode: 200,
      );
      when(
        () => mockDio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => response);

      final chunks = await apiClient
          .postStream('chat-messages-send', data: {'content': 'hi'})
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.isLeft(), isTrue);
      chunks.single.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test(
      'a DioException with no response at all -> Left(NetworkOffline), same '
      'mapping as the non-streaming methods',
      () async {
        final dioError = DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.connectionError,
        );
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(dioError);

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        expect(chunks, hasLength(1));
        chunks.single.match(
          (failure) => expect(failure, isA<NetworkOffline>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test(
      'a non-2xx response whose body is a stream-typed ResponseBody still '
      'decodes {code, message} into the matching Failure (dio never '
      'auto-parses a stream response body into a Map, even on error)',
      () async {
        final errorBodyStream = Stream<Uint8List>.fromIterable([
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'code': 'RATE_LIMITED',
                'message': 'Too many requests',
                'retryable': true,
              }),
            ),
          ),
        ]);
        final errorResponse = Response<ResponseBody>(
          requestOptions: requestOptions,
          statusCode: 429,
          data: ResponseBody(errorBodyStream, 429),
        );
        final dioError = DioException(
          requestOptions: requestOptions,
          response: errorResponse,
          type: DioExceptionType.badResponse,
        );
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(dioError);

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        expect(chunks, hasLength(1));
        chunks.single.match((failure) {
          expect(failure, isA<RateLimited>());
          expect(failure.retryable, isTrue);
        }, (_) => fail('expected Left'));
      },
    );

    test(
      'a non-2xx response whose body cannot be decoded as {code, message} '
      'falls back to the generic mapping, never throwing',
      () async {
        final errorBodyStream = Stream<Uint8List>.fromIterable([
          Uint8List.fromList(utf8.encode('not json at all')),
        ]);
        final errorResponse = Response<ResponseBody>(
          requestOptions: requestOptions,
          statusCode: 500,
          data: ResponseBody(errorBodyStream, 500),
        );
        final dioError = DioException(
          requestOptions: requestOptions,
          response: errorResponse,
          type: DioExceptionType.badResponse,
        );
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(dioError);

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        expect(chunks, hasLength(1));
        chunks.single.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );

    test(
      'a non-DioException thrown by dio -> Left(MalformedResponse), never a '
      'crash',
      () async {
        when(
          () => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ),
        ).thenThrow(StateError('unexpected native failure'));

        final chunks = await apiClient
            .postStream('chat-messages-send', data: {'content': 'hi'})
            .toList();

        expect(chunks, hasLength(1));
        chunks.single.match(
          (failure) => expect(failure, isA<MalformedResponse>()),
          (_) => fail('expected Left'),
        );
      },
    );
  });
}
