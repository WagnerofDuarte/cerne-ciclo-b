---
title: 'Metadata Filters'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 1
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

### Review Findings (round 2)

**Patch (round 2):**
- [x] [Review][Patch] [Decision: resolved — exempt live entries] `DateRangePreset.rangeFrom()` freezes `dateTo` to `DateTime.now()` at the moment "Aplicar" is tapped (Design Notes: "dateTo is always now itself"), and the code-review-fix guard `_matchesActiveFilters()` rejects any `occurredAt` that `isAfter(_activeDateTo!)`. Since a freshly-created entry's `occurredAt` is by definition after the filter's apply-time, every entry created after applying "Esta semana"/"Este mês" was permanently excluded from view for as long as that filter stayed active — deterministic, not a rare timing coincidence, and silent. [lib/features/entries/presentation/cubit/meus_registros_cubit.dart:93-105 (`_matchesActiveFilters`)] — `docs/input/` is silent on this exact interaction (AGENTS.md: "decide and proceed"); resolved in favor of consistency with every other filter dimension in this cubit (new entries show live unless they actually violate the filter) — fix: the local live-match guard no longer enforces the `dateTo` upper bound at all (a freshly-created entry's `occurredAt` is always "now", so it can never meaningfully exceed a `dateTo` that only makes sense as a server-query narrowing bound); `dateTo` keeps narrowing the server `list()` query exactly as before — only the local overlay check changes. Secondary, same root cause: `_matchesActiveFilters()`'s `dateFrom` lower-bound check remains a client-side inclusivity assumption (`isBefore`, i.e. inclusive-at-the-boundary) that could still disagree with the backend's own real narrowing for an entry landing exactly on the lower boundary — accepted as a pre-existing, out-of-scope limitation (same rationale as the spec's own already-frozen boundary-inclusivity Reject note), since it only affects the local overlay's instant-visibility signal and the next full reload still shows the server's authoritative answer.
- [x] [Review][Patch] `dateRangePresetMatching()` re-derives the active date-range preset from `_activeDateFrom` by exact-equality match against a freshly recomputed "today" boundary. Once a day/week/month boundary rolls over while a date filter stays active (the filter is session-scoped and outlives any single day), reopening `EntriesFilterSheet` mis-pre-selects "Todo o período" instead of the still-active preset, and tapping "Aplicar" with nothing touched then calls `rangeFrom()` on that wrong preset, resolving to `(null, null)` — silently clearing the still-active date filter. The active-filter chip row mislabels the same way (shows "Todo o período" while a date filter is still narrowing every query). [lib/features/entries/presentation/widgets/entries_filter_sheet.dart:44-85 (`DateRangePreset.rangeFrom`, `dateRangePresetMatching`), :167-175 (`_EntriesFilterSheetState.initState`), lib/features/entries/presentation/screens/meus_registros_screen.dart:~691 (chip label)] — suggested fix: store the selected `DateRangePreset` itself as an explicit field on `MeusRegistrosCubit` (alongside `_activeDateFrom`/`_activeDateTo`, set directly by `applyFilters()`/`clearFilters()`/`loadFirstPage()`), and have both the sheet's `initState` and the chip label read it directly instead of re-deriving it from `dateFrom`.
- [x] [Review][Patch] No screen-level (widget) test verifies that `_ErrorState`'s "Tentar novamente" button — rewired from `loadFirstPage` to `retryCurrentPage()` specifically so a failed *filtered* query retries with the same filter rather than silently falling back to the full unfiltered list — actually preserves an active filter when tapped through the real UI. The existing cubit test calls `retryCurrentPage()` directly (bypassing the screen's wiring entirely); the one widget test that taps the real button never has a filter active, where `loadFirstPage()`/`retryCurrentPage()` are behaviorally identical. A regression reverting `onRetry` back to `loadFirstPage` would go undetected by either test. [test/features/entries/presentation/screens/meus_registros_screen_test.dart] — suggested fix: add a case mirroring the existing "load failure renders retry" test, but with a filter applied first, a queued failure, a tap on "Tentar novamente", and an assertion that the retried call still carries the active filter.
- [x] [Review][Patch] The funnel icon's `tooltip` is the unconditional literal `'Filtros'` regardless of `hasActiveFilters` — a screen-reader user has no way to learn filters are currently applied without separately discovering the active-filter chip row. [lib/features/entries/presentation/widgets/entries_search_bar.dart] — suggested fix: `tooltip: hasActiveFilters ? 'Filtros (ativos)' : 'Filtros'` (or equivalent).
- [x] [Review][Patch] No test exercises "date range filter only" applied from a clean, no-filter starting state — the one existing date-only assertion is reached by removing the source chip from an already-combined filter, not a from-scratch date-only `applyFilters()` call, leaving "Source filter only"'s own dedicated I/O-matrix row asymmetric with its date-only counterpart. [test/features/entries/presentation/cubit/meus_registros_cubit_test.dart]
- [x] [Review][Patch] No cubit-level unit test removes the *date-range* chip while keeping *source* active — only the reverse direction (removing source, keeping date range) is tested at the cubit level (`meus_registros_cubit_test.dart:771-794`); the date-chip-removal direction is covered only at the screen widget-test level, so a regression isolated to the cubit's own `applyFilters(source: source)` call path could ship undetected by the cubit suite alone. [test/features/entries/presentation/cubit/meus_registros_cubit_test.dart]
- [x] [Review][Patch] `EntriesFilterSheet`'s reopen-preselection round-trip test only exercises the "Este mês" preset through the sheet's actual `initState`/reopen flow; "Esta semana" is tested only against the bare `dateRangePresetMatching()` function directly (`entries_filter_sheet_test.dart:338-348`), never through the real reopen wiring, leaving that pre-selection path's actual wiring for "Esta semana" unverified end-to-end. [test/features/entries/presentation/widgets/entries_filter_sheet_test.dart]
- [x] [Review][Patch] No `test-summary.md` entry exists for story 5-2-metadata-filters — breaks the pattern every prior story (4.3, 4.4, 5.1) in this repo followed; this diff's `tests/test-summary.md` changes are entirely about closing out story 5.1's round-2 patch. [_bmad-output/implementation-artifacts/tests/test-summary.md]
- [x] [Review][Patch] No test exercises the ordering where a confirmed/pending item is already visible under "no active filter" and `applyFilters()` is then called while it's still outstanding, verifying it correctly drops out of view once it no longer matches the newly-applied filter — every existing "must never violate the active filter" test applies the filter first and has the item arrive afterward, never the reverse order. Code-reading confirms this is structurally safe by construction (`_loadFiltered()` fully replaces `entries`/`pendingWrites` from a fresh server-filtered page plus `_visiblePendingWrites` on every filter change, so no separate incremental path could drift) — this is a coverage gap, not a known live bug. [test/features/entries/presentation/cubit/meus_registros_cubit_test.dart]

