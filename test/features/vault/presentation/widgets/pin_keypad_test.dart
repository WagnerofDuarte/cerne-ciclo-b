import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/vault/presentation/widgets/pin_keypad.dart';

Widget _wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: Material(child: Center(child: child)),
        );
      },
    ),
  );
}

Future<void> _tapDigit(WidgetTester tester, String digit) async {
  await tester.tap(find.text(digit));
  await tester.pump();
}

/// Covers spec-2-2's Code Map item for this new component: grid entry,
/// backspace, the 350ms no-explicit-confirm auto-advance (UX-DR14), and no
/// clipping/truncation at the largest Dynamic Type size (UX-DR22).
void main() {
  testWidgets(
    'tapping 4 digits auto-advances 350ms later with no explicit confirm '
    'tap, calling onSubmit exactly once with the entered PIN',
    (tester) async {
      String? submittedPin;
      var submitCount = 0;

      await tester.pumpWidget(
        _wrap(
          PinKeypad(
            onSubmit: (pin) {
              submittedPin = pin;
              submitCount += 1;
            },
          ),
        ),
      );

      await _tapDigit(tester, '1');
      await _tapDigit(tester, '2');
      await _tapDigit(tester, '3');
      await _tapDigit(tester, '4');

      // Not yet — the 350ms window hasn't elapsed.
      expect(submittedPin, isNull);

      await tester.pump(const Duration(milliseconds: 349));
      expect(submittedPin, isNull);

      await tester.pump(const Duration(milliseconds: 2));
      expect(submittedPin, '1234');
      expect(submitCount, 1);
    },
  );

  testWidgets(
    'backspace removes the most recently entered digit before the 4th is '
    'reached',
    (tester) async {
      String? submittedPin;

      await tester.pumpWidget(
        _wrap(PinKeypad(onSubmit: (pin) => submittedPin = pin)),
      );

      await _tapDigit(tester, '1');
      await _tapDigit(tester, '2');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      // Buffer is now just '1' — these three bring it to 4 digits: '1345'.
      await _tapDigit(tester, '3');
      await _tapDigit(tester, '4');
      await _tapDigit(tester, '5');

      await tester.pump(const Duration(milliseconds: 350));

      // Had backspace been a no-op, the buffer would have filled at '1234'
      // (the 4th tap, '4') instead and never seen the 5th tap at all.
      expect(submittedPin, '1345');
    },
  );

  testWidgets(
    'backspace during the 350ms auto-advance window cancels the pending '
    'submit — a corrected 4th digit is what actually gets submitted, '
    'never the stale pre-backspace value',
    (tester) async {
      final submittedPins = <String>[];

      await tester.pumpWidget(_wrap(PinKeypad(onSubmit: submittedPins.add)));

      await _tapDigit(tester, '1');
      await _tapDigit(tester, '2');
      await _tapDigit(tester, '3');
      await _tapDigit(tester, '4'); // Schedules the 350ms submit of '1234'.

      // Correct the 4th digit well inside the 350ms window.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      await _tapDigit(tester, '9'); // Would schedule submit of '1239'.

      // Advance past when the FIRST (cancelled) timer would have fired.
      await tester.pump(const Duration(milliseconds: 350));
      expect(submittedPins, ['1239']);

      // And nothing further fires later either — there was only ever one
      // live timer.
      await tester.pump(const Duration(milliseconds: 350));
      expect(submittedPins, ['1239']);
    },
  );

  testWidgets('backspace on an empty buffer is a harmless no-op', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(PinKeypad(onSubmit: (_) => fail('should not submit'))),
    );

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'after a submit, the buffer is already cleared — entering a fresh 4 '
    'digits submits only the new PIN, never a stale concatenation',
    (tester) async {
      final submittedPins = <String>[];

      await tester.pumpWidget(_wrap(PinKeypad(onSubmit: submittedPins.add)));

      for (final digit in '1111'.split('')) {
        await _tapDigit(tester, digit);
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(submittedPins, ['1111']);

      for (final digit in '2222'.split('')) {
        await _tapDigit(tester, digit);
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(submittedPins, ['1111', '2222']);
    },
  );

  testWidgets(
    'renders with no overflow/clipping exception at the largest Dynamic '
    'Type size (UX-DR22 — the PIN keypad is one of the tightest-fit '
    'surfaces)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          PinKeypad(onSubmit: (_) {}),
          textScaler: const TextScaler.linear(3.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PinKeypad), findsOneWidget);
      for (final digit in ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']) {
        expect(find.text(digit), findsOneWidget);
      }
    },
  );

  group('enabled: false — every tap is ignored', () {
    testWidgets(
      'digit taps do nothing while disabled: no onSubmit even after the '
      '350ms window, no exception',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            PinKeypad(
              enabled: false,
              onSubmit: (_) => fail('should not submit while disabled'),
            ),
          ),
        );

        for (final digit in '1234'.split('')) {
          await _tapDigit(tester, digit);
        }
        await tester.pump(const Duration(milliseconds: 350));

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('backspace does nothing while disabled (no exception)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PinKeypad(enabled: false, onSubmit: (_) {})),
      );

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'digits ignored while disabled are not silently queued — toggling '
      'back to enabled still starts from an empty buffer',
      (tester) async {
        final submittedPins = <String>[];
        const key = Key('pin-keypad');

        await tester.pumpWidget(
          _wrap(
            PinKeypad(key: key, enabled: false, onSubmit: submittedPins.add),
          ),
        );
        for (final digit in '12'.split('')) {
          await _tapDigit(tester, digit);
        }

        // Same key -> same State -> any buffered digits from the
        // disabled taps above would still be present here if the guard
        // only blocked onSubmit rather than the buffer write itself.
        await tester.pumpWidget(
          _wrap(PinKeypad(key: key, onSubmit: submittedPins.add)),
        );
        for (final digit in '9876'.split('')) {
          await _tapDigit(tester, digit);
        }
        await tester.pump(const Duration(milliseconds: 350));

        expect(submittedPins, ['9876']);
      },
    );

    testWidgets(
      'buttons report disabled semantics and are visually dimmed while '
      'disabled, and report enabled/full opacity again once re-enabled '
      "(review finding: enabled: false previously had no cue at all)",
      (tester) async {
        // Semantics are only computed while something is listening — a
        // handle must be held open for `find.bySemanticsLabel`/
        // `getSemantics` to see anything at all.
        final semanticsHandle = tester.ensureSemantics();

        const key = Key('pin-keypad');
        await tester.pumpWidget(
          _wrap(PinKeypad(key: key, enabled: false, onSubmit: (_) {})),
        );

        final disabledOpacity = tester.widget<Opacity>(
          find.ancestor(of: find.text('1'), matching: find.byType(Opacity)),
        );
        expect(disabledOpacity.opacity, lessThan(1));

        final disabledButtonSemantics = find
            .ancestor(of: find.text('1'), matching: find.byType(Semantics))
            .first;
        expect(
          tester.getSemantics(disabledButtonSemantics),
          isSemantics(hasEnabledState: true, isEnabled: false),
        );

        await tester.pumpWidget(_wrap(PinKeypad(key: key, onSubmit: (_) {})));

        final enabledOpacity = tester.widget<Opacity>(
          find.ancestor(of: find.text('1'), matching: find.byType(Opacity)),
        );
        expect(enabledOpacity.opacity, 1);

        final enabledButtonSemantics = find
            .ancestor(of: find.text('1'), matching: find.byType(Semantics))
            .first;
        expect(
          tester.getSemantics(enabledButtonSemantics),
          isSemantics(hasEnabledState: true, isEnabled: true),
        );

        semanticsHandle.dispose();
      },
    );
  });

  testWidgets('every digit/backspace tap target is at least 44pt (UX-DR23)', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(PinKeypad(onSubmit: (_) {})));

    // The nearest `InkWell` ancestor is the actual tappable surface
    // (the `Text`/`Icon` glyph itself is intentionally smaller, shrunk
    // to fit via `FittedBox` — UX-DR22 — so measuring the glyph would
    // under-report the real hit area).
    final digitTarget = tester.getSize(
      find.ancestor(of: find.text('5'), matching: find.byType(InkWell)),
    );
    expect(digitTarget.width, greaterThanOrEqualTo(44));
    expect(digitTarget.height, greaterThanOrEqualTo(44));

    final backspaceTarget = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.backspace_outlined),
        matching: find.byType(InkWell),
      ),
    );
    expect(backspaceTarget.width, greaterThanOrEqualTo(44));
    expect(backspaceTarget.height, greaterThanOrEqualTo(44));
  });
}
