import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/resource.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../../../dashboard/domain/entities/dashboard_aggregate.dart';
import '../../../dashboard/presentation/cubit/dashboard_cubit.dart';
import '../../../dashboard/presentation/cubit/dashboard_narrative_cubit.dart';
import '../../../dashboard/presentation/widgets/dashboard_chart_section.dart';
import '../cubit/account_settings_cubit.dart';

/// Tela 6 — Configurações, Story 2.4's real build (Acceptance Criteria:
/// "shows only the biometric toggle — minimal, Epic 8 extends it, never
/// rebuilds it") extended by spec-8-1 with the "Sua evolução" chart
/// section below the toggle, and by spec-8-2 with its independent AI
/// narrative fetch. Replaces the former `ConfiguracoesPlaceholderScreen`.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    required this.cubit,
    required this.dashboardCubit,
    required this.narrativeCubit,
    super.key,
  });

  final AccountSettingsCubit cubit;

  /// spec-8-1 — the "Sua evolução" chart section's own cubit, a DI
  /// `lazySingleton` like [cubit] (Code Map); this `StatefulWidget` never
  /// closes it either, same rationale [cubit]'s own doc already gives.
  final DashboardCubit dashboardCubit;

  /// spec-8-2 — the chart section's own independent AI narrative fetch, a
  /// second DI `lazySingleton` like [dashboardCubit] above (Boundaries:
  /// "two independent fetches fired in parallel, neither awaiting the
  /// other").
  final DashboardNarrativeCubit narrativeCubit;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Review finding: clears a leftover error from a previous visit's
    // failed toggle — this cubit is a DI singleton, so without this a
    // stale message would still be showing on an unrelated later visit.
    widget.cubit.clearStaleError();
    // Boundaries: "`AccountSettingsScreen.initState` calls
    // `dashboardCubit.load()` unconditionally... so every open is a live
    // fetch, never the singleton's stale state" (FR-09: "computed on
    // demand, never stale").
    widget.dashboardCubit.load();
    // spec-8-2 — fired alongside the call above, neither awaiting the
    // other (Boundaries: "two independent fetches fired in parallel").
    widget.narrativeCubit.load();
  }

  // Review finding: mirrors `vault_lock_screen.dart`'s own `_announce` —
  // VoiceOver (this app is iOS-only) doesn't reliably treat a live-region
  // subtree update as an announcement on its own, so a failed/reverted
  // toggle is spoken explicitly here instead.
  Future<void> _announce(String message) async {
    if (!mounted) {
      return;
    }
    await SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: widget.cubit),
        // spec-8-1 — makes `DashboardCubit` available to
        // `DashboardChartSection` below, same two-cubit convention
        // `MeusRegistrosScreen` already uses for its own `cubit`/
        // `searchCubit` pair.
        BlocProvider.value(value: widget.dashboardCubit),
        // spec-8-2 — makes `DashboardNarrativeCubit` available to
        // `DashboardChartSection`'s own narrative section, same
        // convention as `dashboardCubit` above.
        BlocProvider.value(value: widget.narrativeCubit),
      ],
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        body: Column(
          children: [
            const BackArrowHeader(title: 'Configurações'),
            // spec-8-1 — now `Expanded` + scrollable: the toggle alone
            // always fit unscrolled, but the chart section below it can
            // grow past the available height on a shorter device/larger
            // text scale (Design Notes: "decide and proceed" — neither
            // `prototype-extract.md` nor the frozen spec says whether this
            // screen scrolls).
            Expanded(
              child: SingleChildScrollView(
                padding: DesignTokens.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlocConsumer<AccountSettingsCubit, AccountSettingsState>(
                      listener: (context, state) {
                        if (state.errorMessage != null) {
                          _announce(state.errorMessage!);
                        }
                      },
                      builder: (context, state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MergeSemantics(
                              child: Semantics(
                                label: 'Entrar com biometria',
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ExcludeSemantics(
                                        child: Text(
                                          'Entrar com biometria',
                                          style: DesignTokens.textBodyLg
                                              .copyWith(
                                                color: DesignTokens
                                                    .colorTextPrimary,
                                              ),
                                        ),
                                      ),
                                    ),
                                    if (state.isSaving) ...[
                                      const SizedBox(
                                        width: DesignTokens
                                            .accountSettingsSavingIndicatorSize,
                                        height: DesignTokens
                                            .accountSettingsSavingIndicatorSize,
                                        child: CircularProgressIndicator(
                                          strokeWidth: DesignTokens
                                              .accountSettingsSavingIndicatorStrokeWidth,
                                          color: DesignTokens.colorAccent,
                                        ),
                                      ),
                                      const SizedBox(
                                        width: DesignTokens.spacingSm,
                                      ),
                                    ],
                                    Switch(
                                      value: state.biometricEnabled,
                                      // Boundaries: "no new tokens" — reuses
                                      // `colorAccent` (Design Notes).
                                      activeThumbColor:
                                          DesignTokens.colorAccent,
                                      // Review finding: `null` while a
                                      // toggle is already in flight
                                      // (`state.isSaving`) — a disabled
                                      // `Switch` can't be tapped again, so a
                                      // double-tap can never start a
                                      // second, overlapping
                                      // `toggleBiometric` call.
                                      onChanged: state.isSaving
                                          ? null
                                          : (value) => context
                                                .read<AccountSettingsCubit>()
                                                .toggleBiometric(value),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (state.errorMessage != null) ...[
                              const SizedBox(height: DesignTokens.spacingSm),
                              Text(
                                state.errorMessage!,
                                style: DesignTokens.textBodyMd.copyWith(
                                  color: DesignTokens.colorError,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    // spec-8-1 — "Sua evolução", sibling to the biometric
                    // toggle section above (Code Map: "insert chart as
                    // sibling Column child").
                    const SizedBox(height: DesignTokens.spacingXl),
                    // Review finding: unlike the biometric toggle's own
                    // `BlocConsumer` above, the chart section previously
                    // never announced its own fetch failures to
                    // VoiceOver — a `ResourceError` only ever showed as
                    // silent inline text. Reuses the same [_announce]
                    // this `State` already uses for the toggle's error,
                    // same "VoiceOver doesn't reliably treat a live-region
                    // update as an announcement on its own" rationale.
                    MultiBlocListener(
                      listeners: [
                        BlocListener<
                          DashboardCubit,
                          Resource<DashboardAggregate>
                        >(
                          listener: (context, state) {
                            if (state is ResourceError<DashboardAggregate>) {
                              _announce(state.failure.message);
                            }
                          },
                        ),
                        // Spec Change Log (spec-8-2 amendment) — the
                        // original unconditional version of this listener
                        // could speak a narrative-failed announcement for
                        // a user whose screen never shows the narrative
                        // section at all (0/1/mid-range counts), in
                        // tension with the adjacent frozen "Never: show
                        // narrative text or its error for 0/1-count
                        // states" line. Gated on `DashboardCubit`'s own
                        // *current* state — read directly via
                        // `context.read`, never merged with this
                        // `Resource<String>` into one state object (the
                        // "Never: couple the two Resources" line is
                        // unaffected) — and announces the same fixed copy
                        // the narrative section itself renders
                        // (`DashboardChartSection.narrativeUnavailableMessage`)
                        // rather than the raw, unsanitized `Failure.
                        // message`, so VoiceOver and sighted users hear/
                        // read the same wording for the same failure.
                        BlocListener<DashboardNarrativeCubit, Resource<String>>(
                          listener: (context, state) {
                            if (state is! ResourceError<String>) {
                              return;
                            }
                            final dashboardState = context
                                .read<DashboardCubit>()
                                .state;
                            if (dashboardState
                                    is ResourceData<DashboardAggregate> &&
                                dashboardState.data.totalCount > 30) {
                              _announce(
                                DashboardChartSection
                                    .narrativeUnavailableMessage,
                              );
                            }
                          },
                        ),
                      ],
                      child: const DashboardChartSection(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
