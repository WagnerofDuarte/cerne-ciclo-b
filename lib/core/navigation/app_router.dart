import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../di/injection_container.dart';
import '../../features/auth/domain/entities/session_status.dart';
import '../../features/auth/domain/repositories/session_repository.dart';
import '../../features/auth/presentation/cubit/auth_cubit.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/vault/domain/entities/vault_status.dart';
import '../../features/vault/domain/repositories/vault_repository.dart';
import '../../features/vault/presentation/screens/vault_lock_screen.dart';
import 'placeholder_screens.dart';

/// Every route this app shell resolves — Story 1.6's original set
/// (`/boot`, `/auth`, `/reauth`, `/`, `/meus-registros`, `/planos-de-acao`,
/// `/configuracoes`) plus Epic 2/spec-2-1's `/vault` lock screen. Named
/// constants so no call site retypes a path literal that could drift from
/// the one `GoRouter` below.
abstract final class AppRoutePaths {
  static const boot = '/boot';
  static const auth = '/auth';
  static const reauth = '/reauth';
  static const vaultLock = '/vault';
  static const home = '/';
  static const meusRegistros = '/meus-registros';
  static const planosDeAcao = '/planos-de-acao';
  static const configuracoes = '/configuracoes';
}

/// The epic's ONE `GoRouter`/`redirect` (Boundaries: "never a second
/// competing `redirect`") — composes [VaultRepository.currentStatus] first,
/// then [SessionRepository.currentStatus] (AD-14). Both repositories are
/// taken as parameters (rather than this file reaching into `sl` itself)
/// purely so a test can pass fakes/mocks directly, without touching the
/// global DI container.
///
/// [navigatorKey] is accepted explicitly (rather than letting `GoRouter`
/// generate its own internally) so the caller — `main.dart`'s
/// `ExpiryOverlayHost` — can reach the Navigator's own `BuildContext`
/// through the same, public, documented key instead of reaching into
/// `GoRouter`'s internal `routerDelegate` (not part of its public API).
GoRouter buildAppRouter({
  required VaultRepository vaultRepository,
  required SessionRepository sessionRepository,
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: AppRoutePaths.boot,
    refreshListenable: _GoRouterRefreshStream([
      vaultRepository.statusStream,
      sessionRepository.statusStream,
    ]),
    redirect: (context, state) =>
        _redirect(vaultRepository, sessionRepository, state),
    routes: [
      GoRoute(
        path: AppRoutePaths.vaultLock,
        builder: (context, state) =>
            VaultLockScreen(vaultRepository: vaultRepository),
      ),
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
///   other location is left alone *except* `/reauth` while already
///   `authenticated` (bounced home below — `/reauth` is meant to be
///   reached only by the expiry overlay's own explicit navigation while
///   `expired`, code review Story 1.6) — a mid-session expiry never
///   navigates away (Story 1.5 behavior preserved), and the three
///   non-Home destinations stay reachable while `expired`.
///
/// AD-14: Epic 2's `VaultStatus` gate (RF03) is composed first, strictly
/// ahead of every `SessionStatus` check below — the vault gate overrides
/// any location whenever it isn't `unlocked`, and only once it is does the
/// rest of this function (unchanged from Story 1.6) ever run.
String? _redirect(
  VaultRepository vaultRepository,
  SessionRepository sessionRepository,
  GoRouterState state,
) {
  final location = state.matchedLocation;

  // AD-14 — checked before SessionStatus, per Boundaries ("`_redirect`
  // checks `VaultStatus` before `SessionStatus`"). `VaultStatus.locked` is
  // the default from construction (never `null`), so this never waits on
  // an async warm-up the way the `status == null` boot check below does.
  if (vaultRepository.currentStatus != VaultStatus.unlocked) {
    return location == AppRoutePaths.vaultLock
        ? null
        : AppRoutePaths.vaultLock;
  }

  final status = sessionRepository.currentStatus;

  if (status == null) {
    return location == AppRoutePaths.boot ? null : AppRoutePaths.boot;
  }

  if (status == SessionStatus.unauthenticated) {
    return location == AppRoutePaths.auth ? null : AppRoutePaths.auth;
  }

  // status is authenticated or expired.
  // `vaultLock` is included here too: once the vault unlocks while this
  // location is still `/vault` (the normal cold-start path once
  // `authenticate()` succeeds), the same fall-through that already bounces
  // `/boot`/`/auth` to Home applies — `/vault` is never a valid resting
  // place once `VaultStatus.unlocked`.
  if (location == AppRoutePaths.boot ||
      location == AppRoutePaths.auth ||
      location == AppRoutePaths.vaultLock) {
    return AppRoutePaths.home;
  }
  // `/reauth` is a throwaway placeholder standing in for Epic 2's real
  // reauth flow; it should never be sitting open once the session is back
  // to fully `authenticated` (code review, Story 1.6).
  if (location == AppRoutePaths.reauth &&
      status == SessionStatus.authenticated) {
    return AppRoutePaths.home;
  }
  return null;
}

/// Wraps [streams] as a single `Listenable` so `GoRouter`'s
/// `refreshListenable` can re-run [_redirect] on every emission from either
/// one — go_router 18.1.1 exports no `GoRouterRefreshStream` of its own
/// (Code Map), so this is that small local class. Extended by AD-14 to
/// subscribe to both the vault and the session streams (previously just
/// the one session stream), composing them into the one `Listenable`
/// `GoRouter` itself requires (Boundaries: "never a second
/// `GoRouter`/`redirect`").
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Iterable<Stream<dynamic>> streams) {
    _subscriptions = [
      for (final stream in streams)
        stream.listen(
          (_) => notifyListeners(),
          // Mirrors `ExpiryOverlayHost`'s and `SessionRepositoryImpl`'s own
          // subscriptions to this same stream — no current implementation
          // ever errors on it, but a future one that did must not surface
          // as an unhandled zone exception here specifically.
          onError: (_, _) {},
        ),
    ];
  }

  late final List<StreamSubscription<dynamic>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
