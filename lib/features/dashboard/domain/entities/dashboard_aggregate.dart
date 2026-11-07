/// `GET /dashboard/aggregate`'s own domain shape (spec-8-1) — the chart
/// section only ever needs the period total and each bucket's own count
/// (Code Map: "domain `DashboardAggregate` exposes only
/// `totalCount`/`bucketCounts`"); every other contract field
/// (`buckets[].date`/`.sources`, `totals.sources`) stops at
/// `DashboardAggregateDto`, never reaching this layer. No AI narrative
/// field either — that's Story 8.2, explicitly out of scope here (Intent).
class DashboardAggregate {
  const DashboardAggregate({
    required this.totalCount,
    required this.bucketCounts,
  });

  /// `totals.count` — the one value the 0/1/>30/2..30 state matrix
  /// (Boundaries) branches on.
  final int totalCount;

  /// One count per contract `buckets[]` entry, in the same (chronological)
  /// order the backend returns them — `DashboardChartSection`'s own
  /// condensation/bar-height logic relies on that order being preserved
  /// end to end (`DashboardAggregateDto.toDomain()` maps it straight
  /// across, with no reordering of its own).
  final List<int> bucketCounts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DashboardAggregate &&
          other.totalCount == totalCount &&
          _listEquals(other.bucketCounts, bucketCounts));

  @override
  int get hashCode => Object.hash(totalCount, Object.hashAll(bucketCounts));

  @override
  String toString() =>
      'DashboardAggregate(totalCount: $totalCount, '
      'bucketCounts: $bucketCounts)';
}

bool _listEquals(List<int> a, List<int> b) {
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
