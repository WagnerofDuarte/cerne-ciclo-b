/// INTERVALO DE DATA's own 3 choices (spec-5-2; `prototype-extract.md`) —
/// each computes its own `dateFrom`/`dateTo` pair via [rangeFrom]. [allTime]
/// is itself a selectable choice meaning "no date filter at all", not some
/// maximal range — it resolves to `(null, null)`.
///
/// Lives in the domain layer (RNF06) rather than alongside
/// `EntriesFilterSheet` so `MeusRegistrosCubit` can store the selected
/// preset directly (code-review fix: re-deriving it from `dateFrom` by
/// equality match against a freshly recomputed "today" boundary goes stale
/// the moment a day/week/month boundary rolls over while the filter stays
/// active) without the cubit importing a presentation-layer widget file.
/// UI-facing copy (`label`) stays out of this enum, same split
/// `EntrySource`/`entrySourceLabel` already uses — see
/// `entries_filter_sheet.dart`'s own `dateRangePresetLabel`.
enum DateRangePreset {
  allTime,
  thisWeek,
  thisMonth;

  /// This preset's own `(dateFrom, dateTo)` pair, anchored to [now] (a
  /// parameter only so a test can pin it — every real call site passes
  /// `DateTime.now()`). `dateTo` is always [now] itself — "through right
  /// now" — `docs/input/` is silent on inclusive/exclusive bounds here
  /// (AGENTS.md policy: "decide and proceed"). `dateFrom` is local
  /// midnight of the Monday starting this week, or the 1st of this
  /// calendar month.
  (DateTime?, DateTime?) rangeFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case DateRangePreset.allTime:
        return (null, null);
      case DateRangePreset.thisWeek:
        return (today.subtract(Duration(days: today.weekday - 1)), now);
      case DateRangePreset.thisMonth:
        return (DateTime(today.year, today.month), now);
    }
  }
}
