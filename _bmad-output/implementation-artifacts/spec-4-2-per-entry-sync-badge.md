---
title: 'Story 4.2: Per-Entry Sync Badge'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 2
context: []
baseline_commit: '5b3ba873db3a254e34ad44613d085dcdb0fb4f2e'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A capture write (Epic 3) is a blocking round trip with no trace on Meus Registros: a failed write vanishes silently (only the capture modal's own local error shows), and nothing on a listed card tells the user whether what they wrote is actually saved server-side.

**Approach:** Introduce one shared in-memory `PendingEntryWriteTracker` domain port that the three capture cubits and `MeusRegistrosCubit` both consume. Capture cubits route `create()` through it (optimistic pending record before the call, resolved/failed after); `MeusRegistrosCubit` overlays the tracker's live pending writes on its confirmed list. One pure derivation function (`entries/domain`) computes each card's badge from `Entry.serverRevision`/`updatedAt` plus matching pending-write status, per `docs/input/backend/sync-badge.md`. Tapping an error badge retries through the same tracker when retryable; otherwise shows inline explanation only.

## Boundaries & Constraints

**Always:**
- New port + impl `entries/domain/services/pending_entry_write_tracker.dart` (pure Dart, RNF06 — no Flutter/data import; mirrors `SessionExpiryNotifier` pattern). API: `Future<Either<Failure, Entry>> create({required String content, required EntrySource source, int? mediaDurationSeconds})` (identical contract to `EntriesRepository.create()` today — capture cubits swap the dependency, no call-site logic change); `Future<void> retry(String tempId)`; `Stream<List<PendingEntryWrite>> get pendingWrites` — replay-capable (`Stream.multi` + cached last value, mirror `SessionRepositoryImpl.statusStream`, `session_repository_impl.dart:69-89`) so a late subscriber sees current pending state immediately.
- New value class `entries/domain/entities/pending_entry_write.dart`: `{tempId, content, source, mediaDurationSeconds, startedAt, status}`, `status` = `inFlight` or `failed(Failure)`. On `create()` success: tracker drops the record; `MeusRegistrosCubit` prepends the confirmed `Entry` into its own state (existing `_dedupedById` absorbs a later duplicate from `list()`). On failure: record flips `failed`, persists only in memory until `retry()` succeeds (no queued/offline write — UX-DR30, sync-badge.md: nothing survives restart).
- `create()` first drops any existing `failed`-status record before registering the new `inFlight` one (never more than one failed record at a time). Safe because exactly one Insertion Modal exists app-wide (one factory-scoped cubit, reset on each open — UX-DR26, UX-DR36), so there is only ever one "live" capture lineage: a user retrying by tapping "Salvar" again in the same still-open modal (not via the badge) must not leave the superseded attempt's error card as a permanent orphan on Meus Registros.
- One derivation fn `deriveSyncBadgeState(Entry? entry, PendingEntryWrite? pending)` in `entries/domain/entities/sync_badge_state.dart`, pure, returns sealed `SyncBadgeState` (`synchronizing | synchronized | error(Failure)`) (AD-10) — the only place this logic lives.
- Register tracker `lazySingleton` in `entries_injection.dart` (mirrors `MeusRegistrosCubit`'s own registration); inject into `TextEntryCubit`/`AudioEntryCubit`/`PhotoEntryCubit` (`capture_injection.dart`, replacing their direct `EntriesRepository.create()` call) and into `MeusRegistrosCubit` — constructor injection only, never cubit-to-cubit (AD-7).
- `EntryRecordCard` gains a badge (dot: `colorWarningSync`/`colorSuccess`/`colorError`, `design_tokens.dart:51,54,57`) + accessible label on tap/long-focus; retry hit area uses `DesignTokens.insertionModalTapTargetMin` (`design_tokens.dart:283`), scoped to the badge's own sub-widget only — the card itself stays non-tappable-for-navigation (Story 4.4's job).
- Tap on `error` badge: if `failure.retryable` (existing getter, `lib/core/failure/failure.dart`) call `tracker.retry(tempId)`; else render inline explanation text, no tap affordance.

**Ask First:** none — scope above is complete per investigation.

**Never:** persisting pending writes; a second retry endpoint (retry replays `create()` verbatim); any screen recomputing badge state inline; `EntryRecordCard` becoming navigation-tappable.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Fresh save | Capture cubit calls `tracker.create()` | Card appears top-of-today, ochre "Synchronizing" badge, before server responds | N/A |
| Write confirmed | `create()` resolves `Right(entry)` | Pending record removed, entry prepended, badge flips green "Synchronized" | N/A |
| Write fails, retryable | `create()` resolves `Left(networkTimeout)` | Card stays, red "Synchronization error" badge | Tap calls `tracker.retry(tempId)`, re-sends same payload |
| Write fails, non-retryable | `create()` resolves `Left(validation)` | Red badge, inline explanation on tap | No network call on tap |
| App restarts mid-pending | Pending write existed, app killed | Pending card is gone (not persisted) | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/entries/domain/services/pending_entry_write_tracker.dart` -- new, port + impl
- `lib/features/entries/domain/entities/pending_entry_write.dart` -- new value class
- `lib/features/entries/domain/entities/sync_badge_state.dart` -- new sealed class + `deriveSyncBadgeState()`
- `lib/features/entries/domain/repositories/entries_repository.dart` -- `create()` signature the tracker mirrors/wraps
- `lib/features/entries/presentation/widgets/sync_badge.dart` -- new, dot + label + retry widget
- `lib/features/entries/presentation/widgets/entry_record_card.dart` -- add badge + retry callback
- `lib/features/entries/presentation/cubit/meus_registros_{state,cubit}.dart` -- merge `pendingWrites` stream with confirmed entries, retry handler
- `lib/features/entries/entries_injection.dart` -- register tracker
- `lib/features/capture/presentation/cubit/{text,audio,photo}_entry_cubit.dart` -- swap `EntriesRepository` dep for tracker
- `lib/features/capture/capture_injection.dart` -- inject tracker into the three cubit factories
- `lib/core/failure/failure.dart` -- existing `retryable` getter, reused as-is
- `lib/core/design_tokens.dart` -- existing colors/tap-target token, reused as-is
- `lib/features/auth/data/repositories/session_repository_impl.dart:69-89` -- replay-stream pattern to mirror
- `docs/input/backend/sync-badge.md`, `error-taxonomy.md` -- authoritative semantics, read-only

## Tasks & Acceptance

**Execution:**
- [x] `pending_entry_write.dart` -- new value class, hand-rolled equality (existing convention)
- [x] `sync_badge_state.dart` -- new sealed state + pure derivation fn + unit tests (all 3 states, null/non-null combos)
- [x] `pending_entry_write_tracker.dart` -- port + impl, replay-capable stream, `create()`/`retry()`
- [x] `entries_injection.dart` -- register tracker `lazySingleton`
- [x] `{text,audio,photo}_entry_cubit.dart` + `capture_injection.dart` -- depend on tracker instead of `EntriesRepository`
- [x] `sync_badge.dart` -- new widget, dot + accessible label + ≥44pt retry target
- [x] `entry_record_card.dart` -- render badge, wire retry callback
- [x] `meus_registros_{state,cubit}.dart` -- subscribe to `pendingWrites`, merge/dedupe, expose retry method
- [x] Tests: tracker (create/confirm/fail/retry), derivation fn edge cases, cubit merge/dedupe + retry, widget (badge states, tap targets, non-retryable has no tap)

**Acceptance Criteria:**
- [x] Given a capture save in flight, when it's not yet confirmed, then its card shows the Synchronizing badge until the server confirms, then Synchronized.
- [x] Given a failed retryable write, when the badge is tapped, then the same write replays and the badge updates on the new result.
- [x] Given a failed non-retryable write, when the badge is tapped, then an inline explanation shows and no network call fires.
- [x] Given a failed write, when the user retries by saving again from the same still-open capture modal (not via the badge), then the superseded failed record is dropped — no duplicate ghost card remains (`pending_entry_write_tracker_test.dart`'s "spec amendment" group).

### Review Findings

- [x] [Review][Patch] `tracker.retry()` has no internal `retryable` guard — invariant enforced only in `SyncBadge`'s `onTap`; add the same check inside `PendingEntryWriteTrackerImpl.retry()` for defense-in-depth [pending_entry_write_tracker.dart:180] — fixed: `retry()` now checks `failedStatus.failure.retryable` itself before replaying.
- [x] [Review][Patch] No widget test exercises the full chain: tap a rendered error `SyncBadge` inside a real `MeusRegistrosScreen` → `MeusRegistrosCubit.retry(entry.id)`; a regression in `onRetryTap: (entry) => widget.cubit.retry(entry.id)` would ship undetected [meus_registros_screen.dart:109] — fixed: added `meus_registros_screen_test.dart`'s new "retry wiring (spec-4-2, screen-level)" group with a controllable tracker fake.
- [x] [Review][Patch] `loadFirstPage()`'s failure branch ignores `_pendingWrites` — unlike the success branch, it emits `MeusRegistrosError` unconditionally, hiding a pending/failed write's placeholder card until the next `pendingWrites` emission [meus_registros_cubit.dart:147] — fixed: the failure branch now mirrors the success branch's `_pendingWrites` overlay.
- [x] [Review][Patch] `EntryRecordCard`/`SyncBadge` built with no `key:` in the per-day `for` loop — when list order changes (placeholder → confirmed entry swap), Flutter can reuse `SyncBadge`'s local `_explanationExpanded` state across a different card at the same position [meus_registros_screen.dart:277] — fixed: added `key: ValueKey(entry.id)`.
- [x] [Review][Patch] `_displayEntries` prepends `pendingWrites` oldest-first among themselves, inverted relative to the newest-first convention `groupEntriesByDate` documents its callers must follow; with 2+ concurrent pending writes the older one renders above the newer one [meus_registros_state.dart:980] — fixed: iterates `pendingWrites.reversed`.
- [x] [Review][Patch] `_dedupedById` mutates the caller-supplied `seenIds` set in place when one is passed — harmless today (the one caller discards it afterward) but an undocumented side effect [meus_registros_cubit.dart:259] — fixed: now builds a local copy (`{...?seenIds}`) instead of reusing the caller's set.
- [x] [Review][Defer] `create()` drops *any* existing failed pending write regardless of lineage (not scoped to the same modal session), silently discarding an unrelated previously-failed write's content with no replay possible — deferred, pre-existing: this is the literal rule the Spec Change Log above already added deliberately in round 1 ("create() drops any existing failed record before registering a new inFlight one"), but that entry's own rationale talks only about the same still-open modal retrying; the shipped rule is broader. Worth revisiting if product wants lineage-scoped dropping instead, but that's a spec renegotiation, not a code fix. [pending_entry_write_tracker.dart:156-158]

## Spec Change Log

- **Triggered by:** code-review round 1, blind-hunter layer — "Capture-modal retry orphans the original failed pending write instead of replacing it": the frozen contract gave `create()` an identical signature to `EntriesRepository.create()` with no way for a caller to learn or supersede its own prior `tempId`, so retrying from the still-open modal (not via the badge) left the old failed record as a permanent duplicate ghost card — unbounded, since nothing else ever cleans up an abandoned failed write either.
  **Amended:** added a bullet to Boundaries & Constraints: `create()` drops any existing `failed` record before registering a new `inFlight` one.
  **Known-bad state avoided:** permanent duplicate error cards accumulating on Meus Registros every time a user retries a failed capture from the same modal.
  **KEEP:** `create()`'s external signature/contract is unchanged — this is purely new internal tracker behavior, not a capture-cubit call-site change; the rest of the frozen Boundaries/Code Map stand as written.

## Design Notes

The tracker, not `MeusRegistrosCubit`, owns reconciliation: it is the single `create()`/`retry()` entry point for all three capture cubits, so "in flight" / "failed" per-write state exists in exactly one place regardless of which screen is open when it resolves (AD-10's single-derivation-function intent applied one layer below the function itself).

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

**Manual checks (if no CLI):**
- Trigger a save with the device offline: card appears Synchronizing then flips to error with a working retry once back online.

## Suggested Review Order

**Pending-write tracker — the new domain port everything else hangs on**

- Entry point — `create()`'s identical-to-`EntriesRepository` contract, now also clearing a superseded `failed` record first (review-round fix).
  [`pending_entry_write_tracker.dart:142`](../../lib/features/entries/domain/services/pending_entry_write_tracker.dart#L142)

- The one-at-a-time-failed-record invariant itself — the actual fix for the ghost-card intent gap.
  [`pending_entry_write_tracker.dart:156`](../../lib/features/entries/domain/services/pending_entry_write_tracker.dart#L156)

- `retry()` — replays the exact same payload, no second endpoint.
  [`pending_entry_write_tracker.dart:180`](../../lib/features/entries/domain/services/pending_entry_write_tracker.dart#L180)

- `_resolve()` — success/failure reconciliation, now emitting `confirmedWrites` as `(tempId, entry)` so the cubit can drop its own placeholder atomically (review-round fix for the duplicate-card race).
  [`pending_entry_write_tracker.dart:206`](../../lib/features/entries/domain/services/pending_entry_write_tracker.dart#L206)

- `pendingWrites` — replay-capable via `Stream.multi`, mirrors `SessionRepositoryImpl.statusStream`.
  [`pending_entry_write_tracker.dart:112`](../../lib/features/entries/domain/services/pending_entry_write_tracker.dart#L112)

**Badge derivation and UI — AD-10's single source of truth**

- `deriveSyncBadgeState()` — the one pure function every badge-rendering screen must consume.
  [`sync_badge_state.dart:92`](../../lib/features/entries/domain/entities/sync_badge_state.dart#L92)

- `SyncBadge` — retryable error taps call back, non-retryable toggles inline explanation instead.
  [`sync_badge.dart:117`](../../lib/features/entries/presentation/widgets/sync_badge.dart#L117)

- `EntryRecordCard` — badge wired in; card itself still has no `InkWell` of its own (4.4's job).
  [`entry_record_card.dart:120`](../../lib/features/entries/presentation/widgets/entry_record_card.dart#L120)

**`MeusRegistrosCubit`/`State` — overlaying pending writes on the confirmed list**

- `_onEntryConfirmed` — prepends the real `Entry` and drops its matching placeholder in one emission.
  [`meus_registros_cubit.dart:84`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L84)

- `_onPendingWritesChanged` — overlays pending writes onto `Loaded`/`Empty`/`Error` alike (review-round fix: `Error` previously dropped this silently).
  [`meus_registros_cubit.dart:59`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L59)

- `loadFirstPage()` — cursor forced `null` on an empty page unconditionally, independent of any pending overlay (review-round fix, keeps 4.1's degenerate-cursor guard intact).
  [`meus_registros_cubit.dart:136`](../../lib/features/entries/presentation/cubit/meus_registros_cubit.dart#L136)

- `badgeFor()` — the one call site translating cubit state into `deriveSyncBadgeState()` input.
  [`meus_registros_state.dart:113`](../../lib/features/entries/presentation/cubit/meus_registros_state.dart#L113)

**Wiring — capture feature now depends on the tracker, not the repository directly**

- `TextEntryCubit.save()` (and its audio/photo siblings) — same call shape, new dependency.
  [`text_entry_cubit.dart:132`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L132)

- DI registration, including the review-round disposal fix.
  [`entries_injection.dart:43`](../../lib/features/entries/entries_injection.dart#L43)

**Peripherals**

- Accessibility fix — `ExcludeSemantics` + `container: true` so the badge's label announces exactly once.
  [`sync_badge.dart:1`](../../lib/features/entries/presentation/widgets/sync_badge.dart#L1)
