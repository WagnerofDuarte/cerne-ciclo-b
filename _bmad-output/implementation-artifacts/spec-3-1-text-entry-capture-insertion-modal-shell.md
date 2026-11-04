---
title: 'Story 3.1: Text Entry Capture & Insertion Modal Shell'
type: 'feature'
created: '2026-11-04'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '12cdeaa93f773d1e68061196f04bb89627cdc849'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** There is no way to capture a journal Entry yet — `features/entries/` and `features/capture/` are empty scaffolds, and the Home/Chat screen has no "+" entry point.

**Approach:** Stand up `features/entries/` (Entry entity, `EntriesRepository.create` port, entries Hive box) and `features/capture/` (Insertion Modal bottom sheet with 3 tabs), and add a minimal "+" control to the Home/Chat placeholder that opens it. Only the Texto tab is functional this story.

## Boundaries & Constraints

**Always:**
- `features/entries/domain` owns `Entry` (plain class, no freezed — mirrors `AuthenticatedUser`), `EntrySource` enum (`manual`/`audio`/`photo`/`chat`), and `EntriesRepository` (abstract, one method: `create`). `features/capture/` imports only `entries/domain`, never `entries/data` or `entries/presentation` (RNF06).
- `EntriesRepository.create` → `Either<Failure, Entry>`, posts to `entries-create` via the shared `ApiClient.post`, source=`manual` for this story. On success, write the entry through to the `entries` Hive box (`Box<Map>`, keyed by id) — first use of `hive_ce` in the app.
- Insertion Modal: `showModalBottomSheet(isScrollControlled: true, barrierColor: DesignTokens.colorScrimHeavy)`, `radiusLg` top corners, `elevation2`, new `DesignTokens.durationSheetUp` (200ms) entrance, skipped under Reduce Motion. 3 equal-width tabs (Texto/Áudio/Foto); only the active tab fills `colorPrimary`. Close "x" always present. Opens on Texto, all 3 tabs idle/empty.
- Texto tab: text field + Salvar. Salvar fires `POST /entries`; success closes the modal; failure (including offline, via the existing `Failure.networkOffline`) shows `Failure.message` inline and re-enables Salvar — no auto-retry, reuse `Failure.fromCode`/`retryable` as-is.
- "+" control on `HomeChatPlaceholderScreen`: always tappable, opens the modal. No proactive offline detection or banner in this story (deferred — see Spec Change Log / `deferred-work.md`); an offline save attempt surfaces the same way any other failed save does.
- 44pt tap targets, Dynamic Type with no truncation, announced labels for every state change (no color-only signal).

**Ask First:** none identified.

**Never:**
- Implement Áudio/Foto tab capture logic (render idle/empty only — Stories 3.2/3.3).
- Implement the full cross-tab cancel-safety rule (Story 3.4) — this story only needs the trivial case: the text tab never calls `create` except on explicit Salvar.
- Build the full chat composer (text field + send icon) — RF04's scope. Add only the "+" tap target.
- Add a connectivity service, offline banner, or any proactive offline-disabling of "+" — deferred (see `deferred-work.md`); no existing pattern to reuse, and the prototype doesn't represent this state.
- Add `GET /entries`, listing, search, or any `Entry` fields beyond `{id, content, source, chatMessageId, occurredAt, serverRevision, createdAt, updatedAt}` (tags/piiStatus/embeddingStatus belong to later epics).
- Use the shared `Resource<T>` type for capture's state — capture defines its own sealed state class.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Happy path save | Texto tab, non-empty text, tap Salvar | `POST /entries` (`source: manual`) fires; on success modal closes, returns to Home | N/A |
| Modal open resets | "+" tapped | Opens on Texto; all 3 tabs idle/empty regardless of prior session | N/A |
| Save fails (incl. offline) | Salvar tapped, backend call returns a mapped error code (e.g. `NETWORK_OFFLINE`) | Inline message from `Failure.message`; Salvar re-enabled; modal stays open | `Failure.fromCode`, no auto-retry |
| Cancel before save | "x" tapped or user leaves with unsaved text | Modal closes/resets; no `POST /entries` fires | N/A |

</frozen-after-approval>

## Code Map

