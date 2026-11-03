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
class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  // Guards every action below against a rapid double-tap (on the same
  // item, or a different one) firing `Navigator.of(context).pop()` twice —
  // the second call would land after the drawer's own pop already started
  // closing it, popping the route beneath the drawer instead of being a
  // no-op (code review, Story 1.6).
  bool _actionTaken = false;

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
              onTap: () => _closeDrawer(context),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            // Second drawer block (code review, Story 1.6): the prototype's
            // own markup groups "Novo Chat" separately from the three
            // static nav items below, via a `border-top` + `padding-top`
            // on this section (ground truth: `cerne-prototype.html`'s
            // `<!-- OVERLAY: Drawer -->` block) — not reproduced until now.
            Container(
              padding: DesignTokens.drawerSectionDividerPadding,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: DesignTokens.colorBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DrawerNavItem(
                    icon: Icons.menu_book_outlined,
                    label: 'Meus Registros',
                    onTap: () =>
                        _navigate(context, AppRoutePaths.meusRegistros),
                  ),
                  _DrawerNavItem(
                    icon: Icons.view_kanban_outlined,
                    label: 'Planos de Ação',
                    onTap: () =>
                        _navigate(context, AppRoutePaths.planosDeAcao),
                  ),
                  _DrawerNavItem(
                    icon: Icons.settings_outlined,
                    label: 'Configurações',
                    onTap: () =>
                        _navigate(context, AppRoutePaths.configuracoes),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeDrawer(BuildContext context) {
    if (_actionTaken) {
      return;
    }
    _actionTaken = true;
    Navigator.of(context).pop();
  }

  void _navigate(BuildContext context, String location) {
    if (_actionTaken) {
      return;
    }
    _actionTaken = true;
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
