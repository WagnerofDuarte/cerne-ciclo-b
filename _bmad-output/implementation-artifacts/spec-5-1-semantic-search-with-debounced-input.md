---
title: 'Semantic Search with Debounced Input'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '6f6a672b3a7aa50b5b65f839796586ed2b490122'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Meus Registros has no way to find an Entry by meaning — a user who phrased a thought differently than how they search for it today finds nothing, and there is no search surface on the screen at all yet.

**Approach:** Add a permanently-docked search bar to Meus Registros, backed by a new `EntriesSearchCubit` (first real `Resource<T>` consumer) that debounces input 300ms and calls a new `EntriesRepository.search()` method against `entries-search`; an empty query reverts to the normal timeline, and offline resolves immediately to `Failure.networkOffline` with no cache fallback.

## Boundaries & Constraints

**Always:**
- `EntriesRepository.search(String query)` → `Either<Failure, List<Entry>>`. `EntriesRemoteDataSource.search()` calls `ApiClient.get('entries-search', queryParameters: {'q': query})` (no `limit`/`cursor`), decodes `json['data']` with existing `EntryDto.fromJson`; extra `similarity`/`mode` fields are never read, same as other superset fields `_toEntry` already drops.
- `search()` is only called with a non-empty, pre-trimmed query — the cubit owns that guarantee, never the repository.
- On success, persist via `_toEntry`'s "persist then return" (`putAll`, mirrors `list()`). On any `Failure`, return `Left` unmapped — no cache fallback (AD-9: no client-side vector index).
- New `EntriesSearchCubit extends Cubit<Resource<List<Entry>>>`, starts `ResourceIdle()`. `onQueryChanged(raw)`: cancel pending debounce `Timer`; empty-after-trim → emit `ResourceIdle()`, no request; else restart a 300ms `Timer` → `ResourceLoading()` → `search()`. A monotonic `_generation` counter (mirrors `MeusRegistrosCubit._generation`) discards stale results.
- New `EntriesSearchBar` widget: paper-elevated (`colorSurfaceElevated`, `radiusMd`, `elevation1`), hint "Buscar nos registros...", trailing `Icons.filter_list` button (44pt, reuses `insertionModalTapTargetMin`) wired as a no-op this story (filters are 5.2); never submitted by a button — `onChanged` feeds `cubit.onQueryChanged` directly.
- `MeusRegistrosScreen`: dock the bar above the list; non-`ResourceIdle` search state renders search results (own 300ms skeleton threshold, mirrors `_skeletonTimer`) in place of the timeline; `ResourceIdle` shows the timeline unchanged.
- Register `EntriesSearchCubit` as `lazySingleton` (`dispose: cubit.close()`) in `entries_injection.dart`, mirrors `MeusRegistrosCubit`; add its resolution assertion to `bootstrap_integration_test.dart`.

**Ask First:** none — scope is fully pinned by `epic-5-context.md` and the ACs below.

**Never:** `source`/`dateFrom`/`dateTo` params on `search()` (5.2); a second `Entry`/DTO model; a cache fallback for search; a functional filter sheet; an update/delete method on `EntriesRepository`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Semantic match | query "ansiedade" | results include an entry only containing "nervosismo" | N/A |
| Rapid typing | 5 keystrokes within 300ms | exactly one `entries-search` call fires, for the final value | N/A |
| Query cleared | non-empty → empty/whitespace | pending timer cancelled, state → `ResourceIdle`, timeline shown, no request | N/A |
| Offline | any non-empty query, no connectivity | `ApiClient` → `Failure.networkOffline`, no cache fallback | `ResourceError(networkOffline)` rendered |
| Stale response | query A in flight, query B supersedes it | A's result discarded on arrival (generation mismatch) | N/A |
| Slow request | request exceeds 300ms | loading indicator appears | N/A — faster responses show none |

</frozen-after-approval>

## Code Map

- `entries_repository.dart` — add `search()`; fix stale "third and last method ... forever" comment (AD-11 is create+read-only, not count-capped).
- `entries_remote_data_source.dart:54-76` / `entries_repository_impl.dart:54-94` — `list()`'s try/catch + persist-then-return pattern to mirror; `search()` has no fallback branch.
- `meus_registros_cubit.dart:48-57` — `_generation` staleness-guard pattern to mirror.
- `lib/core/resource.dart` — existing `Resource<T>`; first real consumer.
- `meus_registros_screen.dart:117-153` — wire both cubits via nested `BlocBuilder`s.
- `entries_injection.dart:54-60`, `bootstrap_integration_test.dart:196-197` — DI registration + assertion patterns to mirror.
- `design_tokens.dart` — reuse `colorSurfaceElevated`, `radiusMd`, `elevation1`, `spacingMd/Lg`, `textBodyMd`, `insertionModalTapTargetMin`; no new token.

## Tasks & Acceptance

