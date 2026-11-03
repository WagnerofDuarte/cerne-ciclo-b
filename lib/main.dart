import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'core/di/injection_container.dart';
import 'core/failure/failure.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/expiry_overlay_host.dart';
import 'features/auth/domain/repositories/session_repository.dart';

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
/// epic's UX constraints; the portrait lock itself lives in
/// `ios/Runner/Info.plist`, Story 1.6).
///
/// Story 1.6 scope: the ad-hoc `StreamBuilder`/`Navigator.push` shell
/// Stories 1.3-1.5 built this on top of is replaced by the one real
/// `go_router` (`core/navigation/app_router.dart`) plus its
/// `ExpiryOverlayHost` wrapper — [restoreSession] still fires once at boot
/// here (unchanged from Story 1.4), but every screen transition and the
/// expiry overlay's own "Entrar novamente" now go through that router
/// instead of an imperative `Navigator`.
class CerneApp extends StatefulWidget {
  const CerneApp({super.key});

  @override
  State<CerneApp> createState() => _CerneAppState();
}

class _CerneAppState extends State<CerneApp> {
  late final SessionRepository _sessionRepository;
  late final GoRouter _router;

  // Created here (not left for `GoRouter` to generate internally) and
  // passed to both `buildAppRouter` and `ExpiryOverlayHost` below, so the
  // latter can reach the Navigator's own `BuildContext` through this
  // public, documented key instead of reaching into `GoRouter`'s internal
  // `routerDelegate`.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>(
    debugLabel: 'root',
  );

  @override
  void initState() {
    super.initState();
    _sessionRepository = sl<SessionRepository>();
    _router = buildAppRouter(
      sessionRepository: _sessionRepository,
      navigatorKey: _navigatorKey,
    );
    // Fire-and-forget: the outcome reaches the UI through
    // `SessionRepository.currentStatus`/`statusStream` (which the router's
    // `redirect`/`refreshListenable` already watch), not through this
    // call's return value. `restoreSession()` already maps every internal
    // failure to `Left`/an `unauthenticated` emission and never throws.
    // This `catchError` is NOT a UI recovery path — its handler's return
    // value is discarded by `unawaited` and never reaches `statusStream`.
    // It exists purely so a future regression that broke the "never
    // throws" contract above would surface as a logged message instead of
    // an unhandled zone exception.
    unawaited(
      _sessionRepository.restoreSession().catchError(_asUnauthenticated),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
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
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      builder: (context, child) => ExpiryOverlayHost(
        sessionRepository: _sessionRepository,
        router: _router,
        navigatorKey: _navigatorKey,
        child: child!,
      ),
    );
  }
}
