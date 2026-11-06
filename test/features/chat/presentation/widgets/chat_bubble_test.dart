import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/chat/domain/entities/bookmark_state.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_bubble.dart';

Future<void> _pump(
  WidgetTester tester,
  ChatUiMessage message, {
  bool disableAnimations = false,
  VoidCallback? onRetry,
  ValueChanged<String>? onBookmark,
}) async {
  await tester.pumpWidget(
    Builder(
      builder: (outerContext) => MediaQuery(
        data: MediaQuery.of(outerContext).copyWith(
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: ChatBubble(
              message: message,
              onRetry: onRetry,
              onBookmark: onBookmark,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('ChatBubble — exactly 3 visible states (RF04 Acceptance Criteria)', () {
    testWidgets(
      'user bubble: colorChatBubbleUser fill, squared bottom-right corner',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Olá',
            status: ChatMessageStatus.complete,
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(ChatBubble),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, DesignTokens.colorChatBubbleUser);
        final radius = decoration.borderRadius! as BorderRadius;
        expect(radius.bottomRight, Radius.zero);
        expect(radius.bottomLeft, const Radius.circular(DesignTokens.radiusMd));
        expect(decoration.boxShadow, isNull);
      },
    );

    testWidgets(
      'AI bubble: colorSurfaceElevated fill, squared bottom-left corner, '
      'resting elevation',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Oi, como posso ajudar?',
            status: ChatMessageStatus.complete,
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(ChatBubble),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration as BoxDecoration;
        expect(decoration.color, DesignTokens.colorSurfaceElevated);
        final radius = decoration.borderRadius! as BorderRadius;
        expect(radius.bottomLeft, Radius.zero);
        expect(radius.bottomRight, const Radius.circular(DesignTokens.radiusMd));
        expect(decoration.boxShadow, DesignTokens.elevation1);
      },
    );

    testWidgets(
      'streaming state shows a blinking cursor by default',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Gerando',
            status: ChatMessageStatus.streaming,
          ),
        );

        expect(find.text('▏'), findsOneWidget);
      },
    );

    testWidgets(
      'Reduce Motion (disableAnimations) skips the cursor entirely, text '
      'still renders',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Gerando',
            status: ChatMessageStatus.streaming,
          ),
          disableAnimations: true,
        );

        expect(find.text('▏'), findsNothing);
        expect(find.textContaining('Gerando'), findsOneWidget);
      },
    );

    testWidgets(
      'complete state shows no cursor',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Pronto',
            status: ChatMessageStatus.complete,
          ),
        );

        expect(find.text('▏'), findsNothing);
      },
    );

    testWidgets(
      'spec-6-3: failed state shows the tap-to-retry copy above the '
      'timestamp caption (never in place of it), text is never cleared',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'resposta parcial',
            status: ChatMessageStatus.failed,
          ),
        );

        expect(find.textContaining('resposta parcial'), findsOneWidget);
        expect(
          find.text('Falha ao gerar resposta — toque para tentar novamente'),
          findsOneWidget,
        );
        // Correction: `cerne-prototype.html`'s own `{{ msg.time }}` span is
        // unconditional — a failed bubble still shows the timestamp
        // caption right below the retry note, never hidden behind it.
        expect(find.text('agora'), findsOneWidget);
        // No cursor either — streaming and failed are mutually exclusive
        // visible states.
        expect(find.text('▏'), findsNothing);
      },
    );

    testWidgets(
      'spec-6-3: tapping the retry copy invokes onRetry — tap target is '
      '44pt min and exposed as Semantics(button: true)',
      (tester) async {
        var tapped = false;
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'resposta parcial',
            status: ChatMessageStatus.failed,
          ),
          onRetry: () => tapped = true,
        );

        await tester.tap(
          find.text('Falha ao gerar resposta — toque para tentar novamente'),
        );
        await tester.pump();
        expect(tapped, isTrue);

        final semantics = tester.getSemantics(
          find.ancestor(
            of: find.text(
              'Falha ao gerar resposta — toque para tentar novamente',
            ),
            matching: find.byWidgetPredicate((w) => w is Semantics),
          ).first,
        );
        expect(
          semantics.flagsCollection.isButton,
          isTrue,
        );

        final constrainedBoxes = tester.widgetList<ConstrainedBox>(
          find.ancestor(
            of: find.text(
              'Falha ao gerar resposta — toque para tentar novamente',
            ),
            matching: find.byType(ConstrainedBox),
          ),
        );
        expect(
          constrainedBoxes.map((c) => c.constraints.minHeight),
          contains(DesignTokens.insertionModalTapTargetMin),
        );
      },
    );

    testWidgets(
      'spec-6-3 review finding: a failed bubble built with no onRetry '
      'callback exposes no button semantics node',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'resposta parcial',
            status: ChatMessageStatus.failed,
          ),
        );

        expect(
          find.textContaining('toque para tentar novamente'),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'a non-failed bubble never renders the retry copy, regardless of '
      'onRetry being set',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Pronto',
            status: ChatMessageStatus.complete,
          ),
          onRetry: () {},
        );

        expect(
          find.textContaining('toque para tentar novamente'),
          findsNothing,
        );
      },
    );
  });

  group('spec-6-4 — bookmark affordance, user bubbles only', () {
    testWidgets(
      'Boundaries: never rendered on an AI bubble, regardless of state or '
      'onBookmark being set',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.assistant,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.saved(),
          ),
          onBookmark: (_) {},
        );

        expect(find.byIcon(Icons.bookmark_border), findsNothing);
        expect(find.byIcon(Icons.check), findsNothing);
      },
    );

    testWidgets(
      'idle: outline icon, neutral color',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
          ),
          onBookmark: (_) {},
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.bookmark_border));
        expect(icon.color, DesignTokens.colorTextSecondary);
        expect(icon.size, DesignTokens.chatBookmarkIconSize);
      },
    );

    testWidgets(
      'saving: a spinner by default',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.saving(),
          ),
          onBookmark: (_) {},
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Salvando'), findsNothing);
      },
    );

    testWidgets(
      'saving under Reduce Motion: a static label instead of the '
      'spinner, in a width-capped slot',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.saving(),
          ),
          disableAnimations: true,
          onBookmark: (_) {},
        );

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Salvando'), findsOneWidget);
        final constrainedBoxes = tester.widgetList<ConstrainedBox>(
          find.ancestor(
            of: find.text('Salvando'),
            matching: find.byType(ConstrainedBox),
          ),
        );
        expect(
          constrainedBoxes.map((c) => c.constraints.maxWidth),
          contains(DesignTokens.chatBookmarkSavingLabelMaxWidth),
        );
      },
    );

    testWidgets(
      'saved: ochre check (colorAccent)',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.saved(),
          ),
          onBookmark: (_) {},
        );

        final icon = tester.widget<Icon>(find.byIcon(Icons.check));
        expect(icon.color, DesignTokens.colorAccent);
      },
    );

    testWidgets(
      'error: red warning icon (colorError)',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: '1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.error(
              Failure.networkTimeout(message: 'timeout'),
            ),
          ),
          onBookmark: (_) {},
        );

        final icon = tester.widget<Icon>(
          find.byIcon(Icons.warning_amber_rounded),
        );
        expect(icon.color, DesignTokens.colorError);
      },
    );

    testWidgets(
      'tapping it invokes onBookmark with the message id — tap target is '
      '44pt min and exposed as Semantics(button: true)',
      (tester) async {
        String? tappedId;
        await _pump(
          tester,
          const ChatUiMessage(
            id: 'msg-1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
          ),
          onBookmark: (id) => tappedId = id,
        );

        await tester.tap(find.byIcon(Icons.bookmark_border));
        await tester.pump();

        expect(tappedId, 'msg-1');

        final semantics = tester.getSemantics(
          find.ancestor(
            of: find.byIcon(Icons.bookmark_border),
            matching: find.byWidgetPredicate((w) => w is Semantics),
          ).first,
        );
        expect(semantics.flagsCollection.isButton, isTrue);

        final constrainedBoxes = tester.widgetList<ConstrainedBox>(
          find.ancestor(
            of: find.byIcon(Icons.bookmark_border),
            matching: find.byType(ConstrainedBox),
          ),
        );
        expect(
          constrainedBoxes.map((c) => c.constraints.minWidth),
          contains(DesignTokens.insertionModalTapTargetMin),
        );
        expect(
          constrainedBoxes.map((c) => c.constraints.minHeight),
          contains(DesignTokens.insertionModalTapTargetMin),
        );
      },
    );

    testWidgets(
      'with no onBookmark callback: the icon still renders (state is '
      'always visible) but exposes no button semantics node',
      (tester) async {
        await _pump(
          tester,
          const ChatUiMessage(
            id: 'msg-1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
          ),
        );

        expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.button ?? false),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tapping a saved bubble is still routed through onBookmark — the '
      'client-side no-op lives in ChatCubit, not this widget',
      (tester) async {
        var tapCount = 0;
        await _pump(
          tester,
          const ChatUiMessage(
            id: 'msg-1',
            role: ChatMessageRole.user,
            content: 'Oi',
            status: ChatMessageStatus.complete,
            bookmarkState: BookmarkState.saved(),
          ),
          onBookmark: (_) => tapCount++,
        );

        await tester.tap(find.byIcon(Icons.check));
        await tester.pump();

        expect(tapCount, 1);
      },
    );
  });
}
