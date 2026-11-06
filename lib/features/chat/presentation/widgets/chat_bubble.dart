import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../domain/entities/bookmark_state.dart';
import '../../domain/entities/chat_message.dart';
import '../cubit/chat_state.dart';

/// Review finding: shared by the `Semantics.label` and the visible `Text`
/// below so a future copy edit can't desync the spoken label from what's
/// actually on screen.
const _retryCopy = 'Falha ao gerar resposta — toque para tentar novamente';

/// spec-6-4 — the bookmark affordance's own per-[BookmarkState] semantics
/// label (`Semantics.label`), kept alongside its own icon/color mapping
/// below so the two can never desync, same rationale [_retryCopy] already
/// gives.
String _bookmarkSemanticsLabel(BookmarkState state) => switch (state) {
  BookmarkIdle() => 'Salvar como registro',
  BookmarkSaving() => 'Salvando registro',
  BookmarkSaved() => 'Registro salvo',
  BookmarkError() => 'Falha ao salvar registro — toque para tentar novamente',
};

/// One message bubble — user (Boundaries: `colorChatBubbleUser`, squared
/// bottom-right corner) vs AI (`colorSurfaceElevated`, squared bottom-left
/// corner, resting [DesignTokens.elevation1]). Exactly the 3 visible
/// states RF04's Acceptance Criteria names render here, driven by
/// [ChatUiMessage.status]: `streaming` (progressive text + blinking
/// cursor), `failed` (spec-6-3: a tappable tap-to-retry indicator,
/// invoking [onRetry], renders *above* the timestamp caption —
/// `cerne-prototype.html`'s own markup never hides the time behind it),
/// `complete` (plain text, nothing else). [ChatUiMessage.content] itself is
/// rendered as-is in every state — never cleared on failure (I/O matrix).
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    required this.message,
    this.onRetry,
    this.onBookmark,
    super.key,
  });

  final ChatUiMessage message;

  /// spec-6-3 — invoked when the user taps a `failed` AI bubble's own
  /// retry copy; `null` on a user bubble (never shown there, only an AI
  /// response ever fails) or whenever a caller has nothing to wire it to.
  final VoidCallback? onRetry;

  /// spec-6-4 — invoked with [message.id] when the user taps the bookmark
  /// affordance on one of their own ([ChatMessageRole.user]) bubbles;
  /// `null` whenever a caller has nothing to wire it to (same convention
  /// [onRetry] already uses). Never shown at all on an AI bubble
  /// (Boundaries), regardless of this being set.
  final ValueChanged<String>? onBookmark;

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
    // indicator. Correction: `cerne-prototype.html`'s own markup renders
    // this as a bare `<span>` below the bubble — plain red text, no
    // background band, not banded *inside* the bubble the way a previous
    // pass built it. Correction: the prototype's own `{{ msg.time }}` span
    // sits right after this one, unconditionally — this note is additional
    // (shown above the timestamp), never a replacement for it; an earlier
    // pass rendered the two as mutually exclusive, hiding the time whenever
    // a bubble failed.
    // `Semantics(button: true)` only wraps it when [onRetry] is actually
    // supplied (review finding) — a bubble built with no retry callback
    // must never be announced to a screen reader as a working button.
    final retryIndicator = InkWell(
      onTap: onRetry,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: DesignTokens.insertionModalTapTargetMin,
        ),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: DesignTokens.chatFailureIndicatorPadding,
            child: Text(
              _retryCopy,
              style: DesignTokens.textCaptionSm.copyWith(
                color: DesignTokens.colorError,
              ),
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

    // Correction: `cerne-prototype.html`'s own bubble markup puts this
    // `IBM Plex Mono`/`colorTextSecondary` caption *below* the bubble, on
    // every message — including a `failed` one (right below the retry
    // note, never hidden behind it) — a previous pass never rendered it at
    // all. "agora"
    // ([ChatUiMessage.createdAt]'s own doc) for a message with no server
    // timestamp yet; otherwise the server `createdAt`'s local wall-clock
    // time, `HH:mm` (same parse-for-display convention
    // `entry_record_card.dart`'s own `_formatTime` already uses — a
    // malformed timestamp falls back to the same "agora" placeholder
    // rather than throwing, RNF09).
    final timeCaption = Text(
      _formatTime(message.createdAt),
      style: DesignTokens.textMonoCaption.copyWith(
        color: DesignTokens.colorTextSecondary,
      ),
    );

    // spec-6-4 — Boundaries: the bookmark affordance exists only on
    // `ChatMessageRole.user` bubbles; its icon+color pair is driven
    // unconditionally off `message.bookmarkState` (same "icon always
    // reflects state regardless of a wired callback" convention
    // `retryIndicator` above already uses), with the tappable
    // `Semantics(button: true)` wrapper gated on `onBookmark` actually
    // being supplied. Built lazily, only inside the `isUser` branch below
    // (review finding: an AI bubble can never carry a meaningful
    // `bookmarkState`, so there's no reason to construct this —
    // including `_BookmarkIndicator`'s own switch over it — just to
    // discard it every AI-bubble rebuild).
    final onBookmark = widget.onBookmark;
    Widget buildBookmarkButton() {
      final bookmarkButton = InkWell(
        onTap: onBookmark == null ? null : () => onBookmark(message.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: DesignTokens.insertionModalTapTargetMin,
            minHeight: DesignTokens.insertionModalTapTargetMin,
          ),
          child: Center(
            child: _BookmarkIndicator(
              state: message.bookmarkState,
              reduceMotion: reduceMotion,
            ),
          ),
        ),
      );
      return onBookmark == null
          ? bookmarkButton
          : Semantics(
              button: true,
              label: _bookmarkSemanticsLabel(message.bookmarkState),
              excludeSemantics: true,
              child: bookmarkButton,
            );
    }

    // The timestamp caption and the bookmark button sit side by side
    // (Code Map: "bookmark button beside timeCaption") — only on a user
    // bubble; an AI bubble's own caption row is unchanged. The caption is
    // wrapped in `Flexible` + ellipsis (review finding) so this 2-child
    // row — new with this story, the AI-only `timeCaption` alone was
    // never at risk — can't overflow under extreme accessibility text
    // scaling; in practice the `HH:mm`/"agora" caption is always short
    // enough that this never visibly truncates.
    final timeRow = isUser
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _formatTime(message.createdAt),
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textMonoCaption.copyWith(
                    color: DesignTokens.colorTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spacingXs),
              buildBookmarkButton(),
            ],
          )
        : timeCaption;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width *
              DesignTokens.chatBubbleMaxWidthFraction,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: DesignTokens.chatBubbleGap),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: DesignTokens.chatBubblePadding,
                decoration: BoxDecoration(
                  color: isUser
                      ? DesignTokens.colorChatBubbleUser
                      : DesignTokens.colorSurfaceElevated,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(DesignTokens.radiusMd),
                    topRight: const Radius.circular(DesignTokens.radiusMd),
                    bottomLeft: Radius.circular(
                      isUser ? DesignTokens.radiusMd : 0,
                    ),
                    bottomRight: Radius.circular(
                      isUser ? 0 : DesignTokens.radiusMd,
                    ),
                  ),
                  boxShadow: isUser ? null : DesignTokens.elevation1,
                ),
                child: Text.rich(
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
              ),
              const SizedBox(height: DesignTokens.spacingXs),
              // Correction: the prototype's own `{{ msg.time }}` span is
              // unconditional — a `failed` bubble shows the retry note
              // *and* the time caption right below it (the retry
              // indicator's own `chatFailureIndicatorPadding` bottom inset
              // already supplies the matching 4px gap between the two).
              if (message.status == ChatMessageStatus.failed)
                retryIndicatorWithSemantics,
              timeRow,
            ],
          ),
        ),
      ),
    );
  }
}

