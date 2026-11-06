import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/failure/failure.dart';
import '../../../../core/widgets/app_drawer.dart';
import '../../../capture/presentation/cubit/audio_entry_cubit.dart';
import '../../../capture/presentation/cubit/photo_entry_cubit.dart';
import '../../../capture/presentation/cubit/text_entry_cubit.dart';
import '../../../capture/presentation/widgets/insertion_modal.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_bubble.dart';

/// Tela 1 — Home/Chat, RF04's first real (non-placeholder) screen: the
/// same dark-green header + drawer chrome the deleted
/// `HomeChatPlaceholderScreen` used, now with a real message list and
/// composer. [cubit] is injected rather than resolved internally
/// (`sl<ChatCubit>()` stays the router's own job, Code Map), so a test can
/// pass a fake-repository-backed instance directly.
class ChatScreen extends StatefulWidget {
  const ChatScreen({required this.cubit, super.key});

  final ChatCubit cubit;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _composerFocusNode = FocusNode();

  /// The last [ChatReady.sessionId] this screen has already reacted to —
  /// `null` until the very first [ChatReady] (bootstrap). Distinguishes
  /// "the active session just changed" (spec-6-2: `switchSession`/
  /// `startNewSession`, or the initial bootstrap) from an ordinary
  /// in-session update (a streamed token, a bookmark state change) that
  /// happens to carry the same [ChatReady.restoreScrollOffset] value
  /// forward via `copyWith` — only the former should ever trigger a
  /// scroll jump or request composer focus.
  String? _lastSessionId;

  @override
  void initState() {
    super.initState();
    // `ChatCubit.init()`'s own no-op guard makes this safe to call on
    // every mount (Boundaries: "silently ensure one Chat Session exists").
    widget.cubit.init();
    _scrollController.addListener(_recordScrollOffset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_recordScrollOffset);
    _textController.dispose();
    _scrollController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  /// Boundaries: "Scroll-offset restore is in-memory only, keyed by
  /// `sessionId`, on `ChatCubit`" — this is the one listener that keeps
  /// it current, firing on every scroll update while a session is active.
  void _recordScrollOffset() {
    final state = widget.cubit.state;
    if (state is ChatReady && _scrollController.hasClients) {
      widget.cubit.recordScrollOffset(
        state.sessionId,
        _scrollController.position.pixels,
      );
    }
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      return;
    }
    widget.cubit.sendMessage(text);
    _textController.clear();
  }

