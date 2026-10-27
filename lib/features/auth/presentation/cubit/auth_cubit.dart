import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/resource.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/validators/auth_validators.dart';
import 'auth_state.dart';

/// Drives Tela 0.1a. Calls [AuthRepository] directly (no use-case — Code Map:
/// this story's scope is small enough that an extra indirection layer isn't
/// justified yet); a BLoC/Cubit constructor never takes another BLoC/Cubit as
/// a dependency (architecture spine), so this takes the repository port.
class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._authRepository) : super(const AuthState());

  final AuthRepository _authRepository;

  /// Toggles login/signup — same screen, not a navigation (epics.md Story
  /// 1.3 AC). Keeps whatever the user already typed; clears any error from
  /// the previous mode's attempt.
  void toggleMode() {
    emit(
      AuthState(
        mode: state.mode == AuthMode.login ? AuthMode.signUp : AuthMode.login,
        email: state.email,
        password: state.password,
      ),
    );
  }

  void emailChanged(String value) {
    emit(
      state.copyWith(
        email: value,
        clearEmailError: true,
        clearPasswordError: true,
        clearFormError: true,
      ),
    );
  }

  void passwordChanged(String value) {
    emit(
      state.copyWith(
        password: value,
        clearPasswordError: true,
        clearFormError: true,
      ),
    );
  }

  /// Validates locally first — a malformed email (or empty password) blocks
  /// submit *before* any round trip (epics.md Story 1.3 AC), each as its own
  /// single-field error so only the offending field is ever bordered. Only
  /// once local validation passes does it call `auth-signup`/`auth-login`
  /// with exactly `{email, password}` (the e-mail trimmed — stray
  /// leading/trailing whitespace must never reach the backend and risk a
  /// spurious `AUTH_INVALID`), saving the access token (via the repository)
  /// before this resolves.
  Future<void> submit() async {
    if (state.isSubmitting) {
      return;
    }

    final emailError = validateEmail(state.email);
    if (emailError != null) {
      emit(
        state.copyWith(
          emailError: emailError,
          clearPasswordError: true,
          clearFormError: true,
        ),
      );
      return;
    }

    final passwordError = validatePassword(state.password);
    if (passwordError != null) {
      emit(
        state.copyWith(
          passwordError: passwordError,
          clearEmailError: true,
          clearFormError: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        status: const ResourceLoading<Unit>(),
        clearEmailError: true,
        clearPasswordError: true,
        clearFormError: true,
      ),
    );

    final trimmedEmail = state.email.trim();
    final result = state.mode == AuthMode.login
        ? await _authRepository.logIn(
            email: trimmedEmail,
            password: state.password,
          )
        : await _authRepository.signUp(
            email: trimmedEmail,
            password: state.password,
          );

    result.match(
      (failure) => emit(
        state.copyWith(
          status: const ResourceIdle<Unit>(),
          formError: failure.message,
        ),
      ),
      (_) => emit(state.copyWith(status: const ResourceData<Unit>(unit))),
    );
  }
}
