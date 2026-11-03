import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_tokens.dart';
import '../navigation/app_router.dart';
import 'avatar.dart';

/// Tela 3 — Menu lateral, the sole navigation hub (Boundaries: "no
/// drawer-within-drawer, no tab bar"). Native Flutter `Drawer` (Boundaries:
/// "not a hand-rolled overlay like `ConfirmationDialog`").
///
/// The header shows a generic, non-personalized [Avatar] + static label —
/// no real logged-in identity is wired up yet (Boundaries; see
/// deferred-work.md for why). There is no `CONVERSAS`/past-session list
/// (RF04/RF07 aren't built) — only the static "Novo Chat" action (closes
/// the drawer, no-op) and the three nav items.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: DesignTokens.drawerWidth,
      backgroundColor: DesignTokens.colorSurfaceElevated,
      shape: const RoundedRectangleBorder(),
      // No `SafeArea` here — `drawerContentPadding`'s fixed top value (59)
      // already clears the status bar, same convention every other header
      // in this story uses (`HomeChatPlaceholderScreen`, `_BackArrowHeader`
      // in `placeholder_screens.dart`); the epic's fixed 390x844 single
      // frame has no responsive/dynamic-inset handling anywhere else, so
      // stacking `SafeArea` on top would double-count that clearance.
      child: Padding(
        padding: DesignTokens.drawerContentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: DesignTokens.drawerHeaderPadding,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: DesignTokens.colorBorder),
                ),
              ),
              child: const Row(
                children: [
                  Avatar(initials: 'U'),
                  SizedBox(width: DesignTokens.drawerHeaderGap),
                  Text('Usuário', style: DesignTokens.textTitleSm),
                ],
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            _DrawerPrimaryAction(
              icon: Icons.add,
              label: 'Novo Chat',
              // No real chat yet (RF04/RF07) — closes the drawer, stays
              // on `/` (I/O matrix: "drawer closes, stays on /").
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            _DrawerNavItem(
              icon: Icons.menu_book_outlined,
              label: 'Meus Registros',
              onTap: () => _navigate(context, AppRoutePaths.meusRegistros),
            ),
            _DrawerNavItem(
              icon: Icons.view_kanban_outlined,
              label: 'Planos de Ação',
              onTap: () => _navigate(context, AppRoutePaths.planosDeAcao),
            ),
            _DrawerNavItem(
              icon: Icons.settings_outlined,
              label: 'Configurações',
              onTap: () => _navigate(context, AppRoutePaths.configuracoes),
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String location) {
    Navigator.of(context).pop();
    context.go(location);
  }
}

class _DrawerPrimaryAction extends StatelessWidget {
  const _DrawerPrimaryAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.radiusSm),
      ),
      child: Container(
        padding: DesignTokens.drawerPrimaryActionPadding,
        decoration: const BoxDecoration(
          color: DesignTokens.colorPrimary,
          borderRadius: BorderRadius.all(
            Radius.circular(DesignTokens.radiusSm),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: DesignTokens.drawerItemIconSize,
              color: DesignTokens.colorOnPrimary,
            ),
            const SizedBox(width: DesignTokens.navHeaderGap),
            Text(
              label,
              style: DesignTokens.textLabelMd.copyWith(
                color: DesignTokens.colorOnPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: DesignTokens.drawerNavItemPadding,
        child: Row(
          children: [
            Icon(
              icon,
              size: DesignTokens.drawerItemIconSize,
              color: DesignTokens.colorTextPrimary,
            ),
            const SizedBox(width: DesignTokens.navHeaderGap),
            Text(
              label,
              style: DesignTokens.textBodyMd.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
