import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;

import 'core/design_tokens.dart';
import 'core/di/injection_container.dart';
import 'core/failure/failure.dart';
import 'features/auth/domain/entities/session_status.dart';
import 'features/auth/domain/repositories/session_repository.dart';
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
/// Story 1.4 scope: `home` branches on `SessionRepository.statusStream`
/// instead of hardcoding `AuthScreen` — `restoreSession()` fires once at
/// boot (unconditional, no client-side expiry math) and the stream's first
/// emission decides whether the user lands on `AuthScreen` or the post-auth
/// placeholder. No `go_router` yet (Story 1.6): the `MaterialApp`/`Navigator`
/// shape is unchanged, and a successful signup/login still simply
/// pushes-replaces via `onAuthenticated`.
class CerneApp extends StatefulWidget {
  const CerneApp({super.key});

  @override
  State<CerneApp> createState() => _CerneAppState();
}

class _CerneAppState extends State<CerneApp> {
  late final SessionRepository _sessionRepository;

  @override
  void initState() {
    super.initState();
    _sessionRepository = sl<SessionRepository>();
    // Fire-and-forget: the outcome reaches the UI through `statusStream`
    // below, not through this call's return value. `restoreSession()`
    // already maps every internal failure to `Left`/an `unauthenticated`
    // emission and never throws, but swallowing any error here anyway is
    // cheap insurance against it otherwise surfacing as an unhandled zone
    // exception.
    unawaited(
      _sessionRepository.restoreSession().catchError(_asUnauthenticated),
    );
  }

  // `catchError`'s handler must still complete the Future with a value of
  // its declared type (`Either<Failure, Unit>`) — a `void`-returning
  // handler would try to complete it with `null`, which isn't assignable
  // to that non-nullable type and would itself throw.
  static Either<Failure, Unit> _asUnauthenticated(
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('CerneApp: restoreSession() threw unexpectedly ($error)');
    return left(Failure.malformedResponse(message: error.toString()));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<SessionStatus>(
        stream: _sessionRepository.statusStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            // No emission yet: brief-blank for the happy path (RNF01's
            // 300ms threshold) — `_BootLoadingScreen` only surfaces a
            // spinner once the wait actually crosses that.
            return const _BootLoadingScreen();
          }
          if (snapshot.data == SessionStatus.authenticated) {
            return const _PostAuthPlaceholder();
          }
          return AuthScreen(
            cubit: sl<AuthCubit>(),
            onAuthenticated: (context) => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const _PostAuthPlaceholder()),
            ),
          );
        },
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
        child: Text('Autenticado', style: DesignTokens.textHeadlineMd),
      ),
    );
  }
}

/// Shown while `statusStream` has no data yet. Blank for the happy path
/// (RNF01: no loading UI below 300ms), but surfaces a centered spinner once
/// the wait crosses that threshold — `auth-refresh` is retried by
/// `RetryInterceptor` on `NETWORK_TIMEOUT`/`NETWORK_OFFLINE`, so a slow or
/// offline boot could otherwise leave the screen looking frozen for several
/// seconds with zero feedback. Kept as a private, inline, one-off widget
/// (no new shared-widget param) — same minimal-treatment convention Story
/// 1.3's submit button uses for its own >300ms affordance.
class _BootLoadingScreen extends StatefulWidget {
  const _BootLoadingScreen();

  @override
  State<_BootLoadingScreen> createState() => _BootLoadingScreenState();
}

class _BootLoadingScreenState extends State<_BootLoadingScreen> {
  static const _threshold = Duration(milliseconds: 300);

  bool _showIndicator = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_threshold, () {
      if (mounted) {
        setState(() => _showIndicator = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Center(
        child: _showIndicator
            ? const CircularProgressIndicator(color: DesignTokens.colorPrimary)
            : const SizedBox.shrink(),
      ),
    );
  }
}
