import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/chat/domain/entities/chat_insight.dart';
import 'package:cerne/features/chat/presentation/widgets/insight_card.dart';

const _insight = ChatInsight(
  id: 'ins-1',
  content: 'Você mencionou gratidão em 3 registros esta semana.',
);

Future<void> _pump(
  WidgetTester tester, {
  ChatInsight insight = _insight,
  VoidCallback? onDismiss,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InsightCard(
          insight: insight,
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the mono "INSIGHT" label and the insight\'s own '
      'content', (tester) async {
    await _pump(tester);

    expect(find.text('INSIGHT'), findsOneWidget);
    expect(
      find.text('Você mencionou gratidão em 3 registros esta semana.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'the ochre spine is the only accent-colored element — a '
    'colorAccent-filled bar of chatInsightSpineWidth, and nothing else in '
    'the card uses that color',
    (tester) async {
      await _pump(tester);

      final accentContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(InsightCard),
              matching: find.byType(Container),
            ),
          )
          .where((container) => container.color == DesignTokens.colorAccent)
          .toList();

      // Review fix: the frozen Acceptance Criteria says the spine is the
      // *only* accent-colored element — exactly one colorAccent surface
      // must exist, and the "INSIGHT" label itself must stay neutral
      // (`colorTextSecondary`, same convention `ChatBubble.timeCaption`
      // already uses), not also colorAccent.
      expect(accentContainers, hasLength(1));
      final spine = accentContainers.single;
      expect(spine.constraints?.maxWidth, DesignTokens.chatInsightSpineWidth);
      expect(spine.constraints?.minWidth, DesignTokens.chatInsightSpineWidth);

      final labelStyle = tester.widget<Text>(find.text('INSIGHT')).style;
      expect(labelStyle?.color, DesignTokens.colorTextSecondary);
    },
  );

  testWidgets('tapping the dismiss icon calls onDismiss exactly once', (
    tester,
  ) async {
    var dismissCount = 0;
    await _pump(tester, onDismiss: () => dismissCount++);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissCount, 1);
  });

  testWidgets(
    'the dismiss icon sits inside a tappable area at least '
    'insertionModalTapTargetMin wide/tall (44pt min tap target)',
    (tester) async {
      await _pump(tester);

      final constrainedBoxes = tester.widgetList<ConstrainedBox>(
        find.descendant(
          of: find.byType(InsightCard),
          matching: find.byType(ConstrainedBox),
        ),
      );
      final dismissTapTarget = constrainedBoxes.firstWhere(
        (box) =>
            box.constraints.minWidth ==
                DesignTokens.insertionModalTapTargetMin &&
            box.constraints.minHeight ==
                DesignTokens.insertionModalTapTargetMin,
      );

      expect(dismissTapTarget.constraints.minWidth, greaterThanOrEqualTo(44));
      expect(
        dismissTapTarget.constraints.minHeight,
        greaterThanOrEqualTo(44),
      );
    },
  );

  testWidgets(
    'the dismiss affordance is announced to assistive tech as a button',
    (tester) async {
      await _pump(tester);

      final semantics = tester.getSemantics(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byWidgetPredicate((w) => w is Semantics),
        ).first,
      );
      expect(semantics.flagsCollection.isButton, isTrue);
    },
  );
}
