---
title: 'Combined Search + Filter & Non-Disruptive Clearing'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'afb4d317b6cdd39d6fbf4d87943e5e0aae51da05'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `EntriesSearchCubit` (5.1) and `MeusRegistrosCubit`'s filters (5.2) are mutually inert — applying/clearing a filter during an active search silently no-ops, and a search query never carries the active filter.

**Approach:** Give `EntriesSearchCubit` its own filter fields plus `updateFilters()`; have `MeusRegistrosScreen` (the only place composing both cubits) call it alongside every existing filter-mutating call; have `_search()` forward those fields to `entries-search`. Clearing/removing a filter mid-search re-runs the same term with the new filter set — no query-box change, no reload.

## Boundaries & Constraints

**Always:**
- `EntriesRepository.search({required String query, EntrySource? source, DateTime? dateFrom, DateTime? dateTo})`; `EntriesRemoteDataSource.search()` forwards non-null values to `entries-search`, mirroring `list()`'s own convention (`.name`, `.toUtc().toIso8601String()`).
- `EntriesSearchCubit` gains `_activeSource`/`_activeDateFrom`/`_activeDateTo` + `_lastQuery` + `updateFilters({source, dateFrom, dateTo})`: always stores the fields; only when `_lastQuery` is non-empty, cancels any pending debounce and immediately re-runs `_search(_lastQuery)`, bumping `_generation` (same race-guard `_search` already uses). While idle: silent storage, no call.
- `_search(query)` passes `source`/`dateFrom`/`dateTo` to `_repository.search()` alongside `query`.
- `MeusRegistrosScreen` threads `searchCubit` into `EntriesFilterSheet`/`_ActiveFiltersRow` (new required param on both); their 4 filter-mutating call sites (`_applyAndClose`, chip-remove ×2, "Limpar filtros") also call `searchCubit.updateFilters(...)` right after the existing `cubit.applyFilters()`/`clearFilters()`.
- Funnel fill (`meus_registros_screen.dart:217-219`) drops its `ResourceIdle` gate — becomes `widget.cubit.hasActiveFilters` unconditionally. `_ActiveFiltersRow` renders above `_SearchResults` too, same condition.
- Clearing the search box while filters stay active needs no new code — `MeusRegistrosCubit`'s filtered state is already kept current in the background regardless of which branch is visible (5.2, unchanged).
- `MeusRegistrosScreen.initState()`'s existing `cubit.loadFirstPage()` call also calls `searchCubit.updateFilters(source: null, dateFrom: null, dateTo: null)` — both cubits are `lazySingleton`s, so a fresh mount must reset both, or a re-entered screen carries a stale filter from a previous visit into a still-active search.

**Ask First:** none — scope pinned by `epic-5-context.md` and RF06.

**Never:** the two cubits importing each other (RNF06) — filters flow only via the screen bridge; a debounce on the filter-triggered re-search; a "CATEGORIA"/tag filter; changing `_loadFiltered()`'s own background `entries-list` query.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Apply filter during active search | search "ansiedade" active, Aplicar "áudio" | one `entries-search` call: `q=ansiedade&source=audio` | N/A |
| Clear filters during active search | source+date active + search term, "Limpar filtros" tapped | re-queries `entries-search` with only `q`; box/screen undisturbed | N/A |
| Remove one of two chips mid-search | source+date active, search active, "x" on source chip | re-queries `entries-search` with `q` + remaining date range | N/A |
| Filter applied/cleared/box emptied while search idle | empty box | stored silently; `entries-list` queried (5.2 path, unchanged), no `entries-search` call | N/A |
| Re-enter screen after a prior combined session | leave with search+filter active, return | both cubits' filters reset on `initState`; no stale filter carried forward | N/A |

</frozen-after-approval>

## Code Map

