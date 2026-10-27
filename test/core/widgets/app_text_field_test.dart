import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/app_text_field.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    ),
  );
}

OutlineInputBorder _borderOf(InputBorder? border) => border as OutlineInputBorder;

void main() {
  testWidgets('default (unfocused, no error) renders a colorBorder 1dp border', (tester) async {
    await tester.pumpWidget(_wrap(const AppTextField(labelText: 'E-mail')));

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;
    final border = _borderOf(decoration.enabledBorder);

    expect(border.borderSide.color, DesignTokens.colorBorder);
    expect(border.borderSide.width, DesignTokens.borderWidthDefault);
    expect(border.borderRadius, BorderRadius.all(Radius.circular(DesignTokens.radiusSm)));
    expect(decoration.errorText, isNull);
  });

  testWidgets('focused border is colorPrimary at 1.5dp', (tester) async {
    await tester.pumpWidget(_wrap(const AppTextField(labelText: 'E-mail')));

    final field = tester.widget<TextField>(find.byType(TextField));
    final border = _borderOf(field.decoration!.focusedBorder);

    expect(border.borderSide.color, DesignTokens.colorPrimary);
    expect(border.borderSide.width, DesignTokens.borderWidthEmphasis);
  });

  testWidgets('error state renders a colorError 1.5dp border and the error text', (tester) async {
    await tester.pumpWidget(_wrap(const AppTextField(labelText: 'Senha', errorText: 'Senha inválida')));

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;

    expect(decoration.errorText, 'Senha inválida');
    final errorBorder = _borderOf(decoration.errorBorder);
    expect(errorBorder.borderSide.color, DesignTokens.colorError);
    expect(errorBorder.borderSide.width, DesignTokens.borderWidthEmphasis);

    final focusedErrorBorder = _borderOf(decoration.focusedErrorBorder);
    expect(focusedErrorBorder.borderSide.color, DesignTokens.colorError);
    expect(focusedErrorBorder.borderSide.width, DesignTokens.borderWidthEmphasis);
  });

  testWidgets('a long error message at a large text scale never truncates', (tester) async {
    const longError =
        'Esta é uma mensagem de erro bastante longa para verificar que o campo nunca corta ou trunca o texto de erro sob Dynamic Type.';

    await tester.pumpWidget(
      _wrap(const AppTextField(labelText: 'E-mail', errorText: longError), textScale: 3.0),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.errorMaxLines, isNull);
  });
}
