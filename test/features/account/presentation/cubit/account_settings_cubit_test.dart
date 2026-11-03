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
  Future<Either<Failure, Unit>> fetchBiometricEnabled() async =>
      right(unit);

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

    test('a later successful toggle clears the previous error message',
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
    });
  });
}
