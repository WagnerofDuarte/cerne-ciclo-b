---
title: 'Story 8.2: Independent Narrative Text & Narrative-Unavailable State'
type: 'feature'
created: '2026-11-07'
status: 'done'
review_loop_iteration: 1
context: []
baseline_commit: '6548fec2d856ea7063bb16f7e53d1745784c3eb2'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Configurações' "Sua evolução" chart (spec-8-1) never shows the AI narrative paragraph FR-39 requires alongside it, and has no distinct state for when only that narrative fails.

**Approach:** Add a second, independent fetch (`GET /dashboard/narrative`) with its own `Resource<String>` cubit. Render the resulting text below the chart only in the >30-entries state — the only scenario with a narrative in the prototype — with a dedicated "unavailable, tap to retry" message when just that fetch fails; the chart itself never degrades.

## Boundaries & Constraints

**Always:**
- Call `dashboard-narrative-get` with `queryParameters: {'period': 'all'}` — same fixed value as `dashboard-aggregate-get` (spec-8-1 precedent).
- New `DashboardNarrativeCubit extends Cubit<Resource<String>>`, mirroring `DashboardCubit`'s exact shape: `registerLazySingleton`, constructor-subscribes to `PendingEntryWriteTracker.confirmedWrites` (recompute on every entry write, same as the aggregate), `load()` is generation-guarded.
- `AccountSettingsScreen.initState` calls `narrativeCubit.load()` unconditionally, alongside the existing `dashboardCubit.load()` — two independent fetches fired in parallel, neither awaiting the other.
- `DashboardChartSection` renders the narrative section *only* inside its existing `totalCount > 30` branch — confirmed by `prototype-extract.md` (lines 110-113) and the raw prototype's `cenarioDashboard` enum (`Zero registros`/`Uma entrada`/`Mais de 30`): the AI narrative exists only in the >30 scenario; the `0`/`1`-count branches keep their current hardcoded messages untouched, never fetching or showing narrative text.
- Narrative states inside that branch: `ResourceData<String>` → the text, styled with a new `DesignTokens.dashboardNarrativeTextStyle` (Karla 400 · 13/20, read off `cerne-prototype.html`'s dashboard narrative markup — no existing token matches) + `colorTextSecondary`; `ResourceError<String>` → "Não foi possível gerar o balanço agora" in the same style, plus a tappable "tentar novamente" in `colorAccent` that re-calls `narrativeCubit.load()` (verbatim prototype copy/behavior — `cerne-prototype.html`'s `retryNarrative`); `Idle`/`Loading` → render nothing, so the chart never waits on the narrative.
- `DashboardNarrativeDto` mirrors the full contract (`text`, `generatedAt`), same "decode everything, domain narrows" precedent as `DashboardAggregateDto`; `toDomain()` returns only `text` as a plain `String` (one field — no new entity).
- `DashboardRepository`/`DashboardRemoteDataSource`/`DashboardRepositoryImpl` each gain one new method (`getNarrative`) — same files, same thin-pass-through/decode-to-`malformedResponse` shape as `getAggregate`, not a parallel class.
- `AccountSettingsScreen` announces a narrative `ResourceError` via its existing `_announce` **only when `DashboardCubit`'s own current state is `ResourceData` with `totalCount > 30`** (i.e. only when the narrative section is actually visible) — never for `0`/`1`/mid-range counts, consistent with Never below. The announced text is the same fixed `"Não foi possível gerar o balanço agora"` copy the narrative section itself renders, never the raw `Failure.message` (keeps VoiceOver and on-screen text in sync; amended, see Spec Change Log).

