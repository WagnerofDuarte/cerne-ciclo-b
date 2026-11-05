import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/widgets/back_arrow_header.dart';

/// Story 2.4 extracted this from `placeholder_screens.dart`'s former
/// private `_BackArrowHeader` so it's reused, rather than duplicated, by
/// the real `AccountSettingsScreen` — `placeholder_screens_test.dart`
/// already proves `ActionPlansPlaceholderScreen` still renders/navigates
/// correctly through it (spec-4-1 later gave `MeusRegistrosScreen` its own
/// dedicated coverage of the same thing, `meus_registros_screen_test.dart`);
/// this suite proves the extracted widget itself, directly.
GoRouter _routerFrom(Widget screen) {
  return GoRouter(
    initialLocation: '/other',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('Home')),
      GoRoute(path: '/other', builder: (context, state) => screen),
    ],
  );
}

void main() {
  testWidgets('renders the given title', (tester) async {
    final router = _routerFrom(
      const Scaffold(body: BackArrowHeader(title: 'Qualquer Título')),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Qualquer Título'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('tapping the back arrow always targets / (Boundaries: "matches '
      'prototype\'s goHome on all three")', (tester) async {
    final router = _routerFrom(
      const Scaffold(body: BackArrowHeader(title: 'Qualquer Título')),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/');
    expect(find.text('Home'), findsOneWidget);
  });
}
