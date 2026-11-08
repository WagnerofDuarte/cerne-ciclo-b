import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/resource.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/avatar.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../../../../core/widgets/confirmation_dialog.dart';
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
  /// spec-8-3 — the inline name field's own controller. Its text is kept
  /// in sync with `AccountSettingsState.nameDraft` only when entering edit
  /// mode (the `BlocListener` below); while editing, the field's own
  /// `onChanged` is this screen's single source for both the controller's
  /// displayed text and the cubit's `nameDraft`.
  late final TextEditingController _nameController;

  /// Review finding (code review): tracks whether the narrative-
  /// unavailable announcement has already fired for the current
  /// `totalCount > 30` streak, across `DashboardCubit.load()`'s own
  /// `ResourceLoading` emissions — `load()` always emits `ResourceLoading`
  /// before `ResourceData` (`dashboard_cubit.dart`), so comparing only
  /// against the immediately-previous emitted state (the original
  /// `listenWhen` approach) could never actually suppress a repeat
  /// announcement on a `confirmedWrites`-triggered reload: the state right
  /// before the next qualifying `ResourceData` is always `ResourceLoading`,
  /// never a qualifying `ResourceData`, so the old guard was true again
  /// every time. Reset only on an explicit `ResourceData` crossing back to
  /// `totalCount <= 30` — `ResourceLoading`/`ResourceError` emissions leave
  /// it untouched.
  bool _dashboardOverflowAnnounced = false;

  @override
  void initState() {
    super.initState();
    // Review finding: `widget.cubit` is a DI singleton that outlives this
    // `State` — if it's already mid-edit on mount (e.g. the user left
    // Configurações via the back arrow, which never calls
    // `cancelEditingName`, then reopened it), a fresh, empty controller
    // would otherwise desync from the retained `nameDraft`: the field
    // shows blank while `confirmEditingName()` would silently save the
    // old, invisible draft.
    final cubitState = widget.cubit.state;
    _nameController = TextEditingController(
      text: cubitState.isEditingName ? cubitState.nameDraft : '',
    );
    if (cubitState.isEditingName) {
      _nameController.selection = TextSelection.collapsed(
        offset: _nameController.text.length,
      );
    }
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

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// spec-8-3 — caller derives initials from the display name (Boundaries):
  /// first letter of the first word plus first letter of the last word (a
  /// single-word name yields one letter) — `Avatar` itself only renders
  /// whatever it's given, uppercased.
  ///
  /// Code-review patch: extracts each initial via `Characters.first`
  /// (Unicode grapheme-cluster aware), not `String.substring(0, 1)` —
  /// `substring` slices by UTF-16 code unit, which would split an astral-
  /// plane character (e.g. an emoji) that starts a word into an unpaired
  /// surrogate half.
  String _initialsFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '';
    }
    final first = words.first.characters.first;
    if (words.length == 1) {
      return first;
    }
    final last = words.last.characters.first;
    return '$first$last';
  }

  /// spec-8-3 — the profile header: 52dp avatar + name/email, the pencil-
  /// becomes-check inline name edit (Intent/Boundaries). Built from
  /// `AccountSettingsState` directly, same "cubit is the single source"
  /// convention the rest of this screen already follows.
  Widget _buildNameRow(BuildContext context, AccountSettingsState state) {
    final cubit = context.read<AccountSettingsCubit>();
    if (!state.isEditingName) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              state.displayName,
              style: DesignTokens.textTitleSm.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
              // Code-review patch: the backend allows a displayName up to
              // 80 characters — without this, a long name wraps to
              // multiple lines inside this `Flexible`, misaligning against
              // the fixed-size pencil icon beside it.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Semantics(
            button: true,
            label: 'Editar nome',
            excludeSemantics: true,
            child: InkWell(
              onTap: cubit.startEditingName,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: DesignTokens.insertionModalTapTargetMin,
                  minHeight: DesignTokens.insertionModalTapTargetMin,
                ),
                child: const Icon(
                  Icons.edit,
                  size: DesignTokens.dialogIconSize,
                  color: DesignTokens.colorPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Boundaries: "Field + check icon in one TapRegion(onTapOutside:
    // cancelEditingName)" — a tap anywhere outside this field+icon pair
    // reverts the unconfirmed edit, no PATCH sent.
    return TapRegion(
      onTapOutside: (_) => cubit.cancelEditingName(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: AppTextField(
              controller: _nameController,
              errorText: state.nameErrorMessage,
              onChanged: cubit.updateNameDraft,
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          if (state.isSavingName)
            const SizedBox(
              width: DesignTokens.accountSettingsSavingIndicatorSize,
              height: DesignTokens.accountSettingsSavingIndicatorSize,
              child: CircularProgressIndicator(
                strokeWidth:
                    DesignTokens.accountSettingsSavingIndicatorStrokeWidth,
                color: DesignTokens.colorAccent,
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Salvar nome',
              excludeSemantics: true,
              child: InkWell(
                onTap: cubit.confirmEditingName,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: DesignTokens.insertionModalTapTargetMin,
                    minHeight: DesignTokens.insertionModalTapTargetMin,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: DesignTokens.dialogIconSize,
                    color: DesignTokens.colorPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, AccountSettingsState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Avatar(
          size: AvatarSize.large,
          initials: _initialsFor(state.displayName),
        ),
        const SizedBox(width: DesignTokens.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildNameRow(context, state),
              const SizedBox(height: DesignTokens.spacingXs),
              Text(
                state.email,
                style: DesignTokens.dashboardNarrativeTextStyle.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
                // Review finding: same overflow fix as the adjacent name
                // `Text` above — a long e-mail would otherwise wrap to
                // multiple lines and misalign this row.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
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

  /// Story 8.5 — the "Apagar conta" button's own tap handler: opens the
  /// destructive-variant `ConfirmationDialog` (Boundaries). `onCancel`
  /// pops the dialog only, no network call; `onConfirm` pops the dialog
  /// synchronously, then calls `AccountSettingsCubit.deleteAccount()` —
  /// same "caller pops its own dialog" convention `expiry_overlay_host.
  /// dart`'s own `onConfirm` already follows (`ConfirmationDialog`'s class
  /// doc).
  void _openDeleteAccountDialog(BuildContext context) {
    final cubit = context.read<AccountSettingsCubit>();
    ConfirmationDialog.show(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        icon: Icons.delete_outline,
        title: 'Apagar sua conta?',
        message:
            'Essa ação é permanente e não pode ser desfeita. Todos os seus '
            'dados serão apagados para sempre, conforme a LGPD.',
        confirmLabel: 'Apagar tudo',
        titleColor: DesignTokens.colorError,
        confirmButtonColor: DesignTokens.colorError,
        barrierColor: DesignTokens.colorScrimHeavy,
        cancelLabel: 'Cancelar',
        onCancel: () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
        onConfirm: () {
          if (dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
          cubit.deleteAccount();
        },
      ),
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
                    // spec-8-3 — Code Map: "header is the first scroll-
                    // Column child, above the toggle".
                    MultiBlocListener(
                      listeners: [
                        // Syncs the field's controller only at the moment
                        // editing starts — while editing, the field's own
                        // `onChanged` (-> `updateNameDraft`) is this
                        // screen's single source for both the
                        // controller's displayed text and the cubit's own
                        // `nameDraft`.
                        BlocListener<
                          AccountSettingsCubit,
                          AccountSettingsState
                        >(
                          listenWhen: (previous, current) =>
                              !previous.isEditingName && current.isEditingName,
                          listener: (context, state) {
                            _nameController.text = state.nameDraft;
                            _nameController.selection = TextSelection.collapsed(
                              offset: _nameController.text.length,
                            );
                          },
                        ),
                        // Boundaries: "`_announce` fires on a save
                        // failure, same `BlocListener` convention as the
                        // toggle's error".
                        BlocListener<
                          AccountSettingsCubit,
                          AccountSettingsState
                        >(
                          listenWhen: (previous, current) =>
                              current.nameErrorMessage != null &&
                              current.nameErrorMessage !=
                                  previous.nameErrorMessage,
                          listener: (context, state) {
                            _announce(state.nameErrorMessage!);
                          },
                        ),
                      ],
                      child:
                          BlocBuilder<
                            AccountSettingsCubit,
                            AccountSettingsState
                          >(
                            builder: (context, state) =>
                                _buildProfileHeader(context, state),
                          ),
                    ),
                    const SizedBox(height: DesignTokens.spacingXl),
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
                        // Review finding: the listener above only reads
                        // `DashboardNarrativeCubit`'s *current* state at
                        // the instant `DashboardCubit` itself transitions
                        // past 30 — but the two fetches race independently
                        // (Boundaries: "neither awaiting the other"), so
                        // the narrative can just as easily resolve to
                        // `ResourceError` *before* the aggregate ever
                        // reaches `totalCount > 30`. Without this sibling
                        // listener that ordering silently drops the
                        // announcement forever for that screen-open, even
                        // though the error text later becomes visible once
                        // the aggregate resolves — the exact VoiceOver/
                        // on-screen desync the amendment above exists to
                        // prevent. Same read-only, ungated-state check as
                        // the listener above, just triggered from the
                        // other cubit's own transition.
                        BlocListener<
                          DashboardCubit,
                          Resource<DashboardAggregate>
                        >(
                          // Review finding: without this, every later
                          // `DashboardCubit` emission with `totalCount >
                          // 30` (e.g. each further `confirmedWrites`-
                          // triggered reload) re-ran the listener and
                          // re-announced the same unchanged narrative
                          // error — not just the one missed transition
                          // this listener exists to catch. Only fires on
                          // the transition *into* `totalCount > 30`.
                          //
                          // Code-review patch: a `listenWhen` comparing
                          // only to the immediately-previous *emitted*
                          // state can't express that — `load()` always
                          // emits `ResourceLoading` first, so the state
                          // right before any reload's `ResourceData` is
                          // never itself a qualifying `ResourceData`. The
                          // "only once" tracking now lives in
                          // [_dashboardOverflowAnnounced] instead, updated
                          // only on actual `ResourceData` emissions.
                          listener: (context, state) {
                            if (state is! ResourceData<DashboardAggregate>) {
                              return;
                            }
                            if (state.data.totalCount <= 30) {
                              _dashboardOverflowAnnounced = false;
                              return;
                            }
                            if (_dashboardOverflowAnnounced) {
                              return;
                            }
                            final narrativeState = context
                                .read<DashboardNarrativeCubit>()
                                .state;
                            if (narrativeState is ResourceError<String>) {
                              _dashboardOverflowAnnounced = true;
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
                    // Story 8.4 — "Sair": the scroll column's last child,
                    // below DashboardChartSection (Code Map). No new
                    // navigation code — the existing app_router.dart
                    // redirect (already watching both the vault and
                    // session streams) takes the user to Biometria once
                    // VaultRepository.lock() relocks the vault.
                    const SizedBox(height: DesignTokens.spacingXl),
                    BlocBuilder<AccountSettingsCubit, AccountSettingsState>(
                      builder: (context, state) => AppButton(
                        label: 'Sair',
                        variant: AppButtonVariant.secondaryOutline,
                        onPressed: state.isLoggingOut
                            ? null
                            : widget.cubit.logout,
                      ),
                    ),
                    // Story 8.5 — "Apagar conta": the scroll column's last
                    // child, after "Sair" (Code Map,
                    // prototype-extract.md:116).
                    const SizedBox(height: DesignTokens.spacingXl),
                    BlocConsumer<AccountSettingsCubit, AccountSettingsState>(
                      listener: (context, state) {
                        if (state.deleteAccountErrorMessage != null) {
                          _announce(state.deleteAccountErrorMessage!);
                        }
                      },
                      builder: (context, state) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppButton(
                              label: 'Apagar conta',
                              variant: AppButtonVariant.textGhost,
                              textColor: DesignTokens.colorError,
                              onPressed: state.isDeletingAccount
                                  ? null
                                  : () => _openDeleteAccountDialog(context),
                            ),
                            if (state.deleteAccountErrorMessage != null) ...[
                              const SizedBox(height: DesignTokens.spacingSm),
                              Text(
                                state.deleteAccountErrorMessage!,
                                style: DesignTokens.textBodyMd.copyWith(
                                  color: DesignTokens.colorError,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
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
