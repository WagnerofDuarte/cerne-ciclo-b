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
}) async {
  await tester.pumpWidget(
    Builder(
      builder: (outerContext) => MediaQuery(
        data: MediaQuery.of(outerContext).copyWith(
          disableAnimations: disableAnimations,
        ),
        child: MaterialApp(
          home: Scaffold(body: ChatBubble(message: message)),
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
      'failed state: the generic error indicator replaces the timestamp '
      'slot, text is never cleared, and the copy is never the tap-to-retry '
      'copy (that action belongs to a later story)',
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
        expect(find.text('Falha ao gerar resposta'), findsOneWidget);
        expect(
          find.textContaining('toque para tentar novamente'),
          findsNothing,
        );
        // No cursor either — streaming and failed are mutually exclusive
        // visible states.
        expect(find.text('▏'), findsNothing);
      },
    );
  });
}
