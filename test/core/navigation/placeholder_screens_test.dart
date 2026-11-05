import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/navigation/placeholder_screens.dart';

/// Minimal two-route `GoRouter` for the three back-arrow placeholders —
/// their header's back arrow does `context.go('/')` (Boundaries: "back-arrow
/// always targets `/`"), which needs a real `GoRouter` ancestor to resolve.
GoRouter _routerFrom(String path, Widget screen) {
  return GoRouter(
    initialLocation: path,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const Text('Home')),
      GoRoute(path: path, builder: (context, state) => screen),
    ],
  );
}

void main() {
  group('BootSplashScreen (moved from main.dart)', () {
    testWidgets(
      'stays blank below the 300ms threshold, shows a spinner once past it',
      (tester) async {
        await tester.pumpWidget(const MaterialApp(home: BootSplashScreen()));

        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(milliseconds: 299));
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.pump(const Duration(milliseconds: 2));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );
  });

  group('BiometricReauthPlaceholderScreen (moved from main.dart)', () {
    testWidgets('renders the throwaway "Biometria" placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: BiometricReauthPlaceholderScreen()),
      );

      expect(find.text('Biometria'), findsOneWidget);
    });
  });

  group(
    'ActionPlansPlaceholderScreen — Tela 5, extension, never implemented',
    () {
      testWidgets(
        'renders the prototype\'s exact static 3-column kanban with its '
        'hardcoded example cards, and its back arrow targets /',
        (tester) async {
          final router = _routerFrom(
            '/planos-de-acao',
            const ActionPlansPlaceholderScreen(),
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(MaterialApp.router(routerConfig: router));

          expect(find.text('Planos de Ação'), findsOneWidget);

          // Columns, with counts.
          expect(find.text('A Fazer'), findsOneWidget);
          expect(find.text('Em Andamento'), findsOneWidget);
          expect(find.text('Concluído'), findsOneWidget);
          expect(find.text('2'), findsNWidgets(2));
          expect(find.text('1'), findsOneWidget);

          // Exact hardcoded example cards from the prototype.
          expect(find.text('Organizar registros da semana'), findsOneWidget);
          expect(find.text('Revisar metas do mês'), findsOneWidget);
          expect(
            find.text('Praticar escrita livre 3x por semana'),
            findsOneWidget,
          );
          expect(find.text('Configurar lembretes diários'), findsOneWidget);
          expect(find.text('Primeira semana de registros'), findsOneWidget);

          await tester.tap(find.byIcon(Icons.chevron_left));
          await tester.pumpAndSettle();
          expect(router.state.uri.toString(), '/');
        },
      );
    },
  );
}
