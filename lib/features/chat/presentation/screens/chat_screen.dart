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

  @override
  void initState() {
    super.initState();
    // `ChatCubit.init()`'s own no-op guard makes this safe to call on
    // every mount (Boundaries: "silently ensure one Chat Session exists").
    widget.cubit.init();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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
            Expanded(
              child: BlocConsumer<ChatCubit, ChatState>(
                listener: (context, state) {
                  if (state is ChatReady) {
                    _scrollToBottomSoon();
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
                    ),
                  ),
                },
              ),
            ),
            _ChatComposer(controller: _textController, onSend: _send),
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

/// The composer row — "+" (`InsertionModal.show`, unchanged), a text
/// field (placeholder "Escreva uma mensagem...") and a send icon.
/// Disabled as a whole while the bootstrap hasn't resolved yet or while
/// an AI bubble is still `streaming` (Code Map/`ChatCubit.sendMessage`'s
/// own same-shaped guard) — never a dedicated offline banner/lock, that's
/// Story 6.3's job (Boundaries).
class _ChatComposer extends StatelessWidget {
  const _ChatComposer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final canSend = state is ChatReady && !state.isSending;
        return SafeArea(
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
                    icon: const Icon(Icons.add, color: DesignTokens.colorPrimary),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
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
                    icon: Icon(
                      Icons.send,
                      color: canSend
                          ? DesignTokens.colorPrimary
                          : DesignTokens.colorTextSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
