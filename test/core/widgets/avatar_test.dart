import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/widgets/avatar.dart';

Widget _wrap(Widget child, {double textScale = 1.0}) {
  return MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('small variant renders a 40dp colorPrimary circle', (tester) async {
    await tester.pumpWidget(_wrap(const Avatar(initials: 'WD')));

    final container = tester.widget<Container>(find.byType(Container));
    expect(tester.getSize(find.byType(Container)), const Size(DesignTokens.avatarSizeSm, DesignTokens.avatarSizeSm));

    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, DesignTokens.colorPrimary);
    expect(decoration.shape, BoxShape.circle);

    expect(find.text('WD'), findsOneWidget);
  });

  testWidgets('large variant renders a 52dp circle', (tester) async {
    await tester.pumpWidget(_wrap(const Avatar(initials: 'AM', size: AvatarSize.large)));

    expect(tester.getSize(find.byType(Container)), const Size(DesignTokens.avatarSizeLg, DesignTokens.avatarSizeLg));
  });

  testWidgets('uppercases lowercase initials', (tester) async {
    await tester.pumpWidget(_wrap(const Avatar(initials: 'wd')));

    expect(find.text('WD'), findsOneWidget);
    expect(find.text('wd'), findsNothing);
  });

  testWidgets('initials never clip or truncate under a large Dynamic Type scale', (tester) async {
    await tester.pumpWidget(_wrap(const Avatar(initials: 'WD'), textScale: 3.0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // The circle itself stays fixed-size (it's a design-token, not a
    // text-driven container); FittedBox is what prevents clipping by
    // shrinking the initials to fit instead.
    expect(tester.getSize(find.byType(Container)), const Size(DesignTokens.avatarSizeSm, DesignTokens.avatarSizeSm));
    expect(find.byType(FittedBox), findsOneWidget);

    final text = tester.widget<Text>(find.text('WD'));
    expect(text.maxLines, 1);
  });
}
