import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/entities/date_range_preset.dart';
import '../../domain/entities/entry.dart';
import '../cubit/entries_search_cubit.dart';
import '../cubit/meus_registros_cubit.dart';

/// TIPO DE ENTRADA's own label for each [EntrySource]
/// (`prototype-extract.md` Tela 4 — Sheet de filtro) — shared by this
/// sheet's own chips and `MeusRegistrosScreen`'s active-filter chip row,
/// so the two surfaces never drift out of sync with each other (Code Map).
String entrySourceLabel(EntrySource source) => switch (source) {
  EntrySource.manual => 'Manual',
  EntrySource.audio => 'Áudio',
  EntrySource.photo => 'Foto',
  EntrySource.chat => 'Chat',
};

/// [DateRangePreset]'s own UI copy — kept out of the domain enum itself,
/// same split [entrySourceLabel] already gives [EntrySource]; shared by
/// this sheet's own chips and `MeusRegistrosScreen`'s active-filter chip
/// row.
String dateRangePresetLabel(DateRangePreset preset) => switch (preset) {
  DateRangePreset.allTime => 'Todo o período',
  DateRangePreset.thisWeek => 'Esta semana',
  DateRangePreset.thisMonth => 'Este mês',
};

/// The filter bottom sheet (spec-5-2) — a "Filtrar registros" title over
/// two single-choice groups, "TIPO DE ENTRADA" then "PERÍODO" (correction:
/// `cerne-prototype.html`'s own Tela 4 filter-sheet markup has the type
/// group first and names the date group "PERÍODO", not "INTERVALO DE
/// DATA"; Design Notes: no "CATEGORIA" group either way — the backend has
/// no category filter, RF06), plus a single full-width "Aplicar" button —
/// the prototype's own sheet has no separate "Limpar" button; clearing is
/// `MeusRegistrosScreen`'s own "Limpar filtros" link, outside this sheet.
/// Mirrors `InsertionModal.show()`'s own bottom-sheet choreography
/// (`isScrollControlled`, `useSafeArea`, `colorScrimHeavy`, a
/// Reduce-Motion-aware `durationSheetUp` entrance) — Code Map.
class EntriesFilterSheet extends StatefulWidget {
  const EntriesFilterSheet({
    required this.cubit,
    required this.searchCubit,
    super.key,
  });

  /// Passed in directly rather than read via `context.read` (same
  /// rationale `InsertionModal`'s own cubit constructor params give): a
  /// `showModalBottomSheet` route's `builder` context is inserted above
  /// `MeusRegistrosScreen`'s own `MultiBlocProvider`, not below it, so
  /// nothing that `BlocProvider` exposes would be reachable from here
  /// anyway.
  final MeusRegistrosCubit cubit;

  /// spec-5-3 — `MeusRegistrosScreen`'s own bridge to
  /// `EntriesSearchCubit` (Design Notes: the two cubits never import each
  /// other, RNF06); [_EntriesFilterSheetState._applyAndClose] calls
  /// [cubit]'s `applyFilters()` and this cubit's own `updateFilters()`
  /// side by side.
  final EntriesSearchCubit searchCubit;

  /// Presents the sheet exactly as the class doc describes. [cubit]'s own
  /// `applyFilters()` is called directly by this sheet's "Aplicar" button
  /// (`_EntriesFilterSheetState._applyAndClose`) — this `static` method
  /// itself never touches the cubit.
  static Future<void> show(
    BuildContext context, {
    required MeusRegistrosCubit cubit,
    required EntriesSearchCubit searchCubit,
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
        builder: (_) =>
            EntriesFilterSheet(cubit: cubit, searchCubit: searchCubit),
      );
    } finally {
      // Same "wait for the exit animation before disposing the
      // controller" rationale as `InsertionModal.show()`'s own `finally`
      // block (see its doc for the full explanation) — disposing the
      // moment `showModalBottomSheet`'s own `Future` resolves would cut
      // the still-running reverse animation's ticker off mid-flight.
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
    }
  }

  @override
  State<EntriesFilterSheet> createState() => _EntriesFilterSheetState();
}

class _EntriesFilterSheetState extends State<EntriesFilterSheet> {
  late EntrySource? _pendingSource;
  late DateRangePreset _pendingDateRange;

