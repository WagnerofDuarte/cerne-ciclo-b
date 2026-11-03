import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../di/injection_container.dart';
import '../../features/auth/domain/entities/session_status.dart';
import '../../features/auth/domain/repositories/session_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import 'placeholder_screens.dart';

/// Every route this story's app shell resolves (Boundaries: "Routes:
/// `/boot`, `/auth`, `/reauth`, `/`, `/meus-registros`, `/planos-de-acao`,
/// `/configuracoes`"). Named constants so no call site retypes a path
/// literal that could drift from the one `GoRouter` below.
abstract final class AppRoutePaths {
  static const boot = '/boot';
  static const auth = '/auth';
  static const reauth = '/reauth';
  static const home = '/';
  static const meusRegistros = '/meus-registros';
  static const planosDeAcao = '/planos-de-acao';
  static const configuracoes = '/configuracoes';
}

/// The epic's ONE `GoRouter`/`redirect` (Boundaries: "never a second
/// competing `redirect`") — composes only [SessionRepository.currentStatus]
/// for now. [sessionRepository] is taken as a parameter (rather than this
/// file reaching into `sl` itself) purely so a test can pass a fake/mock one
/// directly, without touching the global DI container.
///
/// [navigatorKey] is accepted explicitly (rather than letting `GoRouter`
/// generate its own internally) so the caller — `main.dart`'s
/// `ExpiryOverlayHost` — can reach the Navigator's own `BuildContext`
/// through the same, public, documented key instead of reaching into
/// `GoRouter`'s internal `routerDelegate` (not part of its public API).
GoRouter buildAppRouter({
  required SessionRepository sessionRepository,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutePaths.boot,
    refreshListenable: _GoRouterRefreshStream(sessionRepository.statusStream),
    redirect: (context, state) => _redirect(sessionRepository, state),
    routes: [
      GoRoute(
        path: AppRoutePaths.boot,
        builder: (context, state) => const BootSplashScreen(),
      ),
      GoRoute(
        path: AppRoutePaths.auth,
        builder: (context, state) => AuthScreen(
          cubit: sl<AuthCubit>(),
          onAuthenticated: (context) => context.go(AppRoutePaths.home),
        ),
      ),
      GoRoute(
        path: AppRoutePaths.reauth,
        builder: (context, state) => const BiometricReauthPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutePaths.home,
        builder: (context, state) => const HomeChatPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutePaths.meusRegistros,
        builder: (context, state) => const MeusRegistrosPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutePaths.planosDeAcao,
        builder: (context, state) => const ActionPlansPlaceholderScreen(),
      ),
      GoRoute(
        path: AppRoutePaths.configuracoes,
        builder: (context, state) => const ConfiguracoesPlaceholderScreen(),
      ),
    ],
  );
}

/// I/O & Edge-Case Matrix:
/// - status not yet known (`null`) -> `/boot`, unless already there.
/// - `unauthenticated` -> `/auth`, unless already there.
/// - `authenticated`/`expired` -> leaves `/boot`/`/auth` for `/`; every
///   other location (including `/reauth`, reached only by the expiry
///   overlay's own explicit navigation) is left alone — a mid-session
///   expiry never navigates away (Story 1.5 behavior preserved), and the
///   three non-Home destinations stay reachable while `expired`.
///
/// AD-14 seam: Epic 2 (RF03) plugs a local `VaultStatus` gate in here,
/// checked *before* this session check (Cross-Story Dependencies: "vault
/// checked first") — e.g. `if (vaultStatus == VaultStatus.locked) return
/// AppRoutePaths.vaultLock;` ahead of the block below. Nothing here should
/// assume session validity alone ever decides access once that lands.
String? _redirect(SessionRepository sessionRepository, GoRouterState state) {
  final status = sessionRepository.currentStatus;
  final location = state.matchedLocation;

  if (status == null) {
    return location == AppRoutePaths.boot ? null : AppRoutePaths.boot;
  }

  if (status == SessionStatus.unauthenticated) {
    return location == AppRoutePaths.auth ? null : AppRoutePaths.auth;
  }

  // status is authenticated or expired.
  if (location == AppRoutePaths.boot || location == AppRoutePaths.auth) {
    return AppRoutePaths.home;
  }
  return null;
}

/// Wraps [stream] as a `Listenable` so `GoRouter`'s `refreshListenable` can
/// re-run [_redirect] on every emission — go_router 18.1.1 exports no
/// `GoRouterRefreshStream` of its own (Code Map), so this is that small
/// local class.
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen(
      (_) => notifyListeners(),
      // Mirrors `ExpiryOverlayHost`'s and `SessionRepositoryImpl`'s own
      // subscriptions to this same stream — no current implementation
      // ever errors on it, but a future one that did must not surface as
      // an unhandled zone exception here specifically.
      onError: (_, _) {},
    );
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
