import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/failure/failure.dart';
import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/sync_badge_state.dart';
import 'package:cerne/features/entries/presentation/widgets/entry_record_card.dart';
import 'package:cerne/features/entries/presentation/widgets/sync_badge.dart';

Entry _entry(EntrySource source) => Entry(
  id: 'e1',
  content: 'content',
  source: source,
  chatMessageId: null,
  occurredAt: '2026-01-01T10:00:00Z',
  serverRevision: 1,
  createdAt: '2026-01-01T10:00:00Z',
  updatedAt: '2026-01-01T10:00:00Z',
);

Future<void> _pump(WidgetTester tester, Entry entry) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EntryRecordCard(
          entry: entry,
          badgeState: const SyncBadgeState.synchronized(),
          onTap: () {},
        ),
      ),
    ),
  );
}

/// Review finding: every other `EntryRecordCard` test (`meus_registros_
/// screen_test.dart`/`meus_registros_cubit_test.dart`) only ever builds an
/// `EntrySource.manual` entry — this suite is the one place that exercises
/// origin marking for all four `EntrySource` values, asserting each one's
/// icon + spine color exactly matches `cerne-prototype.html`'s own
/// `sourceMeta` mapping (`_sourceMeta`'s own doc comment in
/// `entry_record_card.dart`).
void main() {
  Color spineColor(WidgetTester tester) {
    // Scoped to a descendant of EntryRecordCard — Scaffold/MaterialApp's
    // own internals also use ColoredBox, so an unscoped find.byType would
    // match more than the one spine this card renders.
    final coloredBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(EntryRecordCard),
        matching: find.byType(ColoredBox),
      ),
    );
    return coloredBox.color;
  }

  testWidgets('EntrySource.manual renders Icons.edit_outlined with '
      'colorPrimary spine', (tester) async {
    await _pump(tester, _entry(EntrySource.manual));

    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(spineColor(tester), DesignTokens.colorPrimary);
  });

  testWidgets('EntrySource.audio renders Icons.mic with colorSecondary spine', (
    tester,
  ) async {
    await _pump(tester, _entry(EntrySource.audio));

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(spineColor(tester), DesignTokens.colorSecondary);
  });

  testWidgets('EntrySource.photo renders Icons.image_outlined with '
      'colorTextSecondary spine', (tester) async {
    await _pump(tester, _entry(EntrySource.photo));

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(spineColor(tester), DesignTokens.colorTextSecondary);
  });

  testWidgets(
    'EntrySource.chat renders Icons.chat_bubble_outline with colorAccent '
    'spine',
    (tester) async {
      await _pump(tester, _entry(EntrySource.chat));

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(spineColor(tester), DesignTokens.colorAccent);
    },
  );

  testWidgets('a malformed occurredAt renders the --:-- placeholder instead of '
      'throwing (RNF09)', (tester) async {
    await _pump(
      tester,
      Entry(
        id: 'e1',
        content: 'content',
        source: EntrySource.manual,
        chatMessageId: null,
        occurredAt: 'not-a-date',
        serverRevision: 1,
        createdAt: '2026-01-01T10:00:00Z',
        updatedAt: '2026-01-01T10:00:00Z',
      ),
    );

    expect(find.text('--:--'), findsOneWidget);
  });

  group('spec-4-4: onTap navigation', () {
    testWidgets('tapping the card body (not the badge) calls onTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryRecordCard(
              entry: _entry(EntrySource.manual),
              badgeState: const SyncBadgeState.synchronized(),
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('content'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets(
      'tapping within the colored spine strip itself also calls onTap '
      '(round-1 review fix: the tappable InkWell wraps the whole Stack, '
      'spine included, not just the content Padding — review finding, '
      'round 2: no test previously hit a point inside the spine\'s own '
      'bounds)',
      (tester) async {
        var tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EntryRecordCard(
                entry: _entry(EntrySource.manual),
                badgeState: const SyncBadgeState.synchronized(),
                onTap: () => tapped = true,
              ),
            ),
          ),
        );

        final cardTopLeft = tester.getTopLeft(find.byType(EntryRecordCard));
        final cardSize = tester.getSize(find.byType(EntryRecordCard));
        // Well inside the spine's own width (DesignTokens
        // .kanbanCardSpineWidth), never inside the content Padding beside
        // it.
        final spinePoint =
            cardTopLeft +
            Offset(DesignTokens.kanbanCardSpineWidth / 2, cardSize.height / 2);

        await tester.tapAt(spinePoint);
        await tester.pump();

        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'tapping a retryable error SyncBadge calls onRetryTap, never onTap '
      '(the badge\'s own InkWell wins the hit test)',
      (tester) async {
        var tapped = false;
        var retried = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: EntryRecordCard(
                entry: _entry(EntrySource.manual),
                badgeState: const SyncBadgeState.error(
                  Failure.networkTimeout(message: 'Timed out'),
                ),
                onTap: () => tapped = true,
                onRetryTap: () => retried = true,
              ),
            ),
          ),
        );

        await tester.tap(find.byType(SyncBadge));
        await tester.pump();

        expect(retried, isTrue);
        expect(tapped, isFalse);
      },
    );
  });

  group('spec-4-2: sync badge forwarding', () {
    testWidgets('renders a SyncBadge with the given badgeState', (
      tester,
    ) async {
      await _pump(tester, _entry(EntrySource.manual));

      expect(find.byType(SyncBadge), findsOneWidget);
      final badge = tester.widget<SyncBadge>(find.byType(SyncBadge));
      expect(badge.state, const SyncBadgeState.synchronized());
    });

    testWidgets('forwards onRetryTap through to the SyncBadge verbatim', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryRecordCard(
              entry: _entry(EntrySource.manual),
              badgeState: const SyncBadgeState.error(
                Failure.networkTimeout(message: 'Timed out'),
              ),
              onTap: () {},
              onRetryTap: () => retried = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SyncBadge));
      await tester.pump();

      expect(retried, isTrue);
    });
  });
}
