import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/entities/session_status.dart';
import '../../features/auth/domain/repositories/session_repository.dart';
import '../design_tokens.dart';
import '../widgets/confirmation_dialog.dart';
import 'app_router.dart';

/// `MaterialApp.router`'s `builder:` (moved from `main.dart`, Story 1.5's
/// overlay wiring now reworked for `go_router`, Code Map). Wraps whatever
/// [child] the router currently shows with the same one-shot
/// expired-session overlay `main.dart` used to own directly — the only
/// change is that "Entrar novamente" now navigates via [router] instead of
/// an imperative `Navigator.push`.
///
/// [router] is called directly (`router.go(...)`), never via
/// `context.go(...)` — `MaterialApp.router`'s `builder:` widget is inserted
/// *above* the `Navigator`/`InheritedGoRouter` it wraps (per
/// `WidgetsApp.builder`'s own doc), so this widget's own `BuildContext`
/// has no `GoRouter` ancestor to look up.
///
/// [navigatorKey] must be the exact same key passed to `GoRouter`'s own
/// `navigatorKey:` (via `buildAppRouter`) — it is how this widget reaches a
/// `BuildContext` *below* the Navigator (needed for `showGeneralDialog`)
/// using only `GoRouter`'s public, documented constructor API, rather than
/// reaching into its internal `routerDelegate`.
///
/// Story 1.5's boundaries are unchanged here: the overlay traps focus
/// until dismissed/actioned, is the only overlay allowed on screen at a
/// time, never navigates away on its own, and fires at most once per
/// `expired` episode.
class ExpiryOverlayHost extends StatefulWidget {
  const ExpiryOverlayHost({
    super.key,
    required this.sessionRepository,
    required this.router,
    required this.navigatorKey,
    required this.child,
  });

  final SessionRepository sessionRepository;
  final GoRouter router;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<ExpiryOverlayHost> createState() => _ExpiryOverlayHostState();
}

class _ExpiryOverlayHostState extends State<ExpiryOverlayHost> {
  StreamSubscription<SessionStatus>? _subscription;

  // Same two one-shot guards `main.dart` used to own (code review of
  // story-1-5): `_expiryOverlayShown` is a per-episode latch (nothing
  // today transitions `SessionStatus` back out of `expired`, so without
  // it a later event on this same subscription would reopen the overlay
  // on top of wherever the user already navigated after confirming it);
  // `_reauthRouteRequested` guards the dialog's own confirm callback
  // against a rapid double-tap during its 180ms exit fade.
  bool _expiryOverlayShown = false;
  bool _reauthRouteRequested = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.sessionRepository.statusStream.listen(
      _onStatus,
      // Mirrors `SessionRepositoryImpl`'s own internal subscriptions — no
      // current implementation ever errors on this stream, but a future
      // one that did must not surface as an unhandled zone exception.
      onError: (_, _) {},
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onStatus(SessionStatus status) {
    if (status != SessionStatus.expired || _expiryOverlayShown) {
      return;
    }
    _expiryOverlayShown = true;
    // `showGeneralDialog` (inside `ConfirmationDialog.show`) pushes a
    // route, which must never happen mid-build/mid-stream-callback —
    // deferred to `addPostFrameCallback`, same as `main.dart` did.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // This widget's own `context` sits *above* the router's `Navigator`
      // (see class doc) — `showGeneralDialog` needs a context *below* it,
      // which `NavigatorState.overlay`'s own context always is.
      final overlayContext = widget.navigatorKey.currentState?.overlay?.context;
      if (overlayContext == null) {
        // Navigator not mounted yet — nothing to show an overlay over.
        _expiryOverlayShown = false;
        return;
      }
      unawaited(
        ConfirmationDialog.show(
          context: overlayContext,
          builder: (dialogContext) => ConfirmationDialog(
            icon: Icons.lock_outline,
            title: 'Sessão expirada',
            message:
                'Sua sessão expirou por segurança. Entre novamente para '
                'continuar — sua conversa continua aqui.',
            caption: 'o histórico e a posição do scroll são preservados',
            confirmLabel: 'Entrar novamente',
            barrierColor: DesignTokens.colorScrim,
            onConfirm: () {
              if (_reauthRouteRequested) {
                return;
              }
              _reauthRouteRequested = true;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
              widget.router.go(AppRoutePaths.reauth);
            },
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
