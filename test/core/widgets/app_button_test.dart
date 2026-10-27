import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/app_button.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 200, child: child),
        ),
      ),
    ),
  );
}

ButtonStyleButton _buttonOf(WidgetTester tester) {
  final elevated = tester.widgetList<ElevatedButton>(find.byType(ElevatedButton));
  if (elevated.isNotEmpty) return elevated.first;
  final outlined = tester.widgetList<OutlinedButton>(find.byType(OutlinedButton));
  if (outlined.isNotEmpty) return outlined.first;
  return tester.widget<TextButton>(find.byType(TextButton));
}

void main() {
  group('AppButton — primary', () {
    testWidgets('enabled renders colorPrimary background and colorOnPrimary text', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'Entrar', onPressed: () {})));

      final button = _buttonOf(tester);
      final bg = button.style!.backgroundColor!.resolve({});
      final fg = button.style!.foregroundColor!.resolve({});
      expect(bg, DesignTokens.colorPrimary);
      expect(fg, DesignTokens.colorOnPrimary);

      final shape = button.style!.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.all(Radius.circular(DesignTokens.radiusSm)));
    });

    testWidgets('pressed overlay resolves to colorPrimaryPressed', (tester) async {
      await tester.pumpWidget(_wrap(AppButton(label: 'Entrar', onPressed: () {})));

      final button = _buttonOf(tester);
      final overlay = button.style!.overlayColor!.resolve({WidgetState.pressed});
      expect(overlay, DesignTokens.colorPrimaryPressed);
    });

    testWidgets('disabled renders colorBorder background and colorTextSecondary text, never dimmed opacity', (tester) async {
      await tester.pumpWidget(_wrap(const AppButton(label: 'Entrar', onPressed: null)));

      final button = _buttonOf(tester);
      final bg = button.style!.backgroundColor!.resolve({WidgetState.disabled});
      final fg = button.style!.foregroundColor!.resolve({WidgetState.disabled});
      expect(bg, DesignTokens.colorBorder);
      expect(fg, DesignTokens.colorTextSecondary);
      expect(bg!.a, 1.0, reason: 'disabled background must be opaque, not a dimmed/transparent version of another color');

      expect(button.enabled, isFalse);
    });
  });

  group('AppButton — secondaryOutline', () {
    testWidgets('enabled renders colorPrimary outline, no fill', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Cancelar', onPressed: () {}, variant: AppButtonVariant.secondaryOutline)),
      );

      final button = _buttonOf(tester) as OutlinedButton;
      final side = button.style!.side!.resolve({});
      final bg = button.style!.backgroundColor!.resolve({});
      expect(side!.color, DesignTokens.colorPrimary);
      expect(bg, Colors.transparent);
    });

    testWidgets('disabled renders colorBorder background and colorTextSecondary text', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppButton(label: 'Cancelar', onPressed: null, variant: AppButtonVariant.secondaryOutline)),
      );

      final button = _buttonOf(tester) as OutlinedButton;
      final bg = button.style!.backgroundColor!.resolve({WidgetState.disabled});
      final fg = button.style!.foregroundColor!.resolve({WidgetState.disabled});
      final side = button.style!.side!.resolve({WidgetState.disabled});
      expect(bg, DesignTokens.colorBorder);
      expect(fg, DesignTokens.colorTextSecondary);
      expect(side!.color, DesignTokens.colorBorder);
      expect(side.width, DesignTokens.borderWidthDefault);
    });
  });

  group('AppButton — textGhost', () {
    testWidgets('enabled defaults to colorPrimary text, no background', (tester) async {
      await tester.pumpWidget(
        _wrap(AppButton(label: 'Fechar', onPressed: () {}, variant: AppButtonVariant.textGhost)),
      );

      final button = _buttonOf(tester) as TextButton;
      final fg = button.style!.foregroundColor!.resolve({});
      final bg = button.style!.backgroundColor!.resolve({});
      expect(fg, DesignTokens.colorPrimary);
      expect(bg, Colors.transparent);
    });

    testWidgets('honors an explicit contextual text color', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppButton(
            label: 'Limpar',
            onPressed: () {},
            variant: AppButtonVariant.textGhost,
            textColor: DesignTokens.colorTextSecondary,
          ),
        ),
      );

      final button = _buttonOf(tester) as TextButton;
      final fg = button.style!.foregroundColor!.resolve({});
      expect(fg, DesignTokens.colorTextSecondary);
    });

    testWidgets('disabled renders colorBorder background and colorTextSecondary text', (tester) async {
      await tester.pumpWidget(
        _wrap(const AppButton(label: 'Fechar', onPressed: null, variant: AppButtonVariant.textGhost)),
      );

      final button = _buttonOf(tester) as TextButton;
      final bg = button.style!.backgroundColor!.resolve({WidgetState.disabled});
      final fg = button.style!.foregroundColor!.resolve({WidgetState.disabled});
      expect(bg, DesignTokens.colorBorder);
      expect(fg, DesignTokens.colorTextSecondary);
    });
  });

  group('AppButton — Dynamic Type', () {
    testWidgets('a long label at a large text scale never clips or truncates', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppButton(
            label: 'Um rótulo de botão bem mais longo do que o normal para testar a quebra de linha',
            onPressed: () {},
          ),
          textScale: 3.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final text = tester.widget<Text>(find.text(
        'Um rótulo de botão bem mais longo do que o normal para testar a quebra de linha',
      ));
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.softWrap ?? true, isTrue);
    });
  });
}
