---
title: 'Story 4.1: Chronological Entry List with Origin Marking'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '8e5c168858c9ad6eb85b6b1772c7f933245ae6c3'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Entries from text/audio/photo capture (Epic 3) are invisible — "Meus Registros" is still the Epic 1 placeholder, and `EntriesRepository` only has `create`.

**Approach:** Replace the placeholder with a screen listing every Entry, newest first, grouped by day, each card marked by origin. Extend `EntriesRepository` with paginated `list()`, falling back to Hive when offline. No sync badge, no tap-to-detail, no search/filter — those are 4.2/4.4/Epic 5.

## Boundaries & Constraints

**Always:**
- `EntriesRepository.list({cursor, limit = 20})` → `Either<Failure, EntriesPage>`. Server assumed newest-first by `occurredAt` (undocumented, decided per AGENTS.md policy).
- `networkOffline`/`networkTimeout` → fall back to a full `entries` Hive box dump, sorted `occurredAt` desc, `nextCursor: null`. Other failures propagate as `Left`.
- Successful page persists to the Hive box, same "persist then return" shape `create()` uses.
- Group by `occurredAt.toLocal()` truncated to day, never `createdAt`. Grouping fn is pure Dart (no flutter import, RNF06) in `entries/domain`; day labels are presentation's job.
- Card spine by `EntrySource`, exact hex match to prototype's `sourceMeta`: manual→`colorPrimary`, audio→`colorSecondary`, photo→`colorTextSecondary`, chat→`colorAccent`. Plus source icon, time, excerpt. No badge, not tappable.
- Skeleton only past 300ms (mirror `BootSplashScreen`'s `Timer` pattern), new generic `SkeletonBox` in `lib/core/widgets/` built only from existing tokens — no new colors.
- `MeusRegistrosCubit` gets its own sealed state, never `Resource<T>` (its doc comment excludes RF07). `lazySingleton` in `registerEntriesFeature()`.
- Global `ExpiryOverlayHost` already covers this screen; just confirm this screen's `ScrollController`/cubit aren't torn down under it.

**Ask First:** None — open calls are pinned above.

**Never:** sync badge (4.2), tap/detail nav (4.4), filters/search (Epic 5, tags), pull-to-refresh, any repository method beyond `list`/`create`, polished empty-state CTA (4.3 — plain "no entries" text only).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| First load, online | Screen opens | Skeleton past 300ms, then grouped list | N/A |
| Scroll pagination | Near list end, `nextCursor != null` | Next page appended, no dup ids | Fetch failure keeps current items + inline retry |
| Offline fallback | `list()` returns offline/timeout | Cached entries shown, sorted desc | N/A |
| Other failure | e.g. `authExpired` | Error state rendered | Global overlay or inline retry |
| Zero entries | Empty page + empty cache | Plain "no entries yet" text | N/A |

</frozen-after-approval>

## Code Map

- `entries/domain/repositories/entries_repository.dart` -- add `list()` to the one-method port
- `entries/domain/entities/entry.dart` -- `occurredAt` stays raw ISO string, parsed only for grouping
- `entries/data/repositories/entries_repository_impl.dart` -- `create()`'s mirror shape for `list()`
- `entries/data/datasources/entries_remote_data_source.dart` -- `create()`'s call/error-map shape to mirror
- `entries/entries_injection.dart` -- add `MeusRegistrosCubit` registration
- `lib/core/network/api_client.dart` -- `get(function, {queryParameters})` already fits
- `lib/core/failure/failure.dart` -- `networkOffline`/`networkTimeout` = fallback triggers
- `lib/core/resource.dart` -- doc excludes RF07 from `Resource<T>`
- `app_router.dart:118-120`, `placeholder_screens.dart:159-182` -- route + placeholder
- `placeholder_screens.dart:355-397` (`_KanbanCard`) -- spine-card structure to mirror
- `placeholder_screens.dart:18-58` (`BootSplashScreen`) -- 300ms skeleton-delay pattern
- `lib/core/widgets/back_arrow_header.dart` -- reused as-is
- `openapi.yaml:480-645` -- `entries-list`: `cursor`/`limit`, `{data, meta.nextCursor}`

## Tasks & Acceptance

**Execution:**
- [x] `entries/domain/entities/entries_page.dart` -- new `EntriesPage{items, nextCursor}`
- [x] `entries/domain/entities/entry_date_group.dart` -- new `EntryDateGroup{date, entries}` + pure `groupEntriesByDate()`
- [x] `entries/domain/repositories/entries_repository.dart` -- add `list({cursor, limit = 20})`
- [x] `entries/data/datasources/entries_remote_data_source.dart` -- add `list()` via `ApiClient.get('entries-list', ...)`
- [x] `entries/data/repositories/entries_repository_impl.dart` -- implement `list()` incl. offline fallback
- [x] `lib/core/widgets/skeleton_box.dart` -- new generic shimmer, tokens-only
- [x] `entries/presentation/cubit/meus_registros_{state,cubit}.dart` -- new, `loadFirstPage()`/`loadMore()`
- [x] `entries/presentation/widgets/entry_record_card.dart` -- new, mirrors `_KanbanCard`, no tap handler
- [x] `entries/presentation/widgets/entry_skeleton_card.dart` -- new, from `SkeletonBox`
- [x] `entries/presentation/screens/meus_registros_screen.dart` -- new, scroll pagination + skeleton delay + grouped list
- [x] `entries/entries_injection.dart` -- register `MeusRegistrosCubit` as `lazySingleton`
- [x] `lib/core/navigation/app_router.dart` -- route builds `MeusRegistrosScreen(cubit: sl())`
- [x] `lib/core/navigation/placeholder_screens.dart` -- delete `MeusRegistrosPlaceholderScreen`
- [x] Tests: grouping edge cases (midnight boundary, empty), `list()` datasource/repository incl. offline, cubit, screen (skeleton timing, pagination, zero/error)

**Acceptance Criteria:**
- Given a successful load with multi-day entries, when rendered, then the list is grouped by day with each card's spine colored by `EntrySource`.
- Given offline, when the screen loads, then cached entries render with no crash or duplicates.
- Given a session expiry while visible, when the global overlay appears, then scroll position is preserved and nothing throws.

## Design Notes

Code-review clarification (not a frozen-intent change): the Boundaries' offline/timeout Hive-fallback rule and the I/O matrix's "Scroll pagination: fetch failure keeps current items + inline retry" row only fully co-exist when the fallback is scoped to `cursor == null` (the first/fresh page). `EntriesRepositoryImpl.list()` must apply `_offlineFallback()` only for that case; a paginated call (`cursor != null`) that fails with `networkOffline`/`networkTimeout` propagates as `Left` like any other pagination failure, so `MeusRegistrosCubit._fetchMore()`'s existing `loadMoreFailed`/retry path handles it uniformly — otherwise a connectivity drop mid-scroll silently merges an unrelated full-cache dump into the paginated list and breaks its newest-first ordering.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

**Manual checks (if no CLI):**
- Airplane mode with entries cached, reopen screen, confirm cached list renders instead of an error.

## Suggested Review Order

**Screen composition**

- Entry point — skeleton delay, scroll pagination, and the grouped list composed into one screen, replacing the old placeholder.
  [`meus_registros_screen.dart:29`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L29)

- Scroll listener triggers `loadMore()` a little before the real end (pre-fetch buffer).
  [`meus_registros_screen.dart:68`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L68)

- "Hoje"/"Ontem"/date formatting — presentation's own job, not the pure grouping fn's.
  [`meus_registros_screen.dart:303`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L303)

**Pagination correctness (cubit) — includes code-review round fixes**

- Sealed state, no shared `Resource<T>` — this screen's composite lifecycle doesn't fit it.
  [`meus_registros_cubit.dart:12`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L12)

- Generation counter (review fix) — discards a stale `loadFirstPage()`/`loadMore()` result that resolves after a newer call already changed state.
  [`meus_registros_cubit.dart:26`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L26)

- `_fetchMore` — dedup by id, plus the degenerate-cursor guard (review fix): zero genuinely-new items forces `nextCursor: null` so a stuck server cursor can't retrigger forever.
  [`meus_registros_cubit.dart:75`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L75)

**Offline fallback & persistence (repository)**

- `list()` — the offline/timeout Hive fallback is now scoped to `cursor == null` (review fix): a paginated continuation that fails offline propagates as `Left` instead of silently merging an unrelated cache dump.
  [`entries_repository_impl.dart:55`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L55)

- The fallback itself — full box dump sorted `occurredAt` desc, always `nextCursor: null`.
  [`entries_repository_impl.dart:102`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L102)

- Batched `putAll` (review fix) — one atomic cache write per page instead of N sequential `put()` calls.
  [`entries_repository_impl.dart:78`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L78)

- Remote call mirrors `create()`'s own `ApiClient`/error-mapping shape.
  [`entries_remote_data_source.dart:54`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L54)

- The port `list()` extends — one new method alongside the existing `create`.
  [`entries_repository.dart:38`](../../lib/features/entries/domain/repositories/entries_repository.dart#L38)

**Origin marking & grouping (domain + widgets)**

- Pure, flutter-free day-grouping (RNF06) — now skips a malformed `occurredAt` instead of throwing (review fix).
  [`entry_date_group.dart:51`](../../lib/features/entries/domain/entities/entry_date_group.dart#L51)

- Exact prototype hex-to-token spine/icon mapping per `EntrySource`.
  [`entry_record_card.dart:25`](../../lib/features/entries/presentation/widgets/entry_record_card.dart#L25)

- `_formatTime` — now returns a safe placeholder on a malformed date instead of throwing (review fix).
  [`entry_record_card.dart:120`](../../lib/features/entries/presentation/widgets/entry_record_card.dart#L120)

**Wiring**

- `MeusRegistrosCubit` registered as `lazySingleton`, long-lived across visits.
  [`entries_injection.dart:42`](../../lib/features/entries/entries_injection.dart#L42)

- `/meus-registros` now builds the real screen instead of the deleted placeholder.
  [`app_router.dart:122`](../../lib/core/navigation/app_router.dart#L122)

**Peripherals**

- New generic shimmer placeholder, built only from existing design tokens.
  [`skeleton_box.dart:16`](../../lib/core/widgets/skeleton_box.dart#L16)
