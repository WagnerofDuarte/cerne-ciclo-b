import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/account/data/datasources/account_remote_data_source.dart';
import 'package:cerne/features/account/data/models/account_settings_dto.dart';
import 'package:cerne/features/account/data/repositories/account_settings_repository_impl.dart';

class MockAccountRemoteDataSource extends Mock
    implements AccountRemoteDataSource {}

/// Covers spec-2-4's I/O & Edge-Case Matrix exactly:
/// - boot fetch resolves `false`/`true` -> `currentBiometricEnabled`/
///   `biometricEnabledStream` updated.
/// - boot fetch fails -> swallowed, `currentBiometricEnabled` unchanged.
/// - toggle succeeds -> flips immediately, persists, no error.
/// - toggle fails -> reverts to the prior value, `Left(Failure)` returned
///   so the caller can surface its message.
void main() {
  late MockAccountRemoteDataSource mockRemoteDataSource;
  late AccountSettingsRepositoryImpl repository;

  setUp(() {
    mockRemoteDataSource = MockAccountRemoteDataSource();
    repository = AccountSettingsRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
    );
  });

  tearDown(() => repository.dispose());

  /// Same rationale as `vault_repository_impl_test.dart`'s own
  /// `emittedDuring` helper: `biometricEnabledStream` always synchronously
  /// replays the current value to a brand-new listener, so that replay is
  /// drained and discarded here first.
  Future<List<bool>> emittedDuring(Future<void> Function() act) async {
    final emitted = <bool>[];
    final subscription = repository.biometricEnabledStream.listen(emitted.add);
    await Future<void>.delayed(Duration.zero);
    emitted.clear();
    await act();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return emitted;
  }

  group('currentBiometricEnabled — starts true, never null (Boundaries)', () {
    test('currentBiometricEnabled is true before any fetch/toggle call', () {
      expect(repository.currentBiometricEnabled, isTrue);
    });

    test('a listener that subscribes before any call still immediately '
        'sees true, not nothing until the first emission (Stream.multi '
        'replay)', () async {
      final value = await repository.biometricEnabledStream.first;

      expect(value, isTrue);
    });
  });

  group('fetchBiometricEnabled() — boot fetch', () {
    test(
      'resolves false -> currentBiometricEnabled/stream update to false',
      () async {
        when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
          (_) async => right(
            const AccountSettingsDto(
              biometricEnabled: false,
              displayName: '',
              email: '',
            ),
          ),
        );

        Either<Failure, Unit>? result;
        final emitted = await emittedDuring(() async {
          result = await repository.fetchBiometricEnabled();
        });

        expect(emitted, [false]);
        expect(repository.currentBiometricEnabled, isFalse);
        expect(result!.isRight(), isTrue);
      },
    );

    test('resolves true -> currentBiometricEnabled/stream update to true '
        '(still true, but goes through the real emit path, not just the '
        'untouched default)', () async {
      when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: '',
            email: '',
          ),
        ),
      );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.fetchBiometricEnabled();
      });

      expect(emitted, [true]);
      expect(repository.currentBiometricEnabled, isTrue);
      expect(result!.isRight(), isTrue);
    });

    test('fails -> currentBiometricEnabled unchanged, no emission, '
        'Left(Failure) returned (swallowed by the caller, fire-and-forget '
        'like restoreSession())', () async {
      when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.fetchBiometricEnabled();
      });

      expect(emitted, isEmpty);
      expect(repository.currentBiometricEnabled, isTrue);
      expect(result!.isLeft(), isTrue);
    });
  });

  group('setBiometricEnabled() — optimistic toggle', () {
    test('succeeds -> flips immediately (before the PATCH call resolves) '
        'and stays flipped, Right(unit) returned', () async {
      final patchCompleter = Completer<Either<Failure, AccountSettingsDto>>();
      when(() => mockRemoteDataSource.updateBiometricEnabled(false))
          .thenAnswer((_) => patchCompleter.future);

      final emitted = <bool>[];
      final subscription = repository.biometricEnabledStream.listen(
        emitted.add,
      );
      await Future<void>.delayed(Duration.zero);
      emitted.clear();

      final resultFuture = repository.setBiometricEnabled(false);
      // The flip already happened synchronously, before the PATCH call's
      // own Future even resolves (RNF01, <100ms — Boundaries).
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentBiometricEnabled, isFalse);
      expect(emitted, [false]);

      patchCompleter.complete(
        right(
          const AccountSettingsDto(
            biometricEnabled: false,
            displayName: '',
            email: '',
          ),
        ),
      );
      final result = await resultFuture;
      await subscription.cancel();

      expect(result.isRight(), isTrue);
      expect(repository.currentBiometricEnabled, isFalse);
    });

    test('fails -> reverts to the prior value, Left(Failure) returned so '
        'the caller can show the message inline', () async {
      // Starts true (default) -> toggling to false, then the PATCH fails.
      when(() => mockRemoteDataSource.updateBiometricEnabled(false)).thenAnswer(
        (_) async =>
            left(const Failure.networkTimeout(message: 'fake: timed out')),
      );

      Either<Failure, Unit>? result;
      final emitted = await emittedDuring(() async {
        result = await repository.setBiometricEnabled(false);
      });

      // Optimistic flip to false, then reverted back to true.
      expect(emitted, [false, true]);
      expect(repository.currentBiometricEnabled, isTrue);
      expect(result!.isLeft(), isTrue);
      result!.match(
        (failure) => expect(failure, isA<NetworkTimeout>()),
        (_) => fail('expected Left'),
      );
    });

    test('calls the data source with exactly the requested value', () async {
      when(() => mockRemoteDataSource.updateBiometricEnabled(true)).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: '',
            email: '',
          ),
        ),
      );

      await repository.setBiometricEnabled(true);

      verify(() => mockRemoteDataSource.updateBiometricEnabled(true)).called(1);
    });
  });

  group('dispose()', () {
    test('closes the underlying stream — a subsequent fetch/toggle never '
        'throws trying to emit on a closed controller, the attempted emit '
        'is a silent no-op', () async {
      when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: false,
            displayName: '',
            email: '',
          ),
        ),
      );

      await repository.dispose();

      final result = await repository.fetchBiometricEnabled();

      expect(result.isRight(), isTrue);
      // The emit attempt was a no-op since the controller is already
      // closed — currentBiometricEnabled stays at whatever it was before
      // dispose() (still the default true).
      expect(repository.currentBiometricEnabled, isTrue);
    });

    test('a subsequent setBiometricEnabled() also never throws trying to '
        'emit on a closed controller — covers the optimistic-flip side of '
        'the same guard, not just fetchBiometricEnabled()\'s', () async {
      when(() => mockRemoteDataSource.updateBiometricEnabled(false)).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: false,
            displayName: '',
            email: '',
          ),
        ),
      );

      await repository.dispose();

      final result = await repository.setBiometricEnabled(false);

      expect(result.isRight(), isTrue);
      // Both the optimistic flip and the (here, unreached) revert path
      // attempt to emit on an already-closed controller — a silent no-op,
      // same as fetchBiometricEnabled()'s own case above.
      expect(repository.currentBiometricEnabled, isTrue);
    });
  });

  group('overlapping calls — only the latest one\'s result ever applies '
      '(review finding)', () {
    test('a fetchBiometricEnabled() that resolves after a later '
        'setBiometricEnabled() has already started is discarded as stale '
        '— it must not clobber the newer optimistic flip', () async {
      final fetchCompleter = Completer<Either<Failure, AccountSettingsDto>>();
      when(() => mockRemoteDataSource.fetchSettings())
          .thenAnswer((_) => fetchCompleter.future);
      when(() => mockRemoteDataSource.updateBiometricEnabled(false)).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: false,
            displayName: '',
            email: '',
          ),
        ),
      );

      // The boot fetch starts first and is held pending...
      final fetchFuture = repository.fetchBiometricEnabled();

      // ...then a toggle starts and completes while the fetch is still in
      // flight, flipping (and confirming) the value to false.
      final toggleResult = await repository.setBiometricEnabled(false);
      expect(toggleResult.isRight(), isTrue);
      expect(repository.currentBiometricEnabled, isFalse);

      // The stale fetch now resolves with a DIFFERENT value (true) — if
      // it were applied, it would wrongly stomp the toggle's already-
      // confirmed false.
      fetchCompleter.complete(
        right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: '',
            email: '',
          ),
        ),
      );
      final fetchResult = await fetchFuture;

      expect(repository.currentBiometricEnabled, isFalse);
      // Review finding: a stale fetch must not report success either —
      // its own result was discarded, mirroring `setBiometricEnabled`'s
      // stale-generation branch.
      expect(fetchResult.isLeft(), isTrue);
    });

    test('an older setBiometricEnabled() call that resolves after a newer '
        'overlapping one has already settled must not revert/confirm on '
        'top of it (double-tap)', () async {
      final firstPatchCompleter =
          Completer<Either<Failure, AccountSettingsDto>>();
      when(() => mockRemoteDataSource.updateBiometricEnabled(false))
          .thenAnswer((_) => firstPatchCompleter.future);
      when(() => mockRemoteDataSource.updateBiometricEnabled(true)).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: '',
            email: '',
          ),
        ),
      );

      // First toggle (to false) starts and is held pending.
      final firstResultFuture = repository.setBiometricEnabled(false);
      expect(repository.currentBiometricEnabled, isFalse);

      // A second, overlapping toggle (back to true) starts and completes
      // first — this is the newest call, so it owns the final value.
      final secondResult = await repository.setBiometricEnabled(true);
      expect(secondResult.isRight(), isTrue);
      expect(repository.currentBiometricEnabled, isTrue);

      // The first (now superseded) call's PATCH finally resolves — as a
      // failure, which would otherwise revert back to its own captured
      // "previous" value (true, the value before IT started). Even though
      // that happens to match here, the call must be recognized as
      // superseded and return `Left` rather than silently succeeding on a
      // value it no longer owns.
      firstPatchCompleter.complete(
        left(const Failure.networkTimeout(message: 'fake: too slow')),
      );
      final firstResult = await firstResultFuture;

      expect(firstResult.isLeft(), isTrue);
      // The second call's confirmed value must still be in effect,
      // untouched by the first (superseded) call's own resolution.
      expect(repository.currentBiometricEnabled, isTrue);
    });
  });

  // spec-8-3 — Boundaries: "fetchBiometricEnabled()'s success branch also
  // sets new _currentDisplayName/_currentEmail (default '') from that
  // response" — no new network call, piggybacking on the same DTO.
  group('currentDisplayName/currentEmail — start \'\', boot-fetch piggyback '
      '(spec-8-3)', () {
    test('currentDisplayName/currentEmail are \'\' before any fetch', () {
      expect(repository.currentDisplayName, '');
      expect(repository.currentEmail, '');
    });

    test('a successful fetchBiometricEnabled() also sets '
        'currentDisplayName/currentEmail from the same response', () async {
      when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Ana Silva',
            email: 'ana@example.com',
          ),
        ),
      );

      await repository.fetchBiometricEnabled();

      expect(repository.currentDisplayName, 'Ana Silva');
      expect(repository.currentEmail, 'ana@example.com');
    });

    test('a failed fetchBiometricEnabled() leaves currentDisplayName/'
        'currentEmail unchanged (swallowed, same as currentBiometricEnabled '
        'own rule)', () async {
      when(() => mockRemoteDataSource.fetchSettings()).thenAnswer(
        (_) async => left(const Failure.networkOffline(message: 'offline')),
      );

      await repository.fetchBiometricEnabled();

      expect(repository.currentDisplayName, '');
      expect(repository.currentEmail, '');
    });

    // Code-review patch: the piggybacked displayName/email write was only
    // guarded by `_generation` (the biometric field's own counter), never
    // by `_nameGeneration` — a stale fetch resolving after a concurrent
    // setDisplayName() already succeeded could silently clobber the
    // just-saved name back to this fetch's own (older) value. Mirrors the
    // existing "stale fetch must not clobber a confirmed toggle" test
    // above, but for the name/email piggyback.
    test('a fetchBiometricEnabled() that resolves after a concurrent '
        'setDisplayName() has already succeeded must not clobber the '
        'already-saved currentDisplayName/currentEmail', () async {
      final fetchCompleter = Completer<Either<Failure, AccountSettingsDto>>();
      when(
        () => mockRemoteDataSource.fetchSettings(),
      ).thenAnswer((_) => fetchCompleter.future);
      when(() => mockRemoteDataSource.updateDisplayName('New Name')).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'New Name',
            email: '',
          ),
        ),
      );

      // The boot fetch starts first and is held pending...
      final fetchFuture = repository.fetchBiometricEnabled();

      // ...then a name save starts and completes while the fetch is still
      // in flight, confirming the new name.
      final saveResult = await repository.setDisplayName('New Name');
      expect(saveResult.isRight(), isTrue);
      expect(repository.currentDisplayName, 'New Name');

      // The stale fetch now resolves with a DIFFERENT displayName — if
      // applied, it would wrongly stomp the already-confirmed 'New Name'.
      fetchCompleter.complete(
        right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Old Name',
            email: 'old@example.com',
          ),
        ),
      );
      await fetchFuture;

      expect(repository.currentDisplayName, 'New Name');
      // The fetch's own (unrelated) email piggyback is also skipped once
      // superseded — both fields move together, never half-applied.
      expect(repository.currentEmail, '');
    });
  });

  // spec-8-3 — setDisplayName's own I/O & Edge-Case Matrix slice: not
  // optimistic (Boundaries) — currentDisplayName only changes once the
  // PATCH actually succeeds, and a superseded overlapping call must not
  // clobber a newer one's already-settled value.
  group('setDisplayName() — not optimistic (spec-8-3)', () {
    test('succeeds -> currentDisplayName only changes once the PATCH '
        'resolves, Right(unit) returned', () async {
      final patchCompleter = Completer<Either<Failure, AccountSettingsDto>>();
      when(() => mockRemoteDataSource.updateDisplayName('Novo Nome'))
          .thenAnswer((_) => patchCompleter.future);

      final resultFuture = repository.setDisplayName('Novo Nome');
      // Unlike setBiometricEnabled's optimistic flip, nothing changes yet.
      await Future<void>.delayed(Duration.zero);
      expect(repository.currentDisplayName, '');

      patchCompleter.complete(
        right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Novo Nome',
            email: '',
          ),
        ),
      );
      final result = await resultFuture;

      expect(result.isRight(), isTrue);
      expect(repository.currentDisplayName, 'Novo Nome');
    });

    test('fails -> currentDisplayName stays unchanged, Left(Failure) '
        'returned so the caller can show the message inline', () async {
      when(() => mockRemoteDataSource.updateDisplayName('Novo Nome'))
          .thenAnswer(
            (_) async =>
                left(const Failure.networkTimeout(message: 'fake: timed out')),
          );

      final result = await repository.setDisplayName('Novo Nome');

      expect(repository.currentDisplayName, '');
      expect(result.isLeft(), isTrue);
      result.match(
        (failure) => expect(failure, isA<NetworkTimeout>()),
        (_) => fail('expected Left'),
      );
    });

    test('calls the data source with exactly the requested name', () async {
      when(() => mockRemoteDataSource.updateDisplayName('Novo Nome'))
          .thenAnswer(
            (_) async => right(
              const AccountSettingsDto(
                biometricEnabled: true,
                displayName: 'Novo Nome',
                email: '',
              ),
            ),
          );

      await repository.setDisplayName('Novo Nome');

      verify(() => mockRemoteDataSource.updateDisplayName('Novo Nome'))
          .called(1);
    });

    // Code-review patch: currentDisplayName must come from the response's
    // own echoed displayName, not the local `name` parameter that was
    // sent — any backend-side normalization (trimming, casing, etc.) must
    // be reflected locally rather than assuming the server stored exactly
    // what was sent.
    test('on success, currentDisplayName is set from the response\'s own '
        'echoed displayName, not the locally-sent name', () async {
      when(() => mockRemoteDataSource.updateDisplayName('  Novo Nome  '))
          .thenAnswer(
            (_) async => right(
              const AccountSettingsDto(
                biometricEnabled: true,
                // The backend normalized the sent name (trimmed it) before
                // echoing it back.
                displayName: 'Novo Nome',
                email: '',
              ),
            ),
          );

      final result = await repository.setDisplayName('  Novo Nome  ');

      expect(result.isRight(), isTrue);
      expect(repository.currentDisplayName, 'Novo Nome');
    });

    test('an older setDisplayName() call that resolves after a newer '
        'overlapping one has already settled must not clobber the newer '
        'one\'s confirmed value — own, separate generation counter from '
        'setBiometricEnabled\'s (Boundaries)', () async {
      final firstPatchCompleter =
          Completer<Either<Failure, AccountSettingsDto>>();
      when(() => mockRemoteDataSource.updateDisplayName('Primeiro'))
          .thenAnswer((_) => firstPatchCompleter.future);
      when(() => mockRemoteDataSource.updateDisplayName('Segundo')).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Segundo',
            email: '',
          ),
        ),
      );

      // First call starts and is held pending.
      final firstResultFuture = repository.setDisplayName('Primeiro');

      // A second, overlapping call starts and completes first.
      final secondResult = await repository.setDisplayName('Segundo');
      expect(secondResult.isRight(), isTrue);
      expect(repository.currentDisplayName, 'Segundo');

      // The first (now superseded) call's PATCH finally resolves as a
      // success — it must not clobber the second call's already-confirmed
      // value, and must report itself as superseded rather than success.
      firstPatchCompleter.complete(
        right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Primeiro',
            email: '',
          ),
        ),
      );
      final firstResult = await firstResultFuture;

      expect(firstResult.isLeft(), isTrue);
      expect(repository.currentDisplayName, 'Segundo');
    });

    test('a setDisplayName() call shares no generation counter with '
        'setBiometricEnabled() — an overlapping toggle must never supersede '
        'a name save, or vice versa (Boundaries: "kept separate")', () async {
      when(() => mockRemoteDataSource.updateDisplayName('Nome')).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: true,
            displayName: 'Nome',
            email: '',
          ),
        ),
      );
      when(() => mockRemoteDataSource.updateBiometricEnabled(false)).thenAnswer(
        (_) async => right(
          const AccountSettingsDto(
            biometricEnabled: false,
            displayName: '',
            email: '',
          ),
        ),
      );

      // A biometric toggle starts and completes first...
      await repository.setBiometricEnabled(false);
      // ...then the name save starts and completes — it must still
      // succeed, unaffected by the toggle's own, separate generation
      // counter.
      final nameResult = await repository.setDisplayName('Nome');

      expect(nameResult.isRight(), isTrue);
      expect(repository.currentDisplayName, 'Nome');
    });
  });
}
