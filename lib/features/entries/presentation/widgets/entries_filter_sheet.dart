import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/entities/entry.dart';
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

/// INTERVALO DE DATA's own 3 choices (`prototype-extract.md`; Design
/// Notes confirms single-choice, same as the prototype itself already
/// shows for this one group) — each computes its own `dateFrom`/`dateTo`
/// pair via [rangeFrom]. [allTime] is itself a selectable choice meaning
/// "no date filter at all", not some maximal range — it resolves to
/// `(null, null)`.
enum DateRangePreset {
  allTime,
  thisWeek,
  thisMonth;

  String get label => switch (this) {
    DateRangePreset.allTime => 'Todo o período',
    DateRangePreset.thisWeek => 'Esta semana',
    DateRangePreset.thisMonth => 'Este mês',
  };

  /// This preset's own `(dateFrom, dateTo)` pair, anchored to [now] (a
  /// parameter only so a test can pin it — every real call site passes
  /// `DateTime.now()`). `dateTo` is always [now] itself — "through right
  /// now" — `docs/input/` is silent on inclusive/exclusive bounds here
  /// (AGENTS.md policy: "decide and proceed"). `dateFrom` is local
  /// midnight of the Monday starting this week, or the 1st of this
  /// calendar month.
  (DateTime?, DateTime?) rangeFrom(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case DateRangePreset.allTime:
        return (null, null);
      case DateRangePreset.thisWeek:
        return (today.subtract(Duration(days: today.weekday - 1)), now);
      case DateRangePreset.thisMonth:
        return (DateTime(today.year, today.month), now);
    }
  }
}

/// The reverse of [DateRangePreset.rangeFrom] — which preset (if any) a
/// given [dateFrom] matches, by its own start boundary alone (`dateTo`
/// drifts with "now" on every render, so it's never part of this match).
/// A `null` [dateFrom] (no date filter active) always matches
/// [DateRangePreset.allTime]; shared by this sheet's own pre-selection
/// (reopening with a filter already active) and `MeusRegistrosScreen`'s
/// active-filter chip row (labeling the currently-active range the same
/// way the sheet itself would).
///
/// Checks [DateRangePreset.thisMonth] *before* [DateRangePreset.thisWeek]
/// (code-review fix) — when the month's 1st day also happens to be this
/// week's own Monday, the two presets' start boundaries are identical, so
/// whichever is checked first always wins; checking `thisWeek` first (the
/// original order) mislabeled a month-long filter as "Esta semana" on
/// every such month.
DateRangePreset dateRangePresetMatching(DateTime? dateFrom, DateTime now) {
  if (dateFrom == null) {
    return DateRangePreset.allTime;
  }
  final today = DateTime(now.year, now.month, now.day);
  if (dateFrom == DateTime(today.year, today.month)) {
    return DateRangePreset.thisMonth;
  }
  if (dateFrom == today.subtract(Duration(days: today.weekday - 1))) {
    return DateRangePreset.thisWeek;
  }
  return DateRangePreset.allTime;
}

/// The filter bottom sheet (spec-5-2) — two single-choice groups
/// ("INTERVALO DE DATA", "TIPO DE ENTRADA"; Design Notes: no "CATEGORIA"
/// group — the backend has no category filter, RF06) plus "Aplicar"/
/// "Limpar". Mirrors `InsertionModal.show()`'s own bottom-sheet
/// choreography (`isScrollControlled`, `useSafeArea`, `colorScrimHeavy`, a
/// Reduce-Motion-aware `durationSheetUp` entrance) — Code Map.
class EntriesFilterSheet extends StatefulWidget {
  const EntriesFilterSheet({required this.cubit, super.key});

  /// Passed in directly rather than read via `context.read` (same
  /// rationale `InsertionModal`'s own cubit constructor params give): a
  /// `showModalBottomSheet` route's `builder` context is inserted above
  /// `MeusRegistrosScreen`'s own `MultiBlocProvider`, not below it, so
  /// nothing that `BlocProvider` exposes would be reachable from here
  /// anyway.
  final MeusRegistrosCubit cubit;

  /// Presents the sheet exactly as the class doc describes. [cubit]'s own
  /// `applyFilters()` is called directly by this sheet's "Aplicar" button
  /// (`_EntriesFilterSheetState._applyAndClose`) — this `static` method
  /// itself never touches the cubit.
  static Future<void> show(
    BuildContext context, {
    required MeusRegistrosCubit cubit,
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
        builder: (_) => EntriesFilterSheet(cubit: cubit),
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
    _pendingSource = widget.cubit.activeSource;
    _pendingDateRange = dateRangePresetMatching(
      widget.cubit.activeDateFrom,
      DateTime.now(),
    );
  }

  void _applyAndClose() {
    final (dateFrom, dateTo) = _pendingDateRange.rangeFrom(DateTime.now());
    widget.cubit.applyFilters(
      source: _pendingSource,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
    Navigator.of(context).pop();
  }

  /// "Limpar" (Boundaries: "resets only the sheet's own pending
  /// selection") — never touches [widget.cubit]/closes the sheet; that's
  /// `MeusRegistrosScreen`'s separate "Limpar filtros" link's own job
  /// (`MeusRegistrosCubit.clearFilters()`).
  void _clearPending() {
    setState(() {
      _pendingSource = null;
      _pendingDateRange = DateRangePreset.allTime;
    });
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
                'INTERVALO DE DATA',
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
                      label: preset.label,
                      selected: _pendingDateRange == preset,
                      onTap: () => setState(() => _pendingDateRange = preset),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingLg),
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
                      // group above (whose 3 choices always include an
                      // explicit "none" — [DateRangePreset.allTime]),
                      // source has no dedicated "any source" chip — tapping
                      // the already-selected one toggles it back off
                      // instead of being a no-op, since that's otherwise
                      // the only way to clear just this one group without
                      // "Limpar" resetting the date group too.
                      onTap: () => setState(
                        () => _pendingSource = _pendingSource == source
                            ? null
                            : source,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Limpar',
                      variant: AppButtonVariant.textGhost,
                      onPressed: _clearPending,
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spacingMd),
                  Expanded(
                    child: AppButton(
                      label: 'Aplicar',
                      onPressed: _applyAndClose,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable group option — reused by both groups ("INTERVALO DE
/// DATA"/"TIPO DE ENTRADA"); selected state is `colorSecondary` fill +
/// `colorCategoryChipText` text, same token pair the active-filter chip
/// row (`MeusRegistrosScreen`) reuses for its own chips (Boundaries: exact
/// token reuse, no new token). Unselected state is a plain `colorBorder`
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
                ? DesignTokens.colorSecondary
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
                  ? DesignTokens.colorCategoryChipText
                  : DesignTokens.colorTextPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
