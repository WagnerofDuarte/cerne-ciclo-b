# Test Automation Summary

## Scope

Story 5.1 (semantic search with debounced input) moved to `done`, including an uncommitted round-2 review patch (`search()`'s own de-dupe, a `MeusRegistrosScreen` skeleton-arm fix, and a cubit recovery test). Cross-checking every I/O-matrix row, acceptance criterion, and round-2 review finding against the existing suite found the feature's own test coverage (cubit, data source, repository, widget, e2e) already comprehensive — six scenarios, both round-1 and round-2 regressions, all exercised. Two concrete gaps remained, both tied directly to the uncommitted patch rather than to the story's original scope:

1. The patch's `initState` fix in `meus_registros_screen.dart` (arms the search skeleton when `EntriesSearchCubit` — a DI singleton — is already `ResourceLoading` at remount) had no test anywhere; every existing "slow request" case only starts a search *after* mount.
2. The patch's extraction of `dedupedById<T>()` into `lib/core/utils/deduped_by_id.dart` (shared by `MeusRegistrosCubit` and `EntriesRepositoryImpl.search()`) left the new generic untested in isolation — both callers' own tests only exercise it indirectly through their own `Entry`/`EntryDto` call sites.

Two items the spec's own round-2 review explicitly deferred (Dynamic Type coverage for `EntriesSearchBar`; the DTO→Entity mapping exception-safety gap in `list()`/`getById()`/`search()`) are left alone — both are pre-existing, feature-wide gaps the spec itself scoped out of this story, not something to fold in silently here.

## Generated Tests

### Widget test (screen-level regression guard)

- [x] `test/features/entries/presentation/screens/meus_registros_screen_test.dart` — new case in the `spec-5-1: docked search bar` group: starts a search, lets it debounce into `ResourceLoading` (held open via the fake repository's `searchGate`), tears the screen down and remounts it against the *same* `MeusRegistrosCubit`/`EntriesSearchCubit` instances (mirroring the real DI-singleton lifetime), then asserts the search skeleton stays blank below 300ms and appears past it — proving the new `initState` arms fresh on remount rather than staying blank forever.
  - Verified the test actually guards the fix: temporarily reverted just the patch's `initState` branch, re-ran the new test alone, confirmed it failed (`Found 0 widgets with type "EntrySkeletonCard"`), then restored the file and confirmed `git diff --stat` matched the original uncommitted diff exactly before re-running the full suite.

### Unit tests (new shared utility)

- [x] `test/core/utils/deduped_by_id_test.dart` (new file) — direct coverage of `dedupedById<T>()`: first-occurrence-wins on a duplicate id, an already-unique list returned unchanged and in order, an empty list, the `seenIds` parameter dropping an item not repeated within the list itself, the caller's own `seenIds` set never being mutated, and genericity over a non-`String` item type keyed by a caller-supplied field.

## Verification

- `fvm flutter analyze` — zero issues.
- `fvm flutter test` — 765/765 passed (7 new tests: 1 widget + 6 unit; none removed).

## Coverage

- Story 5.1's own six I/O-matrix rows (semantic match, rapid typing, query cleared, offline, stale response, slow request) and all three round-2 review-fix regressions (recovery from error, non-const `ResourceLoading` emits, de-dupe) were already covered before this run, across `entries_search_cubit_test.dart`, `entries_search_bar_test.dart`, `entries_remote_data_source_test.dart`, `entries_repository_impl_test.dart`, `meus_registros_screen_test.dart`, `bootstrap_integration_test.dart`, and `entries_search_flow_e2e_test.dart` (real-pipeline happy path + offline).
- The one screen-level round-2 patch without coverage (remount-while-loading skeleton arm) and the one new shared utility without direct coverage (`dedupedById<T>()`) are both covered now.
- Deferred, by design, not by oversight: Dynamic Type/accessibility-scaling coverage for `EntriesSearchBar` (pre-existing feature-wide gap per the spec's own round-2 review) and exception-safety for the DTO→Entity mapping step in `list()`/`getById()`/`search()` (same pre-existing pattern across all three repository methods) — both explicitly deferred in `spec-5-1-semantic-search-with-debounced-input.md` and `deferred-work.md`, not story-5.1-specific regressions.

## Next Steps

- Story 5.2 (metadata filters) is next in delivery order (`sprint-status.yaml`: `backlog`) — re-run this workflow once it's implemented, since it reactivates `EntriesSearchBar`'s currently-inert funnel icon and will need its own I/O-matrix coverage.
- The deferred stale-search-box-on-remount bug (`EntriesSearchBar`'s uncontrolled `TextField` never re-seeding from the cubit's live query) remains a real, acknowledged gap in `deferred-work.md` — it's a product/UX defect, not a missing test, so it wasn't addressed here.

---

## Story 5.2 — metadata filters, round-2 code review (2026-11-05)

`spec-5-2-metadata-filters.md` moved to `review`, then its round-2 code review found and fixed one decision-needed issue and eight patch findings. Tests added to cover them:

- `test/features/entries/presentation/cubit/meus_registros_cubit_test.dart` — "Date range filter only" (I/O-matrix symmetry gap), cubit-level "Remove one of two active chips" reverse direction (date kept, source removed), a confirmed entry/pending write created *after* the active `dateTo` now shows live (the resolved decision: `_matchesActiveFilters()` no longer enforces the `dateTo` upper bound locally), and an already-visible non-matching item correctly drops out of view when `applyFilters()` changes the active filter (reverse ordering).
- `test/features/entries/presentation/widgets/entries_filter_sheet_test.dart` — replaced the two bare-function `dateRangePresetMatching()` tests (the function itself was deleted; `MeusRegistrosCubit` now stores the selected `DateRangePreset` directly instead of re-deriving it) with a full round-trip test through the real "Aplicar" → reopen → pre-select flow for "Esta semana", plus an explicit `dateRangePreset` on the existing "Este mês" direct-priming test.
- `test/features/entries/presentation/screens/meus_registros_screen_test.dart` — a filter applied, then a load failure, then "Tentar novamente" tapped through the real UI, asserting the retried call still carries the filter (the actual wiring `retryCurrentPage()` was introduced for, previously only exercised at the cubit level or with no filter active).
- `test/features/entries/presentation/widgets/entries_search_bar_test.dart` — the funnel's tooltip also signals "Filtros (ativos)" when a filter is active, not just the icon's fill color.

### Verification

- `fvm flutter analyze` — zero issues.
- `fvm flutter test` — all passed (counts not re-stated here; see the commands above for a fresh run).

### Coverage

- All 9 round-2 findings (1 resolved decision + 8 patches) now have direct test coverage, per `spec-5-2-metadata-filters.md`'s own "Review Findings (round 2)" section.
- Deferred, not addressed here: a cosmetic ≤300ms skeleton-timing gap in the bundled story-5.1 round-2 fix (`meus_registros_screen.dart`'s `initState`), whose complete fix needs a `loadingStartedAt` field on `EntriesSearchCubit` (story 5.1, already `done`) — out of this story's own scope.

---

## Story 5.2 — metadata filters, real-pipeline E2E gap (2026-11-05)

Every other test tier for spec-5-2 (cubit state machine, data-source query serialization, repository offline fallback, widget/screen wiring) was already covered going into this run, but — unlike spec-4-1 (`entries_list_flow_e2e_test.dart`) and spec-5-1 (`entries_search_flow_e2e_test.dart`) — the metadata-filters feature itself had no test driving the real network + real disk pipeline: real `UrlBuilder`/`HeaderInterceptor`/`RetryInterceptor`/`Dio` and a real `entries` Hive box underneath `MeusRegistrosCubit.applyFilters()`/`clearFilters()`/`loadMore()`. One behavior in particular — the offline-fallback cache dump staying filter-oblivious by design (AD-9, `EntriesRepository.list()`'s own doc) — only actually shows up at this tier, since the cubit/repository unit tests mock the fallback path away.

### Generated Tests

- [x] `test/features/entries/entries_filters_flow_e2e_test.dart` (new file) — same real-pipeline shape as `entries_list_flow_e2e_test.dart`/`entries_search_flow_e2e_test.dart` (fake `HttpClientAdapter` as the only seam; everything above and below it is genuine production wiring). Five cases:
  1. `applyFilters(source: audio)` sends exactly `{limit, source}` to `entries-list`, with real headers, and persists the filtered page to the real Hive box.
  2. `applyFilters(dateFrom, dateTo)` sends both as `.toUtc().toIso8601String()` (`Z`-suffixed), with no `source` param.
  3. `loadMore()` after a filtered first page carries the same `source`/`dateFrom`/`dateTo` forward alongside the real `cursor`, appending to the real Hive box.
  4. Offline: a filtered `applyFilters()` call genuinely retries `NETWORK_OFFLINE` `maxRetries` times over the real `RetryInterceptor`, then falls back to the *full*, unfiltered cached Hive dump (including an entry that doesn't match the active `source` filter) — locking in the documented AD-9 behavior rather than a client-side-filtered subset.
  5. `clearFilters()` after a filtered load re-queries with just `{limit}` — no leftover filter params.

### Verification

- `fvm flutter analyze` — zero issues.
- `fvm flutter test test/features/entries/entries_filters_flow_e2e_test.dart` — 5/5 passed.
- `fvm flutter test test/features/entries/` — 260/260 passed (no regressions).
- `fvm flutter test` (full suite) — 819/819 passed (no regressions).

### Coverage

- The real-pipeline tier for spec-5-2 now matches the tier spec-4-1/spec-5-1 already have, including the one behavior (filter-oblivious offline fallback) that only surfaces above the mocked-repository level.
- Not duplicated: filter-selection state machine (`meus_registros_cubit_test.dart`) and query-param serialization against a mocked `ApiClient` (`entries_remote_data_source_test.dart`) were already thorough — this file deliberately stays at the real-network/real-disk tier only.

### Next Steps

- No further gaps identified for spec-5-2's own scope. Re-run this workflow once the next story in delivery order (`sprint-status.yaml`) lands.

---

## Story 5.3 — combined search + filter & non-disruptive clearing (2026-11-05)

`spec-5-3-combined-search-filter-non-disruptive-clearing.md` moved to `done`: `EntriesSearchCubit` gained its own `source`/`dateFrom`/`dateTo`/`_lastQuery` fields plus `updateFilters()`, `MeusRegistrosScreen` bridges every filter-mutating call site (`EntriesFilterSheet`'s "Aplicar", the chip row's two chip-removes, "Limpar filtros") to it alongside the existing `MeusRegistrosCubit` call, and the funnel-fill gate/chip row both dropped their `ResourceIdle` restriction so a filter now narrows an active search too. Code review (step-04) then found two patch-level issues in `updateFilters()` itself — a missing `isClosed` guard before its `_search()` call (a real race once `initState()` calls it unconditionally on every mount), and a wasted `entries-search` network call on every such mount when the filter values hadn't actually changed — plus a stale fake-repository doc comment and this file's own missing story-5.3 entry.

### Generated Tests

- [x] `test/features/entries/domain/repositories/entries_repository.dart` / `entries_remote_data_source_test.dart` / `entries_repository_impl_test.dart` — `search()`'s new `source`/`dateFrom`/`dateTo` forwarding, mirroring `list()`'s own omit-when-null / `.name` / `.toUtc().toIso8601String()` serialization tests exactly, plus a repository-level "forwards verbatim" test.
- [x] `test/features/entries/presentation/cubit/entries_search_cubit_test.dart` — new `spec-5-3: updateFilters()` group: idle silent-storage, apply-during-active-search (no debounce), a filter outliving a brand-new query, clear-during-active-search, cancelling an already-pending debounce, and the generation-bump stale-discard guard. Two more cover the round-2 patch directly: calling `updateFilters()` with values identical to what's already stored during an active search fires no redundant `search()` call, and calling it after `close()` never throws.
- [x] `test/features/entries/presentation/widgets/entries_filter_sheet_test.dart` — new `spec-5-3: combined search + filter bridge` group: "Aplicar" during an active search re-queries with the same term plus the new filter; "Aplicar" while idle stores silently with no `entries-search` call.
- [x] `test/features/entries/presentation/screens/meus_registros_screen_test.dart` — new `spec-5-3: combined search + filter & non-disruptive clearing` group covering all five I/O-matrix rows (apply/clear/chip-remove mid-search, idle storage, re-entering the screen with no stale filter carried into a still-active search); rewrote the now-reversed "funnel must not read as filled while searching" 5.2 test (the funnel now *stays* filled, since a filter narrows the search too); fixed the pre-existing round-2 remount test's doc/queued-result count for the patch's no-op-when-unchanged behavior (back to a single `search()` call, since neither mount in that test ever has an active filter to begin with).

### Verification

- `fvm flutter analyze` — zero issues.
- `fvm flutter test` — 838/838 passed (no regressions).

### Coverage

- Every I/O-matrix row in the spec (apply/clear/remove-chip mid-search, idle storage, re-entry) and both round-2 code-review patches (`isClosed` guard, no-op-when-unchanged) now have direct test coverage.
- The two other round-04 review findings were triaged as pre-existing (not caused by this story) and deferred to `deferred-work.md` — no test changes needed for those here.

### Next Steps

- No further gaps identified for spec-5-3's own scope.
