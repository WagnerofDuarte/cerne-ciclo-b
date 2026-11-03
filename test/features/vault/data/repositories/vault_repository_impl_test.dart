import 'dart:async';

import 'package:flutter/widgets.dart';
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
///
/// Plus spec-2-3's own additions (see the dedicated
/// `didChangeAppLifecycleState() — idle re-authentication` group below):
/// idle re-lock after backgrounding for >= 5 minutes while unlocked, no
/// re-lock below the threshold, no duplicate emission while already
/// locked, and no crash on a bare `resumed` with no prior `paused`.
void main() {
  // Story 2.3's constructor now calls `WidgetsBinding.instance.
  // addObserver(this)` — unlike the rest of this file's plain `test()`
  // blocks (no `testWidgets`, which would initialize this implicitly), the
  // binding needs explicit, idempotent initialization up front.
  TestWidgetsFlutterBinding.ensureInitialized();

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

  // Each VaultRepositoryImpl registers itself as a WidgetsBindingObserver
  // in its constructor (Story 2.3) — dispose() here removes it again so a
  // stale observer doesn't linger on the shared
  // TestWidgetsFlutterBinding.instance across test runs.
  tearDown(() => repository.dispose());

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

    test('authenticate() throws LocalAuthException with an OS-lockout '
        'code (biometricLockout) -> same fail-closed outcome as any '
        'other LocalAuthException, no code-specific branch (AC2: no '
        'second biometric-retry affordance, always routes to the PIN '
        'fallback)', () async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenThrow(
        const LocalAuthException(
          code: LocalAuthExceptionCode.biometricLockout,
        ),
      );

      final result = await repository.authenticate();

      expect(repository.currentStatus, VaultStatus.locked);
      expect(result.isLeft(), isTrue);
      result.match(
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

    test('a superseded (stale) call -- one whose own UI-level timeout '
        'already fired and was retried -- never writes its PIN or emits '
        'unlocked once it finally resolves (review finding: the UI '
        "timeout only stops waiting, it doesn't cancel this call)", () async {
      final firstRead = Completer<String?>();
      final secondRead = Completer<String?>();
      final pendingReads = [firstRead, secondRead];
      when(
        () => mockSecureStorage.read(key: any(named: 'key')),
      ).thenAnswer((_) => pendingReads.removeAt(0).future);
      when(
        () => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      final emitted = <VaultStatus>[];
      final subscription = repository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      // The first call's `read()` is still pending (simulating a hang)
      // when the caller retries with a second call.
      final firstResultFuture = repository.submitPin('1111');
      final secondResultFuture = repository.submitPin('2222');

      // The retry's own read resolves first and completes normally.
      secondRead.complete(null);
      final secondResult = await secondResultFuture;
      await Future<void>.delayed(Duration.zero);
      expect(secondResult.isRight(), isTrue);
      verify(
        () => mockSecureStorage.write(key: 'vault_pin', value: '2222'),
      ).called(1);
      expect(repository.currentStatus, VaultStatus.unlocked);
      expect(emitted, [VaultStatus.unlocked]);
      emitted.clear();

      // The original (now superseded) call finally resolves -- must be a
      // no-op: no write with the stale PIN, no re-emission.
      firstRead.complete(null);
      final firstResult = await firstResultFuture;
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(firstResult.isLeft(), isTrue);
      verifyNever(
        () => mockSecureStorage.write(key: 'vault_pin', value: '1111'),
      );
      expect(emitted, isEmpty);
      expect(repository.currentStatus, VaultStatus.unlocked);
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

  /// Covers spec-2-3's I/O & Edge-Case Matrix exactly, via a repository
  /// built with an injectable fake clock — no real `WidgetsBinding`
  /// lifecycle event or device/simulator needed (AGENTS.md: none exists
  /// yet). `didChangeAppLifecycleState` is called directly since it's a
  /// public override.
  group('didChangeAppLifecycleState() — idle re-authentication (spec-2-3)', () {
    late DateTime currentTime;
    late VaultRepositoryImpl idleRepository;

    setUp(() {
      currentTime = DateTime(2026, 1, 1, 12);
      idleRepository = VaultRepositoryImpl(
        localAuthentication: mockLocalAuthentication,
        secureStorage: mockSecureStorage,
        now: () => currentTime,
      );
      // Review finding: the outer-level `repository` (built in the
      // top-level `setUp` above) also registers itself as a
      // WidgetsBindingObserver on this same shared
      // TestWidgetsFlutterBinding.instance, but no test in this group uses
      // it — disposed immediately so only `idleRepository` receives this
      // group's lifecycle dispatches, instead of both silently. The
      // top-level `tearDown`'s own `repository.dispose()` call afterward is
      // then a safe no-op repeat.
      repository.dispose();
    });

    // Same observer-leak rationale as the top-level tearDown above — this
    // group constructs its own repository instance per test.
    tearDown(() => idleRepository.dispose());

    Future<void> unlockRepository() async {
      when(
        () => mockLocalAuthentication.authenticate(
          localizedReason: any(named: 'localizedReason'),
          biometricOnly: any(named: 'biometricOnly'),
          persistAcrossBackgrounding: any(named: 'persistAcrossBackgrounding'),
        ),
      ).thenAnswer((_) async => true);
      await idleRepository.authenticate();
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    }

    test('backgrounded < 5 min, then resumed -> currentStatus stays '
        'unlocked, no emission', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 4));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    });

    test('backgrounded >= 5 min, then resumed -> statusStream emits '
        'locked, currentStatus flips to locked', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 5));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [VaultStatus.locked]);
      expect(idleRepository.currentStatus, VaultStatus.locked);
    });

    test('backgrounded >= 5 min while already locked -> stays locked, no '
        'duplicate emission', () async {
      // Never unlocked in this test — currentStatus starts at locked
      // (VaultStatus's own default).
      expect(idleRepository.currentStatus, VaultStatus.locked);

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 10));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.locked);
    });

    test('driven through the real WidgetsBinding dispatch path (not a '
        'direct method call) -> still re-locks after >= 5 min, proving '
        'the constructor\'s addObserver(this) wiring is actually in '
        'effect, not just the override logic in isolation', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      currentTime = currentTime.add(const Duration(minutes: 5));
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, [VaultStatus.locked]);
      expect(idleRepository.currentStatus, VaultStatus.locked);
    });

    test('backgrounded 4 minutes 59 seconds, then resumed -> still below '
        'the 5-minute threshold, currentStatus stays unlocked, no '
        'emission (pins the >= boundary tightly, one second short)', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(
        const Duration(minutes: 4, seconds: 59),
      );
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    });

    test('inactive and hidden are ignored on their own -> no emission, '
        'currentStatus stays unlocked, _backgroundedAt neither set nor '
        'read (Boundaries: inactive/hidden are not "backgrounded" on '
        'their own)', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.inactive);
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.hidden);
      currentTime = currentTime.add(const Duration(minutes: 10));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.inactive);
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    });

    test('a second paused fires before any resumed -> keeps the earliest '
        'timestamp rather than resetting it, so elapsed is still measured '
        'from the first paused (review finding)', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 4));
      // A second `paused` fires without an intervening `resumed` (e.g. a
      // lifecycle quirk) -- must not reset the clock to this later time.
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 1));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      // Total elapsed since the FIRST paused is 5 minutes -- must re-lock.
      // (Elapsed from the second paused alone would only be 1 minute.)
      expect(emitted, [VaultStatus.locked]);
      expect(idleRepository.currentStatus, VaultStatus.locked);
    });

    test('authenticate() succeeds while still backgrounded (a persisted '
        'call resolving mid-background) resets the idle clock -> resumed '
        'afterward does not immediately re-lock, even past the threshold '
        '(review finding)', () async {
      // Starts locked -- unlocks below while already `paused`, simulating
      // persistAcrossBackgrounding: true resolving during a long call.
      expect(idleRepository.currentStatus, VaultStatus.locked);

      idleRepository.didChangeAppLifecycleState(AppLifecycleState.paused);
      currentTime = currentTime.add(const Duration(minutes: 3));
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      // Total elapsed since the ORIGINAL paused is now 6 minutes (past the
      // threshold), but the mid-background unlock above should have reset
      // the clock -- no re-lock expected.
      currentTime = currentTime.add(const Duration(minutes: 3));
      idleRepository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    });

    test('resumed fires with no prior paused -> no-op, no emission, no '
        'crash', () async {
      await unlockRepository();

      final emitted = <VaultStatus>[];
      final subscription = idleRepository.statusStream.listen(emitted.add);
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      expect(
        () => idleRepository.didChangeAppLifecycleState(
          AppLifecycleState.resumed,
        ),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, isEmpty);
      expect(idleRepository.currentStatus, VaultStatus.unlocked);
    });
  });
}
