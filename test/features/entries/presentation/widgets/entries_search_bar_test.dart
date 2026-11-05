import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/features/entries/presentation/widgets/entries_search_bar.dart';

void main() {
  testWidgets(
    'Acceptance Criteria: renders the hint text, a leading magnifying-glass '
    'icon, a trailing funnel icon, and no submit button anywhere on the '
    'widget',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntriesSearchBar(onChanged: (_) {}, onFilterTap: () {}),
          ),
        ),
      );

      expect(find.text('Buscar nos registros...'), findsOneWidget);
      // Correction: `cerne-prototype.html`'s own search field has its own
      // leading magnifying-glass icon, same as the filter button's own
      // funnel.
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.filter_list), findsOneWidget);
      // No submit affordance anywhere — the one `TextField` never wires
      // `onSubmitted` (Boundaries: "never submitted via a button").
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.onSubmitted, isNull);
    },
  );

  testWidgets(
    'Review finding: the unlabeled funnel icon button carries a tooltip '
    'so a screen-reader user gets some indication of its purpose',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntriesSearchBar(onChanged: (_) {}, onFilterTap: () {}),
          ),
        ),
      );

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Filtros');
    },
  );

  testWidgets(
    'Round-2 review fix: with hasActiveFilters true, the tooltip itself '
    'also signals that filters are currently applied, not just the '
    'filled icon color',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntriesSearchBar(
              onChanged: (_) {},
              onFilterTap: () {},
              hasActiveFilters: true,
            ),
          ),
        ),
      );

      final iconButton = tester.widget<IconButton>(find.byType(IconButton));
      expect(iconButton.tooltip, 'Filtros (ativos)');
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
          home: Scaffold(
            body: EntriesSearchBar(onChanged: received.add, onFilterTap: () {}),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'ansiedade ');

      expect(received, ['ansiedade ']);
    },
  );

  testWidgets(
    'spec-5-2: tapping the trailing funnel button calls onFilterTap, at '
    'the shared 44pt tap target',
    (tester) async {
      var filterTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntriesSearchBar(
              onChanged: (_) {},
              onFilterTap: () => filterTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pump();

      expect(filterTapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('spec-5-2 Boundaries: "fills the funnel icon" — hasActiveFilters '
      'switches the icon from colorTextSecondary to colorPrimary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntriesSearchBar(onChanged: (_) {}, onFilterTap: () {}),
        ),
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.filter_list)).color,
      DesignTokens.colorTextSecondary,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EntriesSearchBar(
            onChanged: (_) {},
            onFilterTap: () {},
            hasActiveFilters: true,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Icon>(find.byIcon(Icons.filter_list)).color,
      DesignTokens.colorPrimary,
    );
  });
}
