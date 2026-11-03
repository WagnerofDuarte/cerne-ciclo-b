import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';

/// Same shape as `app_router_test.dart`'s own `_FakeVaultRepository` — a
/// plain fake (not mocktail) so `authenticate()`'s resolution can be held
/// open with a `Completer`, which this suite needs to observe the screen's
/// mid-flight state, plus a scriptable `submitPin()` for the PIN-flow
/// cases (spec-2-2).
class _FakeVaultRepository implements VaultRepository {
  VaultStatus _status = VaultStatus.locked;
  final _controller = StreamController<VaultStatus>.broadcast();

  /// Controls what the NEXT `authenticate()` call resolves to. Defaults to
  /// `false` (a quiet decline), matching `app_router_test.dart`'s own
  /// default so a bare `pumpWidget` never silently unlocks.
  bool authenticateSucceeds = false;

  /// Lets a test hold `authenticate()` unresolved to inspect a mid-flight
  /// frame before letting it settle.
  Completer<void>? authenticateGate;

  int authenticateCallCount = 0;

  /// The one PIN `submitPin()` treats as "stored" — `null` means no PIN
  /// has been stored yet, matching `VaultRepositoryImpl`'s own set-on-
  /// first-use behavior (spec-2-2 Design Notes).
  String? storedPin;

  int submitPinCallCount = 0;

  /// Lets a test hold `submitPin()` unresolved — mirrors
  /// [authenticateGate]'s own rationale, used to prove `VaultLockScreen`'s
  /// re-entrancy guard against a fast second PIN entry firing a second
  /// concurrent call.
  Completer<void>? submitPinGate;

  @override
  VaultStatus get currentStatus => _status;

  @override
  Stream<VaultStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> authenticate() async {
    authenticateCallCount += 1;
    final gate = authenticateGate;
    if (gate != null) {
      await gate.future;
    }
    if (authenticateSucceeds) {
      _status = VaultStatus.unlocked;
      _controller.add(_status);
      return right(unit);
    }
    return left(
      const Failure.malformedResponse(message: 'fake: biometrics declined'),
    );
  }

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async {
    submitPinCallCount += 1;
    final gate = submitPinGate;
    if (gate != null) {
      await gate.future;
    }
    if (storedPin == null) {
      storedPin = pin;
      _status = VaultStatus.unlocked;
      _controller.add(_status);
      return right(unit);
    }
    if (storedPin == pin) {
      _status = VaultStatus.unlocked;
      _controller.add(_status);
      return right(unit);
    }
    return left(
      const Failure.malformedResponse(message: 'fake: PIN mismatch'),
    );
  }

  @override
  Future<void> dispose() => _controller.close();
}

Widget _wrap(VaultRepository vaultRepository) {
  return MaterialApp(
    home: VaultLockScreen(vaultRepository: vaultRepository),
  );
}

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit));
    await tester.pump();
  }
  // Auto-advance fires 350ms after the 4th digit (UX-DR14).
  await tester.pump(const Duration(milliseconds: 350));
}

