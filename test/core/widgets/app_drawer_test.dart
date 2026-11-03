import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/app_drawer.dart';

/// Tiny standalone `GoRouter` — [AppDrawer] only needs *some* router
/// ancestor to resolve `context.go(...)`; this suite isn't exercising the
/// real app shell's redirect (that's `app_router_test.dart`'s job).
GoRouter _buildTestRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/meus-registros',
        builder: (context, state) => const Text('Meus Registros Screen'),
      ),
      GoRoute(
        path: '/planos-de-acao',
        builder: (context, state) => const Text('Planos Screen'),
      ),
      GoRoute(
        path: '/configuracoes',
        builder: (context, state) => const Text('Config Screen'),
      ),
    ],
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
  await tester.pumpAndSettle();
}

/// Tela 3 — Menu lateral (Boundaries: "no `CONVERSAS`/past-chat-session
/// list ... only the static 'Novo Chat' action ... and the three nav
/// items"; "no persisted/real user identity").
void main() {
  testWidgets(
    'header shows a generic avatar + static label, no real identity',
    (tester) async {
      final router = _buildTestRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      expect(find.text('Usuário'), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
    },
  );

  testWidgets('no CONVERSAS section / past-session list exists in the drawer', (
    tester,
  ) async {
    final router = _buildTestRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    expect(find.text('CONVERSAS'), findsNothing);
  });

  testWidgets(
    'tapping "Novo Chat" closes the drawer and stays on / (no-op, no real '
    'chat)',
    (tester) async {
      final router = _buildTestRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      await tester.tap(find.text('Novo Chat'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsNothing);
      expect(router.state.uri.toString(), '/');
    },
  );

  testWidgets(
    'tapping "Meus Registros" closes the drawer and navigates there',
    (tester) async {
      final router = _buildTestRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      await tester.tap(find.text('Meus Registros'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDrawer), findsNothing);
      expect(router.state.uri.toString(), '/meus-registros');
      expect(find.text('Meus Registros Screen'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Planos de Ação" closes the drawer and navigates there',
    (tester) async {
      final router = _buildTestRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await _openDrawer(tester);

      await tester.tap(find.text('Planos de Ação'));
      await tester.pumpAndSettle();

      expect(router.state.uri.toString(), '/planos-de-acao');
    },
  );

  testWidgets('tapping "Configurações" closes the drawer and navigates there', (
    tester,
  ) async {
    final router = _buildTestRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    await tester.tap(find.text('Configurações'));
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/configuracoes');
  });

  testWidgets('drawer width matches the design token', (tester) async {
    final router = _buildTestRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _openDrawer(tester);

    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.width, DesignTokens.drawerWidth);
  });
}
