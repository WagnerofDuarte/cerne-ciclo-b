---
title: 'Metadata Filters'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '6e4e9d5e37f376592cb6491f0132ecd052511bc0'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Meus Registros' funnel button is a no-op (spec-5-1) — there is no way to narrow the plain timeline by entry source or date range, and `EntriesRepository.list()` has no filter parameters to call.

**Approach:** Extend `list()` with `source`/`dateFrom`/`dateTo`; add a filter bottom sheet and a removable active-filter-chip row to `MeusRegistrosCubit`'s existing plain-timeline branch. Filters apply only to the unfiltered list path this story — combining them with an active search term is story 5.3.

## Boundaries & Constraints

**Always:**
- `EntriesRepository.list({String? cursor, int limit = 20, EntrySource? source, DateTime? dateFrom, DateTime? dateTo})`; `EntriesRemoteDataSource.list()` forwards non-null values as `source`(`.name`)/`dateFrom`/`dateTo` (ISO-8601) to `entries-list`, mirroring `search()`'s existing convention.
- Source is single-choice (`EntrySource?`, not a `Set`) — see Design Notes.
- `MeusRegistrosCubit` gains `applyFilters({source, dateFrom, dateTo})`/`clearFilters()` (own methods, not `loadFirstPage()` — see Design Notes); both bump `_generation`, replace state via `list()`. `_fetchMore()` carries active filters forward alongside `cursor`.
- `_offlineFallback()` stays as-is (full unfiltered box dump, same `cursor == null` trigger) — offline + filters silently returns the full cached list (AD-9: cache is never locally filtered).
- New `EntriesFilterSheet` + static `.show()`, mirroring `InsertionModal.show()`'s pattern (`isScrollControlled`, `useSafeArea`, `colorScrimHeavy`, Reduce-Motion-aware `durationSheetUp`). Groups: "INTERVALO DE DATA" (Todo o período/Esta semana/Este mês → computed `dateFrom`/`dateTo`) and "TIPO DE ENTRADA" (manual/áudio/foto/chat), both single-choice. No "CATEGORIA". "Aplicar" commits via `cubit.applyFilters(...)` + closes; "Limpar" resets only the sheet's pending selection.
- Active-filters chip row renders under the search bar, only inside the existing `ResourceIdle` branch (`meus_registros_screen.dart:209`), when any filter is active; each chip removable ("x", re-applies the rest); "Limpar filtros" link calls `cubit.clearFilters()`. Chips: `colorSecondary`/`colorCategoryChipText`/`radiusFull`.
- `EntriesSearchBar` gains `onFilterTap` (replaces `onPressed: () {}`, line 63) and `hasActiveFilters` (fills the funnel icon).

**Ask First:** none — scope pinned by `epic-5-context.md` and RF06.

**Never:** filter params on `EntriesSearchCubit`/`search()`, or a combined search+filter query (story 5.3); a "CATEGORIA"/tag group (extension, forbidden); client-side filtering/sorting of the cached box; a new cubit/DI registration.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Source filter only | Aplicar with "áudio" selected | query `source=audio`; results narrowed | N/A |
| Source + date range together | both selected, Aplicar | one query, both params — AND narrowing | N/A |
| Remove one of two active chips | tap "x" on the source chip | re-queries with only the date range | N/A |
| Clear all filters | "Limpar filtros" link tapped | full unfiltered list restored in place, no reload/re-mount | N/A |
| Load more with filters active | scroll to bottom, filters active | `_fetchMore` sends `cursor` + same filters | N/A |
| Offline, filters active, first page | no connectivity | `_offlineFallback()`'s full unfiltered cached dump renders, no error shown | N/A (cache content silently ignores filters, per AD-9) |

</frozen-after-approval>

## Code Map

- `entries_repository.dart:38` -- `list()` signature to extend
- `entries_remote_data_source.dart:54-61` -- query-param building to extend
- `entries_repository_impl.dart:55-95` (`list()`), `:189-208` (`_offlineFallback()`, stays filter-oblivious)
- `meus_registros_cubit.dart:58` (`_generation`), `:138-140` (`loadFirstPage()`), `:223-225` (`_fetchMore()`)
- `meus_registros_screen.dart:198` (search bar docking), `:201-237` (`ResourceIdle` fork — chip row + sheet mount here)
- `entries_search_bar.dart:19,58-72` -- funnel no-op to replace with `onFilterTap`/`hasActiveFilters`
- `insertion_modal.dart:63-135` -- bottom-sheet `.show()` pattern to mirror
- `entry.dart:6` -- `EntrySource` enum (manual/audio/photo/chat), confirmed no `tags` field to touch
- `design_tokens.dart` -- reuse `colorSecondary`/`colorCategoryChipText`/`radiusFull`/`radiusLg`/`elevation2`/`textMonoCaption`/`durationSheetUp`/`colorScrimHeavy`; no new token

