import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/navigation/placeholder_screens.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/vault/domain/entities/vault_status.dart';
import 'package:cerne/features/vault/domain/repositories/vault_repository.dart';
import 'package:cerne/features/vault/presentation/screens/vault_lock_screen.dart';
import 'package:cerne/main.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// A plain (non-mocktail) fake — the overlay/router tests below need
/// [currentStatus] to reflect whatever [setStatus] last set, read
/// synchronously by the router's `redirect`, while also actually emitting
/// on [statusStream] so both the router's `refreshListenable` and
/// `ExpiryOverlayHost`'s own subscription react — the same reason
/// `app_router_test.dart` uses one instead of a mocktail stub.
class _FakeSessionRepository implements SessionRepository {
  _FakeSessionRepository({Either<Failure, Unit>? restoreSessionResult})
    : _restoreSessionResult = restoreSessionResult ?? right(unit);

  final Either<Failure, Unit> _restoreSessionResult;
  SessionStatus? _status;
  final _controller = StreamController<SessionStatus>.broadcast();

  @override
  SessionStatus? get currentStatus => _status;

  @override
  Stream<SessionStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> restoreSession() async => _restoreSessionResult;

  @override
  void markAuthenticated() => setStatus(SessionStatus.authenticated);

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(SessionStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// A plain (non-mocktail) fake for [VaultRepository], same rationale as
/// [_FakeSessionRepository] above. [authenticateSucceeds] defaults to
/// `false` so mounting `VaultLockScreen` — which auto-calls [authenticate]
/// once in `initState` — never silently unlocks the vault on its own;
/// [setStatus] stays the single, explicit way a test flips vault state.
class _FakeVaultRepository implements VaultRepository {
  _FakeVaultRepository({VaultStatus initialStatus = VaultStatus.unlocked})
    : _status = initialStatus;

  VaultStatus _status;
  final _controller = StreamController<VaultStatus>.broadcast();
  bool authenticateSucceeds = false;

  /// The one PIN `submitPin()` treats as "stored" (spec-2-2) — `null`
  /// means no PIN has been stored yet, mirroring `VaultRepositoryImpl`'s
  /// own set-on-first-use behavior.
  String? storedPin;

  @override
  VaultStatus get currentStatus => _status;

  @override
  Stream<VaultStatus> get statusStream => _controller.stream;

  @override
  Future<Either<Failure, Unit>> authenticate() async {
    if (authenticateSucceeds) {
      setStatus(VaultStatus.unlocked);
      return right(unit);
    }
    return left(
      const Failure.malformedResponse(message: 'fake: biometrics declined'),
    );
  }

  @override
  Future<Either<Failure, Unit>> submitPin(String pin) async {
    if (storedPin == null || storedPin == pin) {
      storedPin = pin;
      setStatus(VaultStatus.unlocked);
      return right(unit);
    }
    return left(const Failure.malformedResponse(message: 'fake: PIN mismatch'));
  }

  @override
  Future<void> dispose() => _controller.close();

  void setStatus(VaultStatus status) {
    _status = status;
    _controller.add(status);
  }
}

/// Proves the one real production composition root — `CerneApp` resolving
/// `sl<AuthCubit>()`/`sl<SessionRepository>()`/`sl<VaultRepository>()`,
/// building the one `go_router` (Story 1.6; AD-14's vault gate), and
/// wrapping it with `ExpiryOverlayHost` — actually works end to end. Every
/// other test either stops at DI registration
/// (`bootstrap_integration_test.dart`) or supplies its own
/// `AuthCubit`/`onAuthenticated` (`auth_screen_test.dart`), so neither
/// exercises `main.dart`'s own wiring.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  final fakeNativeStorage = <String, String>{};

  Future<dynamic> handleSecureStorageCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>;
    switch (call.method) {
      case 'write':
        fakeNativeStorage[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return fakeNativeStorage[args['key'] as String];
      case 'delete':
        fakeNativeStorage.remove(args['key'] as String);
        return null;
      case 'containsKey':
        return fakeNativeStorage.containsKey(args['key'] as String);
      default:
        return null;
    }
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          secureStorageChannel,
          handleSecureStorageCall,
        );
    await resetCoreDependencies();
    await setupCoreDependencies();
    // `setupCoreDependencies()` registers the real `VaultRepositoryImpl`
    // (backed by the actual `local_auth` plugin, with no platform channel
    // mocked here) — swapped for a fake pre-`unlocked` one so every
    // existing auth/session test case (which predates AD-14's vault gate)
    // is unaffected; a test that wants to exercise the vault gate itself
    // swaps this for its own locked fake.
    sl.unregister<VaultRepository>();
    sl.registerLazySingleton<VaultRepository>(
      () => _FakeVaultRepository(),
      dispose: (repository) => repository.dispose(),
    );
    // `ConfirmationDialog.isOpen` is a static single-overlay guard (shared
    // across every instance by design, Story 1.5) — reset it so one test's
    // unclosed dialog never leaks into the next.
    ConfirmationDialog.isOpen = false;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await resetCoreDependencies();
  });

  testWidgets(
    'CerneApp resolves the real AuthCubit and navigates to / (the real '
    'Home/Chat placeholder) once onAuthenticated fires',
    (tester) async {
      final mockAuthRepository = MockAuthRepository();
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => right(const AuthenticatedUser(id: 'u1', email: 'a@b.com')),
      );

      // Swaps only the repository, before AuthCubit's first resolution, so
      // CerneApp's own `sl<AuthCubit>()` lookup and the real
      // `SessionRepository.markAuthenticated()` run unchanged.
      sl.unregister<AuthRepository>();
      sl.registerLazySingleton<AuthRepository>(() => mockAuthRepository);

      await tester.pumpWidget(const CerneApp());
      // Lets the real `SessionRepository.restoreSession()` boot call (no
      // stored refresh token in the fake secure-storage channel, so it
      // resolves to `unauthenticated` with no network call) settle before
      // interacting with `AuthScreen`.
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
      expect(find.text('Bem-vindo de volta'), findsNothing);
    },
  );

  testWidgets(
    'CerneApp resolves the real AuthCubit and navigates to / once signup '
    'succeeds, with the toggle-to-signup path exercised through the real '
    'composition root (only the login path was covered here before)',
    (tester) async {
      final mockAuthRepository = MockAuthRepository();
      when(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u2', email: 'nova@b.com')),
      );

      sl.unregister<AuthRepository>();
      sl.registerLazySingleton<AuthRepository>(() => mockAuthRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Não tem conta? Criar conta'));
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'nova@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Criar conta'));
      await tester.pumpAndSettle();

      verify(
        () => mockAuthRepository.signUp(
          email: 'nova@b.com',
          password: 'segredo123',
        ),
      ).called(1);
      expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
      expect(find.text('Crie sua conta'), findsNothing);
    },
  );

  testWidgets('CerneApp lands on the Home/Chat placeholder when the session '
      'repository already reports authenticated, with no AuthScreen ever '
      'shown', (tester) async {
    final fakeSessionRepository = _FakeSessionRepository()
      ..setStatus(SessionStatus.authenticated);
    addTearDown(fakeSessionRepository.dispose);

    sl.unregister<SessionRepository>();
    sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

    await tester.pumpWidget(const CerneApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);
  });

  testWidgets(
    'CerneApp lands on AuthScreen when the session repository reports '
    'unauthenticated',
    (tester) async {
      final fakeSessionRepository = _FakeSessionRepository()
        ..setStatus(SessionStatus.unauthenticated);
      addTearDown(fakeSessionRepository.dispose);

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.byType(HomeChatPlaceholderScreen), findsNothing);
    },
  );

  testWidgets(
    'BootSplashScreen stays blank below the 300ms threshold and shows a '
    'spinner once past it, while the session status is not yet known',
    (tester) async {
      final fakeSessionRepository = _FakeSessionRepository();
      addTearDown(fakeSessionRepository.dispose);

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => fakeSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 299));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  group(
    'Story 1.5 — expired-session recovery overlay (now go_router-based)',
    () {
      testWidgets('an expired emission shows the overlay over the same screen '
          '(Home/Chat placeholder never replaced, stays visible under it)', (
        tester,
      ) async {
        final fakeSessionRepository = _FakeSessionRepository();
        addTearDown(fakeSessionRepository.dispose);
        sl.unregister<SessionRepository>();
        sl.registerLazySingleton<SessionRepository>(
          () => fakeSessionRepository,
        );

        await tester.pumpWidget(const CerneApp());
        fakeSessionRepository.setStatus(SessionStatus.authenticated);
        await tester.pumpAndSettle();

        expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
        expect(find.text('Sessão expirada'), findsNothing);

        fakeSessionRepository.setStatus(SessionStatus.expired);
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
        // The underlying screen is still mounted and visible underneath the
        // overlay — it was never navigated away from or rebuilt as a
        // different widget (Boundaries: Story 1.5 behavior unchanged).
        expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
      });

      testWidgets(
        'a second expired emission while the overlay is already open never '
        'stacks a second dialog',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsOneWidget);
        },
      );

      testWidgets(
        '"Entrar novamente" dismisses the overlay and routes to /reauth '
        '(the biometric/PIN placeholder)',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          await tester.tap(find.text('Entrar novamente'));
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsNothing);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );

      testWidgets(
        'after "Entrar novamente" is confirmed, a later rebuild while the '
        'session status is still expired does not reopen the overlay on top '
        'of the placeholder it already routed to',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();

          await tester.tap(find.text('Entrar novamente'));
          await tester.pumpAndSettle();
          expect(find.text('Biometria'), findsOneWidget);

          // Simulates a rebuild that isn't driven by a new stream event
          // while the session status is still `expired` — pumping the same
          // root widget again updates the existing `_CerneAppState` in
          // place (same type, no key) rather than remounting it, forcing
          // `build()` to re-run exactly as a parent rebuild would. Without
          // the overlay's own one-shot-per-episode guard, that re-run would
          // reopen it on top of the placeholder the user already navigated
          // to.
          await tester.pumpWidget(const CerneApp());
          await tester.pumpAndSettle();

          expect(find.text('Sessão expirada'), findsNothing);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );

      testWidgets(
        'tapping "Entrar novamente" twice in quick succession before its '
        'exit fade settles does not throw and routes to /reauth only once',
        (tester) async {
          final fakeSessionRepository = _FakeSessionRepository();
          addTearDown(fakeSessionRepository.dispose);
          sl.unregister<SessionRepository>();
          sl.registerLazySingleton<SessionRepository>(
            () => fakeSessionRepository,
          );

          await tester.pumpWidget(const CerneApp());
          fakeSessionRepository.setStatus(SessionStatus.authenticated);
          await tester.pumpAndSettle();

          fakeSessionRepository.setStatus(SessionStatus.expired);
          await tester.pumpAndSettle();
          expect(find.text('Sessão expirada'), findsOneWidget);

          // `tapAt` the same screen offset twice, with only `pump()` (not
          // `pumpAndSettle()`) between taps, so the second one lands while
          // the dialog's own exit fade/teardown is still in flight — the
          // exact window `_reauthRouteRequested` guards against (code
          // review, Story 1.6). `tapAt` (rather than re-resolving
          // `find.text(...)`) tolerates the button no longer being present
          // by the second tap without failing the test on that alone.
          final confirmButtonCenter = tester.getCenter(
            find.text('Entrar novamente'),
          );
          await tester.tapAt(confirmButtonCenter);
          await tester.pump();
          await tester.tapAt(confirmButtonCenter);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Biometria'), findsOneWidget);
        },
      );
    },
  );

  group('AD-14 — VaultStatus gate composed ahead of SessionStatus (spec-2-1)', () {
    testWidgets(
      'cold start stays on /vault (VaultLockScreen) until a fake '
      'authenticate() success flips VaultStatus to unlocked, at which '
      'point the existing SessionStatus logic takes over and routes to '
      'Home',
      (tester) async {
        final fakeVaultRepository = _FakeVaultRepository(
          initialStatus: VaultStatus.locked,
        );
        addTearDown(fakeVaultRepository.dispose);
        sl.unregister<VaultRepository>();
        sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

        final fakeSessionRepository = _FakeSessionRepository()
          ..setStatus(SessionStatus.authenticated);
        addTearDown(fakeSessionRepository.dispose);
        sl.unregister<SessionRepository>();
        sl.registerLazySingleton<SessionRepository>(
          () => fakeSessionRepository,
        );

        await tester.pumpWidget(const CerneApp());
        await tester.pumpAndSettle();

        // Still locked: the vault gate wins over the already-authenticated
        // session, and VaultLockScreen's own auto-triggered authenticate()
        // call (the fake defaults `authenticateSucceeds: false`) left it
        // that way.
        expect(find.byType(VaultLockScreen), findsOneWidget);
        expect(find.byType(HomeChatPlaceholderScreen), findsNothing);

        // Simulates the OS biometric prompt succeeding: flips VaultStatus
        // straight to unlocked (same effect `VaultRepositoryImpl.
        // authenticate()` would have), which the router's
        // `refreshListenable` picks up and re-runs `_redirect` with no
        // further vault gate in the way.
        fakeVaultRepository.setStatus(VaultStatus.unlocked);
        await tester.pumpAndSettle();

        expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
        expect(find.byType(VaultLockScreen), findsNothing);
      },
    );

    testWidgets(
      'biometric failure falls through to the real PinKeypad wiring '
      '(spec-2-2): the initial auto-attempt fails (authenticateSucceeds '
      'starts false) and shows the keypad, then entering 4 digits stores '
      'them as the new PIN, unlocks the vault and routes through to Home',
      (tester) async {
        final fakeVaultRepository = _FakeVaultRepository(
          initialStatus: VaultStatus.locked,
        );
        addTearDown(fakeVaultRepository.dispose);
        sl.unregister<VaultRepository>();
        sl.registerLazySingleton<VaultRepository>(() => fakeVaultRepository);

        final fakeSessionRepository = _FakeSessionRepository()
          ..setStatus(SessionStatus.authenticated);
        addTearDown(fakeSessionRepository.dispose);
        sl.unregister<SessionRepository>();
        sl.registerLazySingleton<SessionRepository>(
          () => fakeSessionRepository,
        );

        await tester.pumpWidget(const CerneApp());
        await tester.pumpAndSettle();

        // The initial auto-triggered authenticate() call used the fake's
        // default authenticateSucceeds == false, so the PIN keypad is now
        // visible (never a "Tentar novamente" biometric-retry affordance —
        // AC2) and the vault is still locked.
        expect(find.byType(VaultLockScreen), findsOneWidget);
        expect(find.text('Digite seu PIN'), findsOneWidget);
        expect(find.text('Tentar novamente'), findsNothing);

        // Drive the real PinKeypad wiring (_submitPin) rather than
        // setStatus directly — no PIN stored yet, so this first entry
        // becomes the stored PIN (Design Notes).
        for (final digit in '1234'.split('')) {
          await tester.tap(find.text(digit));
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();

        expect(find.byType(HomeChatPlaceholderScreen), findsOneWidget);
        expect(find.byType(VaultLockScreen), findsNothing);
      },
    );
  });
}
