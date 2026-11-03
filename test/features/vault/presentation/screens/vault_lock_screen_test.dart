import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';
import 'package:cerne/features/vault/presentation/widgets/pin_keypad.dart';

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

  /// The `Failure.message` the next failing `authenticate()` call
  /// returns — lets a test simulate a distinctly-flavored failure (e.g.
  /// an OS-lockout code) while still exercising the real production
  /// behavior, which maps every `LocalAuthException`/`false` result to
  /// the same generic `Failure.malformedResponse` with no code-specific
  /// branch (review finding: proves the "same routing regardless of
  /// flavor" claim instead of only asserting it by comment).
  String authenticateFailureMessage = 'fake: biometrics declined';

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
    return left(Failure.malformedResponse(message: authenticateFailureMessage));
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
      'an OS-lockout-flavored failure (a distinct Failure.message, same '
      'as a plain decline from VaultRepositoryImpl\'s point of view) '
      'routes to the same PIN keypad — no code-specific branch, no '
      'biometric-retry affordance ever offered',
      (tester) async {
        // Production code never branches on the failure's flavor — every
        // `LocalAuthException`/`false` result maps to the same generic
        // `Failure.malformedResponse` (vault_repository_impl.dart). Using
        // a distinct message here (rather than reusing the plain-decline
        // default) proves this test isn't just a duplicate of the one
        // above under a different name.
        fakeVaultRepository.authenticateFailureMessage =
            'fake: biometricLockout';

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(
          find.text('Não foi possível reconhecer — digite seu PIN'),
          findsOneWidget,
        );
        expect(find.byType(ElevatedButton), findsNothing);
        expect(fakeVaultRepository.currentStatus, VaultStatus.locked);
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

        // The screen wires `enabled: !_submittingPin` down to PinKeypad
        // itself while the call is pending — checked directly here rather
        // than only inferred from the call count staying at 1 below,
        // since that count would stay flat either way (the screen-level
        // `_submittingPin` early-return guards it too).
        expect(
          tester.widget<PinKeypad>(find.byType(PinKeypad)).enabled,
          isFalse,
        );

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

  group('submitPin() timeout (review finding: a hung call must never be a '
      'dead end)', () {
    testWidgets(
      'a submitPin() that never resolves times out after 10s, shows a '
      'retryable timeout message, and does not leave the keypad '
      'permanently disabled',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';
        fakeVaultRepository.submitPinGate = Completer<void>();

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        await _enterPin(tester, '1234');
        expect(fakeVaultRepository.submitPinCallCount, 1);

        // Still within the 10s bound — no timeout message yet, keypad
        // still disabled while the call is pending.
        await tester.pump(const Duration(seconds: 9, milliseconds: 900));
        expect(
          find.text('Não foi possível verificar o PIN. Tente novamente.'),
          findsNothing,
        );
        expect(
          tester.widget<PinKeypad>(find.byType(PinKeypad)).enabled,
          isFalse,
        );

        // Past the 10s bound.
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          find.text('Não foi possível verificar o PIN. Tente novamente.'),
          findsOneWidget,
        );
        expect(fakeVaultRepository.currentStatus, VaultStatus.locked);

        // `_submittingPin` was reset to false in the `finally` clause even
        // though the underlying call is still hung — the keypad is
        // re-enabled and a fresh entry is accepted, not stuck forever.
        expect(
          tester.widget<PinKeypad>(find.byType(PinKeypad)).enabled,
          isTrue,
        );
        await _enterPin(tester, '1234');
        expect(fakeVaultRepository.submitPinCallCount, 2);

        fakeVaultRepository.submitPinGate!.complete();
        await tester.pumpAndSettle();
      },
    );
  });

  group('AC3 — screen-reader announcements are actually observed', () {
    // Review finding: every existing assertion above only reads the
    // visible `Text` widgets, so a deleted/broken `_announce()` call (or
    // an inverted `shouldAnnounceFailure` guard) would still pass every
    // test in this file. These mock `SystemChannels.accessibility`
    // directly — the channel `SemanticsService.sendAnnouncement` sends
    // on — to assert the real announcement content.
    List<String> interceptAnnouncements(WidgetTester tester) {
      final messages = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<
        dynamic
      >(SystemChannels.accessibility, (dynamic call) async {
        final event = call as Map<dynamic, dynamic>;
        if (event['type'] == 'announce') {
          final data = event['data'] as Map<dynamic, dynamic>;
          messages.add(data['message'] as String);
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<dynamic>(
              SystemChannels.accessibility,
              null,
            ),
      );
      return messages;
    }

    testWidgets(
      'a biometric failure on mount sends the fallback message as a real '
      'screen-reader announcement',
      (tester) async {
        final announcements = interceptAnnouncements(tester);

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        expect(
          announcements,
          contains('Não foi possível reconhecer — digite seu PIN'),
        );
      },
    );

    testWidgets(
      'a PIN mismatch sends the mismatch message as a real screen-reader '
      'announcement',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';
        final announcements = interceptAnnouncements(tester);

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        await _enterPin(tester, '0000');
        await tester.pumpAndSettle();

        expect(announcements, contains('PIN incorreto. Tente novamente.'));
      },
    );

    testWidgets(
      'a submitPin() timeout sends the timeout message as a real '
      'screen-reader announcement',
      (tester) async {
        fakeVaultRepository.storedPin = '1234';
        fakeVaultRepository.submitPinGate = Completer<void>();
        final announcements = interceptAnnouncements(tester);

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pumpAndSettle();

        await _enterPin(tester, '1234');
        await tester.pump(const Duration(seconds: 10, milliseconds: 1));

        expect(
          announcements,
          contains('Não foi possível verificar o PIN. Tente novamente.'),
        );

        fakeVaultRepository.submitPinGate!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'tapping "Usar PIN" before any biometric failure sends no '
      'announcement at all',
      (tester) async {
        fakeVaultRepository.authenticateGate = Completer<void>();
        final announcements = interceptAnnouncements(tester);

        await tester.pumpWidget(_wrap(fakeVaultRepository));
        await tester.pump();

        await tester.tap(find.text('Usar PIN'));
        await tester.pump();

        expect(announcements, isEmpty);

        fakeVaultRepository.authenticateGate!.complete();
        await tester.pumpAndSettle();

        // The pending authenticate() resolving after the user already
        // escaped to the keypad manually must not announce anything
        // either (same "already on keypad" guard as the other assertions
        // for this path).
        expect(announcements, isEmpty);
      },
    );
  });
}
