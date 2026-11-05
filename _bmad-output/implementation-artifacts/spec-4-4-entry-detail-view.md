---
title: 'Story 4.4: Entry Detail View'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: 'aed0a39358f41803c1791a9d16d8a5cd11075f78'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `EntryRecordCard` has no `onTap` at all — a user cannot open a single Entry to see its full content, and `GET /entries/:id` (RF07) is wired nowhere in the app.

**Approach:** Add `EntriesRepository.getById`, a new `EntryDetailCubit`/`EntryDetailScreen` reached via a `/meus-registros/:id` route, and wire the record card's new `onTap` into it. The cubit composes auth status, the one shared sync-badge derivation, and the fetched Entry into its own sealed state — strictly read-only, no prototype precedent to match.

## Boundaries & Constraints

**Always:**
- `EntriesRepository.getById(String id)` returns `Either<Failure, Entry>` — the repository's third and last method; `create`/`list` unchanged (AD-11: create+read only, forever).
- Real call: `ApiClient.get('entries-get', pathParams: [id])`; decode with `EntryDto.fromJson` (its response is a superset, same as `create`/`list`'s DTO reuse).
- `getById` persists the fetched entry to the `entries` Hive box (`put`) before returning `Right`, same "persist then return" ordering `create`/`list` already use. On `Failure.networkOffline`/`networkTimeout` specifically, falls back to `entriesBox.get(id)` if present; a cache miss propagates the original failure unchanged (no synthesized not-found).
- `Failure.notFound` (and any other failure the cache doesn't absorb) renders one generic not-found treatment — identical whether the id never existed or belongs to another user (RNF04); never a distinguishable permission-denied state.
- New `EntryDetailCubit` (factory-registered, mirrors the capture cubits' DI shape) combines exactly three sources into its own sealed `EntryDetailState` (mirrors `MeusRegistrosState`'s shape, never `Resource<T>`): `SessionRepository.statusStream`, `PendingEntryWriteTracker` feeding the existing `deriveSyncBadgeState()` (never recomputed inline), and one `getById` fetch — merged only inside this cubit; it never imports/reaches into `MeusRegistrosCubit` or any other Cubit (AD-7).
- Screen renders content, source, local time, and a `SyncBadge` (no `onRetryTap` — a fetched Entry is always server-confirmed) — zero edit affordance anywhere on it.
- `EntryRecordCard` gains a required `onTap`; `MeusRegistrosScreen` wires it to `context.push('${AppRoutePaths.meusRegistros}/${entry.id}')`. A pending/failed placeholder's synthetic `tempId` is a valid, un-special-cased navigation target — it simply 404s into the same generic not-found treatment as any other unknown id (RNF04 already covers this).
- New `GoRoute` nested under `AppRoutePaths.meusRegistros` with a required `:id` segment; reuses the app's single `redirect` and `ExpiryOverlayHost` as-is (no new overlay, no second competing `redirect`).

**Ask First:** none — scope is fully pinned by `epic-4-context.md` and stories 4.1–4.3's established conventions.

**Never:** an update/delete method on `EntriesRepository`; a second sync-badge derivation path; a swipe/long-press gesture implying edit; a second `redirect`; a permission-denied-specific UI state.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Tap a confirmed entry, online | valid real id | Fetches and renders content + source + time + Synchronized badge | N/A |
| Tap entry, offline, already cached | id present in `entries` Hive box | Cached content renders via `getById`'s fallback | N/A |
| Tap a nonexistent id or another user's id | backend `NOT_FOUND` | Generic not-found screen | Identical for both causes (RNF04) |
| Tap a still-pending/failed placeholder card | synthetic `tempId`, unknown to backend | Same generic not-found screen | No special-casing |
| Session expires while viewing detail | `SessionRepository.statusStream` emits expired | `ExpiryOverlayHost`'s existing overlay appears over the screen, no crash | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/entries/domain/repositories/entries_repository.dart` -- add `getById(String id)` to the abstract port
- `lib/features/entries/data/datasources/entries_remote_data_source.dart` -- add `get(String id)` calling `entries-get` via `ApiClient.get(pathParams: [id])`, decoding `EntryDto` from `json['data']`
- `lib/features/entries/data/repositories/entries_repository_impl.dart:30-121` -- implement `getById`: remote call → `_entriesBox.put` → `right(_toEntry(dto))`; offline/timeout fallback reads `_entriesBox.get(id)`, mirroring `_offlineFallback()`'s malformed-cache guard
- `lib/features/entries/domain/entities/sync_badge_state.dart:92-101` -- reuse `deriveSyncBadgeState()` as-is, no changes
- `lib/features/auth/domain/repositories/session_repository.dart` -- `statusStream`/`currentStatus`, consumed read-only by the new cubit
- `lib/features/entries/domain/services/pending_entry_write_tracker.dart` -- `pendingWrites` stream, consumed read-only
- `lib/features/entries/presentation/cubit/entry_detail_cubit.dart` (new) -- `EntryDetailCubit` + sealed `EntryDetailState` (Loading/Data/NotFound/Error), takes `(EntriesRepository, PendingEntryWriteTracker, SessionRepository)`, exposes `load(String id)`
- `lib/features/entries/presentation/screens/entry_detail_screen.dart` (new) -- minimal read-only `BlocBuilder<EntryDetailCubit, EntryDetailState>` screen
- `lib/features/entries/presentation/widgets/entry_record_card.dart:43-56` -- add required `onTap`, drop the "never tappable for navigation (4.4)" doc line
- `lib/features/entries/presentation/screens/meus_registros_screen.dart` -- pass `onTap: () => context.push('${AppRoutePaths.meusRegistros}/${entry.id}')` to each card
- `lib/core/navigation/app_router.dart:26-35,71-125` -- nested `GoRoute` under `meusRegistros` with `:id`, builder wires `sl<EntryDetailCubit>()..load(state.pathParameters['id']!)`
- `lib/features/entries/entries_injection.dart` -- `sl.registerFactory<EntryDetailCubit>(...)`, deps: `sl<EntriesRepository>()`, `sl<PendingEntryWriteTracker>()`, `sl<SessionRepository>()`
- `test/features/entries/data/{datasources,repositories}/*` -- extend existing `entries_remote_data_source_test.dart`/`entries_repository_impl_test.dart` for `get`/`getById` (success, offline-cache-hit, offline-cache-miss, not-found)
- `test/features/entries/presentation/cubit/entry_detail_cubit_test.dart` (new) -- covers the matrix above
- `test/features/entries/presentation/screens/entry_detail_screen_test.dart` (new) -- renders each `EntryDetailState` variant
- `test/features/entries/presentation/widgets/entry_record_card_test.dart` -- add/update `onTap` assertion
- `test/features/entries/presentation/screens/meus_registros_screen_test.dart` -- assert card tap navigates (`context.push`)
- `test/core/navigation/app_router_test.dart` -- assert the new nested route resolves to `EntryDetailScreen`

## Tasks & Acceptance

**Execution:**
- [x] `entries_repository.dart` -- add `getById` port method
- [x] `entries_remote_data_source.dart` -- add `get(id)` calling `entries-get`
- [x] `entries_repository_impl.dart` -- implement `getById` with Hive write-through + offline-cache fallback
- [x] `entry_detail_cubit.dart` -- new cubit + sealed state, three-source composition
- [x] `entry_detail_screen.dart` -- new read-only screen
- [x] `entry_record_card.dart` -- add `onTap`
- [x] `meus_registros_screen.dart` -- wire card tap to `context.push`
- [x] `app_router.dart` -- nested `:id` route
- [x] `entries_injection.dart` -- register `EntryDetailCubit`
- [x] Tests listed in Code Map for each new/changed file above, including the full I/O matrix

**Acceptance Criteria:**
- [x] Given an Entry in the list, when I open it, then `GET /entries/:id` fetches and displays its full content with no edit affordance anywhere on the screen.
- [x] Given an Entry that doesn't exist or belongs to another user, when the detail request is made, then the UI shows the same not-found treatment either way.
- [x] Given this screen composes auth status, Sync Badge state, and Entry data, when those streams are combined, then they combine only through `EntryDetailCubit` — no BLoC in this feature imports another BLoC directly.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

**Manual checks (if no CLI):**
- Tap a confirmed entry's card in Meus Registros: detail screen shows its content and a Synchronized badge, no edit UI. Tap back; tap a never-existing id directly (e.g. via a temporarily hand-edited route) and confirm the generic not-found screen.

## Suggested Review Order

**Domain + data — `getById`, the repository's third and last method**

- Entry point — the new port method, read+create only forever (AD-11).
  [`entries_repository.dart:56`](../../lib/features/entries/domain/repositories/entries_repository.dart#L56)

- Real network call — `entries-get` with `id` as the one path param.
  [`entries_remote_data_source.dart:84`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L84)

- Persist-then-return + offline/timeout cache fallback, scoped to those two failures only.
  [`entries_repository_impl.dart:97`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L97)

- Cache-hit/miss fallback — round-1 review fix: box read now inside the same try/catch (RNF09).
  [`entries_repository_impl.dart:133`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L133)

**Presentation — the three-source composition (AD-7)**

- `EntryDetailCubit` — merges `SessionRepository`, the tracker, and one fetch into its own state.
  [`entry_detail_cubit.dart:31`](../../lib/features/entries/presentation/cubit/entry_detail_cubit.dart#L31)

- `load()` — maps `NotFound` vs. every other failure, guards stale/closed results.
  [`entry_detail_cubit.dart:74`](../../lib/features/entries/presentation/cubit/entry_detail_cubit.dart#L74)

- Sealed state shape mirroring `MeusRegistrosState`, never `Resource<T>`.
  [`entry_detail_state.dart:10`](../../lib/features/entries/presentation/cubit/entry_detail_state.dart#L10)

**Screen — strictly read-only (Acceptance Criteria)**

- `EntryDetailScreen` — owns cubit disposal, switches on each state variant.
  [`entry_detail_screen.dart:26`](../../lib/features/entries/presentation/screens/entry_detail_screen.dart#L26)

- Content render — no edit affordance, `SyncBadge` with no `onRetryTap`.
  [`entry_detail_screen.dart:96`](../../lib/features/entries/presentation/screens/entry_detail_screen.dart#L96)

- RNF04 — `NotFound` and every other failure render the identical generic treatment.
  [`entry_detail_screen.dart:151`](../../lib/features/entries/presentation/screens/entry_detail_screen.dart#L151)

**Navigation wiring — card tap to detail route**

- `EntryRecordCard.onTap` — round-1 review fix: tap target now covers the whole card, spine included.
  [`entry_record_card.dart:104`](../../lib/features/entries/presentation/widgets/entry_record_card.dart#L104)

- `MeusRegistrosScreen` wires the tap — round-1 review fix: id is now URL-encoded.
  [`meus_registros_screen.dart:118`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L118)

- Nested `:id` route under the existing `meusRegistros` `GoRoute` — no new redirect/overlay.
  [`app_router.dart:131`](../../lib/core/navigation/app_router.dart#L131)

- `EntryDetailCubit` DI registration — a `factory`, unlike `MeusRegistrosCubit`'s `lazySingleton`.
  [`entries_injection.dart:67`](../../lib/features/entries/entries_injection.dart#L67)

**Peripherals — tests**

- Full `getById`/`EntryDetailCubit` I/O matrix — success, notFound, cache fallback, stale-guard (both halves after round-1 fix).
  [`entry_detail_cubit_test.dart:1`](../../test/features/entries/presentation/cubit/entry_detail_cubit_test.dart#L1)

- Each `EntryDetailState` variant rendered, including the shared not-found treatment.
  [`entry_detail_screen_test.dart:1`](../../test/features/entries/presentation/screens/entry_detail_screen_test.dart#L1)

- Round-1 review fix — the real DI chain (including `SessionRepository`) is now actually resolved, not just registered.
  [`bootstrap_integration_test.dart:195`](../../test/core/di/bootstrap_integration_test.dart#L195)
