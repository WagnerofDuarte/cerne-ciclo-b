import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/network/access_token_provider.dart';
import 'package:cerne/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:cerne/features/auth/data/models/auth_response_dto.dart';
import 'package:cerne/features/auth/data/repositories/session_repository_impl.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';

import '../../../../support/mock_session_expiry_notifier.dart';

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
  late MockSessionExpiryNotifier mockSessionExpiryNotifier;
  late StreamController<void> expiryController;
  late SessionRepositoryImpl repository;

  setUp(() {
    mockRemoteDataSource = MockAuthRemoteDataSource();
    mockAccessTokenProvider = MockAccessTokenProvider();
    mockSessionExpiryNotifier = MockSessionExpiryNotifier();
    expiryController = StreamController<void>.broadcast();
    when(() => mockSessionExpiryNotifier.expiredEvents)
        .thenAnswer((_) => expiryController.stream);
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
      sessionExpiryNotifier: mockSessionExpiryNotifier,
    );
  });

  tearDown(() async {
    await expiryController.close();
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

    test('stored-but-empty refresh token -> treated the same as no token: '
        'no network call, stream emits unauthenticated', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => '');

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

  group('Story 1.6 — currentStatus / markAuthenticated', () {
    test('currentStatus is null before any emission', () {
      expect(repository.currentStatus, isNull);
    });

    test(
      'currentStatus mirrors the last value emitted on statusStream',
      () async {
        when(() => mockAccessTokenProvider.readRefreshToken())
            .thenAnswer((_) async => null);

        await repository.restoreSession();

        expect(repository.currentStatus, SessionStatus.unauthenticated);
      },
    );

    test('markAuthenticated() synchronously flips currentStatus to '
        'authenticated and emits it on statusStream, with no network/'
        'storage call', () async {
      final emitted = await emittedDuring(() async {
        repository.markAuthenticated();
      });

      expect(repository.currentStatus, SessionStatus.authenticated);
      expect(emitted, [SessionStatus.authenticated]);
      verifyNever(() => mockRemoteDataSource.refresh(any()));
      verifyNever(
        () => mockAccessTokenProvider.saveSession(
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      );
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

  group('logout() — Story 8.4', () {
    test('backend succeeds -> clearSession() called, stream emits '
        'unauthenticated, Right(unit) returned', () async {
      when(() => mockRemoteDataSource.logout())
          .thenAnswer((_) async => right(unit));

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.logout();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isRight(), isTrue);
      verify(() => mockAccessTokenProvider.clearSession()).called(1);
    });

    test('backend call fails (e.g. offline) -> clearSession() still called '
        'UNCONDITIONALLY, stream still emits unauthenticated — must work '
        'even offline (Boundaries)', () async {
      when(() => mockRemoteDataSource.logout()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'Offline')),
      );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.logout();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
      expect(result!.isLeft(), isTrue);
      verify(() => mockAccessTokenProvider.clearSession()).called(1);
    });

    test('clearSession() itself throwing never escapes unmapped (RNF09) — '
        'the stream still emits unauthenticated regardless', () async {
      when(() => mockRemoteDataSource.logout())
          .thenAnswer((_) async => right(unit));
      when(() => mockAccessTokenProvider.clearSession())
          .thenThrow(Exception('secure storage unavailable'));

      final emitted = await emittedDuring(() async {
        await repository.logout();
      });

      expect(emitted, [SessionStatus.unauthenticated]);
    });
  });

  group('Story 1.5 — SessionExpiryNotifier bridged onto statusStream', () {
    test('a mid-session expiry event while authenticated -> stream emits '
        'expired', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer((_) async => right(_newSession));

      final emitted = await emittedDuring(() async {
        await repository.restoreSession();
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
      });

      expect(emitted, [SessionStatus.authenticated, SessionStatus.expired]);
    });

    test('an expiry event while unauthenticated (post-logout race) is a '
        'silent no-op — no emission, no overlay', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => null);

      final emitted = await emittedDuring(() async {
        await repository.restoreSession();
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
      });

      expect(emitted, [SessionStatus.unauthenticated]);
    });

    test('an expiry event before restoreSession() has ever emitted (no '
        'current status yet) is a silent no-op', () async {
      final emitted = await emittedDuring(() async {
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
      });

      expect(emitted, isEmpty);
    });

    test('a second expiry event while already expired does not re-emit — the '
        "single-overlay guard holds at the repository's own stream, not only "
        'in the UI', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer((_) async => right(_newSession));

      final emitted = await emittedDuring(() async {
        await repository.restoreSession();
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
      });

      expect(emitted, [SessionStatus.authenticated, SessionStatus.expired]);
    });

    test('dispose() cancels the expiry subscription — a later event never '
        'reaches the (already-closed) statusStream', () async {
      when(() => mockAccessTokenProvider.readRefreshToken())
          .thenAnswer((_) async => 'stored-refresh-token');
      when(() => mockRemoteDataSource.refresh('stored-refresh-token'))
          .thenAnswer((_) async => right(_newSession));

      final emitted = await emittedDuring(() async {
        await repository.restoreSession();
        await repository.dispose();
        // If `dispose()` ever stopped cancelling `_expirySubscription`,
        // this would still reach `_onSessionExpired()` and — since
        // `_lastStatus` is still `authenticated` — attempt to `_emit()`
        // `expired`. The `isClosed` guard in `_emit()` would swallow that
        // silently, so only actually observing `statusStream` (not just
        // asserting `add()` doesn't throw) can tell the two apart.
        expiryController.add(null);
        await Future<void>.delayed(Duration.zero);
      });

      expect(emitted, [SessionStatus.authenticated]);
    });
  });
}
