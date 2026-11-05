import 'entry.dart';

/// One calendar day's worth of entries — [date] is truncated to midnight
/// *local* time (never UTC, never [Entry.createdAt]; Boundaries), so two
/// entries whose [Entry.occurredAt] fall on the same local day always land
/// in the same group regardless of the UTC offset the backend sent them in.
class EntryDateGroup {
  const EntryDateGroup({required this.date, required this.entries});

  /// Always a `DateTime` with zeroed time-of-day fields (`DateTime(y, m,
  /// d)`) — day-label formatting ("Hoje"/"Ontem"/a date string) is
  /// presentation's job (Boundaries), not this pure entity's.
  final DateTime date;

  final List<Entry> entries;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryDateGroup &&
          other.date == date &&
          _listEquals(other.entries, entries));

  @override
  int get hashCode => Object.hash(date, Object.hashAll(entries));

  @override
  String toString() =>
      'EntryDateGroup(date: $date, entries: ${entries.length})';
}

/// Groups [entries] by their [Entry.occurredAt]'s local calendar day
/// (Boundaries: "never `createdAt`"). Pure Dart — no `package:flutter`
/// import (RNF06), since `entries/domain` must stay flutter-free.
///
/// Preserves [entries]' own relative order within each group, and orders
/// the returned groups by each one's first-encountered entry — callers
/// (`EntriesRepository.list()`/`MeusRegistrosCubit`) always pass entries
/// already newest-first, so that ordering alone already yields groups
/// newest-day-first with no separate sort step needed here.
///
/// An empty [entries] list yields an empty list of groups (the "zero
/// entries" edge case) — never a single empty group.
///
/// A malformed [Entry.occurredAt] (should never happen — every entry here
/// was written by [EntriesRepository.create]/`list()` themselves) is
/// skipped rather than thrown (RNF09), same defensive rationale
/// `EntriesRepositoryImpl._offlineFallback()`'s own `DateTime.parse` guard
/// already uses — one corrupt cached entry shouldn't take down the whole
/// list.
List<EntryDateGroup> groupEntriesByDate(List<Entry> entries) {
  final entriesByDay = <DateTime, List<Entry>>{};
  final dayOrder = <DateTime>[];

  for (final entry in entries) {
    final occurredAt = DateTime.tryParse(entry.occurredAt)?.toLocal();
    if (occurredAt == null) {
      continue;
    }
    final day = DateTime(occurredAt.year, occurredAt.month, occurredAt.day);
    final bucket = entriesByDay.putIfAbsent(day, () {
      dayOrder.add(day);
      return <Entry>[];
    });
    bucket.add(entry);
  }

  return [
    for (final day in dayOrder)
      EntryDateGroup(date: day, entries: entriesByDay[day]!),
  ];
}

bool _listEquals(List<Entry> a, List<Entry> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
