import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'app_button.dart';

/// Shared confirmation-dialog overlay (prototype-extract.md §6: "scrim +
/// centered card; neutral title (session) or red title (destructive
/// deletion)"). Story 1.5 is the first consumer (neutral `colorTextPrimary`
/// title, the session-expiry recovery copy); a later story (Epic 8's
/// account-deletion confirm) reuses this same widget with [titleColor]
/// set to `DesignTokens.colorError` and a heavier [barrierColor].
///
/// UX-DR16/25/27/36: non-dismissible barrier, focus trapped on the dialog,
/// `scrimIn` (0.18s ease-out fade) as the only entrance choreography, and
/// at most one instance open at a time — [show] is the one way this
/// widget is ever presented, and owns that single-overlay guard itself so
/// no caller has to re-implement it.
class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.barrierColor,
    this.titleColor = DesignTokens.colorTextPrimary,
    this.caption,
    this.confirmButtonColor,
    this.cancelLabel,
    this.onCancel,
  }) : assert(
         (cancelLabel == null) == (onCancel == null),
         'cancelLabel and onCancel must be supplied together',
       );

  final IconData icon;
  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;

  /// Story 8.5 — forwarded to the confirm [AppButton]'s own
  /// `backgroundColor`. `null` keeps the exact pre-existing filled-primary
  /// look (Story 1.5's session-expiry confirm); the account-deletion
  /// confirm passes `colorError` for its destructive "Apagar tudo" button.
  final Color? confirmButtonColor;

  /// Story 8.5 — the outline "Cancelar"-style second button, shown only
  /// when both this and [onCancel] are non-null (Boundaries: "both null
  /// together -> no cancel button, exact current session-expiry shape
  /// preserved"). Session-expiry (Story 1.5) passes neither — its overlay
  /// has only the one confirm action.
  final String? cancelLabel;

  /// Story 8.5 — the cancel button's own tap handler. The widget itself
  /// never pops the dialog on the caller's behalf (same convention
  /// [onConfirm] already follows, e.g. `expiry_overlay_host.dart`'s own
  /// `Navigator.of(dialogContext).pop()` inside its `onConfirm`) — the
  /// caller's callback pops the dialog and nothing else (Boundaries:
  /// "pops the dialog only, no network call").
  final VoidCallback? onCancel;

  /// The full-bleed scrim color behind the centered card — callers pass
  /// `DesignTokens.colorScrim` (session-expiry, Story 1.5) or the heavier
  /// drawer/sheet value a later story uses for its own confirmation.
  final Color barrierColor;

  /// Neutral (`colorTextPrimary`, the default — Story 1.5's session copy)
  /// or destructive (`colorError`, a later story's account-deletion
  /// confirm) — never any other color (Boundaries: "neutral
  /// `colorTextPrimary` title, never `colorError`" for *this* story's own
  /// call site).
  final Color titleColor;

  /// Small mono caption below the button (Story 1.5: "o histórico e a
  /// posição do scroll são preservados"). Optional — a future destructive
  /// confirmation has no equivalent.
  final String? caption;

  /// Whether an instance is currently showing — the single-overlay guard
  /// (UX-DR16/25/27/36: "never stacks on another open overlay"). Exposed
  /// for tests; callers should not need to read it directly.
  static bool isOpen = false;

  /// Presents [builder]'s [ConfirmationDialog] as a non-dismissible,
  /// focus-trapped overlay above whatever screen is currently showing,
  /// without replacing it — the underlying route stays mounted, so its
  /// scroll/state is preserved (Boundaries: "the authenticated screen's
  /// widget instance is never replaced").
  ///
  /// A second call while one is already open is a silent no-op (I/O
  /// matrix: "already-open overlay ... no second dialog stacks").
  static Future<void> show({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    if (isOpen) {
      return Future<void>.value();
    }
    isOpen = true;
    try {
      return showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        // The framework's own `ModalBarrier` stays fully transparent — the
        // scrim actually seen on screen is this widget's own `build()`
        // below, which lets `transitionBuilder` fade the scrim and the card
        // together as one `scrimIn` choreography instead of two separately
        // animated layers.
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        pageBuilder: (context, animation, secondaryAnimation) => PopScope(
          // UX-DR16/25/27/36 — non-dismissible: `barrierDismissible: false`
          // above only stops a scrim tap; without this, the system/hardware
          // back gesture would still pop the route and close the overlay.
          canPop: false,
          child: builder(context),
        ),
      ).whenComplete(() => isOpen = false);
    } catch (_) {
      // A synchronous throw from `showGeneralDialog` (e.g. a future caller
      // passing a `context` with no `Navigator` ancestor) must still release
      // the guard — otherwise every later `show()` call, from any caller,
      // silently no-ops forever.
      isOpen = false;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: barrierColor),
        // `LayoutBuilder` + `ConstrainedBox(minHeight: ...)` is the
        // standard "centered, but scrollable if it doesn't fit" shape:
        // ordinary-scale content still centers vertically exactly as
        // before (the min-height constraint is satisfied with room to
        // spare, so `Center` centers within it), but under an extreme
        // Dynamic Type scale — where the card's intrinsic height can
        // exceed the screen — this scrolls instead of overflowing
        // (RNF08's "no control truncates under Dynamic Type").
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: DesignTokens.dialogScreenMargin,
                  child: _Card(
                    icon: icon,
                    title: title,
                    titleColor: titleColor,
                    message: message,
                    confirmLabel: confirmLabel,
                    onConfirm: onConfirm,
                    caption: caption,
                    confirmButtonColor: confirmButtonColor,
                    cancelLabel: cancelLabel,
                    onCancel: onCancel,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.titleColor,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    required this.caption,
    required this.confirmButtonColor,
    required this.cancelLabel,
    required this.onCancel,
  });

  final IconData icon;
  final String title;
  final Color titleColor;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String? caption;
  final Color? confirmButtonColor;
  final String? cancelLabel;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: DesignTokens.dialogCardPadding,
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusLg)),
        boxShadow: DesignTokens.elevation2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: DesignTokens.dialogIconSize,
                color: DesignTokens.colorPrimary,
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Text(
                  title,
                  style: DesignTokens.textTitleSm.copyWith(color: titleColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.dialogContentGap),
          Text(
            message,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorTextSecondary,
            ),
          ),
          const SizedBox(height: DesignTokens.dialogContentGap),
          AppButton(
            label: confirmLabel,
            onPressed: onConfirm,
            backgroundColor: confirmButtonColor,
          ),
          // Story 8.5 — the outline "Cancelar" button, shown only when both
          // cancelLabel/onCancel are supplied (class doc).
          if (cancelLabel != null && onCancel != null) ...[
            const SizedBox(height: DesignTokens.dialogContentGap),
            AppButton(
              label: cancelLabel!,
              onPressed: onCancel,
              variant: AppButtonVariant.secondaryOutline,
            ),
          ],
          if (caption != null) ...[
            const SizedBox(height: DesignTokens.dialogContentGap),
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: DesignTokens.textMonoCaption.copyWith(
                color: DesignTokens.colorTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
