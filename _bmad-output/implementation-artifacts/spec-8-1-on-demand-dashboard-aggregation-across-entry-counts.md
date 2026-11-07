---
title: 'Story 8.1: On-Demand Dashboard Aggregation Across Entry Counts'
type: 'feature'
created: '2026-11-07'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: '5b2f627c5708aeb1689133fb5b4ff9b87e0f2bdf'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Configurações has no evolution chart yet; FR-09's "computed on demand, never stale" isn't met by anything in the codebase.

**Approach:** New `dashboard` feature (already scaffolded empty) fetches `GET /dashboard/aggregate` fresh on every Configurações open, and a new chart section renders one of several states by total entry count: 0 → placeholder, 1 → single bar, >30 → condensed to 10 bars. The narrative paragraph is out of scope (Story 8.2).

## Boundaries & Constraints

**Always:**
- Call `dashboard-aggregate-get` with `queryParameters: {'period': 'all'}` — fixed; no period selector exists anywhere in the product.
- `DashboardCubit` is a `registerLazySingleton` that constructor-subscribes to `PendingEntryWriteTracker.confirmedWrites`, recomputing on each event (entry created on another tab while this one stays mounted).
- `AccountSettingsScreen.initState` calls `dashboardCubit.load()` unconditionally (beside the existing `clearStaleError()`) so every open is a live fetch, never the singleton's stale state.
- States by `totals.count`: `0` → icon + "Comece a registrar para ver sua evolução aqui"; `1` → 1 bar + "Ainda é cedo pra ver um padrão..."; `>30` → `bucketCounts` left-padded with leading zeros to length 10 (when shorter) *before* condensing to exactly 10 bars via 10 contiguous index chunks, summed `count`, remainder in the last chunk, no text; `2..30` → one bar per bucket as-is, no text (matrix gap, resolved per AGENTS.md's "decide and proceed"). Bar height ∝ count / max count shown.
- `DashboardAggregateDto` mirrors the full contract (`buckets[].{date,count,sources}`, `totals.{count,sources}`, same precedent as `ExportJobStatusDto`); domain `DashboardAggregate` exposes only `totalCount`/`bucketCounts`.
- New visual tokens live only in `design_tokens.dart`, values read off `cerne-prototype.html`'s dashboard markup, reusing existing color/radius/elevation/spacing tokens wherever a pixel value already matches.

**Ask First:** None. **Never:** render the AI narrative, a period selector, or cache the aggregate (AD-15 exclusion).

## I/O & Edge-Case Matrix

| Scenario | Input | Expected Output |
|----------|-------|------------------|
| Zero entries | `count == 0` | Icon + "Comece a registrar..." |
| One entry | `count == 1` | 1 bar + "Ainda é cedo..." |
| >30 entries | `count > 30`, any `buckets.length` | Exactly 10 condensed bars, no text |
| Mid-range | `1 < count <= 30` | One bar per bucket, no text |
| Fetch fails | `Left(Failure)` | `ResourceError`, inline error text, no crash |

</frozen-after-approval>

## Code Map

- `lib/features/dashboard/{data,domain,presentation}/` -- empty scaffold; all files below are new
- `lib/core/resource.dart:10-32` -- `Resource<T>`, `DashboardCubit`'s state type
- `entries_search_cubit.dart:20-21,140-170` -- emit/generation-guard template
- `pending_entry_write_tracker.dart:80` (`confirmedWrites`) + `meus_registros_cubit.dart:29-32` (subscription template)
- `export_remote_data_source.dart:27-63` + `api_client.dart:43-52` -- decode-to-`malformedResponse` + `.get(function, queryParameters:)` template
- `export_job_status_dto.dart:1-35` -- `@JsonSerializable()` DTO convention
- `export_injection.dart:18-34` -- DI template; register in `injection_container.dart` (~line 102)
- `account_settings_screen.dart:22-30,48-138` -- insert chart as sibling `Column` child; add `load()` to `initState`
- `app_router.dart:135-138` -- pass `sl<DashboardCubit>()`, mirroring `MeusRegistrosScreen` (113-116)
- `design_tokens.dart:116-122,201-232` -- reuse existing color/radius/elevation tokens; append `// --- Dashboard (spec-8-1) ---` tokens (bar area height 100, bar radius 4, empty gap 10, card padding 20, icon size 28 — from `cerne-prototype.html`)
- `openapi.yaml:1582-1688` -- `GET /dashboard/aggregate` contract (frozen)

## Tasks & Acceptance

**Execution:**
- [x] `domain/entities/dashboard_aggregate.dart` -- `DashboardAggregate{totalCount, bucketCounts}` -- RNF06
- [x] `domain/repositories/dashboard_repository.dart` -- `getAggregate({required period})`
- [x] `data/models/dashboard_aggregate_dto.dart` (+ `.g.dart`) -- full-contract DTOs + `toDomain()`
- [x] `data/datasources/dashboard_remote_data_source.dart` -- `getAggregate` via `ApiClient.get('dashboard-aggregate-get', ...)`
- [x] `data/repositories/dashboard_repository_impl.dart` -- thin pass-through, no cache
- [x] `presentation/cubit/dashboard_cubit.dart` -- `Cubit<Resource<DashboardAggregate>>`, `load()` + generation guard + `confirmedWrites` subscription
- [x] `presentation/widgets/dashboard_chart_section.dart` -- 4 count states + 10-bar condensation + loading/error
- [x] `dashboard_injection.dart` -- `registerDashboardFeature()`, wired into `injection_container.dart`
- [x] `account_settings_screen.dart` -- insert section, wire `load()` into `initState`
- [x] `app_router.dart` -- pass `sl<DashboardCubit>()`
- [x] `design_tokens.dart` -- new Dashboard token section
- [x] Tests under `test/features/dashboard/` (datasource/repository/cubit/widget) covering the I/O matrix + condensation + recompute + generation guard
- [x] Update `account_settings_screen_test.dart` for the widened constructor

**Acceptance Criteria:**
- Given Configurações opens, when the fetch resolves, then the chart reflects the live response, never a stale prior value.
- Given an entry is created elsewhere while mounted, when `confirmedWrites` fires, then the chart recomputes without leaving the screen.
- Given `totals.count > 30`, then exactly 10 bars render regardless of `buckets.length`.

## Spec Change Log

- **Finding (blind-hunter + edge-case-hunter review, confirmed):** the frozen `>30` condensation algorithm ("10 contiguous index chunks, summed count, remainder in the last chunk") degenerates when `bucketCounts.length < 10`: `chunkSize = length ~/ 10 == 0`, so the first 9 chunks each sum an empty range (0) and the 10th chunk absorbs the entire total — renders as 9 invisible bars + 1 full-height bar, defeating the chart's purpose for a plausible user (concentrated activity across fewer than 10 distinct days while exceeding 30 total entries). The shipped implementation was 100% faithful to this frozen text; the defect was in the specified algorithm itself.
- **Amendment:** added a left-pad step — `bucketCounts` is left-padded with leading zero-count entries to length 10 (only when shorter) *before* the existing chunking logic runs. `remainder in the last chunk` wording is otherwise unchanged. Routed to the human (AskUserQuestion) given the root cause sat inside `<frozen-after-approval>`; resolved in favor of a direct patch over a full revert-and-replan, per explicit human instruction to use technical judgment rather than follow the heavier protocol path.
- **Known-bad state avoided:** a `>30`-entries chart collapsing into one meaningless giant bar for any user whose entries cluster into fewer than 10 distinct backend buckets.
- **KEEP:** every other part of the shipped implementation (DI wiring, `Resource<T>`/generation-guard cubit shape, DTO/repository layering, `confirmedWrites` recompute, design tokens, test structure) is correct and must survive re-derivation untouched — only `_condense`'s input needs the left-pad step added ahead of it.

## Verification

**Commands:**
- [x] `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- expected: DTO `.g.dart` generated, no conflicts. **Satisfied**: `dashboard_aggregate_dto.g.dart` generated, 0 conflicts.
- [x] `fvm flutter analyze` -- expected: zero issues. **Satisfied**: "No issues found!".
- [x] `fvm flutter test test/features/dashboard test/features/account` -- expected: all pass. **Satisfied**, re-run after the round-2 review fixes too: `fvm flutter test test/features/dashboard test/features/account test/core/navigation test/core/di` — all passing; full-suite `fvm flutter test` — 1165/1165 passing.

**Manual checks (if no CLI):**
- Open Configurações against 0/1/>30-entry fixtures and confirm the three chart states plus the inline error state on a forced failure. Covered by `dashboard_chart_section_test.dart`'s own widget-level equivalents (0/1/2..30/30/31/>30 with both `buckets.length` >= 10 and < 10, plus the forced-failure inline error state) in lieu of a device/simulator (AGENTS.md: none exists yet).

### Round-2 review fixes (post-implementation)

- Fixed `_condense`'s degenerate small-`bucketCounts` case per the amended Boundaries line above (left-pad to length 10 before chunking) — `dashboard_chart_section.dart`'s `_pad`/`_condense`.
- Added a defensive fallback in `_populatedCard` for `totalCount > 0` with an empty `bucketCounts` (renders one bar for the whole total rather than an empty row).
- Pinned the `totalCount == 30` vs `== 31` boundary with two explicit tests.
- Added screen-reader support: `DashboardChartSection`'s empty-state icon now carries a `semanticLabel`, the bar row is wrapped in one summarizing `Semantics` label (bars themselves excluded from the semantics tree), and `AccountSettingsScreen` now announces a `ResourceError` from `DashboardCubit` via its existing `_announce`, mirroring the biometric toggle's own error announcement.
- Loading/error cards now use `DesignTokens.dashboardCardPadding` (matching the populated card) instead of `DesignTokens.spacingLg`, so the card no longer visibly resizes across a loading -> data transition.
- Added a test proving `AccountSettingsScreen.initState`'s `dashboardCubit.load()` call itself (not test code) drives the rendered result, and renamed/updated the stale "exactly one switch" test to reflect the screen now also rendering the chart section.

## Suggested Review Order

**Fetch & recompute lifecycle**

- Entry point: fixed-period live fetch, generation-guarded against stale in-flight results, re-subscribed on every entry write elsewhere in the app.
  [`dashboard_cubit.dart:25`](../../lib/features/dashboard/presentation/cubit/dashboard_cubit.dart#L25)
- `load()`'s own emit/await/generation-check sequence — the shape every count-state branch downstream depends on.
  [`dashboard_cubit.dart:47`](../../lib/features/dashboard/presentation/cubit/dashboard_cubit.dart#L47)
- Fetch triggers unconditionally on every screen mount, never serving the singleton's stale prior state.
  [`account_settings_screen.dart:48`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L48)

**Count-state rendering & the condensation fix**

- The 0/1/>30/mid-range branch point — where the frozen count matrix becomes concrete widget choices.
  [`dashboard_chart_section.dart:128`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L128)
- `_condense`: left-pads before chunking so `>30` always yields a non-degenerate 10-bar spread, even with under-10 source buckets (round-2 fix; see Spec Change Log).
  [`dashboard_chart_section.dart:223`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L223)
- `_pad`: the actual fix — left-pads with zero-count entries rather than letting floor-division produce empty chunks.
  [`dashboard_chart_section.dart:240`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L240)
- Screen-reader support for the error path, added in review: announces a `DashboardCubit` failure the same way the biometric toggle's own error already is.
  [`account_settings_screen.dart:186`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L186)

**Data flow: backend contract to domain**

- `getAggregate`: the one call site hitting `dashboard-aggregate-get` by function name, decoding to `Failure.malformedResponse` on a shape mismatch.
  [`dashboard_remote_data_source.dart:17`](../../lib/features/dashboard/data/datasources/dashboard_remote_data_source.dart#L17)
- `toDomain()`: deliberately narrows the full-contract DTO down to only what the chart consumes (`totalCount`/`bucketCounts`).
  [`dashboard_aggregate_dto.dart:87`](../../lib/features/dashboard/data/models/dashboard_aggregate_dto.dart#L87)
- Thin pass-through, no cache — the one place that would need to change if caching were ever added.
  [`dashboard_repository_impl.dart:19`](../../lib/features/dashboard/data/repositories/dashboard_repository_impl.dart#L19)
- The port `presentation`/`data` both depend on; `data` never leaks past this abstraction.
  [`dashboard_repository.dart:10`](../../lib/features/dashboard/domain/repositories/dashboard_repository.dart#L10)
- The minimal domain shape — intentionally drops every contract field the chart doesn't need.
  [`dashboard_aggregate.dart:8`](../../lib/features/dashboard/domain/entities/dashboard_aggregate.dart#L8)

**Wiring**

- DI registration order matters here: must run after the entries feature registers the shared `PendingEntryWriteTracker`.
  [`dashboard_injection.dart:15`](../../lib/features/dashboard/dashboard_injection.dart#L15)
- Call-site confirming that registration order in the real bootstrap sequence.
  [`injection_container.dart:108`](../../lib/core/di/injection_container.dart#L108)
- Route builder now resolves a second cubit alongside the existing `AccountSettingsCubit`.
  [`app_router.dart:140`](../../lib/core/navigation/app_router.dart#L140)
- New token section — every pixel value sourced from the raw prototype markup, reusing existing tokens wherever a value already matched.
  [`design_tokens.dart:768`](../../lib/core/design_tokens.dart#L768)

**Tests**

- `dashboard_cubit_test.dart` — success/error/generation-guard/`confirmedWrites`-triggered recompute.
  [`dashboard_cubit_test.dart`](../../test/features/dashboard/presentation/cubit/dashboard_cubit_test.dart)
- `dashboard_chart_section_test.dart` — every I/O-matrix row plus the round-2 boundary (30 vs 31) and small-bucket-count distribution tests.
  [`dashboard_chart_section_test.dart`](../../test/features/dashboard/presentation/widgets/dashboard_chart_section_test.dart)
- `account_settings_screen_test.dart` — the round-2 test proving `initState` itself (not test code) drives the fetch.
  [`account_settings_screen_test.dart`](../../test/features/account/presentation/screens/account_settings_screen_test.dart)