**Ask First:** None. **Never:** couple the two `Resource`s into one state object; show narrative text or its error for `0`/`1`-count states; call `dashboard-narrative-get` from anywhere but `DashboardNarrativeCubit.load()`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| >30 entries, narrative resolves | aggregate `>30`, narrative `Right(text)` | Chart + narrative text below it | N/A |
| >30 entries, narrative fails | aggregate `>30`, narrative `Left(Failure)` | Chart renders normally; "Não foi possível gerar o balanço agora" + "tentar novamente" | Tap re-calls `load()`, no crash |
| 0 or 1 entries | aggregate count `0`/`1` | Narrative fetch result never rendered; existing hardcoded messages unchanged | N/A |
| Narrative fetch pending | `Idle`/`Loading` | No narrative section shown | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/dashboard/domain/repositories/dashboard_repository.dart:10-22` -- add `getNarrative({required period})` beside `getAggregate`
- `lib/features/dashboard/data/datasources/dashboard_remote_data_source.dart:12-33` -- add `getNarrative`, same `.get('dashboard-narrative-get', queryParameters:)` + try/catch-to-`malformedResponse` shape as `getAggregate`
- `lib/features/dashboard/data/repositories/dashboard_repository_impl.dart:13-25` -- add thin pass-through `getNarrative`
- new `lib/features/dashboard/data/models/dashboard_narrative_dto.dart` (+ `.g.dart`) -- `@JsonSerializable()`, fields `text`/`generatedAt`, `toDomain() => text`; mirror `dashboard_aggregate_dto.dart:1-31`'s structure
- `lib/features/dashboard/presentation/cubit/dashboard_cubit.dart:25-68` -- template for new `presentation/cubit/dashboard_narrative_cubit.dart` (`Cubit<Resource<String>>`, same constructor/`load()`/generation-guard/`confirmedWrites` shape)
- `lib/features/dashboard/dashboard_injection.dart:21-45` -- register `DashboardNarrativeCubit` as a second `registerLazySingleton`, same dependencies as `DashboardCubit`
- `lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart:131-213` (`_populatedCard`) -- thread `BuildContext` in, add a narrative `BlocBuilder<DashboardNarrativeCubit, Resource<String>>` only inside the `totalCount > 30` branch
- `lib/features/account/presentation/screens/account_settings_screen.dart:17-30,45-48,65-76,183-193` -- add `narrativeCubit` constructor param, provide it, call `.load()` in `initState`, add a `BlocListener` announcing its `ResourceError`
- `lib/core/navigation/app_router.dart:135-140` -- pass `sl<DashboardNarrativeCubit>()` to `AccountSettingsScreen`
- `lib/core/design_tokens.dart:780-807` -- append `dashboardNarrativeTextStyle` (Karla 400 · 13/20) beside the other dashboard tokens
- `test/features/account/presentation/screens/account_settings_screen_test.dart:86-139` -- `_FakeDashboardRepository` needs a `getNarrative` override once the interface grows; add a `_buildNarrativeCubit` helper mirroring `_buildDashboardCubit`
- `docs/input/backend/api/openapi.yaml:1689-1736` -- `GET /dashboard/narrative` contract (frozen)
- `docs/input/prototype/prototype-extract.md:110,113` + raw `cerne-prototype.html`'s `retryNarrative`/`narrativeFailed` logic -- source of the >30-only scoping and the retry-link behavior

## Tasks & Acceptance

**Execution:**
- [x] `dashboard_repository.dart` / `dashboard_remote_data_source.dart` / `dashboard_repository_impl.dart` -- add `getNarrative` -- new backend call, same layering as `getAggregate`
- [x] `dashboard_narrative_dto.dart` (+ `.g.dart`) -- full-contract DTO + `toDomain()` -- DTO convention (RNF09)
- [x] `dashboard_narrative_cubit.dart` -- `Cubit<Resource<String>>`, `load()` + generation guard + `confirmedWrites` subscription -- mirrors `DashboardCubit`
- [x] `dashboard_injection.dart` -- register `DashboardNarrativeCubit` -- DI wiring
- [x] `dashboard_chart_section.dart` -- render narrative text/error/retry inside the `>30` branch only -- I/O matrix
- [x] `account_settings_screen.dart` + `app_router.dart` -- wire the new cubit through, `load()` on open, announce errors -- screen integration
- [x] `design_tokens.dart` -- `dashboardNarrativeTextStyle` -- AGENTS.md token rule
- [x] Tests under `test/features/dashboard/` (datasource/repository/DTO/cubit/widget) covering the I/O matrix + retry tap + `confirmedWrites` recompute
- [x] Update `account_settings_screen_test.dart`'s fake repository + helpers for the widened constructor

**Acceptance Criteria:**
- Given the aggregate shows `totalCount > 30` and the narrative fetch resolves, when the screen renders, then the narrative text appears below the chart.
- Given the aggregate shows `totalCount > 30` and the narrative fetch fails, when the screen renders, then the chart still renders normally and a distinct "narrativa indisponível" message with a working retry shows — never blank, never the 0/1-entry wording.
- Given `totalCount` is `0` or `1`, when the screen renders, then no narrative text, error, or retry ever appears, regardless of the narrative fetch's own result.

### Review Findings

- [x] [Review][Patch] Gated narrative-error VoiceOver announcement can be permanently missed for the whole screen-open when the narrative fetch errors *before* the aggregate fetch resolves to `totalCount > 30` — the amendment's gate is read once, at the narrative cubit's own error transition, and never re-checked once the aggregate later resolves, so the error becomes visible on screen with no announcement ever having fired [account_settings_screen.dart:231-247] — fixed: added a sibling `BlocListener<DashboardCubit, ...>` that re-checks the narrative cubit's current state whenever the aggregate itself crosses into `totalCount > 30`, covering the other resolution order; regression test added proving the announcement still fires when the narrative errors first.
- [x] [Review][Patch] `_narrativeSection(BuildContext context)`'s own `context` parameter is dead — the inner `BlocBuilder`/`GestureDetector.onTap` already use their own shadowed context, so the `BuildContext` threading the Code Map called for was unnecessary [dashboard_chart_section.dart:249] — fixed: removed, cascading through `_populatedCard`/`_buildBody`, which had no other use for it either.
- [x] [Review][Patch] "tentar novamente" retry link's tap target is no larger than its 13px text glyphs — no padding/minimum-size wrapper — despite this commit's own accessibility pass adding a `Semantics(button: true, ...)` role to the same link without addressing touch-target size [dashboard_chart_section.dart:285-298] — fixed: wrapped in `InkWell` + `ConstrainedBox(minHeight: DesignTokens.insertionModalTapTargetMin)`, same pattern `ChatBubble`'s own retry/bookmark affordances already use.
- [x] [Review][Patch] `heightFraction`'s `.clamp(0, 1)` guard (stops a negative malformed-backend bucket count from crashing the `Container`) has no test — a regression removing it would pass every existing test [dashboard_chart_section.dart:218] — fixed: added a mid-range test with a negative bucket count asserting `heightFraction` stays within `[0, 1]`.
- [x] [Review][Patch] The `maxCount == 0` defensive guard's own target case (a non-empty, all-zero `bucketCounts` from `_condense`) is untested — a regression reverting it to `barCounts.isEmpty` would pass every existing test [dashboard_chart_section.dart:184-187] — fixed: added a `totalCount > 30`, all-zero-`bucketCounts` test asserting exactly one full-height fallback bar.
- [x] [Review][Patch] Blank/whitespace-only narrative string rendering nothing (vs. an empty `Text`) has no test — a regression dropping the `text.trim().isEmpty` check would pass every existing narrative test [dashboard_chart_section.dart:261-262] — fixed: added a test asserting no `Text('   ')` renders.
- [x] [Review][Patch] No semantics-tree assertion proves the retry link's `Semantics(button: true, ...)` role — the only existing retry test taps via `find.text()`, so dropping the `Semantics` wrapper would pass every existing test [dashboard_chart_section.dart:285-293] — fixed: added a `find.bySemanticsLabel('tentar novamente')` assertion to the existing narrative-fails test.
- [x] [Review][Patch] Loading-state `CircularProgressIndicator`'s new `semanticsLabel` ("Carregando gráfico de evolução") has no test asserting the label itself, only `findsOneWidget` [dashboard_chart_section.dart:94] — fixed: added a `find.bySemanticsLabel(...)` assertion to the existing loading-state test.
- [x] [Review][Patch] `DashboardNarrativeCubit.load()`'s `isClosed` half of its stale-call guard is untested — the sibling `DashboardCubit` has a dedicated "close() while load() in flight never throws" test, no equivalent exists here [dashboard_narrative_cubit_test.dart] — fixed: added the equivalent test.
- [x] [Review][Patch] New e2e `DashboardNarrativeCubit` group omits the retryable-`NETWORK_TIMEOUT`-exhausts-`RetryInterceptor` case the sibling `DashboardCubit` e2e group covers for the identical transport pipeline [dashboard_flow_e2e_test.dart] — fixed: added the equivalent e2e test.
- [x] [Review][Patch] No e2e test proves `DashboardNarrativeCubit`'s `confirmedWrites` subscription reacts to the real, DI-wired `PendingEntryWriteTracker` singleton — only a hand-written-fake unit test exercises this, unlike `DashboardCubit`'s own dedicated e2e proof [dashboard_flow_e2e_test.dart] — fixed: added the equivalent e2e test, mirroring `DashboardCubit`'s own.
- [x] [Review][Patch] `test-summary.md`'s edit states "+24 difference from the prior 1175/1175 baseline" immediately after removing a line that put the prior total at 1135/1135 — a 40-test gap nothing in this diff reconciles [tests/test-summary.md] — fixed: re-ran the full suite (1206/1206 passed) and corrected the entry to reconcile against the real 1135/1135 baseline.
- [x] [Review][Defer] `DashboardNarrativeCubit`'s `confirmedWrites.listen((_) => load())` has no `onError` handler [dashboard_narrative_cubit.dart:24] — deferred, pre-existing: mirrors `DashboardCubit`'s identical, already-shipped pattern (frozen spec: "mirroring DashboardCubit's exact shape"), not a new defect introduced here.

## Spec Change Log

- **Finding (blind-hunter + verification-gap review, confirmed):** the original frozen Boundaries line ("announces a narrative `ResourceError` via its existing `_announce`, same as the chart's own error announcement") was unconditional — `narrativeCubit.load()` fires on every screen open regardless of count, so a `0`/`1`/mid-range-count user (for whom `DashboardChartSection` never renders the narrative section at all) could still hear a spoken "narrative failed" announcement for a UI element never shown to them. This also sits in tension with the adjacent frozen `Never: show narrative text or its error for 0/1-count states` line — an audio announcement is a form of showing that error. A second, smaller defect rode along: the announcement used the raw, unsanitized `Failure.message` while the on-screen narrative-unavailable text is fixed copy, so VoiceOver and sighted users received different wording for the same failure.
- **Amendment:** the `_announce` line above now gates on `DashboardCubit`'s own current state (`ResourceData` with `totalCount > 30`) before announcing a narrative error, and announces the same fixed `"Não foi possível gerar o balanço agora"` copy rather than `Failure.message`. This is a read of `DashboardCubit`'s state value from within the narrative listener, not a merge of the two `Resource`s into one state object — the existing `Never: couple the two Resources` line is unaffected.
- **Known-bad state avoided:** a user with 30 or fewer entries hearing a spoken error about a paragraph that was never on screen, and VoiceOver/sighted users hearing/reading two different error messages for the same narrative failure.
- **KEEP:** every other part of the shipped implementation (DTO, repository/datasource methods, `DashboardNarrativeCubit`'s shape, DI wiring, the `>30`-only visual scoping, the retry link's behavior, the >30-only I/O matrix, all passing tests) is correct and must survive re-derivation untouched — only the `AccountSettingsScreen` announcement's gating condition and announced text change. Routed to the human (AskUserQuestion) given the root cause sat inside `<frozen-after-approval>`; resolved in favor of a direct patch over a full revert-and-replan, per explicit human instruction to use technical judgment, consistent with the same precedent set on spec-8-1.

## Design Notes

The >30-only scoping isn't stated verbatim in `epics.md`'s AC text ("Given the chart has rendered with data") but is unambiguous once cross-referenced: `prototype-extract.md:110-113` gives the AI narrative only to "mais de 30 registros," gives "uma entrada" its own non-AI hardcoded line (already shipped verbatim in spec-8-1), and gives "zero entradas" explicitly "no summary paragraph" — and the raw prototype's `cenarioDashboard` enum itself has only three options, with `narrativeFailed` forcibly set to the `'Mais de 30'` scenario. Firing `narrativeCubit.load()` unconditionally (rather than gating the call on the aggregate's count) keeps the two fetches genuinely decoupled per Boundaries, at the cost of one harmless extra backend call for 0/1-count users whose result is simply never rendered.

## Verification

**Commands:**
- `fvm flutter pub run build_runner build --delete-conflicting-outputs` -- expected: `dashboard_narrative_dto.g.dart` generated, no conflicts
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test test/features/dashboard test/features/account` -- expected: all pass

