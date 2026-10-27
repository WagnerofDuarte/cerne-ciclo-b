import 'package:flutter/material.dart';

import 'core/design_tokens.dart';
import 'core/di/injection_container.dart';
import 'features/auth/presentation/cubit/auth_cubit.dart';
import 'features/auth/presentation/screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await setupCoreDependencies();
  } catch (error) {
    debugPrint(
      'Cerne failed to start: could not load .env ($error). Copy '
      '.env.example to .env and fill in FUNCTIONS_BASE_URL + '
      'SUPABASE_ANON_KEY before running the app.',
    );
    rethrow;
  }
  runApp(const CerneApp());
}

/// Root widget. Portrait-only, light-mode-only, fixed 390x844 frame — no
/// breakpoint, landscape or dark-mode path anywhere in the app (per the
/// epic's UX constraints).
///
/// Story 1.3 scope: home is Tela 0.1a (`AuthScreen`). There is no
/// `SessionStatus`/`go_router` yet (Story 1.4/1.6), so a successful
/// signup/login simply pushes-replaces this screen with a throwaway
/// post-auth placeholder — deleted wholesale once Story 1.6's navigation
/// shell exists.
class CerneApp extends StatelessWidget {
  const CerneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthScreen(
        cubit: sl<AuthCubit>(),
        onAuthenticated: (context) => Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const _PostAuthPlaceholder()),
        ),
      ),
    );
  }
}

/// Throwaway placeholder — Story 1.6 replaces this wholesale with the real
/// base navigation shell. Exists only so Story 1.3 has somewhere to land
/// after a successful signup/login.
class _PostAuthPlaceholder extends StatelessWidget {
  const _PostAuthPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: const Center(
        child: Text(
          'Autenticado',
          style: DesignTokens.textHeadlineMd,
        ),
      ),
    );
  }
}