/// spec-6-4 — [ChatBubble]'s own bookmark glyph: icon + color together,
/// never color alone (Boundaries), one combination per [BookmarkState].
/// [BookmarkSaving] swaps to a static label instead of the spinner under
/// Reduce Motion — kept in its own width-capped slot
/// ([DesignTokens.chatBookmarkSavingLabelMaxWidth], the same
/// maxWidth-constrained shape [ChatBubble]'s own outer bubble container
/// is constrained by) so it can never grow past its slot and squeeze the
/// message bubble under large accessibility text scaling.
class _BookmarkIndicator extends StatelessWidget {
  const _BookmarkIndicator({required this.state, required this.reduceMotion});

  final BookmarkState state;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      BookmarkIdle() => const Icon(
        Icons.bookmark_border,
        size: DesignTokens.chatBookmarkIconSize,
        color: DesignTokens.colorTextSecondary,
      ),
      BookmarkSaving() =>
        reduceMotion
            ? ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesignTokens.chatBookmarkSavingLabelMaxWidth,
                ),
                child: Text(
                  'Salvando',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textCaptionSm.copyWith(
                    color: DesignTokens.colorTextSecondary,
                  ),
                ),
              )
            : const SizedBox(
                width: DesignTokens.chatBookmarkIconSize,
                height: DesignTokens.chatBookmarkIconSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
      BookmarkSaved() => const Icon(
        Icons.check,
        size: DesignTokens.chatBookmarkIconSize,
        color: DesignTokens.colorAccent,
      ),
      BookmarkError() => const Icon(
        Icons.warning_amber_rounded,
        size: DesignTokens.chatBookmarkIconSize,
        color: DesignTokens.colorError,
      ),
    };
  }
}

/// [ChatBubble]'s own timestamp caption — `createdAt`'s local wall-clock
/// time, `HH:mm`, or "agora" for a message with no server timestamp yet
/// ([ChatUiMessage.createdAt]'s own doc) or one that fails to parse
/// (RNF09: never throws on a malformed value), same defensive shape
/// `entry_record_card.dart`'s own `_formatTime` already uses.
String _formatTime(String? createdAt) {
  if (createdAt == null) {
    return 'agora';
  }
  final local = DateTime.tryParse(createdAt)?.toLocal();
  if (local == null) {
    return 'agora';
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
