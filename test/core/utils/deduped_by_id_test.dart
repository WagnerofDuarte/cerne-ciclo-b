import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/utils/deduped_by_id.dart';

/// spec-5-1 round-2 review fix — `dedupedById<T>()` was extracted from two
/// near-identical private copies (`MeusRegistrosCubit._dedupedById` and
/// `EntriesRepositoryImpl`'s own `search()` helper) into this one shared
/// generic, but neither extraction left behind a test that exercises it
/// directly: both callers' own test suites only ever exercise it through
/// their respective `Entry`/`EntryDto` call sites.
void main() {
  group('dedupedById', () {
    test('keeps the first occurrence of a duplicate id, drops the rest', () {
      final result = dedupedById(['a1', 'b2', 'a3', 'c4'], (s) => s[0]);

      expect(result, ['a1', 'b2', 'c4']);
    });

    test('an already-duplicate-free list is returned unchanged, in order', () {
      final result = dedupedById(['a', 'b', 'c'], (s) => s);

      expect(result, ['a', 'b', 'c']);
    });

    test('an empty list decodes to an empty list', () {
      final result = dedupedById(<String>[], (s) => s);

      expect(result, isEmpty);
    });

    test('with seenIds, an item whose id is already in the set is dropped '
        'even though it never repeats within the list itself', () {
      final result = dedupedById(['a', 'b'], (s) => s, seenIds: {'a'});

      expect(result, ['b']);
    });

    test('the caller\'s own seenIds set is never mutated — the running set is '
        'this function\'s own local copy', () {
      final seenIds = {'a'};

      dedupedById(['a', 'b', 'c'], (s) => s, seenIds: seenIds);

      expect(seenIds, {'a'});
    });

    test('works over a non-String item type, keyed by a caller-supplied field '
        '— the generic is never coupled to Entry/EntryDto', () {
      final result = dedupedById([
        (id: '1', v: 'x'),
        (id: '2', v: 'y'),
        (id: '1', v: 'z'),
      ], (item) => item.id);

      expect(result.map((item) => item.v), ['x', 'y']);
    });
  });
}
