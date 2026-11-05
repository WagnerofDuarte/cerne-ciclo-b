import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';

/// `MeusRegistrosScreen`'s permanently-docked search bar (spec-5-1,
/// Acceptance Criteria: "permanently docked at the top of Meus Registros
/// with a trailing funnel icon and is never submitted via a button") —
/// paper-elevated like `EntryRecordCard` (`colorSurfaceElevated`,
/// `radiusMd`, `elevation1`). [onChanged] feeds
/// `EntriesSearchCubit.onQueryChanged` directly on every keystroke — there
/// is no submit button anywhere on this widget, by design (Boundaries).
///
/// spec-5-2: the trailing funnel (`Icons.filter_list`) button now opens
/// the filter sheet via [onFilterTap] (`MeusRegistrosScreen`'s own
/// `EntriesFilterSheet.show()` call replaces the former no-op
/// `onPressed: () {}`) — still sized to the shared 44pt minimum tap
/// target (`insertionModalTapTargetMin`, UX-DR23). [hasActiveFilters]
/// fills it (`colorPrimary` instead of the resting `colorTextSecondary`)
/// whenever any filter is active (Boundaries: "fills the funnel icon").
class EntriesSearchBar extends StatelessWidget {
  const EntriesSearchBar({
    required this.onChanged,
    required this.onFilterTap,
    this.hasActiveFilters = false,
    super.key,
  });

  final ValueChanged<String> onChanged;

  /// spec-5-2 — opens the filter sheet.
  final VoidCallback onFilterTap;

  /// spec-5-2 — `true` whenever `MeusRegistrosCubit.hasActiveFilters` is
  /// true; defaults `false` so this widget still renders sensibly for any
  /// caller that has no filter state of its own to report.
  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: onChanged,
                style: DesignTokens.textBodyMd.copyWith(
                  color: DesignTokens.colorTextPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Buscar nos registros...',
                  hintStyle: DesignTokens.textBodyMd.copyWith(
                    color: DesignTokens.colorTextSecondary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: DesignTokens.spacingMd,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: DesignTokens.insertionModalTapTargetMin,
              height: DesignTokens.insertionModalTapTargetMin,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: onFilterTap,
                // Review finding: an unlabeled icon-only button gives a
                // screen-reader user no indication of its purpose.
                // Round-2 review fix: also distinguishes "filters active"
                // for a screen-reader user, who otherwise has no way to
                // learn that beyond separately discovering the chip row.
                tooltip: hasActiveFilters ? 'Filtros (ativos)' : 'Filtros',
                icon: Icon(
                  Icons.filter_list,
                  color: hasActiveFilters
                      ? DesignTokens.colorPrimary
                      : DesignTokens.colorTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
