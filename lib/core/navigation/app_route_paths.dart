/// Every route this app shell resolves — Story 1.6's original set
/// (`/boot`, `/auth`, `/reauth`, `/`, `/meus-registros`, `/planos-de-acao`,
/// `/configuracoes`) plus Epic 2/spec-2-1's `/vault` lock screen. Named
/// constants so no call site retypes a path literal that could drift from
/// the one `GoRouter` in `app_router.dart`.
///
/// Split out of `app_router.dart` (review fix, spec-4-4 round 2) — a
/// screen that only needs a path constant (e.g. `MeusRegistrosScreen`
/// building its own detail-route push) can depend on this file alone
/// instead of on `app_router.dart`, which in turn depends on that same
/// screen to build its route — importing `app_router.dart` from such a
/// screen created an import cycle between the two.
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
