import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/domain/entities/chat_session.dart';
import '../../features/chat/presentation/cubit/chat_cubit.dart';
import '../../features/chat/presentation/cubit/chat_state.dart';
import '../design_tokens.dart';
import '../navigation/app_router.dart';
import 'avatar.dart';

/// Tela 3 — Menu lateral, the sole navigation hub (Boundaries: "no
/// drawer-within-drawer, no tab bar"). Native Flutter `Drawer` (Boundaries:
/// "not a hand-rolled overlay like `ConfirmationDialog`").
///
/// The header shows a generic, non-personalized [Avatar] + static label —
/// no real logged-in identity is wired up yet (Boundaries; see
/// deferred-work.md for why).
///
/// spec-6-2 — the "CONVERSAS" section renders `ChatCubit`'s own
/// [ChatReady.sessions] via `context.read<ChatCubit>()`/`BlocBuilder`, the
/// exact instance `ChatScreen` already provides above this widget via
/// `BlocProvider<ChatCubit>.value` (Boundaries: "never a second
/// `sl<ChatCubit>()` inside `AppDrawer`") — never built/resolved here.
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
      // in this story uses (`ChatScreen`'s own header, `_BackArrowHeader`
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
            // spec-6-3 — "Novo Chat" disables (+ dims) while
            // `ChatReady.isOffline`, same `BlocBuilder<ChatCubit,
            // ChatState>` source the "CONVERSAS" section below already
            // reads from; `_startNewSession`'s own offline `SnackBar`
            // (spec-6-2) stays as a defense-in-depth fallback for the
            // brief window between a tap and the drawer actually
            // disabling (Boundaries: "never removing it").
            BlocBuilder<ChatCubit, ChatState>(
              builder: (context, state) {
                final isOffline = state is ChatReady && state.isOffline;
                return _DrawerPrimaryAction(
                  icon: Icons.add,
                  label: 'Novo Chat',
                  onTap: isOffline ? null : () => _startNewSession(context),
                );
              },
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            // The rest of the drawer scrolls as one unit (CONVERSAS plus
            // the static nav items below it) — a user with many Chat
            // Sessions must never overflow the fixed-height `Drawer`
            // (RenderFlex overflow), while the header and "Novo Chat"
            // above stay pinned.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocBuilder<ChatCubit, ChatState>(
                      builder: (context, state) {
                        if (state is! ChatReady) {
                          return const SizedBox.shrink();
                        }
                        return _ConversasSection(
                          sessions: state.sessions,
                          activeSessionId: state.sessionId,
                          onSelect: (sessionId) =>
                              _switchSession(context, sessionId),
                        );
                      },
                    ),
                    // Second drawer block (code review, Story 1.6): the
                    // prototype's own markup groups "Novo Chat" separately
                    // from the three static nav items below, via a
                    // `border-top` + `padding-top` on this section (ground
                    // truth: `cerne-prototype.html`'s
                    // `<!-- OVERLAY: Drawer -->` block).
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
                            onTap: () => _navigate(
                              context,
                              AppRoutePaths.meusRegistros,
                            ),
                          ),
                          _DrawerNavItem(
                            icon: Icons.view_kanban_outlined,
                            label: 'Planos de Ação',
                            onTap: () => _navigate(
                              context,
                              AppRoutePaths.planosDeAcao,
                            ),
                          ),
                          _DrawerNavItem(
                            icon: Icons.settings_outlined,
                            label: 'Configurações',
                            onTap: () => _navigate(
                              context,
                              AppRoutePaths.configuracoes,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, String location) {
    if (_actionTaken) {
      return;
    }
    _actionTaken = true;
    Navigator.of(context).pop();
    context.go(location);
  }

  /// I/O matrix: "New session online"/"New session offline" — `await`s
  /// `ChatCubit.startNewSession()`'s own `Either` (Boundaries: "a cubit
  /// action's result must be observed by its caller") and surfaces any
  /// [Failure] (including [Failure.networkOffline]) as a transient
  /// `SnackBar`; the drawer closes either way, the current session is
  /// left untouched on failure (`ChatCubit`'s own job, not this widget's).
  Future<void> _startNewSession(BuildContext context) async {
    if (_actionTaken) {
      return;
    }
    _actionTaken = true;
    final cubit = context.read<ChatCubit>();
    // Captured before `Navigator.pop()` closes this widget's own subtree
    // — `ScaffoldMessenger.of(context)` resolves to `ChatScreen`'s own
    // `Scaffold` (an ancestor of the drawer, Boundaries), whose messenger
    // instance outlives the drawer closing.
    final messenger = ScaffoldMessenger.of(context);
    final result = await cubit.startNewSession();
    if (!mounted || !context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      ),
      (_) {},
    );
  }

  /// I/O matrix: "Switch session"/"Switch to already-active session" —
  /// same `await` + observe-the-result shape as [_startNewSession].
  Future<void> _switchSession(BuildContext context, String sessionId) async {
    if (_actionTaken) {
      return;
    }
    _actionTaken = true;
    final cubit = context.read<ChatCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await cubit.switchSession(sessionId);
    if (!mounted || !context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    result.match(
      (failure) => messenger.showSnackBar(
        SnackBar(content: Text(failure.message)),
      ),
      (_) {},
    );
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

  /// spec-6-3 — `null` renders disabled + dimmed (Boundaries), same
  /// "disable by passing a null callback" convention `_ChatComposer`'s
  /// own send button already uses.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
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

/// spec-6-2 — the drawer's "CONVERSAS" section (`cerne-prototype.html`'s
/// Tela 3: "section 'CONVERSAS' with past sessions (title + timestamp)").
/// Renders nothing (an empty [SizedBox]) when [sessions] is empty — it
/// never is in practice, `ChatCubit._bootstrap` always resolves at least
/// one session, but this guard keeps the widget honest on its own.
class _ConversasSection extends StatelessWidget {
  const _ConversasSection({
    required this.sessions,
    required this.activeSessionId,
    required this.onSelect,
  });

  final List<ChatSession> sessions;
  final String activeSessionId;
  final void Function(String sessionId) onSelect;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const SizedBox.shrink();
    }
    // `listSessions()`'s own ordering isn't documented either way
    // (`ChatCubit._bootstrap`'s own comment) — defensively re-sorts most
    // recently updated first, same rationale as `_bootstrap`'s "reuse the
    // most recent" sort. Review finding: a malformed `updatedAt` must
    // never crash this build — `DateTime.tryParse` (same crash-safe
    // convention `_formatSessionTimestamp` below already uses, RNF09)
    // falls back to the epoch, sorting a malformed entry last rather than
    // throwing.
    final sorted = [...sessions]
      ..sort(
        (a, b) => (DateTime.tryParse(b.updatedAt) ?? DateTime(0)).compareTo(
          DateTime.tryParse(a.updatedAt) ?? DateTime(0),
        ),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingXs,
            vertical: DesignTokens.spacingSm,
          ),
          child: Text(
            'CONVERSAS',
            style: DesignTokens.textMonoCaption.copyWith(
              color: DesignTokens.colorTextSecondary,
            ),
          ),
        ),
        for (final session in sorted)
          _DrawerSessionItem(
            session: session,
            isActive: session.id == activeSessionId,
            onTap: () => onSelect(session.id),
          ),
      ],
    );
  }
}