- `entries_repository.dart:88` -- `search()` signature to extend (`entries_repository_impl.dart:135-136` is a thin pass-through, unaffected beyond the new params)
- `entries_remote_data_source.dart:125-143` -- `search()` param-building, mirrors `list()` (:65-96)
- `entries_search_cubit.dart:20-100` -- add filter fields/`_lastQuery`/`updateFilters()`; extend `_search()`
- `meus_registros_screen.dart:87-90` (`initState`), `:208-223` (fill gate), `:260-282` (chip-row branch), `:656-710` (`_ActiveFiltersRow`)
- `entries_filter_sheet.dart:38-96,121-130` (`_applyAndClose`)
- `meus_registros_cubit.dart` -- unchanged; `activeSource`/`activeDateFrom`/`activeDateTo` getters reused read-only
- `date_range_preset.dart` -- unchanged

## Tasks & Acceptance

**Execution:**
- [x] `entries_repository.dart` -- add `source`/`dateFrom`/`dateTo` to `search()`
- [x] `entries_remote_data_source.dart` -- forward new params to `entries-search`
- [x] `entries_search_cubit.dart` -- add filter fields, `_lastQuery`, `updateFilters()`; wire into `_search()`
- [x] `entries_filter_sheet.dart` -- add `searchCubit` param; bridge in `_applyAndClose`
- [x] `meus_registros_screen.dart` -- pass `searchCubit` down; bridge chip-remove/"Limpar"; drop funnel's `ResourceIdle` gate; render chip row over search results too; reset `searchCubit`'s filters in `initState`
- [x] Unit tests covering every I/O Matrix row
- [x] Widget tests: chip row + funnel fill during active search; Aplicar/Limpar/chip-remove mid-search

**Acceptance Criteria:**
- Given an active search term and no filters, when a filter is applied, then the funnel fills and the chip row appears above the search results.
- Given combined search+filter results on screen, when "Limpar filtros" is tapped, then results update to unfiltered semantic-search results for the same query, with no search-box or screen disruption.

### Review Findings

**Patch:**
- [x] [Review][Patch] `updateFilters()`'s "skip when unchanged" short-circuit (`filtersChanged`) compares only the incoming filter values against what's already stored, with no awareness of the cubit's current `Resource` state — if a filter-triggered re-search lands in `ResourceError` and the user then reapplies the exact same filter selection (e.g. reopens the sheet, taps "Aplicar" again with nothing changed), `filtersChanged` evaluates false and `updateFilters()` returns without retrying. `_SearchErrorState` renders no retry button by design (search errors retry only via the next keystroke), so the only recovery for this specific path is editing the search text — an undocumented, non-obvious escape hatch. No new `spec-5-3` test exercises a `ResourceError` outcome through the `updateFilters()`-triggered re-search path at all. [`lib/features/entries/presentation/cubit/entries_search_cubit.dart:112-121`]
- [x] [Review][Patch] `EntriesRemoteDataSource.search()`'s doc comment (edited by this diff) now calls `q` "exactly one required query parameter," but `docs/input/backend/api/openapi.yaml` marks `q` as `required: false` for the `entries-search` operation — the comment conflates "the Dart method's own positional parameter is non-optional" with "the backend requires it," which could mislead a future reader about the actual contract. [`lib/features/entries/data/datasources/entries_remote_data_source.dart:118-119`]

**Defer:**
- [x] [Review][Defer] Source-chip "x" removal while a date-range chip is also active, during an active search, is untested at the `searchCubit.updateFilters()` bridge — every two-chip-removal test (cubit- and widget-level) taps only the date-range chip's "x". A regression in the source-chip's own bridge (dropped call, wrong fields forwarded) would ship with the full suite green. Already self-disclosed and deferred in `deferred-work.md` ("Deferred from: code review of spec-5-3...") as pre-existing, bundled 5.2 round-2 work — not re-added there to avoid a duplicate entry. [`lib/features/entries/presentation/screens/meus_registros_screen.dart:716-728`] — deferred, pre-existing
- [x] [Review][Defer] No e2e test drives `entries-search` with `source`/`dateFrom`/`dateTo` over the real network/Hive pipeline (real `UrlBuilder`/interceptors/`Dio`) — only the mocked-`ApiClient` and fake-repository tiers cover the new combined query params. Already self-disclosed in `deferred-work.md` as a known thin spot, not blocking since every I/O-matrix row is covered at the unit/widget tier. [`test/features/entries/entries_filters_flow_e2e_test.dart`, `test/features/entries/entries_search_flow_e2e_test.dart`] — deferred, pre-existing

