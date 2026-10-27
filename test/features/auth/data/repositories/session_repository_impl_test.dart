import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/models/auth_response_dto.dart';
import 'package:cerne/features/auth/data/repositories/session_repository_impl.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockAccessTokenProvider extends Mock implements AccessTokenProvider {}

const _newSession = AuthSessionDto(
  accessToken: 'new-access-token',
  refreshToken: 'new-refresh-token',
  expiresIn: 3600,
  expiresAt: 1999999999,
  tokenType: 'bearer',
);

void main() {
  late MockAuthRemoteDataSource mockRemoteDataSource;
  late MockAccessTokenProvider mockAccessTokenProvider;
  late SessionRepositoryImpl repository;

  setUp(() {
    mockRemoteDataSource = MockAuthRemoteDataSource();
    mockAccessTokenProvider = MockAccessTokenProvider();
    when(
      () => mockAccessTokenProvider.saveSession(
        accessToken: any(named: 'accessToken'),
        refreshToken: any(named: 'refreshToken'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockAccessTokenProvider.clearSession()).thenAnswer((_) async {});
    repository = SessionRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      accessTokenProvider: mockAccessTokenProvider,
    );
  });

  /// Subscribes before [restoreSession] runs (required for a broadcast
  /// stream) and drains the microtask queue afterwards so the event posted
  /// by `_statusController.add(...)` has definitely been delivered by the
  /// time this returns — same rationale as `auth_cubit_test.dart`'s
  /// `_emittedDuring` helper.
  Future<List<SessionStatus>> emittedDuring(Future<void> Function() act) async {
    final emitted = <SessionStatus>[];
    final subscription = repository.statusStream.listen(emitted.add);
    await act();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return emitted;
  }

  group('cold boot, valid refresh token', () {
    test('auth-refresh succeeds -> new pair saved, stream emits '
        'authenticated, Right(unit) returned', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer((_) async => right(_newSession));

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.authenticated]);
      expect(result!.isRight(), isTrue);
      verify(
        () => mockAccessTokenProvider.saveSession(
          accessToken: 'new-access-token',
          refreshToken: 'new-refresh-token',
        ),
      ).called(1);
      verifyNever(() => mockAccessTokenProvider.clearSession());
    });
  });

  group('cold boot, no stored session', () {
    test('no refresh token -> no network call, stream emits unauthenticated '
        'immediately', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => null);

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<AuthExpired>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockRemoteDataSource.refresh(any()));
      verifyNever(
        () => mockAccessTokenProvider.saveSession(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      );
      verifyNever(() => mockAccessTokenProvider.clearSession());
    });
  });

  group('cold boot, dead refresh token', () {
    test(
      'backend returns AUTH_EXPIRED -> session cleared, stream emits '
      'unauthenticated, silently (Left surfaced to the caller only)',
      () async {
        when(() => mockAccessTokenProvider.readRefreshToken())
            .thenAnswer((_) async => 'dead-refresh-token');
        when(
          () => mockRemoteDataSource.refresh('dead-refresh-token'),
        ).thenAnswer(
          (_) async =>
              left(const Failure.authExpired(message: 'Refresh token dead')),
        );

        Either<Failure, Unit>? result;
        final emitted = await emittedDuring(() async {
          result = await repository.restoreSession();
        });

        expect(emitted, [SessionStatus.unauthenticated]);
        expect(result!.isLeft(), isTrue);
        result!.match(
          (failure) => expect(failure, isA<AuthExpired>()),
          (_) => fail('expected Left'),
        );
        verify(() => mockAccessTokenProvider.clearSession()).called(1);
      },
    );

    test('backend returns AUTH_INVALID -> session cleared, stream emits '
        'unauthenticated', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'invalid-refresh-token');
      when(
        () => mockRemoteDataSource.refresh('invalid-refresh-token'),
      ).thenAnswer(
        (_) async =>
            left(const Failure.authInvalid(message: 'Refresh token invalid')),
      );

      final emitted = await emittedDuring(() async {
        await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      verify(() => mockAccessTokenProvider.clearSession()).called(1);
    });
  });

  group('statusStream replay semantics', () {
    test('a listener that subscribes AFTER restoreSession() has already '
        'emitted still immediately sees the current status, not nothing '
        'until the next change', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => null);

      await repository.restoreSession();

      // No prior subscription here — this is the late-joining listener
      // `Stream.multi` replay exists for.
      final status = await repository.statusStream.first;

      expect(status, SessionStatus.unauthenticated);
    });
  });

  group('platform exceptions never escape unmapped (RNF09)', () {
    test('readRefreshToken() throws -> Left(MalformedResponse), stream emits '
        'unauthenticated, no network call', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenThrow(Exception('secure storage unavailable'));

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
      verifyNever(() => mockRemoteDataSource.refresh(any()));
    });

    test('saveSession() throws after a successful refresh -> '
        'Left(MalformedResponse), stream emits unauthenticated', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer((_) async => right(_newSession));
      when(
        () => mockAccessTokenProvider.saveSession(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenThrow(Exception('secure storage unavailable'));

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('cold boot, offline', () {
    test('no connectivity -> stream emits unauthenticated (fail-closed), '
        'storage left untouched', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer(
            (_) async => left(const Failure.networkOffline(message: 'Offline')),
          );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.restoreSession();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<NetworkOffline>()),
        (_) => fail('expected Left'),
      );
      // Fail-closed, but the stored token is NOT cleared — only a
      // backend-confirmed dead token (AUTH_EXPIRED/AUTH_INVALID) clears it.
      verifyNever(() => mockAccessTokenProvider.clearSession());
    });
  });
}
