import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/features/entries/domain/entities/entry.dart';
import 'package:cerne/features/entries/domain/entities/entry_date_group.dart';

Entry _entry({required String id, required String occurredAt}) => Entry(
  id: id,
  content: 'content-$id',
  source: EntrySource.manual,
  chatMessageId: null,
  occurredAt: occurredAt,
  serverRevision: 1,
  createdAt: occurredAt,
  updatedAt: occurredAt,
);

/// spec-4-1's grouping edge cases: midnight boundary (two entries on
/// opposite sides of local midnight must land in different groups, two
/// entries on the same local day but different UTC offsets must land in
/// the *same* group) and the zero-entries case.
void main() {
  group('groupEntriesByDate — Boundaries: group by occurredAt.toLocal(), '
      'truncated to day, never createdAt', () {
    test('an empty list yields an empty list of groups, never a single '
        'empty group', () {
      expect(groupEntriesByDate(const []), isEmpty);
    });

    test('two entries whose occurredAt sit exactly on opposite sides of local '
        'midnight land in two distinct, adjacent-day groups — written with no '
        'UTC/offset suffix so `DateTime.parse` reads them as local directly, '
        'keeping the assertion independent of the test runner\'s own '
        'timezone (toLocal() on an already-local DateTime is a no-op)', () {
      final entries = [
        _entry(id: 'e1', occurredAt: '2026-03-10T23:59:59'),
        _entry(id: 'e2', occurredAt: '2026-03-11T00:00:00'),
      ];

      final groups = groupEntriesByDate(entries);

      expect(groups, hasLength(2));
      expect(groups[0].date, DateTime(2026, 3, 10));
      expect(groups[0].entries.single.id, 'e1');
      expect(groups[1].date, DateTime(2026, 3, 11));
      expect(groups[1].entries.single.id, 'e2');
    });

    test('two same-local-day entries land in the same group even when one '
        'crosses a UTC-midnight boundary the other does not (both still '
        'written offset-free, same timezone-independence rationale above)', () {
      final entries = [
        _entry(id: 'e1', occurredAt: '2026-03-10T23:30:00'),
        _entry(id: 'e2', occurredAt: '2026-03-10T08:30:00'),
      ];

      final groups = groupEntriesByDate(entries);

      expect(groups, hasLength(1));
      expect(groups.single.date, DateTime(2026, 3, 10));
      expect(groups.single.entries.map((e) => e.id), ['e1', 'e2']);
    });

    test('groups preserve input order for both the day sequence and each '
        "day's own entries — callers already pass entries newest-first", () {
      final entries = [
        _entry(id: 'e3', occurredAt: '2026-03-12T10:00:00Z'),
        _entry(id: 'e2', occurredAt: '2026-03-11T15:00:00Z'),
        _entry(id: 'e1', occurredAt: '2026-03-11T09:00:00Z'),
      ];

      final groups = groupEntriesByDate(entries);

      expect(groups, hasLength(2));
      expect(groups[0].date, DateTime(2026, 3, 12));
      expect(groups[0].entries.map((e) => e.id), ['e3']);
      expect(groups[1].date, DateTime(2026, 3, 11));
      expect(groups[1].entries.map((e) => e.id), ['e2', 'e1']);
    });

    test('never groups by createdAt — a mismatched createdAt is ignored', () {
      final entry = Entry(
        id: 'e1',
        content: 'content',
        source: EntrySource.manual,
        chatMessageId: null,
        occurredAt: '2026-03-10T12:00:00Z',
        serverRevision: 1,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      );

      final groups = groupEntriesByDate([entry]);

      expect(groups.single.date, DateTime(2026, 3, 10));
    });

    test('a malformed occurredAt is skipped rather than thrown, while '
        "well-formed entries in the same list still group correctly", () {
      final entries = [
        _entry(id: 'e1', occurredAt: '2026-03-10T10:00:00'),
        _entry(id: 'bad', occurredAt: 'not-a-date'),
        _entry(id: 'e2', occurredAt: '2026-03-11T10:00:00'),
      ];

      final groups = groupEntriesByDate(entries);

      expect(groups, hasLength(2));
      expect(
        groups.expand((g) => g.entries).map((e) => e.id),
        ['e1', 'e2'],
      );
    });
  });
}
