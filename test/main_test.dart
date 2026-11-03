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

/// Proves the one real production composition root — `CerneApp` resolving
/// `sl<AuthCubit>()`/`sl<SessionRepository>()`, building the one `go_router`
/// (Story 1.6), and wrapping it with `ExpiryOverlayHost` — actually works
/// end to end. Every other test either stops at DI registration
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
    },
  );
}
