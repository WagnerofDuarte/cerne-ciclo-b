import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/account/domain/repositories/account_settings_repository.dart';
import 'package:cerne/features/account/presentation/cubit/account_settings_cubit.dart';

/// A plain (non-mocktail) fake — same rationale as `vault_lock_screen_test.
/// dart`'s own `_FakeVaultRepository`: this suite needs a scriptable
/// `setBiometricEnabled()` result plus a real stream the cubit actually
/// subscribes to, which a mocktail stub can't give as naturally.
class _FakeAccountSettingsRepository implements AccountSettingsRepository {
  bool _value = true;
  final _controller = StreamController<bool>.broadcast();

  /// The next `setBiometricEnabled()` call's own result — defaults to a
  /// failure so a test must opt in to the success path explicitly.
  Either<Failure, Unit> setBiometricEnabledResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );

  int setBiometricEnabledCallCount = 0;

  // spec-8-3 — a scriptable profile-name slice, same rationale
  // [setBiometricEnabledResult] already gives for the toggle: a test must
  // opt in to a non-default [currentDisplayName]/[currentEmail] or a
  // [setDisplayNameResult] success explicitly.
  @override
  String currentDisplayName = '';
  @override
  String currentEmail = '';
  Either<Failure, Unit> setDisplayNameResult = left(
    const Failure.malformedResponse(message: 'fake: not configured'),
  );
  int setDisplayNameCallCount = 0;
  String? lastSetDisplayNameArg;

  /// Lets a test hold `setDisplayName()` unresolved, to observe
  /// `state.isSavingName` mid-flight — same rationale
  /// `account_settings_screen_test.dart`'s own `setBiometricEnabledGate`
  /// already gives for the toggle.
  Completer<void>? setDisplayNameGate;

  @override
  Future<Either<Failure, Unit>> setDisplayName(String name) async {
    setDisplayNameCallCount += 1;
    lastSetDisplayNameArg = name;
    final gate = setDisplayNameGate;
    if (gate != null) {
      await gate.future;
    }
    return setDisplayNameResult;
  }

  @override
  bool get currentBiometricEnabled => _value;

  @override
  Stream<bool> get biometricEnabledStream {
    return Stream<bool>.multi((controller) {
      controller.add(_value);
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  @override
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async => right(unit);

  @override
  Future<Either<Failure, Unit>> setBiometricEnabled(bool enabled) async {
    setBiometricEnabledCallCount += 1;
    final previous = _value;
    _emit(enabled);
    final result = setBiometricEnabledResult;
    if (result.isLeft()) {
      _emit(previous);
    }
    return result;
  }

  @override
  Future<void> dispose() => _controller.close();

  void _emit(bool value) {
    _value = value;
    _controller.add(value);
  }
}

Future<List<AccountSettingsState>> _emittedDuring(
  AccountSettingsCubit cubit,
  Future<void> Function() act,
) async {
  final emitted = <AccountSettingsState>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  // `pumpEventQueue()` (not a single `Future.delayed(Duration.zero)`): the
  // `biometricEnabled` mirror travels repository -> Stream.multi's own
  // forwarding subscription -> cubit's `emit()` -> `_stateController`,
  // several microtask hops deep — one `Duration.zero` delay only guarantees
  // draining one hop, leaving a later hop's delivery to land after this
  // helper already returned.
  await pumpEventQueue();
  await subscription.cancel();
  return emitted;
}

void main() {
  late _FakeAccountSettingsRepository fakeRepository;

  setUp(() {
    fakeRepository = _FakeAccountSettingsRepository();
  });

  group('initial state', () {
    test('mirrors currentBiometricEnabled (true) at construction', () async {
      final cubit = AccountSettingsCubit(fakeRepository);

      expect(cubit.state.biometricEnabled, isTrue);
      expect(cubit.state.errorMessage, isNull);
      await cubit.close();
    });

    test('mirrors a false currentBiometricEnabled (e.g. already fetched '
        'before the screen opened)', () async {
      fakeRepository._emit(false);
      final cubit = AccountSettingsCubit(fakeRepository);

      expect(cubit.state.biometricEnabled, isFalse);
      await cubit.close();
    });
  });

  group('toggleBiometric() — success', () {
    test('flips to the new value and clears any prior error, calling the '
        'repository with exactly the requested value', () async {
      fakeRepository.setBiometricEnabledResult = right(unit);
      final cubit = AccountSettingsCubit(fakeRepository);

      final emitted = await _emittedDuring(
        cubit,
        () => cubit.toggleBiometric(false),
      );

      expect(emitted.last.biometricEnabled, isFalse);
      expect(emitted.last.errorMessage, isNull);
      expect(fakeRepository.setBiometricEnabledCallCount, 1);
      await cubit.close();
    });
  });

  group('toggleBiometric() — failure', () {
    test('the switch reverts (mirrored from the repository\'s own revert) '
        'and the Failure\'s message is surfaced', () async {
      fakeRepository.setBiometricEnabledResult = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );
      final cubit = AccountSettingsCubit(fakeRepository);
      // Drains the constructor's own subscription-replay of the current
      // value (Stream.multi's replay goes through its own forwarding
      // subscription, several microtask hops deep) before the capture
      // window below starts — otherwise that replay (allowed through by
      // Cubit's own "first emit always goes through" rule) can land
      // mid-capture as a spurious extra entry. `pumpEventQueue()` drains
      // repeatedly until the queue is empty, rather than a single
      // `Future.delayed(Duration.zero)` which only guarantees one hop.
      await pumpEventQueue();

      final emitted = await _emittedDuring(
        cubit,
        () => cubit.toggleBiometric(false),
      );

      // Two independent emission paths feed `emitted` here: the
      // `biometricEnabled` flip/revert mirrors the repository's own stream
      // (several `Stream.multi` forwarding hops deep), while the
      // `errorMessage` update is `toggleBiometric()`'s own direct `emit()`
      // (one hop). Their relative *order* isn't guaranteed by either path's
      // own contract, so asserting an exact sequence would pin an
      // implementation accident, not a behavior the spec requires — what
      // the I/O matrix actually requires (and what's asserted below) is
      // that the optimistic flip to `false` was visible at some point, and
      // that the settled end state reverted to `true` with the `Failure`'s
      // message surfaced.
      expect(emitted.map((s) => s.biometricEnabled), contains(false));
      expect(emitted.last.biometricEnabled, isTrue);
      expect(emitted.last.errorMessage, 'Sem conexão');
      expect(cubit.state.biometricEnabled, isTrue);
      expect(cubit.state.errorMessage, 'Sem conexão');
      await cubit.close();
    });

    test(
      'a later successful toggle clears the previous error message',
      () async {
        fakeRepository.setBiometricEnabledResult = left(
          const Failure.networkTimeout(message: 'Sem conexão'),
        );
        final cubit = AccountSettingsCubit(fakeRepository);
        await cubit.toggleBiometric(false);
        // `toggleBiometric()`'s own await only guarantees its direct
        // `setBiometricEnabled()` Future resolved — the `biometricEnabled`
        // mirror it emits travels back through the repository's
        // `Stream.multi` forwarding subscription, several microtask hops
        // behind that Future; drain those before asserting on `cubit.state`
        // (same rationale as `_emittedDuring`'s own `pumpEventQueue()`).
        await pumpEventQueue();
        expect(cubit.state.errorMessage, 'Sem conexão');

        fakeRepository.setBiometricEnabledResult = right(unit);
        await cubit.toggleBiometric(true);
        await pumpEventQueue();

        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.biometricEnabled, isTrue);
        await cubit.close();
      },
    );
  });

  // spec-8-3 — Boundaries: "Cubit reads displayName/email from the
  // repository at construction".
  group('initial state — displayName/email (spec-8-3)', () {
    test('mirrors currentDisplayName/currentEmail at construction', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.currentEmail = 'ana@example.com';
      final cubit = AccountSettingsCubit(fakeRepository);

      expect(cubit.state.displayName, 'Ana Silva');
      expect(cubit.state.email, 'ana@example.com');
      expect(cubit.state.isEditingName, isFalse);
      await cubit.close();
    });
  });

  // spec-8-3 — the full I/O & Edge-Case Matrix for the inline name edit.
  group('startEditingName()', () {
    test('switches to edit mode with draft = current name, clearing any '
        'leftover error (I/O matrix: "Tap pencil")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = AccountSettingsCubit(fakeRepository);

      cubit.startEditingName();

      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.nameDraft, 'Ana Silva');
      expect(cubit.state.nameErrorMessage, isNull);
      await cubit.close();
    });
  });

  group('updateNameDraft()', () {
    test(
      'updates nameDraft without touching isEditingName/displayName',
      () async {
        final cubit = AccountSettingsCubit(fakeRepository);
        cubit.startEditingName();

        cubit.updateNameDraft('Novo Nome');

        expect(cubit.state.nameDraft, 'Novo Nome');
        expect(cubit.state.isEditingName, isTrue);
        expect(cubit.state.displayName, fakeRepository.currentDisplayName);
        await cubit.close();
      },
    );
  });

  group('confirmEditingName() — empty/unchanged draft', () {
    test('an unchanged draft reverts immediately, no PATCH sent (I/O '
        'matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });

    test('an all-whitespace (trims to empty) draft reverts immediately, no '
        'PATCH sent', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('   ');

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });
  });

  group('confirmEditingName() — changed non-empty draft, success', () {
    test('saves (trimmed), shows a saving indicator mid-flight, then '
        'reverts to display mode with the new name (I/O matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = right(unit);
      fakeRepository.setDisplayNameGate = Completer<void>();
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('  Nome Novo  ');

      final confirmFuture = cubit.confirmEditingName();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSavingName, isTrue);
      expect(cubit.state.isEditingName, isTrue);

      fakeRepository.setDisplayNameGate!.complete();
      await confirmFuture;

      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Nome Novo');
      expect(cubit.state.nameErrorMessage, isNull);
      expect(fakeRepository.lastSetDisplayNameArg, 'Nome Novo');
      await cubit.close();
    });
  });

  group('confirmEditingName() — failure', () {
    test('stays editing with the draft kept and an inline error (I/O '
        'matrix)', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = left(
        const Failure.networkTimeout(message: 'Sem conexão'),
      );
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');

      await cubit.confirmEditingName();

      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.nameDraft, 'Nome Novo');
      expect(cubit.state.nameErrorMessage, 'Sem conexão');
      // The display name itself is untouched by a failed save.
      expect(cubit.state.displayName, 'Ana Silva');
      await cubit.close();
    });

    test('the superseded-call message is suppressed, same convention as '
        'toggleBiometric\'s own failure branch', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = left(
        const Failure.malformedResponse(
          message: AccountSettingsRepository.supersededMessage,
        ),
      );
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');

      await cubit.confirmEditingName();

      expect(cubit.state.isSavingName, isFalse);
      expect(cubit.state.nameErrorMessage, isNull);
      await cubit.close();
    });
  });

  group('cancelEditingName()', () {
    test('not saving -> reverts immediately, no PATCH sent (I/O matrix: '
        '"Tap away, not saving")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('Rascunho descartado');

      cubit.cancelEditingName();

      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Ana Silva');
      expect(fakeRepository.setDisplayNameCallCount, 0);
      await cubit.close();
    });

    test('a no-op while saving — the in-flight confirm owns the eventual '
        'transition (I/O matrix: "Tap away, saving")', () async {
      fakeRepository.currentDisplayName = 'Ana Silva';
      fakeRepository.setDisplayNameResult = right(unit);
      fakeRepository.setDisplayNameGate = Completer<void>();
      final cubit = AccountSettingsCubit(fakeRepository);
      cubit.startEditingName();
      cubit.updateNameDraft('Nome Novo');
      final confirmFuture = cubit.confirmEditingName();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.isSavingName, isTrue);

      cubit.cancelEditingName();

      // Still editing/saving — the cancel call above was a no-op.
      expect(cubit.state.isEditingName, isTrue);
      expect(cubit.state.isSavingName, isTrue);

      fakeRepository.setDisplayNameGate!.complete();
      await confirmFuture;

      // The save completes normally, unaffected by the earlier no-op
      // cancel attempt.
      expect(cubit.state.isEditingName, isFalse);
      expect(cubit.state.displayName, 'Nome Novo');
      await cubit.close();
    });
  });
}
