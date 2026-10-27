import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/di/injection_container.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';
import 'package:cerne/features/auth/domain/entities/session_status.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/main.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

/// Proves the one real production composition root — `CerneApp` resolving
/// `sl<AuthCubit>()` and wiring `onAuthenticated` to
/// `Navigator.pushReplacement` — actually works end to end (code review of
/// story-1-3-account-creation-and-login), and (Story 1.4) that `home`
/// actually branches on `SessionRepository.statusStream`'s first emission
/// instead of hardcoding `AuthScreen`. Every other test either stops at DI
/// registration (`bootstrap_integration_test.dart`) or supplies its own
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
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    fakeNativeStorage.clear();
    await resetCoreDependencies();
  });

  testWidgets(
    'CerneApp resolves the real AuthCubit and navigates to the post-auth '
    'placeholder once onAuthenticated fires',
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
      // CerneApp's own `sl<AuthCubit>()` lookup and `main.dart`'s real
      // `onAuthenticated` callback run unchanged.
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

      expect(find.text('Autenticado'), findsOneWidget);
      expect(find.text('Bem-vindo de volta'), findsNothing);
    },
  );

  testWidgets(
    'CerneApp lands on the post-auth placeholder when statusStream emits '
    'authenticated, with no AuthScreen ever shown',
    (tester) async {
      final mockSessionRepository = MockSessionRepository();
      when(() => mockSessionRepository.restoreSession())
          .thenAnswer((_) async => right(unit));
      when(() => mockSessionRepository.statusStream)
          .thenAnswer((_) => Stream.value(SessionStatus.authenticated));

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => mockSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      expect(find.text('Autenticado'), findsOneWidget);
      expect(find.text('Entrar'), findsNothing);
    },
  );

  testWidgets(
    'CerneApp lands on AuthScreen when statusStream emits unauthenticated',
    (tester) async {
      final mockSessionRepository = MockSessionRepository();
      when(
        () => mockSessionRepository.restoreSession(),
      ).thenAnswer((_) async => left(const AuthExpired(message: 'No session')));
      when(() => mockSessionRepository.statusStream)
          .thenAnswer((_) => Stream.value(SessionStatus.unauthenticated));

      sl.unregister<SessionRepository>();
      sl.registerLazySingleton<SessionRepository>(() => mockSessionRepository);

      await tester.pumpWidget(const CerneApp());
      await tester.pumpAndSettle();

      expect(find.text('Entrar'), findsOneWidget);
      expect(find.text('Autenticado'), findsNothing);
    },
  );
}