/// End-to-end widget coverage for the epic's one lock screen
/// (spec-2-1 + spec-2-2) — `app_router_test.dart` already proves the
/// *routing* consequences of `VaultStatus` (AD-14); this suite proves the
/// screen's own user-visible flow in isolation: auto-prompt on mount, the
/// biometric-failure -> PIN-keypad transition (never a "Tentar novamente"
/// affordance), the "Usar PIN" direct path, and PIN submission itself.
void main() {
  late _FakeVaultRepository fakeVaultRepository;

  setUp(() {
    fakeVaultRepository = _FakeVaultRepository();
  });

  tearDown(() => fakeVaultRepository.dispose());

  testWidgets(
    'mounts -> auto-triggers authenticate() exactly once, with no user '
    'interaction',
    (tester) async {
      await tester.pumpWidget(_wrap(fakeVaultRepository));
      await tester.pumpAndSettle();

      expect(fakeVaultRepository.authenticateCallCount, 1);
    },
  );

  testWidgets(
    'while authenticate() is still pending, the biometric copy is shown '
    'and "Usar PIN" is already reachable',
    (tester) async {
      fakeVaultRepository.authenticateGate = Completer<void>();

      await tester.pumpWidget(_wrap(fakeVaultRepository));
      await tester.pump();

      expect(find.text('Cerne bloqueado'), findsOneWidget);
      expect(find.text('Usar PIN'), findsOneWidget);
      expect(find.text('Digite seu PIN'), findsNothing);

      fakeVaultRepository.authenticateGate!.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'authenticate() succeeds on mount -> stays on the biometric view, no '
    'exception, status flips to unlocked',
    (tester) async {
      fakeVaultRepository.authenticateSucceeds = true;

      await tester.pumpWidget(_wrap(fakeVaultRepository));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Digite seu PIN'), findsNothing);
      expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
    },
  );

  group('AC1/AC2 — biometric failure falls through to the PIN keypad', () {
    testWidgets(
      'authenticate() declines on mount -> PIN keypad shown with the '
      'failure error band, never a "Tentar novamente" affordance, vault '
      'stays locked',
      (tester) async {
        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(
          find.text('Não foi possível reconhecer — digite seu PIN'),
          findsOneWidget,
        );
        expect(find.text('Tentar novamente'), findsNothing);
        expect(fakeVaultRepository.currentStatus, VaultStatus.locked);
      },
    );

    testWidgets(
      'an OS-lockout failure (any authenticate() Left) routes to the same '
      'PIN keypad as a plain decline — no code-specific branch, no '
      'biometric-retry affordance ever offered',
      (tester) async {
        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(find.byType(ElevatedButton), findsNothing);
      },
    );
  });

  group('"Usar PIN" reachable directly, pre-failure', () {
    testWidgets(
      'tapping "Usar PIN" while authenticate() is still pending shows the '
      'PIN keypad immediately, with no error band',
      (tester) async {
        fakeVaultRepository.authenticateGate = Completer<void>();

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pump();

        await tester.tap(find.text('Usar PIN'));
        await tester.pump();

        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(
          find.text('Não foi possível reconhecer — digite seu PIN'),
          findsNothing,
        );

        // The pending authenticate() call later failing must not clobber
        // the keypad with an error band the user never caused.
        fakeVaultRepository.authenticateGate!.complete();
        await tester.pumpAndSettle();

        expect(
          find.text('Não foi possível reconhecer — digite seu PIN'),
          findsNothing,
        );
      },
    );
  });

  group('submitPin flow', () {
    testWidgets(
      'no PIN stored yet -> entering 4 digits stores it as the new PIN '
      'and unlocks the vault',
      (tester) async {
        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();
        expect(find.text('Digite seu PIN'), findsOneWidget);

        await _enterPin(tester, '1234');
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.storedPin, '1234');
        expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
      },
    );

    testWidgets(
      'stored PIN matches -> unlocks the vault',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        await _enterPin(tester, '1234');
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
      },
    );

    testWidgets(
      'stored PIN mismatch -> stays locked, shows a mismatch error band, '
      'and the keypad is still usable for another attempt (never a dead '
      'end)',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        await _enterPin(tester, '0000');
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.currentStatus, VaultStatus.locked);
        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(
          find.text('PIN incorreto. Tente novamente.'),
          findsOneWidget,
        );
        expect(fakeVaultRepository.submitPinCallCount, 1);

        // No attempt cap — a second, correct attempt right after still
        // succeeds.
        await _enterPin(tester, '1234');
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
        expect(fakeVaultRepository.submitPinCallCount, 2);
      },
    );

    testWidgets(
      'a fast second PIN entry landing while the first submitPin() call '
      'is still pending never fires a second concurrent call '
      '(re-entrancy guard)',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';
        fakeVaultRepository.submitPinGate = Completer<void>();

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        // First entry: auto-advances and calls submitPin(), which then
        // suspends on the gate.
        await _enterPin(tester, '1234');
        expect(fakeVaultRepository.submitPinCallCount, 1);
        expect(fakeVaultRepository.currentStatus, VaultStatus.locked);

        // PinKeypad has already cleared its own buffer by this point, so
        // a second 4-digit entry lands and auto-advances again while the
        // first call is still gated — the guard must swallow it before it
        // ever reaches the repository.
        await _enterPin(tester, '1234');
        expect(fakeVaultRepository.submitPinCallCount, 1);

        fakeVaultRepository.submitPinGate!.complete();
        await tester.pumpAndSettle();

        expect(fakeVaultRepository.currentStatus, VaultStatus.unlocked);
      },
    );
  });
}