## Tasks & Acceptance

**Execution:**
- [x] `entries_repository.dart` -- add `source`/`dateFrom`/`dateTo` params to `list()`
- [x] `entries_remote_data_source.dart` -- forward new params as query params to `entries-list`
- [x] `entries_repository_impl.dart` -- pass params through; leave `_offlineFallback()` untouched
- [x] `meus_registros_cubit.dart` -- add `applyFilters()`/`clearFilters()`; carry filters into `_fetchMore()`
- [x] `presentation/widgets/entries_filter_sheet.dart` (new) -- date-range + source groups, Aplicar/Limpar
- [x] `entries_search_bar.dart` -- `onFilterTap` + `hasActiveFilters` (filled icon)
- [x] `meus_registros_screen.dart` -- wire sheet trigger; render active-filter chip row in the `ResourceIdle` branch
- [x] Unit tests covering every I/O Matrix row across the new/changed files
- [x] Widget tests: filter sheet (selection, Aplicar/Limpar), chip row (remove one, clear all), filled funnel icon

**Acceptance Criteria:**
- Given the filter sheet, when "áudio" + a date range are both applied, then the single `entries-list` query carries both params and results narrow with AND logic.
- Given active filters, when "Limpar filtros" is tapped, then the full unfiltered list renders in place without a screen reload or re-mount.
- Given active filters, when the user scrolls to load more, then the continuation request carries the same filters alongside `cursor`.
- Given the device is offline with filters active on the first page, when the fallback fires, then it shows the full cached list, not a filtered or empty one.

### Review Findings

**Patch:**
- [x] [Review][Patch] `dateFrom`/`dateTo` were sent via `.toIso8601String()` on local (non-UTC) `DateTime`s, which omits the `Z`/offset the OpenAPI contract's `format: date-time` (RFC3339) requires. [lib/features/entries/data/datasources/entries_remote_data_source.dart:78-79] — fixed: serialize via `.toUtc().toIso8601String()` at the serialization boundary only.
- [x] [Review][Patch] A newly-created/pending entry was prepended into the filtered list unconditionally, visibly violating an active filter. [lib/features/entries/presentation/cubit/meus_registros_cubit.dart] — fixed: added `_matchesActiveFilters()`/`_visiblePendingWrites`, gating both the confirmed-entry prepend and the pending-write placeholder on the active filter.
- [x] [Review][Patch] The funnel's "filled" (active-filters) indicator stayed on during unrelated search results. [lib/features/entries/presentation/screens/meus_registros_screen.dart:208] — fixed: gated on `searchState is ResourceIdle<List<Entry>>` too.
- [x] [Review][Patch] The error-state "Tentar novamente" button called `loadFirstPage()`, which resets active filters before retrying — a failed filtered query silently "succeeded" with the full unfiltered list instead. [lib/features/entries/presentation/screens/meus_registros_screen.dart:233] — fixed: added `MeusRegistrosCubit.retryCurrentPage()` (keeps the active filter selection), wired to `onRetry` instead.
- [x] [Review][Patch] `dateRangePresetMatching()` checked `thisWeek` before `thisMonth`, mislabeling a month-long filter as "Esta semana" whenever the month's 1st coincides with that Monday. [lib/features/entries/presentation/widgets/entries_filter_sheet.dart] — fixed: check order swapped; the separate staleness-after-rollover limitation is left as a known, documented tradeoff.
- [x] [Review][Patch] No Dynamic Type/accessibility-scaling test existed for the new `EntriesFilterSheet`, despite its own doc citing epic-5's explicit UX note. [test/features/entries/presentation/widgets/entries_filter_sheet_test.dart] — fixed: added a `TextScaler.linear(3.0)` test.
- [x] [Review][Patch] No screen-level test exercised two active-filter chips rendered together or the date-range chip's own "x". [test/features/entries/presentation/screens/meus_registros_screen_test.dart] — fixed: added a source+date-range test tapping the date-range chip's removal specifically.
- [x] [Review][Patch] `EntriesFilterSheet.show()`'s reduce-motion branch had no test, unlike `InsertionModal`'s equivalent. [test/features/entries/presentation/widgets/entries_filter_sheet_test.dart] — fixed: added a reduce-motion test mirroring `insertion_modal_test.dart`'s pattern.

**Reject (noise, dropped):** offline+filters silently showing the unfiltered cache is an explicit, already-frozen Boundary (AD-9), not a bug; the funnel staying tappable during an active search is inert by design (updates hidden cubit state with no visible effect until search clears); "date-range boundary inclusivity" isn't testable client-side since the app only forwards `dateFrom`/`dateTo` verbatim — inclusivity is the backend's own contract behavior.

