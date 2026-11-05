import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/entries/presentation/widgets/entries_search_bar.dart';

void main() {
  testWidgets(
    'Acceptance Criteria: renders the hint text, a trailing funnel icon, '
    'and no submit button anywhere on the widget',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EntriesSearchBar(onChanged: (_) {}))),
      );

      expect(find.text('Buscar nos registros...'), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      // No `Icons.search`/submit affordance anywhere, and the one
      // `TextField` never wires `onSubmitted` (Boundaries: "never
      // submitted via a button").
      expect(find.byIcon(Icons.search), findsNothing);
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.onSubmitted, isNull);
    },
  );

  testWidgets(
    'Review finding: the unlabeled funnel icon button carries a tooltip '
    'so a screen-reader user gets some indication of its purpose',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EntriesSearchBar(onChanged: (_) {}))),
      );

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Filtros');
    },
  );

  testWidgets(
    'every keystroke feeds onChanged directly, with the raw (untrimmed) '
    'value — trimming/debouncing is EntriesSearchCubit\'s own job, never '
    'this widget\'s',
    (tester) async {
      final received = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EntriesSearchBar(onChanged: received.add)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ansiedade ');

      expect(received, ['ansiedade ']);
    },
  );

  testWidgets(
    'the trailing funnel button is a no-op this story (spec-5-1 Boundaries '
    '— filters land in spec-5-2) but is tappable at the shared 44pt tap '
    'target',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EntriesSearchBar(onChanged: (_) {}))),
      );

      // Tapping must not throw and must not call onChanged.
      final received = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EntriesSearchBar(onChanged: received.add)),
        ),
      );
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pump();

      expect(received, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
