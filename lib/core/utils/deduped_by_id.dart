/// First-occurrence-wins de-duplication by a caller-supplied id, shared by
/// `MeusRegistrosCubit._dedupedById` (paginated `Entry` lists, with an
/// optional running [seenIds] set across pages) and
/// `EntriesRepositoryImpl.search()` (a single `EntryDto` list) — both are
/// trust-but-verify guards against the backend ever violating its own
/// no-duplicate-ids invariant.
List<T> dedupedById<T>(
  List<T> items,
  String Function(T item) idOf, {
  Set<String>? seenIds,
}) {
  final seen = {...?seenIds};
  return [
    for (final item in items)
      if (seen.add(idOf(item))) item,
  ];
}