  /// Only jumps to the bottom when the view was already there (or close
  /// to it) *before* this update, or hasn't attached to a scrollable yet
  /// (the very first history render) — otherwise a user who deliberately
  /// scrolled up to reread earlier history would get yanked back down on
  /// every single streamed token.
  void _scrollToBottomSoon() {
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      const nearBottomThreshold = 80.0;
      final wasNearBottom =
          position.maxScrollExtent - position.pixels <= nearBottomThreshold;
      if (!wasNearBottom) {
        return;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// I/O matrix: "Switch session" — jumps to [offset] once the just-built
  /// history has attached to a scrollable, clamped to the actual
  /// `maxScrollExtent` in case the recorded offset no longer fits (a
  /// shorter history than when it was recorded).
  void _jumpToOffset(double offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(offset.clamp(0, maxExtent));
      }
    });
  }

  /// Acceptance Criteria: "Given I tap 'Novo Chat' ... it opens empty,
  /// composer focused" — called whenever a session switch (new or past)
  /// lands on zero messages, per the listener's own `state.messages.
  /// isEmpty` guard below; a brand new session is always empty, so this
  /// satisfies the AC, but an empty *past* session switched back into
  /// would trigger it too (harmless — focusing the composer on an empty
  /// conversation is never wrong, just not the literal scenario the AC
  /// names).
  void _focusComposerSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _composerFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatCubit>.value(
      value: widget.cubit,
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        drawer: const AppDrawer(),
        // Boundaries: "heavier drawer scrim rgba(36,31,25,.4)" — overrides
        // `Scaffold`'s own default barrier, same convention the deleted
        // `HomeChatPlaceholderScreen` already used.
        drawerScrimColor: DesignTokens.colorScrimHeavy,
        body: Column(
          children: [
            const _ChatHeader(),
            // spec-6-3 — the offline banner, visible for the lifetime of
            // `ChatReady.isOffline`; renders nothing otherwise. Sits
            // between the header and the message list (Code Map) so
            // history stays fully visible/scrollable underneath it
            // (Boundaries).
            BlocBuilder<ChatCubit, ChatState>(
              builder: (context, state) => state is ChatReady && state.isOffline
                  ? const _OfflineBanner()
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: BlocConsumer<ChatCubit, ChatState>(
                listener: (context, state) {
                  if (state is! ChatReady) {
                    return;
                  }
                  final isNewSession = state.sessionId != _lastSessionId;
                  _lastSessionId = state.sessionId;
                  if (!isNewSession) {
                    _scrollToBottomSoon();
                    return;
                  }
                  final restoreScrollOffset = state.restoreScrollOffset;
                  if (restoreScrollOffset != null) {
                    _jumpToOffset(restoreScrollOffset);
                  } else {
                    _scrollToBottomSoon();
                  }
                  if (state.messages.isEmpty) {
                    _focusComposerSoon();
                  }
                },
                builder: (context, state) => switch (state) {
                  ChatBootstrapLoading() => const Center(
                    child: CircularProgressIndicator(
                      color: DesignTokens.colorPrimary,
                    ),
                  ),
                  ChatBootstrapError(failure: final failure) =>
                    _ChatBootstrapErrorView(failure: failure),
                  ChatReady(messages: final messages) => ListView.builder(
                    controller: _scrollController,
                    padding: DesignTokens.screenPadding,
                    itemCount: messages.length,
                    itemBuilder: (context, index) => ChatBubble(
                      key: ValueKey(messages[index].id),
                      message: messages[index],
                      // spec-6-3 — only a `failed` AI bubble ever renders
                      // the tap-to-retry copy at all (`ChatBubble`'s own
                      // guard), so wiring this unconditionally on every
                      // bubble is harmless.
                      onRetry: () =>
                          widget.cubit.retryMessage(messages[index].id),
                    ),
                  ),
                },
              ),
            ),
            _ChatComposer(
              controller: _textController,
              focusNode: _composerFocusNode,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// The same dark-green header + ☰-opens-drawer wiring the deleted
/// `HomeChatPlaceholderScreen` used — moved here verbatim rather than
/// shared from a common widget, since that screen is deleted wholesale
/// (Code Map) and no third screen needs this exact header yet.
class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.colorPrimary,
      padding: DesignTokens.navHeaderPadding,
      child: Builder(
        builder: (context) => Row(
          children: [
            GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: const Icon(
                Icons.menu,
                size: DesignTokens.navMenuIconSize,
                color: DesignTokens.colorOnPrimary,
              ),
            ),
            Expanded(
              child: Text(
                'Cerne',
                textAlign: TextAlign.center,
                style: DesignTokens.textTitleLg.copyWith(
                  color: DesignTokens.colorOnPrimary,
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.navMenuIconSize),
          ],
        ),
      ),
    );
  }
}

/// I/O matrix: "Bootstrap failure" — a generic error state, not an
/// infinite spinner; no retry action exists yet (Boundaries: the
/// retry-tap action belongs to Story 6.2–6.5).
class _ChatBootstrapErrorView extends StatelessWidget {
  const _ChatBootstrapErrorView({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DesignTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: DesignTokens.spacing2xl,
              color: DesignTokens.colorError,
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            Text(
              'Não foi possível carregar a conversa',
              textAlign: TextAlign.center,
              style: DesignTokens.textHeadlineMd.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// spec-6-3 Boundaries — a full-width band between `_ChatHeader` and the
/// message list, `Icons.wifi_off` + `colorInfoOffline`/`colorOnPrimary`
/// (both pre-existing tokens, `colorInfoOffline`'s own doc: "Offline
/// banner — single use"). Disables sending only — the message list
/// underneath it stays fully visible/scrollable (Boundaries).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: DesignTokens.colorInfoOffline,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off,
            size: DesignTokens.dialogIconSize,
            color: DesignTokens.colorOnPrimary,
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(
            child: Text(
              'Sem conexão — histórico disponível, novas mensagens '
              'bloqueadas',
              style: DesignTokens.textCaptionSm.copyWith(
                color: DesignTokens.colorOnPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The composer row — "+" (`InsertionModal.show`, unchanged), a text
/// field (placeholder "Escreva uma mensagem...") and a send icon. The
/// text field and send icon are disabled while the bootstrap hasn't
/// resolved yet, while an AI bubble is still `streaming` (Code
/// Map/`ChatCubit.sendMessage`'s own same-shaped guard), or while offline
/// (spec-6-3: `ChatReady.isOffline`); the "+" stays tappable regardless,
/// same as the deleted placeholder's own always-tappable "+" and
/// Boundaries: "Disabling the '+' when offline ... [stays]".
class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final canSend =
            state is ChatReady && !state.isSending && !state.isOffline;
        // Correction: `cerne-prototype.html`'s own composer markup is
        // `background:#FBF9F4;border-top:1px solid #E1DACB` — a lighter
        // surface than the screen's own `colorSurfaceBg` behind it, with a
        // thin divider on top; a previous pass left the bar fully
        // transparent (no fill, no border at all).
        return Container(
          decoration: const BoxDecoration(
            color: DesignTokens.colorSurfaceElevated,
            border: Border(top: BorderSide(color: DesignTokens.colorBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: DesignTokens.screenPadding,
              child: Row(
                children: [
                  Semantics(
                    button: true,
                    label: 'Adicionar registro',
                    excludeSemantics: true,
                    child: IconButton(
                      onPressed: () => InsertionModal.show(
                        context,
                        cubit: sl<TextEntryCubit>(),
                        audioCubit: sl<AudioEntryCubit>(),
                        photoCubit: sl<PhotoEntryCubit>(),
                      ),
                      icon: const Icon(
                        Icons.add,
                        color: DesignTokens.colorPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: canSend,
                      // `chat-messages-send`'s own request schema caps
                      // `content` at 8000 characters (openapi.yaml) — a
                      // client-side cap surfaces that limit directly
                      // instead of letting an over-length message fail
                      // only after a round trip, indistinguishable from a
                      // dropped connection.
                      maxLength: 8000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: canSend ? (_) => onSend() : null,
                      style: DesignTokens.textBodyLg.copyWith(
                        color: DesignTokens.colorTextPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Escreva uma mensagem...',
                        counterText: '',
                        contentPadding: DesignTokens.textFieldContentPadding,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(DesignTokens.radiusFull),
                          ),
                          borderSide: BorderSide(
                            color: DesignTokens.colorBorder,
                            width: DesignTokens.borderWidthDefault,
                          ),
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(DesignTokens.radiusFull),
                          ),
                          borderSide: BorderSide(
                            color: DesignTokens.colorBorder,
                            width: DesignTokens.borderWidthDefault,
                          ),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(DesignTokens.radiusFull),
                          ),
                          borderSide: BorderSide(
                            color: DesignTokens.colorPrimary,
                            width: DesignTokens.borderWidthEmphasis,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Enviar mensagem',
                    excludeSemantics: true,
                    child: IconButton(
                      onPressed: canSend ? onSend : null,
                      // Correction: `cerne-prototype.html`'s own
                      // `ph-paper-plane-tilt` is the Phosphor library's
                      // Regular (outline) style — `Icons.send` is a solid
                      // glyph; `Icons.send_outlined` is the matching outline
                      // variant.
                      icon: Icon(
                        Icons.send_outlined,
                        color: canSend
                            ? DesignTokens.colorPrimary
                            : DesignTokens.colorTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