**Execution:**
- [x] `entries_repository.dart` -- add `search(String query)` to the port
- [x] `entries_remote_data_source.dart` -- add `search()` calling `entries-search`
- [x] `entries_repository_impl.dart` -- implement `search()`: persist-then-return, no fallback
- [x] `presentation/cubit/entries_search_cubit.dart` (new) -- debounce + generation guard over `Resource<List<Entry>>`
- [x] `presentation/widgets/entries_search_bar.dart` (new) -- docked input, funnel icon, no submit button
- [x] `meus_registros_screen.dart` -- dock bar; branch render on search state
- [x] `entries_injection.dart` -- register `EntriesSearchCubit` as `lazySingleton`
- [x] `bootstrap_integration_test.dart` -- assert `EntriesSearchCubit` resolves
- [x] Unit tests covering every I/O Matrix row across the new/changed files
- [x] `test/features/entries/entries_search_flow_e2e_test.dart` (new) -- happy-path + offline; new real-pipeline surface, same rationale spec-4-4 used for `getById`

**Acceptance Criteria:**
- Given a query "ansiedade", when results return, then they include an entry that only used "nervosismo" (semantic, not literal match).
- Given a user typing, when each keystroke lands, then the request is debounced 300ms — no request fires per keystroke.
- Given the search bar, when it renders, then it is permanently docked at the top of Meus Registros with a trailing funnel icon and is never submitted via a button.
- Given the user is offline, when a search is attempted, then it resolves to `Failure.networkOffline` immediately, never served from cache.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

## Suggested Review Order

**Search contract (domain + data)**

- Entry point — the new port method the rest of the feature hangs off.
  [`entries_repository.dart:72`](../../lib/features/entries/domain/repositories/entries_repository.dart#L72)

- Data-source call: `GET entries-search` with exactly `{q: query}`, no pagination.
  [`entries_remote_data_source.dart:105`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L105)

- Repository impl: persist-then-return, no offline/timeout cache fallback (AD-9).
  [`entries_repository_impl.dart:125`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L125)

- Review fix: de-dupe by id before `putAll`/return so box and list never disagree.
  [`entries_repository_impl.dart:228`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L228)

**Debounce + staleness state machine**

- `EntriesSearchCubit` — first real `Resource<T>` consumer, single-fetch shape.
  [`entries_search_cubit.dart:20`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L20)

- Debounce entry point: cancels pending timer, empty-after-trim short-circuits to idle.
  [`entries_search_cubit.dart:46`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L46)

- Generation-guarded fetch, mirrors `MeusRegistrosCubit._generation` exactly.
  [`entries_search_cubit.dart:68`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L68)

- Review fix: non-const emit, so back-to-back loading transitions always fire the listener.
  [`entries_search_cubit.dart:81`](../../lib/features/entries/presentation/cubit/entries_search_cubit.dart#L81)

**Screen/UI wiring**

- `MeusRegistrosScreen` takes a second cubit, both resolved from DI.
  [`meus_registros_screen.dart:45`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L45)

- Both cubits provided together; neither closed by this `StatefulWidget`.
  [`meus_registros_screen.dart:166`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L166)

- `ResourceIdle` falls through to the unchanged pre-existing timeline; everything else renders search.
  [`meus_registros_screen.dart:186`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L186)

- Search's own 300ms skeleton threshold (RNF01), re-armed per search, independent of the timeline's.
  [`meus_registros_screen.dart:113`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L113)

- Search-results surface: always-synchronized badges, no pending-write overlay (search results are server-confirmed only).
  [`meus_registros_screen.dart:242`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L242)

- Docked search bar: paper-elevated, no submit button, funnel icon inert this story.
  [`entries_search_bar.dart:18`](../../lib/features/entries/presentation/widgets/entries_search_bar.dart#L18)

- Review fix: accessible tooltip on the otherwise-unlabeled funnel button.
  [`entries_search_bar.dart:66`](../../lib/features/entries/presentation/widgets/entries_search_bar.dart#L66)

**DI + routing**

- `EntriesSearchCubit` registered as `lazySingleton`, mirrors `MeusRegistrosCubit`.
  [`entries_injection.dart:67`](../../lib/features/entries/entries_injection.dart#L67)

- `/meus-registros` route now resolves both cubits.
  [`app_router.dart:114`](../../lib/core/navigation/app_router.dart#L114)

**Peripherals**

- New cubit tests — every I/O Matrix row, including the two review-fix regressions.
  [`entries_search_cubit_test.dart:98`](../../test/features/entries/presentation/cubit/entries_search_cubit_test.dart#L98)

- New widget tests — hint text, no submit, no search icon, tooltip.
  [`entries_search_bar_test.dart:6`](../../test/features/entries/presentation/widgets/entries_search_bar_test.dart#L6)

- Data-source tests for the new `search()` call shape and superset decoding.
  [`entries_remote_data_source_test.dart:460`](../../test/features/entries/data/datasources/entries_remote_data_source_test.dart#L460)

- Repository tests for persist-then-return, no-fallback, and the dedupe regression.
  [`entries_repository_impl_test.dart:588`](../../test/features/entries/data/repositories/entries_repository_impl_test.dart#L588)

- Screen-level coverage: docked bar, debounce timing, clearing, offline, skeleton threshold.
  [`meus_registros_screen_test.dart:914`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L914)

- DI resolution assertion for the new singleton.
  [`bootstrap_integration_test.dart:202`](../../test/core/di/bootstrap_integration_test.dart#L202)

- New end-to-end real-pipeline coverage (happy path + offline) for `search()`.
  [`entries_search_flow_e2e_test.dart:94`](../../test/features/entries/entries_search_flow_e2e_test.dart#L94)
