import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/domain/repositories/session_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/auth/presentation/screens/auth_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSessionRepository extends Mock implements SessionRepository {}

Widget _wrap(
  AuthCubit cubit, {
  required VoidCallback onAuthenticated,
  double textScale = 1.0,
}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      home: AuthScreen(cubit: cubit, onAuthenticated: (_) => onAuthenticated()),
    ),
  );
}

OutlineInputBorder _errorBorderOf(TextField field) =>
    field.decoration!.errorBorder as OutlineInputBorder;

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockSessionRepository mockSessionRepository;
  late AuthCubit cubit;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockSessionRepository = MockSessionRepository();
    when(() => mockSessionRepository.markAuthenticated()).thenReturn(null);
    cubit = AuthCubit(mockAuthRepository, mockSessionRepository);
  });

  tearDown(() => cubit.close());

  testWidgets(
    'valid login: auth-login succeeds, onAuthenticated fires past the screen',
    (tester) async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => right(const AuthenticatedUser(id: 'u1', email: 'a@b.com')),
      );
      var authenticated = false;

      await tester.pumpWidget(
        _wrap(cubit, onAuthenticated: () => authenticated = true),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      await tester.pump();

      verify(
        () =>
            mockAuthRepository.logIn(email: 'a@b.com', password: 'segredo123'),
      ).called(1);
      expect(authenticated, isTrue);
    },
  );

  testWidgets(
    'valid signup: auth-signup is called with exactly {email, password}',
    (tester) async {
      when(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u2', email: 'nova@b.com')),
      );

      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      // Toggle to signup mode first.
      await tester.tap(find.text('Não tem conta? Criar conta'));
      await tester.pump();
      expect(find.text('Crie sua conta'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'nova@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Criar conta'));
      await tester.pump();
      await tester.pump();

      verify(
        () => mockAuthRepository.signUp(
          email: 'nova@b.com',
          password: 'segredo123',
        ),
      ).called(1);
    },
  );

  testWidgets(
    'invalid credentials: AUTH_INVALID borders both fields, shows the '
    'message once, and keeps the typed values',
    (tester) async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            left(const Failure.authInvalid(message: 'Credenciais inválidas')),
      );

      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'senhaerrada',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      await tester.pump();

      // Message shown exactly once.
      expect(find.text('Credenciais inválidas'), findsOneWidget);

      final emailField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'E-mail'),
      );
      final passwordField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Senha'),
      );

      // Both fields bordered: e-mail is border-only (errorText: ''),
      // senha carries the one visible message.
      expect(emailField.decoration!.errorText, '');
      expect(passwordField.decoration!.errorText, 'Credenciais inválidas');
      expect(
        _errorBorderOf(emailField).borderSide.color,
        DesignTokens.colorError,
      );
      expect(
        _errorBorderOf(passwordField).borderSide.color,
        DesignTokens.colorError,
      );

      // Values kept, not cleared.
      expect(emailField.controller!.text, 'a@b.com');
      expect(passwordField.controller!.text, 'senhaerrada');
    },
  );

  testWidgets(
    'malformed email: blocked pre-network with inline "E-mail inválido", '
    'no repository call',
    (tester) async {
      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'nao-e-email',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();

      expect(find.text('E-mail inválido'), findsOneWidget);
      verifyNever(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      verifyNever(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    },
  );

  testWidgets(
    'empty password: blocked pre-network with inline "Senha obrigatória" '
    'under senha only — the e-mail field (already valid) is never bordered',
    (tester) async {
      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();

      expect(find.text('Senha obrigatória'), findsOneWidget);

      final emailField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'E-mail'),
      );
      final passwordField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Senha'),
      );
      expect(emailField.decoration!.errorText, isNull);
      expect(passwordField.decoration!.errorText, 'Senha obrigatória');

      verifyNever(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
    },
  );

  testWidgets(
    'network failure: Failure.message is shown as the same inline error',
    (tester) async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => left(
          const Failure.networkOffline(message: 'Sem conexão com a internet'),
        ),
      );

      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.tap(find.text('Entrar'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Sem conexão com a internet'), findsOneWidget);
    },
  );

  testWidgets(
    'signup mode, backend failure: AUTH_INVALID renders the same as in '
    'login mode (the failure-rendering path is mode-agnostic)',
    (tester) async {
      when(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            left(const Failure.authInvalid(message: 'Credenciais inválidas')),
      );

      await tester.pumpWidget(_wrap(cubit, onAuthenticated: () {}));

      // Toggle to signup mode first.
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
      await tester.pump();
      await tester.pump();

      expect(find.text('Credenciais inválidas'), findsOneWidget);

      final emailField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'E-mail'),
      );
      final passwordField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Senha'),
      );
      expect(emailField.decoration!.errorText, '');
      expect(passwordField.decoration!.errorText, 'Credenciais inválidas');
    },
  );

  testWidgets(
    'the screen renders with no overflow at a large Dynamic Type scale',
    (tester) async {
      await tester.pumpWidget(
        _wrap(cubit, onAuthenticated: () {}, textScale: 3.0),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bem-vindo de volta'), findsOneWidget);
    },
  );
}