**Manual checks (if no CLI):**
- Open Configurações against a >30-entry fixture with narrative success, narrative failure (+ retry tap), and 0/1-entry fixtures confirming no narrative UI appears — covered by widget tests in lieu of a device/simulator (AGENTS.md: none exists yet).

## Suggested Review Order

**>30-only scoping & rendering**

- Entry point — the doc comment framing why the narrative only ever renders inside the chart's existing `>30` branch.
  [`dashboard_chart_section.dart:16`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L16)
- Where the narrative section gets built — only on this one branch, `null` everywhere else.
  [`dashboard_chart_section.dart:167`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L167)
- `_narrativeSection`'s own three-state switch — Idle/Loading render nothing, Data renders text, Error renders the fixed copy + retry.
  [`dashboard_chart_section.dart:249`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L249)
- Review-round fix: a blank/empty narrative string now renders nothing rather than an unexplained blank paragraph.
  [`dashboard_chart_section.dart:261`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L261)
- Review-round fix: the "tentar novamente" retry link now has a real semantic button role, not a bare tap target.
  [`dashboard_chart_section.dart:286`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L286)
- The fixed narrative-unavailable copy, made non-private so the screen's own announcement (below) can stay in sync with it.
  [`dashboard_chart_section.dart:40`](../../lib/features/dashboard/presentation/widgets/dashboard_chart_section.dart#L40)

**Accessibility fix: gated, synced VoiceOver announcement**

- Spec Change Log amendment resolved here — announce only when the narrative is actually on screen (`totalCount > 30`), using the same fixed copy as the visual text, never the raw `Failure.message`.
  [`account_settings_screen.dart:231`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L231)
- The two independent fetches firing in parallel on screen open, neither awaiting the other.
  [`account_settings_screen.dart:59`](../../lib/features/account/presentation/screens/account_settings_screen.dart#L59)

**Independent fetch lifecycle**

- `DashboardNarrativeCubit` — same `Resource<String>`/generation-guard/`confirmedWrites` shape as `DashboardCubit`, deliberately never coupled into one state object.
  [`dashboard_narrative_cubit.dart:21`](../../lib/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart#L21)
- `load()`'s own emit/await/generation-check sequence, mirroring the aggregate cubit's own.
  [`dashboard_narrative_cubit.dart:40`](../../lib/features/dashboard/presentation/cubit/dashboard_narrative_cubit.dart#L40)

**Data flow: backend contract to domain**

- The port both `presentation` and `data` depend on — `getNarrative` as a second, independent method beside `getAggregate`.
  [`dashboard_repository.dart:31`](../../lib/features/dashboard/domain/repositories/dashboard_repository.dart#L31)
- The one call site hitting `dashboard-narrative-get` by function name, decoding to `malformedResponse` on a shape mismatch.
  [`dashboard_remote_data_source.dart:38`](../../lib/features/dashboard/data/datasources/dashboard_remote_data_source.dart#L38)
- Thin pass-through, no cache — same shape `getAggregate`'s own impl already uses.
  [`dashboard_repository_impl.dart:28`](../../lib/features/dashboard/data/repositories/dashboard_repository_impl.dart#L28)
- `DashboardNarrativeDto` — mirrors the full contract; `toDomain()` narrows to the one field the UI needs.
  [`dashboard_narrative_dto.dart:10`](../../lib/features/dashboard/data/models/dashboard_narrative_dto.dart#L10)

**Wiring**

- A second `registerLazySingleton` alongside `DashboardCubit`'s own, same dependencies and dispose lifecycle.
  [`dashboard_injection.dart:50`](../../lib/features/dashboard/dashboard_injection.dart#L50)
- Route builder now resolves a third cubit alongside the two `AccountSettingsScreen` already took.
  [`app_router.dart:142`](../../lib/core/navigation/app_router.dart#L142)
- The one new typography token, pixel-sourced from the raw prototype markup since no existing style matched.
  [`design_tokens.dart:819`](../../lib/core/design_tokens.dart#L819)

**Tests**

- `dashboard_chart_section_test.dart` — every >30-only I/O-matrix row, including the retry tap and the 0/1-count never-shows-narrative proof.
  [`dashboard_chart_section_test.dart:410`](../../test/features/dashboard/presentation/widgets/dashboard_chart_section_test.dart#L410)
- `dashboard_narrative_cubit_test.dart` — success/error/generation-guard/`confirmedWrites`-triggered recompute, same template as the aggregate cubit's own suite.
  [`dashboard_narrative_cubit_test.dart:122`](../../test/features/dashboard/presentation/cubit/dashboard_narrative_cubit_test.dart#L122)
- `account_settings_screen_test.dart` — review-round proof that the announcement fires gated and with the fixed copy, and stays silent for 0/1 counts.
  [`account_settings_screen_test.dart:472`](../../test/features/account/presentation/screens/account_settings_screen_test.dart#L472)
- `dashboard_flow_e2e_test.dart` — review-round addition: a real DI/`Dio` round trip against `dashboard-narrative-get`, not just mocked layers.
  [`dashboard_flow_e2e_test.dart:377`](../../test/features/dashboard/dashboard_flow_e2e_test.dart#L377)
- `dashboard_narrative_dto_test.dart` — decode + `toDomain()` narrowing, same convention as the aggregate DTO's own tests.
  [`dashboard_narrative_dto_test.dart:6`](../../test/features/dashboard/data/models/dashboard_narrative_dto_test.dart#L6)
