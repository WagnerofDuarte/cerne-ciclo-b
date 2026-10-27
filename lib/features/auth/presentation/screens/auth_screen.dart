import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fpdart/fpdart.dart' hide State;

import '../../../../core/design_tokens.dart';
import '../../../../core/resource.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

/// Tela 0.1a (prototype-extract.md §4): "Entrar"/"Criar conta", two
/// `AppTextField`s + one `AppButton` + a ghost toggle link — unchanged
/// shared primitives, no new params. No "usar biometria" link (Epic 2's
/// vault isn't built — omitted rather than shipped dead); no
/// `SessionStatus`/`go_router` (Story 1.4/1.6 scope): [onAuthenticated] is
/// how the caller (`main.dart`) decides what comes after success.
class AuthScreen extends StatelessWidget {
  const AuthScreen({
    super.key,
    required this.cubit,
    required this.onAuthenticated,
  });

  final AuthCubit cubit;

  /// Called once, the first time `state.status` becomes `ResourceData`
  /// (i.e. the access token has already been persisted — the repository
  /// saves it before resolving).
  final void Function(BuildContext context) onAuthenticated;

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: BlocListener<AuthCubit, AuthState>(
        listenWhen: (previous, current) =>
            current.status is ResourceData<Unit> &&
            previous.status is! ResourceData<Unit>,
        listener: (context, state) => onAuthenticated(context),
        child: const _AuthView(),
      ),
    );
  }
}

class _AuthView extends StatefulWidget {
  const _AuthView();

  @override
  State<_AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<_AuthView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // Keeps the (locally-owned) text controllers in sync with the cubit's
  // state without fighting the user's caret position — only written when
  // the value actually diverges (e.g. on `toggleMode`, which doesn't touch
  // field values, this is a no-op). On `AUTH_INVALID`/network failure the
  // cubit state's `email`/`password` are untouched, so this keeps the
  // user's typed values exactly as they were (epics.md Story 1.3 AC).
  void _syncControllers(AuthState state) {
    if (_emailController.text != state.email) {
      _emailController.value = _emailController.value.copyWith(
        text: state.email,
        selection: TextSelection.collapsed(offset: state.email.length),
      );
    }
    if (_passwordController.text != state.password) {
      _passwordController.value = _passwordController.value.copyWith(
        text: state.password,
        selection: TextSelection.collapsed(offset: state.password.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, state) {
            _syncControllers(state);

            final cubit = context.read<AuthCubit>();
            final isLogin = state.mode == AuthMode.login;
            final isSubmitting = state.isSubmitting;

            // Both fields get the error border on a form-level failure
            // (AUTH_INVALID/network); the message itself is shown once,
            // under senha. `errorText: ''` on e-mail is border-only
            // (app_text_field.dart's documented convention). A local,
            // password-only validation error (`passwordError`, "Senha
            // obrigatória") is single-field — the e-mail value already
            // passed its own check, so it must never be bordered for it.
            final emailErrorText = state.emailError ??
                (state.formError != null ? '' : null);
            final passwordErrorText = state.formError ?? state.passwordError;

            return SingleChildScrollView(
              padding: DesignTokens.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: DesignTokens.spacing2xl),
                  Text(
                    isLogin ? 'Bem-vindo de volta' : 'Crie sua conta',
                    textAlign: TextAlign.center,
                    style: DesignTokens.textHeadlineMd.copyWith(
                      color: DesignTokens.colorTextPrimary,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                  AppTextField(
                    controller: _emailController,
                    labelText: 'E-mail',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    errorText: emailErrorText,
                    onChanged: cubit.emailChanged,
                  ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  AppTextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    labelText: 'Senha',
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    errorText: passwordErrorText,
                    onChanged: cubit.passwordChanged,
                  ),
                  const SizedBox(height: DesignTokens.spacingLg),
                  AppButton(
                    label: isSubmitting
                        ? (isLogin ? 'Entrando…' : 'Criando conta…')
                        : (isLogin ? 'Entrar' : 'Criar conta'),
                    onPressed: isSubmitting ? null : cubit.submit,
                  ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  AppButton(
                    variant: AppButtonVariant.textGhost,
                    label: isLogin
                        ? 'Não tem conta? Criar conta'
                        : 'Já tem conta? Entrar',
                    onPressed: isSubmitting ? null : cubit.toggleMode,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
