import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_tokens.dart';
import '../navigation/app_router.dart';

/// Shared back-arrow header (Meus Registros/Planos de Ação/Configurações) —
/// extracted from `core/navigation/placeholder_screens.dart`'s former
/// private `_BackArrowHeader` (Story 2.4 Code Map) so the real Configurações
/// screen can reuse it too, with no duplication. The back arrow always
/// targets `/` (Boundaries: "matches prototype's `goHome` on all three").
class BackArrowHeader extends StatelessWidget {
  const BackArrowHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.colorSurfaceBg,
      padding: DesignTokens.navHeaderPadding,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.go(AppRoutePaths.home),
            child: const Icon(
              Icons.chevron_left,
              size: DesignTokens.navBackIconSize,
              color: DesignTokens.colorTextPrimary,
            ),
          ),
          const SizedBox(width: DesignTokens.navHeaderGap),
          Expanded(
            child: Text(
              title,
              style: DesignTokens.textHeadlineMd.copyWith(
                color: DesignTokens.colorTextPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
