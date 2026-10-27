import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/core/resource.dart';
import 'package:cerne/features/auth/domain/entities/authenticated_user.dart';
import 'package:cerne/features/auth/domain/repositories/auth_repository.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:cerne/features/auth/presentation/cubit/auth_state.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

/// Collects every state the cubit emits for the duration of [act], since the
/// stack has no `bloc_test` pin — this drives [AuthCubit] through its public
/// API only (never the `@protected` `emit`), the same way any other
/// `flutter_bloc` consumer would.
Future<List<AuthState>> _emittedDuring(
  AuthCubit cubit,
  Future<void> Function() act,
) async {
  final emitted = <AuthState>[];
  final subscription = cubit.stream.listen(emitted.add);
  await act();
  // `submit()`'s awaited repository call resolves its mocked Future on a
  // microtask; `Future.delayed(Duration.zero)` only resumes once the whole
  // microtask queue (including the stream's event dispatch to our
  // listener) has drained, so this reliably waits for every emit `act()`
  // triggered before we stop listening.
  await Future<void>.delayed(Duration.zero);
  await subscription.cancel();
  return emitted;
}

void main() {
  late MockAuthRepository mockAuthRepository;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
  });

  group('AuthCubit — mode toggle', () {
    test('toggleMode flips login <-> signUp, keeping typed field values',
        () async {
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('a@b.com');
      cubit.passwordChanged('segredo');

      final emitted = await _emittedDuring(
        cubit,
        () async => cubit.toggleMode(),
      );

      expect(emitted, [
        const AuthState(
          mode: AuthMode.signUp,
          email: 'a@b.com',
          password: 'segredo',
        ),
      ]);
      await cubit.close();
    });
  });

  group('AuthCubit — local validation blocks submit', () {
    test('a malformed email blocks submit before any repository call',
        () async {
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('nao-e-email');
      cubit.passwordChanged('segredo');

      final emitted = await _emittedDuring(cubit, cubit.submit);

      expect(emitted, [
        const AuthState(
          email: 'nao-e-email',
          password: 'segredo',
          emailError: 'E-mail inválido',
        ),
      ]);
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
      await cubit.close();
    });

    test('an empty password blocks submit before any repository call',
        () async {
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('a@b.com');

      final emitted = await _emittedDuring(cubit, cubit.submit);

      expect(emitted, [
        const AuthState(email: 'a@b.com', passwordError: 'Senha obrigatória'),
      ]);
      verifyNever(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      await cubit.close();
    });
  });

  group('AuthCubit — successful submit', () {
    test(
        'login success emits loading then ResourceData, calling auth-login '
        'with exactly the typed email/password', () async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u1', email: 'a@b.com')),
      );
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('a@b.com');
      cubit.passwordChanged('segredo123');

      final emitted = await _emittedDuring(cubit, cubit.submit);

      expect(emitted, [
        const AuthState(
          email: 'a@b.com',
          password: 'segredo123',
          status: ResourceLoading<Unit>(),
        ),
        const AuthState(
          email: 'a@b.com',
          password: 'segredo123',
          status: ResourceData<Unit>(unit),
        ),
      ]);
      verify(
        () => mockAuthRepository.logIn(
          email: 'a@b.com',
          password: 'segredo123',
        ),
      ).called(1);
      await cubit.close();
    });

    test('signup mode calls signUp, not logIn', () async {
      when(
        () => mockAuthRepository.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u2', email: 'nova@b.com')),
      );
      final cubit = AuthCubit(mockAuthRepository);
      cubit.toggleMode();
      cubit.emailChanged('nova@b.com');
      cubit.passwordChanged('segredo123');

      await cubit.submit();

      verify(
        () => mockAuthRepository.signUp(
          email: 'nova@b.com',
          password: 'segredo123',
        ),
      ).called(1);
      verifyNever(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      );
      await cubit.close();
    });

    test(
        'leading/trailing whitespace in the typed e-mail is trimmed before '
        'it reaches the repository', () async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async =>
            right(const AuthenticatedUser(id: 'u1', email: 'a@b.com')),
      );
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('  a@b.com  ');
      cubit.passwordChanged('segredo123');

      await cubit.submit();

      verify(
        () => mockAuthRepository.logIn(
          email: 'a@b.com',
          password: 'segredo123',
        ),
      ).called(1);
      await cubit.close();
    });
  });

  group('AuthCubit — AUTH_INVALID', () {
    test(
        'AUTH_INVALID keeps the typed values and surfaces the message '
        'once, via formError', () async {
      when(
        () => mockAuthRepository.logIn(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => left(
          const Failure.authInvalid(message: 'Credenciais inválidas'),
        ),
      );
      final cubit = AuthCubit(mockAuthRepository);
      cubit.emailChanged('a@b.com');
      cubit.passwordChanged('errada');

      final emitted = await _emittedDuring(cubit, cubit.submit);

      expect(emitted, [
        const AuthState(
          email: 'a@b.com',
          password: 'errada',
          status: ResourceLoading<Unit>(),
        ),
        const AuthState(
          email: 'a@b.com',
          password: 'errada',
          formError: 'Credenciais inválidas',
        ),
      ]);
      await cubit.close();
    });
  });
}
