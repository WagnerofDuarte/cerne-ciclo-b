import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cerne/core/design_tokens.dart';

void main() {
  group('DesignTokens — colors (prototype-extract.md §3)', () {
    test('matches the Design Tokens panel verbatim', () {
      expect(DesignTokens.colorPrimary, const Color(0xFF1F3D34));
      expect(DesignTokens.colorPrimaryPressed, const Color(0xFF16281F));
      expect(DesignTokens.colorOnPrimary, const Color(0xFFF5F1E8));
      expect(DesignTokens.colorAccent, const Color(0xFFC98A3E));
      expect(DesignTokens.colorOnAccent, const Color(0xFF241C0D));
      expect(DesignTokens.colorSecondary, const Color(0xFF7C8B6F));
      expect(DesignTokens.colorSurfaceBg, const Color(0xFFF2EFE7));
      expect(DesignTokens.colorSurfaceElevated, const Color(0xFFFBF9F4));
      expect(DesignTokens.colorBorder, const Color(0xFFE1DACB));
      expect(DesignTokens.colorTextPrimary, const Color(0xFF241F19));
      expect(DesignTokens.colorTextSecondary, const Color(0xFF6B6255));
      expect(DesignTokens.colorError, const Color(0xFFB3402A));
      expect(DesignTokens.colorSuccess, const Color(0xFF4C6B4F));
      expect(DesignTokens.colorWarningSync, const Color(0xFFC98A3E));
      expect(DesignTokens.colorInfoOffline, const Color(0xFF5C7A93));
    });

    test('includes the two colors named outside the panel', () {
      expect(DesignTokens.colorChatBubbleUser, const Color(0xFFD9DFD3));
      expect(DesignTokens.colorCategoryChipText, const Color(0xFF3F4A38));
    });
  });

  group('DesignTokens — typography (prototype-extract.md §3)', () {
    test('textDisplayLg — Fraunces 600 · 32/38', () {
      expect(DesignTokens.textDisplayLg.fontFamily, 'Fraunces');
      expect(DesignTokens.textDisplayLg.fontWeight, FontWeight.w600);
      expect(DesignTokens.textDisplayLg.fontSize, 32);
      expect(DesignTokens.textDisplayLg.height, closeTo(38 / 32, 1e-9));
    });

    test('textHeadlineMd — Fraunces 600 · 24/30', () {
      expect(DesignTokens.textHeadlineMd.fontFamily, 'Fraunces');
      expect(DesignTokens.textHeadlineMd.fontWeight, FontWeight.w600);
      expect(DesignTokens.textHeadlineMd.fontSize, 24);
      expect(DesignTokens.textHeadlineMd.height, closeTo(30 / 24, 1e-9));
    });

    test('textTitleLg — Karla 700 · 20/26', () {
      expect(DesignTokens.textTitleLg.fontFamily, 'Karla');
      expect(DesignTokens.textTitleLg.fontWeight, FontWeight.w700);
      expect(DesignTokens.textTitleLg.fontSize, 20);
      expect(DesignTokens.textTitleLg.height, closeTo(26 / 20, 1e-9));
    });

    test('textTitleSm — Karla 700 · 16/22', () {
      expect(DesignTokens.textTitleSm.fontFamily, 'Karla');
      expect(DesignTokens.textTitleSm.fontWeight, FontWeight.w700);
      expect(DesignTokens.textTitleSm.fontSize, 16);
      expect(DesignTokens.textTitleSm.height, closeTo(22 / 16, 1e-9));
    });

    test('textBodyLg — Karla 400 · 16/24', () {
      expect(DesignTokens.textBodyLg.fontFamily, 'Karla');
      expect(DesignTokens.textBodyLg.fontWeight, FontWeight.w400);
      expect(DesignTokens.textBodyLg.fontSize, 16);
      expect(DesignTokens.textBodyLg.height, closeTo(24 / 16, 1e-9));
    });

    test('textBodyMd — Karla 400 · 14/20', () {
      expect(DesignTokens.textBodyMd.fontFamily, 'Karla');
      expect(DesignTokens.textBodyMd.fontWeight, FontWeight.w400);
      expect(DesignTokens.textBodyMd.fontSize, 14);
      expect(DesignTokens.textBodyMd.height, closeTo(20 / 14, 1e-9));
    });

    test('textLabelMd — Karla 500 · 13/18', () {
      expect(DesignTokens.textLabelMd.fontFamily, 'Karla');
      expect(DesignTokens.textLabelMd.fontWeight, FontWeight.w500);
      expect(DesignTokens.textLabelMd.fontSize, 13);
      expect(DesignTokens.textLabelMd.height, closeTo(18 / 13, 1e-9));
    });

    test('textMonoCaption — IBM Plex Mono 500 · 12/16 · letter-spacing .2', () {
      expect(DesignTokens.textMonoCaption.fontFamily, 'IBMPlexMono');
      expect(DesignTokens.textMonoCaption.fontWeight, FontWeight.w500);
      expect(DesignTokens.textMonoCaption.fontSize, 12);
      expect(DesignTokens.textMonoCaption.height, closeTo(16 / 12, 1e-9));
      expect(DesignTokens.textMonoCaption.letterSpacing, 0.2);
    });
  });

  group('DesignTokens — spacing (4 dp grid)', () {
    test('matches prototype-extract.md §3 verbatim', () {
      expect(DesignTokens.spacingXs, 4);
      expect(DesignTokens.spacingSm, 8);
      expect(DesignTokens.spacingMd, 16);
      expect(DesignTokens.spacingLg, 24);
      expect(DesignTokens.spacingXl, 32);
      expect(DesignTokens.spacing2xl, 48);
    });
  });

  group('DesignTokens — radii', () {
    test('matches prototype-extract.md §3 verbatim', () {
      expect(DesignTokens.radiusSm, 8);
      expect(DesignTokens.radiusMd, 16);
      expect(DesignTokens.radiusLg, 24);
      expect(DesignTokens.radiusFull, 999);
    });
  });

  group('DesignTokens — elevation', () {
    test('elevation1 — 0 1px 3px rgba(36,31,25,.08)', () {
      final shadow = DesignTokens.elevation1.single;
      expect(shadow.offset, const Offset(0, 1));
      expect(shadow.blurRadius, 3);
      expect(shadow.color, const Color.fromRGBO(36, 31, 25, 0.08));
    });

    test('elevation2 — 0 4px 16px rgba(36,31,25,.14)', () {
      final shadow = DesignTokens.elevation2.single;
      expect(shadow.offset, const Offset(0, 4));
      expect(shadow.blurRadius, 16);
      expect(shadow.color, const Color.fromRGBO(36, 31, 25, 0.14));
    });
  });

  group('DesignTokens — components', () {
    test('avatar sizes — 40dp / 52dp', () {
      expect(DesignTokens.avatarSizeSm, 40);
      expect(DesignTokens.avatarSizeLg, 52);
    });

    test('text-field border widths — 1dp default / 1.5dp focused+error', () {
      expect(DesignTokens.borderWidthDefault, 1);
      expect(DesignTokens.borderWidthEmphasis, 1.5);
    });
  });

  group('DesignTokens — layout insets', () {
    test('buttonPadding — horizontal spacingLg, vertical spacingSm', () {
      expect(
        DesignTokens.buttonPadding,
        const EdgeInsets.symmetric(horizontal: DesignTokens.spacingLg, vertical: DesignTokens.spacingSm),
      );
    });

    test('textFieldContentPadding — horizontal spacingMd, vertical spacingSm', () {
      expect(
        DesignTokens.textFieldContentPadding,
        const EdgeInsets.symmetric(horizontal: DesignTokens.spacingMd, vertical: DesignTokens.spacingSm),
      );
    });

    test('avatarInitialsPadding — spacingXs on all sides', () {
      expect(DesignTokens.avatarInitialsPadding, const EdgeInsets.all(DesignTokens.spacingXs));
    });
  });
}