  @override
  void initState() {
    super.initState();
    // Pre-selects whichever filters are already active — `docs/input/` is
    // silent on this exact behavior (AGENTS.md policy: "decide and
    // proceed") — rather than always reopening blank, so reopening the
    // sheet to tweak just one filter doesn't silently discard the other.
    // Round-2 review fix: reads the cubit's own stored preset directly
    // rather than re-deriving it from `activeDateFrom` by equality match —
    // that re-derivation went stale (mis-pre-selecting "Todo o período")
    // the moment a day/week/month boundary rolled over while the filter
    // stayed active.
    _pendingSource = widget.cubit.activeSource;
    _pendingDateRange = widget.cubit.activeDateRangePreset;
  }

  void _applyAndClose() {
    final (dateFrom, dateTo) = _pendingDateRange.rangeFrom(DateTime.now());
    widget.cubit.applyFilters(
      source: _pendingSource,
      dateFrom: dateFrom,
      dateTo: dateTo,
      dateRangePreset: _pendingDateRange,
    );
    // spec-5-3 — right alongside the existing `applyFilters()` call above:
    // a search that's currently active must carry this same filter
    // selection too (Boundaries), not just the plain/filtered timeline.
    widget.searchCubit.updateFilters(
      source: _pendingSource,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: DesignTokens.screenPadding,
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusLg),
        ),
        boxShadow: DesignTokens.elevation2,
      ),
      child: SafeArea(
        top: false,
        // Epic-5 context's own UX note: "Filter chips and the search/
        // filter surfaces are a tight-fit area for Dynamic Type — verify
        // text does not truncate or clip at the largest accessibility
        // size" — a `SingleChildScrollView` guards against this sheet's
        // own content overflowing the screen at a large accessibility
        // text size, same safety net `InsertionModal`'s own tab content
        // already has (wrapped in its own `Flexible`/
        // `SingleChildScrollView` pair).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filtrar registros',
                style: DesignTokens.textTitleSm.copyWith(
                  color: DesignTokens.colorTextPrimary,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                'TIPO DE ENTRADA',
                style: DesignTokens.textMonoCaption.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Wrap(
                spacing: DesignTokens.spacingSm,
                runSpacing: DesignTokens.spacingSm,
                children: [
                  for (final source in EntrySource.values)
                    _FilterChip(
                      label: entrySourceLabel(source),
                      selected: _pendingSource == source,
                      // Single choice (Design Notes): unlike the date-range
                      // group below (whose 3 choices always include an
                      // explicit "none" — [DateRangePreset.allTime]),
                      // source has no dedicated "any source" chip — tapping
                      // the already-selected one toggles it back off
                      // instead of being a no-op, since that's otherwise
                      // the only way to clear just this one group (the
                      // sheet has no "Limpar" of its own).
                      onTap: () => setState(
                        () => _pendingSource = _pendingSource == source
                            ? null
                            : source,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                'PERÍODO',
                style: DesignTokens.textMonoCaption.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingSm),
              Wrap(
                spacing: DesignTokens.spacingSm,
                runSpacing: DesignTokens.spacingSm,
                children: [
                  for (final preset in DateRangePreset.values)
                    _FilterChip(
                      label: dateRangePresetLabel(preset),
                      selected: _pendingDateRange == preset,
                      onTap: () => setState(() => _pendingDateRange = preset),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              AppButton(label: 'Aplicar', onPressed: _applyAndClose),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable group option — reused by both groups ("TIPO DE
/// ENTRADA"/"PERÍODO"); selected state is `colorPrimary` fill +
/// `colorOnPrimary` text (correction: `cerne-prototype.html`'s own filter-
/// sheet markup fills a selected chip dark green, `background:#1F3D34`,
/// not the olive `colorSecondary` a previous pass shared with the
/// *active-filter* chip row outside this sheet — the two surfaces use
/// different token pairs now). Unselected state is a plain `colorBorder`
/// outline — not itself named by Boundaries, since only the *selected*
/// look is actually specified there.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusFull),
        ),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: DesignTokens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? DesignTokens.colorPrimary
                : DesignTokens.colorSurfaceBg,
            borderRadius: const BorderRadius.all(
              Radius.circular(DesignTokens.radiusFull),
            ),
            border: selected
                ? null
                : Border.all(
                    color: DesignTokens.colorBorder,
                    width: DesignTokens.borderWidthDefault,
                  ),
          ),
          child: Text(
            label,
            style: DesignTokens.textLabelMd.copyWith(
              color: selected
                  ? DesignTokens.colorOnPrimary
                  : DesignTokens.colorTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
