import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/failure/failure.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/entities/export_job_state.dart';
import '../cubit/export_job_cubit.dart';

/// The export bottom sheet (spec-7-1) — Tela 4's own "Export job card"
/// overlay (`cerne-prototype.html`), its 5 states (Pendente/Processando/
/// Concluído/Narrativa falhou/Período vazio) swapped in place by one
/// `BlocBuilder` over [cubit]'s own [ExportJobState] — the sheet itself
/// never closes/reopens mid-job (Boundaries); every state keeps "Fechar"
/// at the bottom (UX-DR15).
///
/// Mirrors `EntriesFilterSheet.show()`'s own choreography
/// (`isScrollControlled`, `useSafeArea`, `colorScrimHeavy`, a
/// Reduce-Motion-aware `durationSheetUp` entrance/exit) — Code Map.
/// [cubit] is a fresh, `get_it`-factory-scoped instance the caller has
/// already started (`ExportJobCubit.start()`) before ever showing this
/// sheet (Boundaries: "Create fails → inline error, sheet never opens") —
/// closed here, once the sheet is gone, mirroring `InsertionModal.
/// show()`'s own cubit-disposal convention; the caller never has to
/// remember to do this itself.
class ExportStatusSheet extends StatelessWidget {
  const ExportStatusSheet({required this.cubit, super.key});

  final ExportJobCubit cubit;