**Defer:**
- [x] [Review][Defer] The round-2 fix for story 5.1 bundled into this same commit (`MeusRegistrosScreen.initState` arming `_searchSkeletonTimer` when `EntriesSearchCubit` is already `ResourceLoading` at remount) always starts a fresh 300ms timer regardless of how long the search has already been loading — a remount after the search has been loading well past the threshold still waits up to another full 300ms before showing the skeleton. [lib/features/entries/presentation/screens/meus_registros_screen.dart:96-105] — deferred: a complete fix needs `EntriesSearchCubit` (story 5.1, already `done`) to expose a `loadingStartedAt` timestamp, which is out of this story's own scope; the consequence is a sub-300ms cosmetic delay in an already-narrow remount-while-loading scenario, not a correctness issue.

**Reject (noise, dropped — round 2):** `EntriesFilterSheet`'s "Aplicar" always re-triggers `_loadFiltered()`'s network round-trip even when the pending selection is unchanged from what's already active — correct result either way, no AC requires short-circuiting it, and adding one would be unrequested scope; a large fraction of this diff's test-file hunks are pure dart-format reflow of pre-existing tests with no behavioral change mixed into the functional diff — a review-process observation, not a code defect; `hasActiveFilters`/`activeSource`/etc. being plain getters on the cubit rather than carried on `MeusRegistrosState` means `EntriesSearchBar` rebuilds on every unrelated `MeusRegistrosCubit` emission (e.g. each `loadMore()` page) — real but purely a rebuild-efficiency nitpick on a cheap, pure `StatelessWidget`, with no visible or correctness impact.

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
