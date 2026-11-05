import 'entry.dart';

/// `EntriesRepository.list()`'s return shape — one page of [items] plus the
/// server's own opaque [nextCursor] (`null` once there is no further page,
/// `openapi.yaml`'s `entries-list` `meta.nextCursor`). The Hive-fallback
/// path (`EntriesRepositoryImpl.list()`) always returns `nextCursor: null`
/// (Boundaries) — a cached dump has no further page to request.
class EntriesPage {
  const EntriesPage({required this.items, required this.nextCursor});

  final List<Entry> items;
  final String? nextCursor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntriesPage &&
          other.nextCursor == nextCursor &&
          _listEquals(other.items, items));

  @override
  int get hashCode => Object.hash(Object.hashAll(items), nextCursor);

  @override
  String toString() =>
      'EntriesPage(items: ${items.length}, nextCursor: $nextCursor)';
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