  static Future<void> show(
    BuildContext context, {
    required ExportJobCubit cubit,
  }) async {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final controller =
        BottomSheet.createAnimationController(Navigator.of(context))
          ..duration = reduceMotion
              ? Duration.zero
              : DesignTokens.durationSheetUp
          ..reverseDuration = reduceMotion ? Duration.zero : null;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        barrierColor: DesignTokens.colorScrimHeavy,
        backgroundColor: Colors.transparent,
        elevation: 0,
        transitionAnimationController: controller,
        builder: (_) => ExportStatusSheet(cubit: cubit),
      );
    } finally {
      // Same "wait for the exit animation before disposing the
      // controller" rationale as `EntriesFilterSheet.show()`'s own
      // `finally` block.
      if (!controller.isDismissed) {
        final animationDone = Completer<void>();
        void onStatusChange(AnimationStatus status) {
          if (status == AnimationStatus.dismissed) {
            animationDone.complete();
          }
        }

        controller.addStatusListener(onStatusChange);
        await animationDone.future;
        controller.removeStatusListener(onStatusChange);
      }
      controller.dispose();
      // The one-shot factory cubit's own disposal — mirrors
      // `InsertionModal.show()`'s own `await cubit.close()` convention;
      // cancels `ExportJobCubit`'s internal poll `Timer` too (its own
      // `close()` override).
      await cubit.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: DesignTokens.exportSheetPadding,
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusLg),
        ),
        boxShadow: DesignTokens.elevation2,
      ),
      child: SafeArea(
        top: false,
        child: BlocBuilder<ExportJobCubit, ExportJobState>(
          bloc: cubit,
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Review finding (blind-hunter layer) — `liveRegion: true`
                // so a screen reader announces each poll-driven stage
                // change (Pendente → Processando → Concluído/Erro) instead
                // of staying silent until the user manually re-explores
                // the sheet.
                Semantics(
                  liveRegion: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _contentFor(context, cubit, state),
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingXs),
                // Review finding (round 2) — the outer Column's own
                // `CrossAxisAlignment.stretch` stretches any direct child
                // to full width; `Center` restores "Fechar"'s previous
                // small, centered-link footprint instead of a full-width
                // button bar.
                Center(
                  child: AppButton(
                    label: 'Fechar',
                    variant: AppButtonVariant.textGhost,
                    textColor: DesignTokens.colorTextSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The spinner/text/progress-bar sequence [ExportJobGenerating] and
/// [ExportJobState.dataReady] render identically (review finding, code
/// review patch item 7 — the two cases below previously duplicated this
/// verbatim) — `data_ready` is the exact same "narrative still generating"
/// visual, just with an enabled download button appended beneath it.
const _generatingSequence = <Widget>[
  _StatusSpinner(),
  SizedBox(height: DesignTokens.exportStatusContentGap),
  _StatusText('Gerando resumo com IA...'),
  SizedBox(height: DesignTokens.exportStatusContentGap),
  _StatusProgressBar(),
];

/// Builds this sheet's own per-state content, above the always-present
/// "Fechar" link — a plain top-level function (not a `switch` expression
/// return type juggling `Widget` vs `List<Widget>`) so each case can emit
/// more than one widget (icon + text + progress bar/buttons) without an
/// extra wrapping `Column` per case. [context]/[cubit] are only actually
/// used by the two cases that render a live download button
/// ([ExportJobDataReady]/[ExportJobDone]) — threaded through every case
/// regardless, so the `switch` stays one expression.
List<Widget> _contentFor(
  BuildContext context,
  ExportJobCubit cubit,
  ExportJobState state,
) => switch (state) {
  ExportJobPreparing() => const [
    _StatusSpinner(),
    SizedBox(height: DesignTokens.exportStatusContentGap),
    _StatusText('Preparando exportação...'),
  ],
  ExportJobGenerating() => _generatingSequence,
  ExportJobDataReady() => [
    ..._generatingSequence,
    const SizedBox(height: DesignTokens.exportStatusContentGap),
    AppButton(
      label: 'Baixar dados brutos',
      variant: AppButtonVariant.secondaryOutline,
      onPressed: () => _handleDownload(context, cubit.downloadRawData),
    ),
  ],
  ExportJobDone(outcome: final outcome) => _doneContent(
    context,
    cubit,
    outcome,
  ),
  ExportJobError() => const [
    Icon(
      Icons.error_outline,
      size: DesignTokens.exportStatusIconSize,
      color: DesignTokens.colorError,
    ),
    SizedBox(height: DesignTokens.exportStatusContentGap),
    _StatusText(
      'Não foi possível gerar a exportação.',
      color: DesignTokens.colorError,
    ),
  ],
  ExportJobEmptyPeriod() => const [
    _StatusText('Nenhum registro nesse período.'),
    SizedBox(height: DesignTokens.spacingSm),
    _StatusText(
      'Ajuste o filtro de período e tente de novo.',
      color: DesignTokens.colorTextSecondary,
    ),
  ],
};

/// `ExportJobDone`'s own two flavors (I/O matrix's "Concluído" vs.
/// "Narrativa falhou/pulada" rows) — spec-7-2: both buttons now wired to a
/// real download via [_handleDownload], never `onPressed: null`.
List<Widget> _doneContent(
  BuildContext context,
  ExportJobCubit cubit,
  ExportOutcome outcome,
) {
  if (outcome == ExportOutcome.narrativeReady) {
    return [
      const Icon(
        Icons.check_circle,
        size: DesignTokens.exportStatusIconSize,
        color: DesignTokens.colorSuccess,
      ),
      const SizedBox(height: DesignTokens.exportStatusContentGap),
      const _StatusText('Resumo pronto'),
      const SizedBox(height: DesignTokens.exportStatusContentGap),
      Row(
        children: [
          Expanded(
            child: AppButton(
              label: 'Baixar PDF',
              onPressed: () => _handleDownload(context, cubit.downloadPdf),
            ),
          ),
          const SizedBox(width: DesignTokens.exportStatusButtonGap),
          Expanded(
            child: AppButton(
              label: 'Baixar dados brutos',
              variant: AppButtonVariant.secondaryOutline,
              onPressed: () => _handleDownload(context, cubit.downloadRawData),
            ),
          ),
        ],
      ),
    ];
  }
  return [
    const Icon(
      Icons.error_outline,
      size: DesignTokens.exportStatusIconSize,
      color: DesignTokens.colorError,
    ),
    const SizedBox(height: DesignTokens.exportStatusContentGap),
    const _StatusText(
      'Não foi possível gerar o resumo — a narrativa falhou, mas seus '
      'dados continuam disponíveis.',
      color: DesignTokens.colorError,
    ),
    const SizedBox(height: DesignTokens.exportStatusContentGap),
    AppButton(
      label: 'Baixar dados brutos',
      variant: AppButtonVariant.secondaryOutline,
      onPressed: () => _handleDownload(context, cubit.downloadRawData),
    ),
  ];
}

/// Routes a download-button tap through [download] (`cubit.downloadPdf`/
/// `cubit.downloadRawData`, bound), then surfaces whatever `Failure` it
/// resolves to — if any — as an inline `SnackBar`, mirroring
/// `_onExportTap`'s own create-failure pattern
/// (`meus_registros_screen.dart`). Reads the outcome straight off
/// [download]'s own return value (review finding, code review patch
/// item 6 — a shared mutable field on the cubit, written by the cubit and
/// mutated by this widget, broke encapsulation and was racy under a rapid
/// double-tap); never touches [ExportJobCubit.state]/rebuilds the sheet's
/// own job-status content (Boundaries).
Future<void> _handleDownload(
  BuildContext context,
  Future<Failure?> Function() download,
) async {
  final failure = await download();
  if (failure == null || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(failure.message)));
}

/// Pendente/Processando's own spinner — `cerne-prototype.html`'s spinning
/// `ph-circle-notch` glyph, approximated with Material's own
/// `CircularProgressIndicator` (same icon-font-approximation rationale
/// `DesignTokens.dialogIconSize`'s own doc already gives elsewhere).
class _StatusSpinner extends StatelessWidget {
  const _StatusSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: DesignTokens.exportStatusIconSize,
    height: DesignTokens.exportStatusIconSize,
    child: CircularProgressIndicator(color: DesignTokens.colorPrimary),
  );
}

/// Processando's own progress bar (I/O matrix: "Progress bar") —
/// indeterminate, since no job-progress percentage exists anywhere in the
/// contract (`export-status-get` reports `status`/`narrativeStatus` only,
/// never a numeric progress field).
class _StatusProgressBar extends StatelessWidget {
  const _StatusProgressBar();

  @override
  Widget build(BuildContext context) => const ClipRRect(
    borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusSm)),
    child: LinearProgressIndicator(
      color: DesignTokens.colorPrimary,
      backgroundColor: DesignTokens.colorBorder,
    ),
  );
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: DesignTokens.textBodyMd.copyWith(
      color: color ?? DesignTokens.colorTextPrimary,
    ),
  );
}
