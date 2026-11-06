import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/chat_message.dart';
import '../cubit/chat_state.dart';

/// Review finding: shared by the `Semantics.label` and the visible `Text`
/// below so a future copy edit can't desync the spoken label from what's
/// actually on screen.
const _retryCopy = 'Falha ao gerar resposta — toque para tentar novamente';

/// One message bubble — user (Boundaries: `colorChatBubbleUser`, squared
/// bottom-right corner) vs AI (`colorSurfaceElevated`, squared bottom-left
/// corner, resting [DesignTokens.elevation1]). Exactly the 3 visible
/// states RF04's Acceptance Criteria names render here, driven by
/// [ChatUiMessage.status]: `streaming` (progressive text + blinking
/// cursor), `failed` (spec-6-3: a tappable tap-to-retry indicator replaces
/// the timestamp slot, invoking [onRetry]), `complete` (plain text,
/// nothing else). [ChatUiMessage.content] itself is rendered as-is in
/// every state — never cleared on failure (I/O matrix).
class ChatBubble extends StatefulWidget {
  const ChatBubble({required this.message, this.onRetry, super.key});

  final ChatUiMessage message;

  /// spec-6-3 — invoked when the user taps a `failed` AI bubble's own
  /// retry copy; `null` on a user bubble (never shown there, only an AI
  /// response ever fails) or whenever a caller has nothing to wire it to.
  final VoidCallback? onRetry;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _syncCursorAnimation();
  }

  @override
  void didUpdateWidget(ChatBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCursorAnimation();
  }

  /// Keeps the ticker running only while actually needed — a message
  /// that finalizes to `complete`/`failed` must stop ticking forever
  /// after, both so a long-lived chat session never leaks one live
  /// `AnimationController` per past message, and so nothing waiting on
  /// "every animation in the tree has settled" (e.g. a test's own
  /// `pumpAndSettle()`) ever blocks on a bubble that finished streaming.
  void _syncCursorAnimation() {
    final shouldAnimate = widget.message.status == ChatMessageStatus.streaming;
    if (shouldAnimate && !_cursorController.isAnimating) {
      _cursorController.repeat(reverse: true);
    } else if (!shouldAnimate && _cursorController.isAnimating) {
      _cursorController.stop();
    }
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final onRetry = widget.onRetry;
    final isUser = message.role == ChatMessageRole.user;
    // Boundaries: "cursor skipped under
    // `MediaQuery.of(context).disableAnimations`" — the real token text
    // itself always reveals as real tokens actually arrive (there is no
    // separate typing-speed animation to collapse here), only the
    // blinking-cursor glyph is conditional on Reduce Motion.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final showCursor =
        message.status == ChatMessageStatus.streaming && !reduceMotion;

    // spec-6-3 Boundaries: tap-to-retry copy, tappable, 44pt min tap
    // target — replaces the earlier generic (non-tappable) error
    // indicator. The visible copy renders identically either way;
    // `Semantics(button: true)` only wraps it when [onRetry] is actually
    // supplied (review finding) — a bubble built with no retry callback
    // must never be announced to a screen reader as a working button.
    final retryIndicator = InkWell(
      onTap: onRetry,
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.radiusSm),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.insertionModalTapTargetMin,
        ),
        child: Container(
          alignment: Alignment.centerLeft,
          padding: DesignTokens.chatFailureIndicatorPadding,
          decoration: const BoxDecoration(
            color: DesignTokens.colorErrorBg,
            borderRadius: BorderRadius.all(
              Radius.circular(DesignTokens.radiusSm),
            ),
          ),
          child: Text(
            _retryCopy,
            style: DesignTokens.textCaptionSm.copyWith(
              color: DesignTokens.colorError,
            ),
          ),
        ),
      ),
    );
    final retryIndicatorWithSemantics = onRetry == null
        ? retryIndicator
        : Semantics(
            button: true,
            label: _retryCopy,
            excludeSemantics: true,
            child: retryIndicator,
          );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: DesignTokens.chatBubbleGap),
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              DesignTokens.chatBubbleMaxWidthFraction,
        ),
        padding: DesignTokens.chatBubblePadding,
        decoration: BoxDecoration(
          color: isUser
              ? DesignTokens.colorChatBubbleUser
              : DesignTokens.colorSurfaceElevated,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(DesignTokens.radiusMd),
            topRight: const Radius.circular(DesignTokens.radiusMd),
            bottomLeft: Radius.circular(isUser ? DesignTokens.radiusMd : 0),
            bottomRight: Radius.circular(isUser ? 0 : DesignTokens.radiusMd),
          ),
          boxShadow: isUser ? null : DesignTokens.elevation1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: message.content),
                  if (showCursor)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: ExcludeSemantics(
                        child: FadeTransition(
                          opacity: _cursorController,
                          child: const Text('▏'),
                        ),
                      ),
                    ),
                ],
              ),
              style: DesignTokens.textBodyLg.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
            ),
            if (message.status == ChatMessageStatus.failed) ...[
              const SizedBox(height: DesignTokens.spacingXs),
              retryIndicatorWithSemantics,
            ],
          ],
        ),
      ),
    );
  }
}
