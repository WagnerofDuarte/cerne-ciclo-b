import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/sync_badge_state.dart';

/// `EntryRecordCard`'s own sync badge (Code Map) — a colored dot
/// ([DesignTokens.colorWarningSync]/[DesignTokens.colorSuccess]/
/// [DesignTokens.colorError]) plus its text label, always visible (not
/// hidden behind a tap). "Accessible label on tap/long-focus" is split
/// across two single-purpose widgets rather than two that both also
/// announce it: the dot's [Tooltip] (`excludeFromSemantics: true`) gives
/// the *visual* long-press popup only, while the one [Semantics] node
/// wrapping the whole badge (below) is the single accessibility
/// announcement on focus — code-review round 1 finding: a [Tooltip] left
/// at its default `excludeFromSemantics: false` injects its own semantics
/// label too, so pairing it with an outer [Semantics] of the same label
/// double-announced it to screen readers.
///
/// Only an [SyncBadgeError] badge is ever tappable (Boundaries): a
/// [Failure.retryable] one calls [onRetryTap] on tap (I/O matrix: "Tap
/// calls `tracker.retry(tempId)`, re-sends same payload"); a
/// non-retryable one instead toggles an inline explanation
/// ([SyncBadgeError.failure]'s own `message`) with no network call and no
/// retry affordance (Boundaries: "else render inline explanation text, no
/// tap affordance"). [SyncBadgeSynchronizing]/[SyncBadgeSynchronized] are
/// never tappable at all.
class SyncBadge extends StatefulWidget {
  const SyncBadge({required this.state, this.onRetryTap, super.key});

  final SyncBadgeState state;

  /// Called on tap only for a retryable [SyncBadgeError] — ignored (never
  /// even referenced) for every other state, and for a non-retryable
  /// error (Boundaries: "no tap affordance" there means no retry action,
  /// not no tap at all — tapping a non-retryable error still reveals its
  /// explanation, just never calls this).
  final VoidCallback? onRetryTap;

  @override
  State<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<SyncBadge> {
  bool _explanationExpanded = false;

  @override
  void didUpdateWidget(SyncBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A retry attempt (or any other state transition) collapses a
    // previously-shown explanation — stale text from a superseded
    // failure should never linger once the badge has moved on (e.g.
    // synchronizing -> a *new* error after a retry that fails again).
    if (widget.state != oldWidget.state) {
      _explanationExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final (color, label) = switch (state) {
      SyncBadgeSynchronizing() => (
        DesignTokens.colorWarningSync,
        'Sincronizando',
      ),
      SyncBadgeSynchronized() => (DesignTokens.colorSuccess, 'Sincronizado'),
      SyncBadgeError() => (DesignTokens.colorError, 'Erro de sincronização'),
    };

    // Reuses the existing kanban color-dot token (8dp) rather than a new
    // literal (RNF08) — same shape/role (a small colored status dot), just
    // a different screen. `excludeFromSemantics: true` (Review finding):
    // the outer `Semantics(label: label)` below is this badge's one and
    // only accessibility announcement — this Tooltip exists purely for
    // its own visual long-press popup.
    final dot = Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Container(
        width: DesignTokens.kanbanDotSize,
        height: DesignTokens.kanbanDotSize,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );

    // `ExcludeSemantics` (Review finding): without it, the visible `Text`
    // below contributes its *own* implicit semantics label ("Sincronizando",
    // same string) that merges straight into the explicit `Semantics(label:
    // label)` container wrapping this whole row — doubling the announced
    // label even after the dot's own `Tooltip` was already excluded above.
    // The one `Semantics(label: label)` node is this badge's single source
    // of truth for its accessible text; this row is purely visual.
    final labelRow = ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: DesignTokens.spacingXs),
          Text(
            label,
            style: DesignTokens.textMonoCaption.copyWith(color: color),
          ),
        ],
      ),
    );

    if (state is! SyncBadgeError) {
      // `container: true` (Review finding) — without it, a `Semantics`
      // widget with no interactive descendant doesn't form its own node;
      // Flutter merges its `label` up into the nearest explicit container
      // ancestor instead (e.g. the Scaffold's own), so `label` alone is
      // never exactly what a screen reader (or `find.bySemanticsLabel`)
      // reports for this widget specifically.
      return Semantics(label: label, container: true, child: labelRow);
    }

    final retryable = state.failure.retryable;
    return Semantics(
      label: label,
      container: true,
      button: true,
      child: InkWell(
        onTap: () {
          if (retryable) {
            widget.onRetryTap?.call();
          } else {
            setState(() => _explanationExpanded = !_explanationExpanded);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DesignTokens.insertionModalTapTargetMin,
            minHeight: DesignTokens.insertionModalTapTargetMin,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                labelRow,
                if (!retryable && _explanationExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                    child: Text(
                      state.failure.message,
                      style: DesignTokens.textCaptionSm.copyWith(
                        color: DesignTokens.colorTextSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
