import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/app_button.dart';
import 'package:cerne/core/widgets/app_text_field.dart';

/// Composes two of the core shared widgets (`AppTextField` x2 +
/// `AppButton`) the way a form screen will, to exercise interaction
/// behavior across widgets — real taps, keystrokes and focus changes —
/// that neither a single-widget test (one component in isolation) nor a
/// screen-level BLoC test (focused on state transitions, not raw widget
/// interaction — see `auth_screen_test.dart`) covers: obscured text
/// while typing, keyboard-action focus movement, and a disabled
/// button's `onPressed` truly staying null rather than merely looking
/// disabled.
class _LoginShapedForm extends StatefulWidget {
  const _LoginShapedForm({required this.onSubmit});

  final ValueChanged<(String email, String senha)> onSubmit;

  @override
  State<_LoginShapedForm> createState() => _LoginShapedFormState();
}

class _LoginShapedFormState extends State<_LoginShapedForm> {
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final _senhaFocus = FocusNode();
  String? _emailError;
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _senhaFocus.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailController.text.isNotEmpty && _senhaController.text.isNotEmpty;

  void _validateAndSubmit() {
    setState(() {
      _submitted = true;
      _emailError = _emailController.text.contains('@')
          ? null
          : 'E-mail inválido';
    });
    if (_emailError == null) {
      widget.onSubmit((_emailController.text, _senhaController.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: _emailController,
              labelText: 'E-mail',
              errorText: _submitted ? _emailError : null,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            AppTextField(
              controller: _senhaController,
              focusNode: _senhaFocus,
              labelText: 'Senha',
              obscureText: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            AppButton(
              label: 'Entrar',
              onPressed: _canSubmit ? _validateAndSubmit : null,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('Component library — login-shaped form composition', () {
    testWidgets('submit stays disabled until both fields are filled', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_LoginShapedForm(onSubmit: (_) {})));

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'a@b.com',
      );
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
        reason: 'senha is still empty',
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('tapping the enabled button submits the typed values', (
      tester,
    ) async {
      (String, String)? submitted;
      await tester.pumpWidget(
        _wrap(_LoginShapedForm(onSubmit: (v) => submitted = v)),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail'),
        'wagner@cerne.app',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.pump();

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(submitted, ('wagner@cerne.app', 'segredo123'));
    });

    testWidgets(
      'an invalid e-mail surfaces the error border and text, and never submits',
      (tester) async {
        var submitCount = 0;
        await tester.pumpWidget(
          _wrap(_LoginShapedForm(onSubmit: (_) => submitCount++)),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'E-mail'),
          'nao-e-email',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Senha'),
          'segredo123',
        );
        await tester.pump();

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(submitCount, 0);
        expect(find.text('E-mail inválido'), findsOneWidget);

        final emailField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'E-mail'),
        );
        final errorBorder =
            emailField.decoration!.errorBorder as OutlineInputBorder;
        expect(errorBorder.borderSide.color, DesignTokens.colorError);
        expect(errorBorder.borderSide.width, DesignTokens.borderWidthEmphasis);
      },
    );

    testWidgets(
      'correcting an invalid e-mail and resubmitting clears the error and submits',
      (tester) async {
        (String, String)? submitted;
        await tester.pumpWidget(
          _wrap(_LoginShapedForm(onSubmit: (v) => submitted = v)),
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'E-mail'),
          'nao-e-email',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Senha'),
          'segredo123',
        );
        await tester.pump();

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(find.text('E-mail inválido'), findsOneWidget);
        expect(submitted, isNull);

        await tester.enterText(
          find.widgetWithText(TextField, 'E-mail'),
          'wagner@cerne.app',
        );
        await tester.pump();

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(find.text('E-mail inválido'), findsNothing);
        expect(submitted, ('wagner@cerne.app', 'segredo123'));
      },
    );

    testWidgets(
      'submitting the e-mail field via the keyboard action moves focus to senha',
      (tester) async {
        await tester.pumpWidget(_wrap(_LoginShapedForm(onSubmit: (_) {})));

        await tester.enterText(
          find.widgetWithText(TextField, 'E-mail'),
          'wagner@cerne.app',
        );
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pump();

        final senhaField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'Senha'),
        );
        expect(senhaField.focusNode!.hasFocus, isTrue);
      },
    );

    testWidgets('senha stays obscured while typing', (tester) async {
      await tester.pumpWidget(_wrap(_LoginShapedForm(onSubmit: (_) {})));

      await tester.enterText(
        find.widgetWithText(TextField, 'Senha'),
        'segredo123',
      );
      await tester.pump();

      final senhaField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Senha'),
      );
      expect(senhaField.obscureText, isTrue);
    });

    testWidgets('a disabled button never calls onPressed, even when tapped', (
      tester,
    ) async {
      var submitCount = 0;
      await tester.pumpWidget(
        _wrap(_LoginShapedForm(onSubmit: (_) => submitCount++)),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();

      expect(submitCount, 0);
    });

    testWidgets(
      'the whole form renders with no overflow at a large Dynamic Type scale',
      (tester) async {
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
            child: _wrap(_LoginShapedForm(onSubmit: (_) {})),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(AppTextField), findsNWidgets(2));
        expect(find.byType(AppButton), findsOneWidget);
      },
    );
  });
}