- `lib/core/navigation/placeholder_screens.dart:76-130` (`HomeChatPlaceholderScreen`) — add the "+" entry point here; body is currently a pure placeholder (RF04 not built), no composer exists.
- `lib/core/design_tokens.dart:85` (`colorScrimHeavy`, already reserved for "a later story's insertion modal"), `:199` (`radiusLg`), `:218` (`elevation2`) — reuse as-is; add `durationSheetUp` near these, no `Duration`/motion token exists yet.
- `lib/core/failure/failure.dart:67-83` (`Failure.fromCode`) — reuse unchanged; already generic, no new mapping needed.
- `lib/core/network/api_client.dart:52-62` (`post`) — call via the new `EntriesRemoteDataSource`.
- `lib/core/network/header_interceptor.dart:20-24` (`anonKeyOnlyFunctions`) — `entries-create` is not in that set, so it auto-gets the user bearer token; no changes needed.
- `lib/core/di/injection_container.dart:26-84` (`setupCoreDependencies`) — add `Hive.initFlutter()` + `registerEntriesFeature()` + `registerCaptureFeature()`, after the existing `registerAccountFeature()` call.
- `lib/features/account/account_injection.dart`, `account_remote_data_source.dart`, `account_settings_dto.dart`, `account_settings_repository_impl.dart`, `account_settings_cubit.dart` — structural patterns to mirror (DI registration, `ApiClient` datasource, `@JsonSerializable` DTO, repository impl, cubit calling repository directly — no use-case layer exists in this codebase).
- `lib/features/auth/domain/entities/authenticated_user.dart` — plain-class entity pattern (no freezed) to mirror for `Entry`.
- `lib/features/entries/{data,domain,presentation}/.gitkeep`, `lib/features/capture/{data,domain,presentation}/.gitkeep` — empty scaffolds to fill.
- `docs/input/backend/api/openapi.yaml:327-449` — `entries-create` request/response schema.
- `pubspec.yaml:42-43` — `hive_ce`/`hive_ce_flutter` already a dependency, unused until now.
- `test/features/account/**` — test directory layout to mirror under `test/features/entries/` and `test/features/capture/`.

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/design_tokens.dart` -- add `durationSheetUp = Duration(milliseconds: 200)` -- no entrance-animation token exists yet (RNF08).
- [x] `lib/features/entries/domain/entities/entry.dart` (new) -- `Entry` class + `EntrySource` enum -- mirrors `AuthenticatedUser`.
- [x] `lib/features/entries/domain/repositories/entries_repository.dart` (new) -- abstract `EntriesRepository.create(...)` → `Future<Either<Failure, Entry>>` -- the port later epics extend.
- [x] `lib/features/entries/data/models/entry_dto.dart` (+ generated `.g.dart`) -- `@JsonSerializable()` mirroring the response `data` object.
- [x] `lib/features/entries/data/datasources/entries_remote_data_source.dart` (new) -- posts to `entries-create` via `ApiClient.post`, decodes `EntryDto`.
- [x] `lib/features/entries/data/repositories/entries_repository_impl.dart` (new) -- implements `create`; on success writes to the `entries` Hive box keyed by id; maps `EntryDto` → `Entry`.
- [x] `lib/features/entries/entries_injection.dart` (new) -- registers datasource/repository, opens/registers the `entries` Hive box.
- [x] `lib/core/di/injection_container.dart` -- wire `Hive.initFlutter()` + `registerEntriesFeature()` + `registerCaptureFeature()`.
- [x] `lib/features/capture/presentation/cubit/text_entry_cubit.dart` (new) -- own sealed state (active tab, text, saving/error); calls `EntriesRepository.create` directly on Salvar.
- [x] `lib/features/capture/presentation/widgets/insertion_modal.dart` (new) -- 3-tab bottom sheet; Texto functional, Áudio/Foto idle placeholders.
- [x] `lib/features/capture/capture_injection.dart` (new) -- registers `TextEntryCubit`.
- [x] `lib/core/navigation/placeholder_screens.dart` -- add the always-tappable "+" control to `HomeChatPlaceholderScreen` that opens `InsertionModal`.
- [x] Unit/widget tests under `test/features/entries/`, `test/features/capture/` covering the I/O matrix above.

**Acceptance Criteria:**
- Given `features/entries/` doesn't exist yet, when this story is built, then `entries/domain` owns `Entry` + `EntriesRepository(create)` + the entries Hive box, and `features/capture/` never imports `entries/data` or `entries/presentation`.
- Given the "+" control, when tapped, then the Insertion Modal opens with the `sheetUp` entrance (skipped under Reduce Motion).
- Given any state change this story introduces, when a screen reader is active, then an announced label accompanies it — never color/animation alone.
- Given `fvm flutter analyze` and `fvm flutter test`, then both report zero issues / all green.

## Spec Change Log

- 2026-11-04 — Token-count checkpoint (step-02): spec exceeded 1600 tokens (~2676) because it bundled a proactive offline-detection/banner pattern that doesn't exist anywhere in the app yet. Human chose [S] Split: carved the connectivity/banner work out to `deferred-work.md` and narrowed this story's "+" control to always-tappable, with offline failures surfacing through the existing reactive `Failure.networkOffline` path. KEEP: the `entries`/`capture` feature stand-up, Hive write-through, and modal-shell scope are otherwise unchanged from the original investigation.

## Design Notes

- **Hive storage shape:** entries are cached as raw `Map<String, dynamic>` (via `EntryDto.toJson()`), not a generated `HiveObject`/`TypeAdapter` — avoids adapter codegen for a box nothing reads yet (reads start in Epic 4); revisit if a future story needs typed queries.
- **No use-case layer:** `TextEntryCubit` calls `EntriesRepository.create` directly, matching this codebase's existing convention (`AccountSettingsCubit`, `AuthCubit`) — RF10's reuse requirement is satisfied by the port itself, not an extra use-case class.
- **"+" is minimal:** a single tappable control, not the RF04 composer bar — avoids building chat-input UI that RF04 will define and may not match.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves with no conflicts.
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- generates `entry_dto.g.dart` with no errors.
- `fvm flutter analyze` -- zero issues.
- `fvm flutter test` -- all green, including new tests under `test/features/entries/`, `test/features/capture/`.

## Suggested Review Order

**Entries domain & port**

- The one-method port every later epic (Search, Timeline, RF10) extends — its shape is this story's main architectural bet.
  [`entries_repository.dart:17`](../../lib/features/entries/domain/repositories/entries_repository.dart#L17)

- Plain entity, 8 fields only, no `freezed` (mirrors `AuthenticatedUser`) — deliberately not speculative beyond what the API returns.
  [`entry.dart:20`](../../lib/features/entries/domain/entities/entry.dart#L20)

- The 4-value `source` enum the port and DTO both key off of.
  [`entry.dart:6`](../../lib/features/entries/domain/entities/entry.dart#L6)

**Entries data layer**

- `create()` posts to `entries-create`, decodes `EntryDto`, maps parse failures to `malformedResponse`.
  [`entries_remote_data_source.dart:20`](../../lib/features/entries/data/datasources/entries_remote_data_source.dart#L20)

- Write-through cache: persists to the `entries` Hive box *before* returning `Right` — the ordering that matters.
  [`entries_repository_impl.dart:43`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L43)

- `EntriesRepositoryImpl.create` — full success/failure mapping, including the Hive-write-failure branch.
  [`entries_repository_impl.dart:30`](../../lib/features/entries/data/repositories/entries_repository_impl.dart#L30)

- `@JsonSerializable` DTO — the wire/cache shape; enum round-trips via `.name`.
  [`entry_dto.dart:19`](../../lib/features/entries/data/models/entry_dto.dart#L19)

- First `hive_ce` box in the app — raw `Box<Map>`, opened before DI registers on top of it.
  [`entries_injection.dart:21`](../../lib/features/entries/entries_injection.dart#L21)

**Capture state machine**

- Sealed state (Idle/Saving/Saved/Error) — deliberately not the shared `Resource<T>`.
  [`text_entry_cubit.dart:16`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L16)

- `save()` — fires `create`, maps the result, guards against emitting after `close()`.
  [`text_entry_cubit.dart:110`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L110)

- `selectTab` — review-added guard: no-ops while a save is in flight (race fix).
  [`text_entry_cubit.dart:86`](../../lib/features/capture/presentation/cubit/text_entry_cubit.dart#L86)

**Insertion Modal UI**

- `show()` — the custom `transitionAnimationController` lifecycle; read the comments, this is the trickiest code in the diff.
  [`insertion_modal.dart:33`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L33)

- `_announce` and its listener switch — the accessibility contract this story's AC requires.
  [`insertion_modal.dart:138`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L138)

- Tab bar disabled while saving — review-added fix for the stale-completion race.
  [`insertion_modal.dart:312`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L312)

- Close button disabled while saving — same race fix, UI side.
  [`insertion_modal.dart:356`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L356)

- Texto tab: frozen prototype copy + backend's `maxLength` mirrored exactly (both review-added).
  [`insertion_modal.dart:420`](../../lib/features/capture/presentation/widgets/insertion_modal.dart#L420)

**Wiring**

- `Hive.initFlutter()` ahead of `registerEntriesFeature()`/`registerCaptureFeature()` — ordering is load-bearing here.
  [`injection_container.dart:90`](../../lib/core/di/injection_container.dart#L90)

- `TextEntryCubit` registered as a **factory**, not a singleton — a fresh instance per "+" tap.
  [`capture_injection.dart:13`](../../lib/features/capture/capture_injection.dart#L13)

- The "+" entry point — deliberately a bare FAB, not RF04's composer (see Design Notes).
  [`placeholder_screens.dart:94`](../../lib/core/navigation/placeholder_screens.dart#L94)

- First `Duration`/motion token this file defines.
  [`design_tokens.dart:236`](../../lib/core/design_tokens.dart#L236)

**Tests**

- Real-box round-trip (review-added) — the only test that exercises actual `hive_ce` encoding, not a mock.
  [`entries_repository_impl_integration_test.dart`](../../test/features/entries/data/repositories/entries_repository_impl_integration_test.dart#L1)

- Announcement assertions (review-added) via the newly-extracted shared helper.
  [`intercept_announcements.dart`](../../test/support/intercept_announcements.dart#L1)

- Full I/O-matrix coverage for the modal (happy path, offline/failure, cancel, Reduce Motion, saving-disables-controls).
  [`insertion_modal_test.dart`](../../test/features/capture/presentation/widgets/insertion_modal_test.dart#L1)

- Cubit unit tests, including the save/selectTab race guard.
  [`text_entry_cubit_test.dart`](../../test/features/capture/presentation/cubit/text_entry_cubit_test.dart#L1)

- Mocked-datasource repository tests, DI resolution smoke test, and the FAB/bootstrap wiring checks.
  [`entries_repository_impl_test.dart`](../../test/features/entries/data/repositories/entries_repository_impl_test.dart#L1)
