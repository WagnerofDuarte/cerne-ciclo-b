import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/entries/presentation/widgets/sync_badge.dart';

Future<void> _pump(
  WidgetTester tester,
  SyncBadgeState state, {
  VoidCallback? onRetryTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SyncBadge(state: state, onRetryTap: onRetryTap),
      ),
    ),
  );
}

/// Covers spec-4-2's own Tasks item: "widget (badge states, tap targets,
/// non-retryable has no tap)".
void main() {
  group('the 3 badge states', () {
    testWidgets('SyncBadgeSynchronizing renders the "Sincronizando" label in '
        'colorWarningSync', (tester) async {
      await _pump(tester, const SyncBadgeState.synchronizing());

      expect(find.text('Sincronizando'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Sincronizando'));
      expect(text.style!.color, DesignTokens.colorWarningSync);
    });

    testWidgets('SyncBadgeSynchronized renders the "Sincronizado" label in '
        'colorSuccess', (tester) async {
      await _pump(tester, const SyncBadgeState.synchronized());

      expect(find.text('Sincronizado'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Sincronizado'));
      expect(text.style!.color, DesignTokens.colorSuccess);
    });

    testWidgets('SyncBadgeError renders the "Erro de sincronização" label in '
        'colorError', (tester) async {
      await _pump(
        tester,
        const SyncBadgeState.error(
          Failure.networkTimeout(message: 'Timed out'),
        ),
      );

      expect(find.text('Erro de sincronização'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Erro de sincronização'));
      expect(text.style!.color, DesignTokens.colorError);
    });
  });

  group('tap target', () {
    testWidgets(
      'a retryable error badge is at least insertionModalTapTargetMin in '
      'both dimensions, even though its own content (a small dot + short '
      'label) is naturally much smaller',
      (tester) async {
        // `UnconstrainedBox` lets the subtree size itself to its own
        // natural (intrinsic) size instead of stretching to fill the
        // Scaffold body — the only way to actually observe whether the
        // badge's own `ConstrainedBox` minimums are doing any work, since
        // an `Align` with no width/height factor otherwise expands to
        // fill all the loose space a `Scaffold` body offers regardless of
        // content size.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: UnconstrainedBox(
                child: SyncBadge(
                  state: const SyncBadgeState.error(
                    Failure.networkTimeout(message: 'Timed out'),
                  ),
                  onRetryTap: () {},
                ),
              ),
            ),
          ),
        );

        final size = tester.getSize(find.byType(InkWell));
        expect(
          size.width,
          greaterThanOrEqualTo(DesignTokens.insertionModalTapTargetMin),
        );
        expect(
          size.height,
          greaterThanOrEqualTo(DesignTokens.insertionModalTapTargetMin),
        );
      },
    );
  });

  group('I/O matrix: tap behavior', () {
    testWidgets('a retryable error badge tap calls onRetryTap, never shows an '
        'inline explanation', (tester) async {
      var retried = false;
      await _pump(
        tester,
        const SyncBadgeState.error(
          Failure.networkTimeout(message: 'Timed out'),
        ),
        onRetryTap: () => retried = true,
      );

      await tester.tap(find.byType(SyncBadge));
      await tester.pump();

      expect(retried, isTrue);
      expect(find.text('Timed out'), findsNothing);
    });

    testWidgets(
      'a non-retryable error badge tap reveals the inline explanation and '
      'never calls onRetryTap — no network call (Acceptance Criteria)',
      (tester) async {
        var retried = false;
        await _pump(
          tester,
          const SyncBadgeState.error(
            Failure.validation(message: 'Conteúdo inválido.'),
          ),
          onRetryTap: () => retried = true,
        );

        expect(find.text('Conteúdo inválido.'), findsNothing);

        await tester.tap(find.byType(SyncBadge));
        await tester.pump();

        expect(find.text('Conteúdo inválido.'), findsOneWidget);
        expect(retried, isFalse);
      },
    );

    testWidgets(
      'a non-retryable error badge tapped twice toggles the explanation '
      'back off',
      (tester) async {
        await _pump(
          tester,
          const SyncBadgeState.error(
            Failure.validation(message: 'Conteúdo inválido.'),
          ),
        );

        await tester.tap(find.byType(SyncBadge));
        await tester.pump();
        expect(find.text('Conteúdo inválido.'), findsOneWidget);

        await tester.tap(find.byType(SyncBadge));
        await tester.pump();
        expect(find.text('Conteúdo inválido.'), findsNothing);
      },
    );

    testWidgets(
      'SyncBadgeSynchronizing/SyncBadgeSynchronized are never tappable — '
      'no InkWell at all',
      (tester) async {
        await _pump(tester, const SyncBadgeState.synchronizing());
        expect(find.byType(InkWell), findsNothing);

        await _pump(tester, const SyncBadgeState.synchronized());
        expect(find.byType(InkWell), findsNothing);
      },
    );
  });

  group(
    'code-review round 1 finding: duplicate accessibility announcement',
    () {
      testWidgets('the dot\'s own Tooltip is excluded from semantics — the one '
          'Semantics node wrapping the whole badge is the single '
          'accessible-label source, not two', (tester) async {
        await _pump(tester, const SyncBadgeState.synchronizing());

        final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
        expect(tooltip.excludeFromSemantics, isTrue);
      });

      testWidgets(
        'the semantics tree carries the "Sincronizando" label exactly '
        'once, not twice (Tooltip + outer Semantics both announcing it)',
        (tester) async {
          // Disposed explicitly at the end of this test body, not via
          // `addTearDown` — in this Flutter version, `addTearDown`'s own
          // callback runs too late relative to the framework's own
          // end-of-test "every SemanticsHandle was disposed" check,
          // tripping that unrelated assertion on an otherwise-passing
          // test.
          final handle = tester.ensureSemantics();

          await _pump(tester, const SyncBadgeState.synchronizing());

          expect(find.bySemanticsLabel('Sincronizando'), findsOneWidget);

          handle.dispose();
        },
      );

      testWidgets(
        'same single-occurrence guarantee holds for a tappable (error) '
        'badge too',
        (tester) async {
          final handle = tester.ensureSemantics();

          await _pump(
            tester,
            const SyncBadgeState.error(
              Failure.networkTimeout(message: 'Timed out'),
            ),
            onRetryTap: () {},
          );

          expect(
            find.bySemanticsLabel('Erro de sincronização'),
            findsOneWidget,
          );

          handle.dispose();
        },
      );
    },
  );
}