**Reject (noise, dropped):** fake-repository test doubles in `entries_search_cubit_test.dart`/`meus_registros_screen_test.dart` record filtered-search calls via two incompatible internal shapes (index-aligned parallel lists vs. a single combined list) — a test-fixture-maintenance nitpick with no behavioral impact; the I/O & Edge-Case Matrix table not mentioning the parallel backgrounded `entries-list` call alongside `entries-search` is a spec-documentation completeness note on a frozen artifact, not a code defect; `applyFilters(dateRangePreset)` being type-decoupled from `dateFrom`/`dateTo` is a hypothetical future-misuse concern with no concrete failure scenario today (every call site passes them in sync); the remount-skeleton-timer gap has already been deferred identically across three consecutive stories (5.1/5.2/5.3), a process note rather than a new finding; `EntriesFilterSheet`'s "Esta semana" round-trip test not re-asserting `dateTo` advances on a second "Aplicar" tap is a narrow test nitpick on simple, by-design behavior; the Acceptance Auditor's two FYI observations (Code Map's stale "unchanged" claim for `meus_registros_cubit.dart`; `sprint-status.yaml` showing `review` while this file's own frontmatter already says `done`) are non-blocking metadata/documentation notes, not defects.

## Design Notes

Filter state is duplicated, not shared — RNF06 forbids one cubit importing the other, so the screen is the only legitimate bridge.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

## Suggested Review Order

**Combined filter mechanism (entry point)**

- `updateFilters()` — the one new method that makes filters and search interact; stores the selection, only re-searches when active and actually changed.
  [`entries_search_cubit.dart:107`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L107)

- Review fix: `isClosed` guard before the re-search — `initState()` now calls this unconditionally on every mount, making the race real.
  [`entries_search_cubit.dart:127`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L127)

- Review fix: `filtersChanged` short-circuit — skips a wasted `entries-search` network call when nothing actually changed.
  [`entries_search_cubit.dart:112`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L112)

**Search gains filter params (domain + data)**

- `EntriesRepository.search()` — the port extended with `source`/`dateFrom`/`dateTo`, mirroring `list()`'s own shape.
  [`entries_repository.dart:96`](../../lib/features/entries/domain/repositories/entries_repository.dart#L96)

- `EntriesRemoteDataSource.search()` — forwards the new params to `entries-search`, same UTC-serialization convention as `list()`.
  [`entries_remote_data_source.dart:130`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L130)

**Screen bridge (the only legitimate place to sync two cubits, RNF06)**

- `initState()` resets `searchCubit`'s filters on every mount — closes the stale-filter-across-remount gap.
  [`meus_registros_screen.dart:96`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L96)

- Funnel fill drops its old `ResourceIdle` gate — now unconditional on `hasActiveFilters`.
  [`meus_registros_screen.dart:230`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L230)

- `_ActiveFiltersRow` now renders over search results too, not only the plain timeline.
  [`meus_registros_screen.dart:301`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L301)

- `_ActiveFiltersRow`'s three bridges — clear/chip-remove ×2 — each pairs `cubit.applyFilters()/clearFilters()` with `searchCubit.updateFilters()`.
  [`meus_registros_screen.dart:727`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L727)

- `EntriesFilterSheet._applyAndClose` — the sheet's own "Aplicar" bridge, same pairing.
  [`entries_filter_sheet.dart:135`](../../lib/features/entries/presentation/widgets/entries_filter_sheet.dart#L135)

**Peripherals**

- `updateFilters()` test group — every I/O-matrix row plus the two review-fix regressions (no-op-when-unchanged, post-`close()` safety).
  [`entries_search_cubit_test.dart:1`](../../test/features/entries/presentation/cubit/entries_search_cubit_test.dart#L1)

- Screen-level combined-search-+-filter group — Aplicar/Limpar/chip-remove mid-search, plus the re-entry "no stale filter" case.
  [`meus_registros_screen_test.dart:1`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L1)
