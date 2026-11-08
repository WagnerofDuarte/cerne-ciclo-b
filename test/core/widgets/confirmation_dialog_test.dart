import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/confirmation_dialog.dart';

Widget _appWithOpenButton({
  required VoidCallback onConfirm,
  String title = 'Sessão expirada',
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => ConfirmationDialog.show(
              context: context,
              builder: (dialogContext) => ConfirmationDialog(
                icon: Icons.lock_outline,
                title: title,
                message:
                    'Sua sessão expirou por segurança. Entre novamente para '
                    'continuar — sua conversa continua aqui.',
                caption: 'o histórico e a posição do scroll são preservados',
                confirmLabel: 'Entrar novamente',
                barrierColor: DesignTokens.colorScrim,
                onConfirm: onConfirm,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // `ConfirmationDialog.isOpen` is static (the single-overlay guard is
  // shared across every instance, by design — UX-DR16/25/27/36) — reset it
  // before each test so one test's unclosed dialog never leaks into the
  // next.
  setUp(() => ConfirmationDialog.isOpen = false);

  group('ConfirmationDialog', () {
    testWidgets(
      'renders with the neutral colorTextPrimary title by default, never '
      'colorError',
      (tester) async {
        await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final titleText = tester.widget<Text>(find.text('Sessão expirada'));
        expect(titleText.style!.color, DesignTokens.colorTextPrimary);
        expect(titleText.style!.color, isNot(DesignTokens.colorError));
      },
    );

    testWidgets(
      'honors a custom titleColor — the destructive variant a later story '
      '(account deletion) reuses this same widget for',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ConfirmationDialog.show(
                      context: context,
                      builder: (_) => ConfirmationDialog(
                        icon: Icons.delete_outline,
                        title: 'Apagar sua conta?',
                        message: 'Ação irreversível.',
                        confirmLabel: 'Apagar tudo',
                        titleColor: DesignTokens.colorError,
                        barrierColor: DesignTokens.colorScrim,
                        onConfirm: () {},
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final titleText = tester.widget<Text>(find.text('Apagar sua conta?'));
        expect(titleText.style!.color, DesignTokens.colorError);
      },
    );

    testWidgets(
      'tapping the scrim does nothing — the barrier is non-dismissible and '
      'the dialog stays on screen',
      (tester) async {
        await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);

        // Well outside the centered card (which has a 20dp screen margin
        // and is vertically centered) — squarely on the scrim.
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
      },
    );

    testWidgets(
      'the scrim actually absorbs the tap — it never reaches a widget '
      'behind the overlay (not just "the dialog is still there")',
      (tester) async {
        var backgroundTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: GestureDetector(
                        onTap: () => backgroundTapped = true,
                        child: const SizedBox(width: 20, height: 20),
                      ),
                    ),
                    Center(
                      child: ElevatedButton(
                        onPressed: () => ConfirmationDialog.show(
                          context: context,
                          builder: (_) => ConfirmationDialog(
                            icon: Icons.lock_outline,
                            title: 'Sessão expirada',
                            message: 'Mensagem.',
                            confirmLabel: 'Entrar novamente',
                            barrierColor: DesignTokens.colorScrim,
                            onConfirm: () {},
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Squarely on the background `GestureDetector` at (0,0)-(20,20).
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(backgroundTapped, isFalse);
      },
    );

    testWidgets(
      'focus is trapped on the dialog — Tab traversal never reaches a '
      'focusable widget in the screen behind it',
      (tester) async {
        final backgroundFocusNode = FocusNode(debugLabel: 'background');
        addTearDown(backgroundFocusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    TextField(focusNode: backgroundFocusNode),
                    Center(
                      child: ElevatedButton(
                        onPressed: () => ConfirmationDialog.show(
                          context: context,
                          builder: (_) => ConfirmationDialog(
                            icon: Icons.lock_outline,
                            title: 'Sessão expirada',
                            message: 'Mensagem.',
                            confirmLabel: 'Entrar novamente',
                            barrierColor: DesignTokens.colorScrim,
                            onConfirm: () {},
                          ),
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        for (var i = 0; i < 5; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(backgroundFocusNode.hasFocus, isFalse);
        }
      },
    );

    testWidgets('the overlay route is wrapped in a non-poppable PopScope — the '
        'system back gesture cannot dismiss it (canPop: false bypasses only '
        'an explicit Navigator.pop/maybePop call, never the OS back button, '
        'which is the one this guards against)', (tester) async {
      await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets(
      'at most one instance is ever open — a second show() call while one '
      'is already open is a silent no-op (I/O matrix: no second dialog '
      'stacks)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      ConfirmationDialog.show(
                        context: context,
                        builder: (_) => ConfirmationDialog(
                          icon: Icons.lock_outline,
                          title: 'First overlay',
                          message: 'First message.',
                          confirmLabel: 'Ok',
                          barrierColor: DesignTokens.colorScrim,
                          onConfirm: () {},
                        ),
                      );
                      ConfirmationDialog.show(
                        context: context,
                        builder: (_) => ConfirmationDialog(
                          icon: Icons.lock_outline,
                          title: 'Second overlay',
                          message: 'Second message.',
                          confirmLabel: 'Ok',
                          barrierColor: DesignTokens.colorScrim,
                          onConfirm: () {},
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('First overlay'), findsOneWidget);
        expect(find.text('Second overlay'), findsNothing);
      },
    );

    testWidgets(
      'no cancelLabel/onCancel -> exactly one button, the exact current '
      'session-expiry shape preserved (Boundaries: "both null together")',
      (tester) async {
        await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(OutlinedButton), findsNothing);
        expect(
          find.widgetWithText(ElevatedButton, 'Entrar novamente'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'cancelLabel + onCancel both supplied -> a second, outline button '
      'appears below the confirm button (Story 8.5)',
      (tester) async {
        var cancelled = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ConfirmationDialog.show(
                      context: context,
                      builder: (dialogContext) => ConfirmationDialog(
                        icon: Icons.delete_outline,
                        title: 'Apagar sua conta?',
                        message: 'Ação irreversível.',
                        confirmLabel: 'Apagar tudo',
                        titleColor: DesignTokens.colorError,
                        confirmButtonColor: DesignTokens.colorError,
                        barrierColor: DesignTokens.colorScrimHeavy,
                        cancelLabel: 'Cancelar',
                        onCancel: () {
                          cancelled = true;
                          Navigator.of(dialogContext).pop();
                        },
                        onConfirm: () {},
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Apagar tudo'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        expect(cancelled, isTrue);
        // Tapping Cancelar must pop the dialog only — no further assertion
        // possible here on "no network call" (this widget has no network
        // dependency of its own), but the dialog closing proves the pop
        // happened via the caller's own onCancel, not any built-in widget
        // behavior.
        expect(find.text('Apagar sua conta?'), findsNothing);
      },
    );

    testWidgets(
      'confirmButtonColor fills the confirm AppButton, titleColor colors '
      'the title — both colorError for the destructive variant (Story 8.5)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => ConfirmationDialog.show(
                      context: context,
                      builder: (_) => ConfirmationDialog(
                        icon: Icons.delete_outline,
                        title: 'Apagar sua conta?',
                        message: 'Ação irreversível.',
                        confirmLabel: 'Apagar tudo',
                        titleColor: DesignTokens.colorError,
                        confirmButtonColor: DesignTokens.colorError,
                        barrierColor: DesignTokens.colorScrimHeavy,
                        cancelLabel: 'Cancelar',
                        onCancel: () {},
                        onConfirm: () {},
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final confirmButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Apagar tudo'),
        );
        final bg = confirmButton.style!.backgroundColor!.resolve({});
        expect(bg, DesignTokens.colorError);
      },
    );

    testWidgets(
      'a null confirmButtonColor keeps the confirm button\'s exact '
      'pre-existing colorPrimary fill — the default stays unchanged',
      (tester) async {
        await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        final confirmButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'Entrar novamente'),
        );
        final bg = confirmButton.style!.backgroundColor!.resolve({});
        expect(bg, DesignTokens.colorPrimary);
      },
    );

    testWidgets('tapping the confirm button calls onConfirm', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        _appWithOpenButton(onConfirm: () => confirmed = true),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Entrar novamente'));
      await tester.pump();

      expect(confirmed, isTrue);
    });

    testWidgets(
      'renders with no overflow exception at a large Dynamic Type scale',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
            child: _appWithOpenButton(onConfirm: () {}),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ConfirmationDialog), findsOneWidget);
      },
    );

    testWidgets(
      'a synchronous throw from showGeneralDialog (no Navigator ancestor) '
      'still releases the isOpen guard — a later valid show() call keeps '
      'working',
      (tester) async {
        late BuildContext noNavigatorContext;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) {
                noNavigatorContext = context;
                return const SizedBox();
              },
            ),
          ),
        );

        expect(
          () => ConfirmationDialog.show(
            context: noNavigatorContext,
            builder: (_) => ConfirmationDialog(
              icon: Icons.lock_outline,
              title: 'Sessão expirada',
              message: 'Mensagem.',
              confirmLabel: 'Entrar novamente',
              barrierColor: DesignTokens.colorScrim,
              onConfirm: () {},
            ),
          ),
          throwsA(anything),
        );
        expect(
          ConfirmationDialog.isOpen,
          isFalse,
          reason: 'the guard must release even though show() threw',
        );

        // Proves the guard wasn't left permanently locked by the failed
        // call above — a later, valid caller must still be able to open it.
        await tester.pumpWidget(_appWithOpenButton(onConfirm: () {}));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Sessão expirada'), findsOneWidget);
      },
    );
  });
}