/// One "CONVERSAS" row — [_DrawerNavItem]'s own tokens reused verbatim
/// (Boundaries: "no new design tokens"), plus a trailing mono timestamp
/// (prototype: "title + timestamp").
class _DrawerSessionItem extends StatelessWidget {
  const _DrawerSessionItem({
    required this.session,
    required this.isActive,
    required this.onTap,
  });

  final ChatSession session;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Boundaries: "An empty `title` renders fallback label 'Nova
    // conversa'" (the contract leaves an untitled session's `title`
    // undocumented).
    final title = session.title.trim().isEmpty
        ? 'Nova conversa'
        : session.title;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: DesignTokens.drawerNavItemPadding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DesignTokens.textBodyMd.copyWith(
                  color: isActive
                      ? DesignTokens.colorPrimary
                      : DesignTokens.colorTextPrimary,
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.spacingSm),
            Text(
              _formatSessionTimestamp(session.updatedAt),
              style: DesignTokens.textMonoCaption.copyWith(
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `updatedAt`'s local wall-clock time, `HH:mm` — same presentation-only
/// parse-for-display convention and `'--:--'` malformed-input fallback as
/// `entry_record_card.dart`'s own `_formatTime` (RNF09: never throws).
String _formatSessionTimestamp(String updatedAt) {
  final local = DateTime.tryParse(updatedAt)?.toLocal();
  if (local == null) {
    return '--:--';
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