## Design Notes

TIPO DE ENTRADA is single-choice, not multi-choice as the prototype's chip row suggests: `source` (openapi.yaml, both endpoints) accepts exactly one enum value, and AD-9 forbids merging multiple per-source queries client-side — the prototype is a visual reference, not an API contract, so the frozen backend wins.

`applyFilters()`/`clearFilters()` are separate from `loadFirstPage()` because that method's doc contract is "always re-fetch on mount" — reusing it for an in-session filter change would conflate two different triggers.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

## Suggested Review Order

**Filter contract (domain + data)**

- Entry point — `list()` gains the three filter params the rest of the feature hangs off.
  [`entries_repository.dart:48`](../../lib/features/entries/domain/repositories/entries_repository.dart#L48)

- Query-param forwarding, non-null-only, mirroring `search()`'s existing convention.
  [`entries_remote_data_source.dart:65`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L65)

- Review fix: dates serialize via `.toUtc().toIso8601String()` — local-time would violate the contract's RFC3339 `date-time` format.
  [`entries_remote_data_source.dart:78`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L78)

- Repository impl: params pass straight through; `_offlineFallback()` deliberately stays filter-oblivious (AD-9).
  [`entries_repository_impl.dart:56`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L56)

**Filter state machine (cubit)**

- Session-scoped filter fields — `null` means "no filter of that kind", never a sentinel.
  [`meus_registros_cubit.dart:67`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L67)

- `_loadFiltered()` — the shared "bump generation, replace state via list()" body `applyFilters()`/`clearFilters()`/`loadFirstPage()` all funnel through.
  [`meus_registros_cubit.dart:278`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L278)

- `applyFilters()` — replaces (never merges) the active selection; omitting a param clears that one dimension.
  [`meus_registros_cubit.dart:251`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L251)

- Review fix: `retryCurrentPage()` retries with filters intact — `loadFirstPage()` (the old `onRetry` target) silently dropped them.
  [`meus_registros_cubit.dart:239`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L239)

- Review fix: `_matchesActiveFilters()`/`_visiblePendingWrites` — a non-matching new entry no longer breaks the active filter's visible promise.
  [`meus_registros_cubit.dart:93`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L93)

**Filter sheet + screen wiring (UI)**

- `EntriesFilterSheet` — mirrors `InsertionModal.show()`'s bottom-sheet choreography; two single-choice groups, no "CATEGORIA".
  [`entries_filter_sheet.dart:108`](../../lib/features/entries/presentation/widgets/entries_filter_sheet.dart#L108)

- Review fix: `dateRangePresetMatching()` checks `thisMonth` before `thisWeek` — the prior order mislabeled a month-long filter when the 1st fell on a Monday.
  [`entries_filter_sheet.dart:73`](../../lib/features/entries/presentation/widgets/entries_filter_sheet.dart#L73)

- Sheet trigger — funnel tap opens the sheet; the screen now rebuilds on `MeusRegistrosCubit`'s own state too.
  [`meus_registros_screen.dart:213`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L213)

- Review fix: funnel "filled" indicator gated on `ResourceIdle` too — it no longer lies during an active, unrelated search.
  [`meus_registros_screen.dart:217`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L217)

- Review fix: error-state retry now calls `retryCurrentPage`, not `loadFirstPage`.
  [`meus_registros_screen.dart:250`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L250)

- Active-filter chip row — mounted only in the plain-timeline branch; each chip's "x" re-applies the rest.
  [`meus_registros_screen.dart:656`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L656)

- `EntriesSearchBar`'s funnel button — real `onFilterTap`/`hasActiveFilters` replacing spec-5-1's no-op.
  [`entries_search_bar.dart:23`](../../lib/features/entries/presentation/widgets/entries_search_bar.dart#L23)

**Peripherals**

- Cubit tests — every I/O Matrix row plus the two filter-bypass review-fix regressions.
  [`meus_registros_cubit_test.dart:715`](../../test/features/entries/presentation/cubit/meus_registros_cubit_test.dart#L715)

- Filter sheet tests — groups, Aplicar/Limpar, Dynamic Type, reduce-motion (review fixes).
  [`entries_filter_sheet_test.dart:1`](../../test/features/entries/presentation/widgets/entries_filter_sheet_test.dart#L1)

- Screen tests — funnel fill/revert across search state, two-chip removal (review fix), end-to-end clearing.
  [`meus_registros_screen_test.dart:1139`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L1139)

- Data-source tests for the new query-param shape, including the UTC-serialization review fix.
  [`entries_remote_data_source_test.dart:239`](../../test/features/entries/data/datasources/entries_remote_data_source_test.dart#L239)
