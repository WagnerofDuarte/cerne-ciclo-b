import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
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
                ..._contentFor(state),
                const SizedBox(height: DesignTokens.spacingXs),
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      'Fechar',
                      style: DesignTokens.textMonoCaption.copyWith(
                        color: DesignTokens.colorTextSecondary,
                      ),
                    ),
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

/// Builds this sheet's own per-state content, above the always-present
/// "Fechar" link — a plain top-level function (not a `switch` expression
/// return type juggling `Widget` vs `List<Widget>`) so each case can emit
/// more than one widget (icon + text + progress bar/buttons) without an
/// extra wrapping `Column` per case.
List<Widget> _contentFor(ExportJobState state) => switch (state) {
  ExportJobPreparing() => const [
    _StatusSpinner(),
    SizedBox(height: DesignTokens.exportStatusContentGap),
    _StatusText('Preparando exportação...'),
  ],
  ExportJobGenerating() => const [
    _StatusSpinner(),
    SizedBox(height: DesignTokens.exportStatusContentGap),
    _StatusText('Gerando resumo com IA...'),
    SizedBox(height: DesignTokens.exportStatusContentGap),
    _StatusProgressBar(),
  ],
  ExportJobDone(outcome: final outcome) => _doneContent(outcome),
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
/// "Narrativa falhou/pulada" rows). Both buttons stay disabled this story
/// (Never: "wire the real download... Story 7.2").
List<Widget> _doneContent(ExportOutcome outcome) {
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
          const Expanded(
            child: AppButton(label: 'Baixar PDF', onPressed: null),
          ),
          const SizedBox(width: DesignTokens.exportStatusButtonGap),
          const Expanded(
            child: AppButton(
              label: 'Baixar dados brutos',
              variant: AppButtonVariant.secondaryOutline,
              onPressed: null,
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
    const AppButton(
      label: 'Baixar dados brutos',
      variant: AppButtonVariant.secondaryOutline,
      onPressed: null,
    ),
  ];
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
