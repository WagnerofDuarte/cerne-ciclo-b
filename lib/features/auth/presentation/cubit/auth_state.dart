import 'package:fpdart/fpdart.dart';

import '../../../../core/resource.dart';

/// Tela 0.1a's two modes — toggled by a text link, never a separate screen
/// (epics.md Story 1.3 AC).
enum AuthMode { login, signUp }

/// Drives [AuthScreen]: mode, the two field values, their errors, and the
/// in-flight submit status.
///
/// [emailError] and [passwordError] are each single-field, pre-network local
/// validation errors — set independently, one per field, never together
/// (`AuthCubit.submit` checks email first and returns before ever touching
/// password validation). [formError] is reserved for an actual backend-call
/// failure (`AUTH_INVALID`/network/any other `Failure`) — it never overlaps
/// with either local error, since `submit` only reaches the network call
/// once both local checks already passed.
class AuthState {
  const AuthState({
    this.mode = AuthMode.login,
    this.email = '',
    this.password = '',
    this.emailError,
    this.passwordError,
    this.formError,
    this.status = const ResourceIdle<Unit>(),
  });

  final AuthMode mode;
  final String email;
  final String password;

  /// Inline "E-mail inválido" from local validation. Shown under the e-mail
  /// field only.
  final String? emailError;

  /// Inline "Senha obrigatória" from local validation. Shown under the
  /// senha field only — unlike [formError], this never borders the e-mail
  /// field too (the e-mail value already passed its own check).
  final String? passwordError;

  /// `AUTH_INVALID`/`Failure.message` from the backend call. Shown once,
  /// under the senha field, while *both* fields get the error border (the
  /// e-mail field via `errorText: ''`, border-only).
  final String? formError;

  final Resource<Unit> status;

  bool get isSubmitting => status is ResourceLoading<Unit>;

  AuthState copyWith({
    AuthMode? mode,
    String? email,
    String? password,
    String? emailError,
    bool clearEmailError = false,
    String? passwordError,
    bool clearPasswordError = false,
    String? formError,
    bool clearFormError = false,
    Resource<Unit>? status,
  }) {
    return AuthState(
      mode: mode ?? this.mode,
      email: email ?? this.email,
      password: password ?? this.password,
      emailError: clearEmailError ? null : (emailError ?? this.emailError),
      passwordError: clearPasswordError
          ? null
          : (passwordError ?? this.passwordError),
      formError: clearFormError ? null : (formError ?? this.formError),
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthState &&
          other.mode == mode &&
          other.email == email &&
          other.password == password &&
          other.emailError == emailError &&
          other.passwordError == passwordError &&
          other.formError == formError &&
          other.status == status);

  @override
  int get hashCode => Object.hash(
    mode,
    email,
    password,
    emailError,
    passwordError,
    formError,
    status,
  );

  @override
  String toString() =>
      'AuthState(mode: $mode, email: $email, password: $password, '
      'emailError: $emailError, passwordError: $passwordError, '
      'formError: $formError, status: $status)';
}
