import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/chat_insight.dart';

/// spec-6-5 — the proactive-insight card: an ochre left spine (UX &
/// Interaction Patterns: "the spine is the only accent-colored element
/// inside the chat stream itself"), a mono "INSIGHT" label, [insight]'s
/// own content, and a dismiss "x". `ChatScreen` interleaves exactly one of
/// these as the trailing item of its message list whenever
/// `ChatReady.activeInsight` is non-null (Code Map) — never a second,
/// independently scrollable surface.
class InsightCard extends StatelessWidget {
  const InsightCard({
    required this.insight,
    required this.onDismiss,
    super.key,
  });

  final ChatInsight insight;

  /// Invoked when the dismiss "x" is tapped — wired to
  /// `ChatCubit.dismissInsight()` by `ChatScreen`; never calls the
  /// backend itself (Boundaries), this widget only ever reports the tap.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: DesignTokens.chatBubbleGap),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        boxShadow: DesignTokens.elevation1,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The ochre spine — a plain colored bar flush against the
            // card's own rounded left edge (via the outer `Container`'s
            // `Clip.antiAlias` above), rather than a `BoxDecoration.
            // border` (a single-sided border combined with
            // `borderRadius` renders unreliably in Flutter).
            Container(
              width: DesignTokens.chatInsightSpineWidth,
              color: DesignTokens.colorAccent,
            ),
            Expanded(
              child: Padding(
                padding: DesignTokens.chatInsightCardPadding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'INSIGHT',
                            // Review fix: the spine is the only
                            // accent-colored element (frozen Acceptance
                            // Criteria) — the label itself stays neutral,
                            // same `colorTextSecondary` mono-caption
                            // convention `ChatBubble`'s own `timeCaption`
                            // already uses.
                            style: DesignTokens.textMonoCaption.copyWith(
                              color: DesignTokens.colorTextSecondary,
                            ),
                          ),
                          const SizedBox(
                            height: DesignTokens.chatInsightLabelSpacing,
                          ),
                          Text(
                            insight.content,
                            style: DesignTokens.textBodyMd.copyWith(
                              color: DesignTokens.colorTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: 'Descartar insight',
                      excludeSemantics: true,
                      child: InkWell(
                        onTap: onDismiss,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: DesignTokens.insertionModalTapTargetMin,
                            minHeight: DesignTokens.insertionModalTapTargetMin,
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.close,
                              size: DesignTokens.chatInsightDismissIconSize,
                              color: DesignTokens.colorTextSecondary,
                            ),
                          ),
                        ),
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
}
