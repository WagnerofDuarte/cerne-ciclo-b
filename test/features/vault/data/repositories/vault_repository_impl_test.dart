import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';

class MockLocalAuthentication extends Mock implements LocalAuthentication {}

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// Covers spec-2-1's I/O & Edge-Case Matrix exactly:
/// - biometrics succeed -> `unlocked` emitted, `Right(unit)`.
/// - biometrics fail/cancelled/unavailable (`false` or a thrown
///   `LocalAuthException`) -> status stays `locked`,
///   `Left(Failure.malformedResponse(...))`, no crash.
///
/// Plus spec-2-2's own additions:
/// - `submitPin`, no PIN stored yet -> stores it, `unlocked`, `Right(unit)`.
/// - `submitPin`, stored PIN matches -> `unlocked`, `Right(unit)`.
/// - `submitPin`, stored PIN mismatch -> stays `locked`,
///   `Left(Failure.malformedResponse(...))`, no attempt cap.
void main() {
  late MockLocalAuthentication mockLocalAuthentication;
  late MockFlutterSecureStorage mockSecureStorage;
  late VaultRepositoryImpl repository;

  setUp(() {
    mockLocalAuthentication = MockLocalAuthentication();
    mockSecureStorage = MockFlutterSecureStorage();
    repository = VaultRepositoryImpl(
      localAuthentication: mockLocalAuthentication,
      secureStorage: mockSecureStorage,
    );
  });

  /// Same rationale as `session_repository_impl_test.dart`'s own
  /// `emittedDuring` helper, with one difference: unlike
  /// `SessionRepository.statusStream` (nullable, no replay until the first
  /// emission), [VaultRepository.statusStream] always synchronously
  /// replays the current (never-null) [VaultStatus] to a brand-new
  /// listener — so the first element this helper's subscription ever sees
  /// is always that initial replay, not an emission caused by [act]. It's
  /// drained and discarded here so the returned list reflects only
  /// emissions [act] itself caused.
  Future<List<VaultStatus>> emittedDuring(
    Future<void> Function() act,
  ) async {
    final emitted = <VaultStatus>[];
    final subscription = repository.statusStream.listen(emitted.add);
    await Future<void>.delayed(Duration.zero);
    emitted.clear();
    await act();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return emitted;
  }

  group('VaultStatus.currentStatus — non-nullable, known at construction', () {
    test('currentStatus is VaultStatus.locked before any authenticate() '
        'call — no async warm-up, unlike SessionStatus (Design Notes)', () {
      expect(repository.currentStatus, VaultStatus.locked);
    });

    test('a listener that subscribes before any authenticate() call still '
        'immediately sees VaultStatus.locked, not nothing until the first '
        'emission (Stream.multi replay, mirrors SessionRepositoryImpl)', () async {
      final status = await repository.statusStream.first;

      expect(status, VaultStatus.locked);
    });
  });

  group('cold start, biometrics succeed', () {
    test('authenticate() returns true -> statusStream emits unlocked, '
        'currentStatus flips to unlocked, Right(unit) returned', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.authenticate();
      });

      expect(emitted, [VaultStatus.unlocked]);
      expect(repository.currentStatus, VaultStatus.unlocked);
      expect(result!.isRight(), isTrue);
    });

    test('authenticate() is called with biometricOnly: true — Boundaries: '
        '"never set biometricOnly: false" — so the OS\'s own device '
        'passcode screen never silently satisfies it', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);

      await repository.authenticate();

      verify(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: true,
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).called(1);
    });
  });

  group('cold start, biometrics fail/cancelled/unavailable', () {
    test('authenticate() returns false -> status stays locked, no '
        'emission, Left(Failure.malformedResponse), never '
        'Failure.authInvalid (Boundaries: reserved for password login)', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => false);

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.authenticate();
      });

      expect(emitted, isEmpty);
      expect(repository.currentStatus, VaultStatus.locked);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('authenticate() throws LocalAuthException (e.g. user cancelled) '
        '-> status stays locked, no emission, Left(Failure.'
        'malformedResponse), no crash (RNF09: never let a platform '
        'exception escape unmapped)', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenThrow(
        const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
      );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.authenticate();
      });

      expect(emitted, isEmpty);
      expect(repository.currentStatus, VaultStatus.locked);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );
    });

    test('authenticate() throws LocalAuthException for no enrolled '
        'biometrics -> same fail-closed outcome as any other '
        'LocalAuthException', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenThrow(
        const LocalAuthException(
          code: LocalAuthExceptionCode.noBiometricsEnrolled,
        ),
      );

      final result = await repository.authenticate();

      expect(repository.currentStatus, VaultStatus.locked);
      expect(result.isLeft(), isTrue);
    });

    test('authenticate() throws a plain (non-LocalAuthException) '
        'exception (e.g. the plugin channel itself failing) -> same '
        'fail-closed outcome, Left(Failure.malformedResponse), no crash '
        '(RNF09: never let a platform exception escape unmapped)', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenThrow(Exception('plugin channel failed'));

      final result = await repository.authenticate();

      expect(repository.currentStatus, VaultStatus.locked);
      expect(result.isLeft(), isTrue);
    });
  });

  group('submitPin() — spec-2-2', () {
    test('no PIN stored yet -> stores the submitted PIN, statusStream '
        'emits unlocked, currentStatus flips to unlocked, Right(unit) '
        'returned (no PIN-creation screen exists anywhere in '
        'docs/input/ — Design Notes)', () async {
      when(
        () => mockSecureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);
      when(
        () => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.submitPin('1234');
      });

      verify(
        () => mockSecureStorage.write(key: 'vault_pin', value: '1234'),
      ).called(1);
      expect(emitted, [VaultStatus.unlocked]);
      expect(repository.currentStatus, VaultStatus.unlocked);
      expect(result!.isRight(), isTrue);
    });

    test('stored PIN matches -> statusStream emits unlocked, '
        'currentStatus flips to unlocked, Right(unit) returned', () async {
      when(
        () => mockSecureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => '1234');

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.submitPin('1234');
      });

      verifyNever(
        () => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
      expect(emitted, [VaultStatus.unlocked]);
      expect(repository.currentStatus, VaultStatus.unlocked);
      expect(result!.isRight(), isTrue);
    });

    test('stored PIN mismatch -> status stays locked, no emission, '
        'Left(Failure.malformedResponse(...)), never Failure.authInvalid '
        '(Boundaries: reserved for password login), no attempt cap — '
        'always retryable', () async {
      when(
        () => mockSecureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => '1234');

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.submitPin('9999');
      });

      expect(emitted, isEmpty);
      expect(repository.currentStatus, VaultStatus.locked);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<MalformedResponse>()),
        (_) => fail('expected Left'),
      );

      // No attempt cap — a second mismatched attempt behaves identically,
      // still retryable, never a dead end.
      final secondResult = await repository.submitPin('0000');
      expect(repository.currentStatus, VaultStatus.locked);
      expect(secondResult.isLeft(), isTrue);
    });

    test('secure-storage throws on read -> Left(Failure.'
        'malformedResponse), status stays locked, no crash (RNF09: never '
        'let a platform exception escape unmapped)', () async {
      when(
        () => mockSecureStorage.read(key: any(named: 'key')),
      ).thenThrow(Exception('keychain unavailable'));

      final result = await repository.submitPin('1234');

      expect(repository.currentStatus, VaultStatus.locked);
      expect(result.isLeft(), isTrue);
    });
  });

  group('dispose()', () {
    test('closes the underlying stream — a subsequent authenticate() '
        'success never throws trying to emit on a closed controller '
        '(mirrors SessionRepositoryImpl\'s isClosed guard); the attempted '
        'emit is a silent no-op, so currentStatus stays at whatever it '
        'was before dispose() even though authenticate() itself still '
        'resolves Right(unit)', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);

      await repository.dispose();

      final result = await repository.authenticate();

      expect(result.isRight(), isTrue);
      expect(repository.currentStatus, VaultStatus.locked);
    });
  });
}
