import 'package:flutter/widgets.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/skeleton_box.dart';

/// `MeusRegistrosScreen`'s first-load skeleton — same outer card shell as
/// `EntryRecordCard` (surface/radius/elevation, no spine) with its content
/// replaced by [SkeletonBox] rectangles sized purely off the existing
/// spacing scale (Code Map/Boundaries: "built only from existing tokens").
/// Shown only past the shared 300ms threshold (`MeusRegistrosScreen`'s own
/// `Timer`, mirroring `BootSplashScreen`'s pattern) — never below it
/// (RNF01).
class EntrySkeletonCard extends StatelessWidget {
  const EntrySkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: Padding(
        padding: DesignTokens.kanbanCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SkeletonBox(
              width: DesignTokens.spacing2xl,
              height: DesignTokens.spacingMd,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            const SkeletonBox(
              width: double.infinity,
              height: DesignTokens.spacingMd,
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            const SkeletonBox(
              width: double.infinity,
              height: DesignTokens.spacingMd,
            ),
          ],
        ),
      ),
    );
  }
}
