import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/core/network/api_client.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';

import '../../../../support/write_failure_matrix_helper.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockAccessTokenProvider extends Mock implements AccessTokenProvider {}

Map<String, dynamic> _successBody({
  String userId = 'user-1',
  String email = 'wagner@cerne.app',
  String accessToken = 'access-token-abc',
}) =>
    {
      'data': {
        'session': {
          'accessToken': accessToken,
          'refreshToken': 'refresh-token-abc',
          'expiresIn': 3600,
          'expiresAt': 1999999999,
          'tokenType': 'bearer',
        },
        'user': {'id': userId, 'email': email},
      },
    };

void main() {
  late MockApiClient mockApiClient;
  late MockAccessTokenProvider mockAccessTokenProvider;
  late AuthRepositoryImpl repository;

  setUp(() {
    mockApiClient = MockApiClient();
    mockAccessTokenProvider = MockAccessTokenProvider();
    when(() => mockAccessTokenProvider.saveAccessToken(any()))
        .thenAnswer((_) async {});
    repository = AuthRepositoryImpl(
      remoteDataSource: AuthRemoteDataSource(mockApiClient),
      accessTokenProvider: mockAccessTokenProvider,
    );
  });

  // RNF09 — the 15-scenario matrix: this story's slice is `auth-signup` and
  // `auth-login`, 3 failure types each.
  runWriteFailureMatrix<AuthenticatedUser>(
    endpointName: 'auth-signup',
    stubNetworkTimeout: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => left(const Failure.networkTimeout(message: 'Timed out')),
    ),
    stubMalformedResponse: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => left(const Failure.networkOffline(message: 'Offline')),
    ),
    invoke: () => repository.signUp(
      email: 'wagner@cerne.app',
      password: 'segredo123',
    ),
  );

  runWriteFailureMatrix<AuthenticatedUser>(
    endpointName: 'auth-login',
    stubNetworkTimeout: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => left(const Failure.networkTimeout(message: 'Timed out')),
    ),
    stubMalformedResponse: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer((_) async => right({'unexpected': 'shape'})),
    stubNoConnection: () => when(
      () => mockApiClient.post(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => left(const Failure.networkOffline(message: 'Offline')),
    ),
    invoke: () => repository.logIn(
      email: 'wagner@cerne.app',
      password: 'segredo123',
    ),
  );

  group('AuthRepositoryImpl — success mapping and token persistence', () {
    test('signUp maps the DTO to AuthenticatedUser and saves the token '
        'before resolving', () async {
      when(() => mockApiClient.post('auth-signup', data: any(named: 'data')))
          .thenAnswer(
        (_) async => right(
          _successBody(
            userId: 'user-42',
            email: 'nova@cerne.app',
            accessToken: 'token-xyz',
          ),
        ),
      );

      final result = await repository.signUp(
        email: 'nova@cerne.app',
        password: 'segredo123',
      );

      expect(result.isRight(), isTrue);
      result.match(
        (_) => fail('expected Right'),
        (user) => expect(
          user,
          const AuthenticatedUser(id: 'user-42', email: 'nova@cerne.app'),
        ),
      );
      verify(() => mockAccessTokenProvider.saveAccessToken('token-xyz'))
          .called(1);
    });

    test('logIn posts exactly {email, password} to auth-login', () async {
      when(() => mockApiClient.post('auth-login', data: any(named: 'data')))
          .thenAnswer((_) async => right(_successBody()));

      await repository.logIn(
        email: 'wagner@cerne.app',
        password: 'segredo123',
      );

      final captured = verify(
        () => mockApiClient.post('auth-login', data: captureAny(named: 'data')),
      ).captured;
      expect(captured.single, {
        'email': 'wagner@cerne.app',
        'password': 'segredo123',
      });
    });

    test('a backend failure never saves a token', () async {
      when(() => mockApiClient.post('auth-login', data: any(named: 'data')))
          .thenAnswer(
        (_) async =>
            left(const Failure.authInvalid(message: 'Invalid credentials')),
      );

      final result = await repository.logIn(
        email: 'wagner@cerne.app',
        password: 'wrong',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<AuthInvalid>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockAccessTokenProvider.saveAccessToken(any()));
    });

    test(
        'a thrown exception while saving the token maps to '
        'Left(MalformedResponse) instead of escaping unmapped (RNF09)',
        () async {
      when(() => mockApiClient.post('auth-login', data: any(named: 'data')))
          .thenAnswer((_) async => right(_successBody()));
      when(() => mockAccessTokenProvider.saveAccessToken(any()))
          .thenThrow(Exception('secure storage unavailable'));

      final result = await repository.logIn(
        email: 'wagner@cerne.app',
        password: 'segredo123',
      );

      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });
}
