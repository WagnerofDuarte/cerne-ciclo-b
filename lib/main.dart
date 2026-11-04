import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:go_router/go_router.dart';

import 'core/di/injection_container.dart';
import 'core/failure/failure.dart';
import 'core/navigation/app_router.dart';
import 'core/navigation/expiry_overlay_host.dart';
import 'features/account/domain/repositories/account_settings_repository.dart';
import 'features/auth/domain/repositories/session_repository.dart';
import 'features/vault/domain/repositories/vault_repository.dart';

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
  // Review finding: `app_router.dart`'s `_redirect` composes the vault
  // gate (AD-14) strictly first, synchronously, ahead of everything else —
  // it routes to `/vault` on the very first redirect evaluation, before
  // `CerneApp`'s own fire-and-forget boot fetch below could ever resolve.
  // `/vault`'s builder reads `currentBiometricEnabled` synchronously at
  // that moment, so without this awaited (bounded) fetch here, every cold
  // start reads the untouched default (`true`) regardless of what the user
  // actually set — not the "one-time, benign gap on a slow-network cold
  // boot" it looked like. Bounded so a hung network call can't delay app
  // launch indefinitely; on timeout/failure, `currentBiometricEnabled` is
  // simply left at its documented default, same outcome as before this
  // fix.
  await sl<AccountSettingsRepository>()
      .fetchBiometricEnabled()
      .timeout(const Duration(seconds: 2), onTimeout: () => right(unit))
      .catchError(_asUnchangedPreference);
  runApp(const CerneApp());
}

// `catchError`'s handler must still complete the Future with a value of
// its declared type (`Either<Failure, Unit>`) — a `void`-returning handler
// would try to complete it with `null`, which isn't assignable to that
// non-nullable type and would itself throw. Top-level (not a
// `_CerneAppState` method) so both `main()`'s own awaited fetch above and
// `CerneApp.initState`'s fire-and-forget one below can share it.
Either<Failure, Unit> _asUnchangedPreference(
  Object error,
  StackTrace stackTrace,
) {
  debugPrint('Cerne: fetchBiometricEnabled() threw unexpectedly ($error)');
  return left(Failure.malformedResponse(message: error.toString()));
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
  late final VaultRepository _vaultRepository;
  late final AccountSettingsRepository _accountSettingsRepository;
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
    _vaultRepository = sl<VaultRepository>();
    _accountSettingsRepository = sl<AccountSettingsRepository>();
    _router = buildAppRouter(
      vaultRepository: _vaultRepository,
      sessionRepository: _sessionRepository,
      accountSettingsRepository: _accountSettingsRepository,
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
    // Story 2.4 — boot-time read of `biometricEnabled`, same
    // fire-and-forget rationale as `restoreSession()` above: the outcome
    // reaches `VaultLockScreen` through `AccountSettingsRepository.
    // currentBiometricEnabled`/`biometricEnabledStream` (which the router's
    // `refreshListenable` already watches), never through this call's
    // return value, and a failure leaves `currentBiometricEnabled`
    // unchanged (I/O matrix) rather than surfacing anywhere.
    unawaited(
      _accountSettingsRepository.fetchBiometricEnabled().catchError(
        _asUnchangedPreference,
      ),
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
