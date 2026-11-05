import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';

/// `MeusRegistrosScreen`'s permanently-docked search bar (spec-5-1,
/// Acceptance Criteria: "permanently docked at the top of Meus Registros
/// with a trailing funnel icon and is never submitted via a button") —
/// two separate bordered pills (correction: `cerne-prototype.html`'s own
/// Tela 4 search row renders the text field and the funnel as sibling
/// `border:1px solid colorBorder` pills, not one shared
/// `elevation1`-shadowed box). [onChanged] feeds
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
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignTokens.colorSurfaceElevated,
              borderRadius: const BorderRadius.all(
                Radius.circular(DesignTokens.radiusFull),
              ),
              border: Border.all(
                color: DesignTokens.colorBorder,
                width: DesignTokens.borderWidthDefault,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.spacingMd,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: DesignTokens.entriesSearchBarIconSize,
                    color: DesignTokens.colorTextSecondary,
                  ),
                  const SizedBox(width: DesignTokens.spacingSm),
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
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: DesignTokens.spacingSm),
        Container(
          width: DesignTokens.insertionModalTapTargetMin,
          height: DesignTokens.insertionModalTapTargetMin,
          decoration: BoxDecoration(
            color: DesignTokens.colorSurfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: DesignTokens.colorBorder,
              width: DesignTokens.borderWidthDefault,
            ),
          ),
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
              size: DesignTokens.entriesSearchBarIconSize,
              color: hasActiveFilters
                  ? DesignTokens.colorPrimary
                  : DesignTokens.colorTextSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
