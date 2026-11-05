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
/// The trailing funnel (`Icons.filter_list`) button is a no-op this story
/// (Boundaries/Never: filters are spec-5-2) — still sized to the shared
/// 44pt minimum tap target (`insertionModalTapTargetMin`, UX-DR23) so it
/// reads as a real, future-functional control rather than a disabled
/// placeholder.
class EntriesSearchBar extends StatelessWidget {
  const EntriesSearchBar({required this.onChanged, super.key});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
        ),
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
            // spec-5-1 Boundaries: a no-op this story — filters land in
            // spec-5-2.
            SizedBox(
              width: DesignTokens.insertionModalTapTargetMin,
              height: DesignTokens.insertionModalTapTargetMin,
              child: IconButton(
                padding: EdgeInsets.zero,
                onPressed: () {},
                // Review finding: an unlabeled icon-only button gives a
                // screen-reader user no indication of its purpose.
                tooltip: 'Filtros',
                icon: const Icon(
                  Icons.filter_list,
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
