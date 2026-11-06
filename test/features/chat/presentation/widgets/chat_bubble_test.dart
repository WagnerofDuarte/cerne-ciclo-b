import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/chat_message.dart';
import 'package:cerne/features/chat/presentation/cubit/chat_state.dart';
import 'package:cerne/features/chat/presentation/widgets/chat_bubble.dart';

Future<void> _pump(
  WidgetTester tester,
  ChatUiMessage message, {
  bool disableAnimations = false,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    Builder(
      builder: (outerContext) => MediaQuery(
        data: MediaQuery.of(outerContext).copyWith(
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: ChatBubble(message: message, onRetry: onRetry),
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
      'spec-6-3: failed state shows the tap-to-retry copy in place of the '
      'timestamp slot, text is never cleared',
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
}
