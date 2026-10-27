import 'package:flutter/widgets.dart';

/// RNF08 — the single source of truth for every color, font, spacing and
/// radius literal in the app. No other file may hardcode a visual value.
///
/// Implemented verbatim from `docs/input/prototype/prototype-extract.md`
/// section 3 (colors, typography, spacing, radii, elevation) — see Story
/// 1.2's Design Notes for the handful of gaps that section leaves silent
/// (shared widget padding, avatar sizes, text-field border widths).
class DesignTokens {
  const DesignTokens._();

  // ---------------------------------------------------------------------
  // Colors — prototype-extract.md §3 "Colors"
  // ---------------------------------------------------------------------

  /// Buttons, app bar, wordmark.
  static const Color colorPrimary = Color(0xFF1F3D34);

  /// Pressed state.
  static const Color colorPrimaryPressed = Color(0xFF16281F);

  /// Text on primary.
  static const Color colorOnPrimary = Color(0xFFF5F1E8);

  /// CTA, insight, saved bookmark.
  static const Color colorAccent = Color(0xFFC98A3E);

  /// Text on accent.
  static const Color colorOnAccent = Color(0xFF241C0D);

  /// Tags, chips, synchronizing.
  static const Color colorSecondary = Color(0xFF7C8B6F);

  /// General background ("paper").
  static const Color colorSurfaceBg = Color(0xFFF2EFE7);

  /// Cards, bubbles, sheets.
  static const Color colorSurfaceElevated = Color(0xFFFBF9F4);

  /// Dividers, borders.
  static const Color colorBorder = Color(0xFFE1DACB);

  /// Main text.
  static const Color colorTextPrimary = Color(0xFF241F19);

  /// Secondary text.
  static const Color colorTextSecondary = Color(0xFF6B6255);

  /// Errors, destructive action.
  static const Color colorError = Color(0xFFB3402A);

  /// Synchronized, confirmations.
  static const Color colorSuccess = Color(0xFF4C6B4F);

  /// "Synchronizing" badge.
  static const Color colorWarningSync = Color(0xFFC98A3E);

  /// Offline banner — single use.
  static const Color colorInfoOffline = Color(0xFF5C7A93);

  /// User chat bubble fill. Named in prototype-extract.md §3 as a color
  /// that "appears on specific screens but not in the [Design Tokens]
  /// panel" — still declared here (not hardcoded by whichever feature
  /// first builds the chat bubble) so RNF08 holds project-wide.
  static const Color colorChatBubbleUser = Color(0xFFD9DFD3);

  /// Text on category chips. Same provenance note as [colorChatBubbleUser].
  static const Color colorCategoryChipText = Color(0xFF3F4A38);

  // ---------------------------------------------------------------------
  // Typography — prototype-extract.md §3 "Typography"
  // ---------------------------------------------------------------------

  static const String _fontFraunces = 'Fraunces';
  static const String _fontKarla = 'Karla';
  static const String _fontMono = 'IBMPlexMono';

  /// Fraunces 600 · 32/38 — splash wordmark.
  static const TextStyle textDisplayLg = TextStyle(
    fontFamily: _fontFraunces,
    fontWeight: FontWeight.w600,
    fontSize: 32,
    height: 38 / 32,
  );

  /// Fraunces 600 · 24/30 — section titles.
  static const TextStyle textHeadlineMd = TextStyle(
    fontFamily: _fontFraunces,
    fontWeight: FontWeight.w600,
    fontSize: 24,
    height: 30 / 24,
  );

  /// Karla 700 · 20/26 — app bar title.
  static const TextStyle textTitleLg = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    height: 26 / 20,
  );

  /// Karla 700 · 16/22 — subtitles.
  static const TextStyle textTitleSm = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w700,
    fontSize: 16,
    height: 22 / 16,
  );

  /// Karla 400 · 16/24 — bubbles, entries.
  static const TextStyle textBodyLg = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    height: 24 / 16,
  );

  /// Karla 400 · 14/20 — secondary text and descriptions.
  static const TextStyle textBodyMd = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 20 / 14,
  );

  /// Karla 500 · 13/18 — button text, chips.
  static const TextStyle textLabelMd = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    height: 18 / 13,
  );

  /// IBM Plex Mono 500 · 12/16 · letter-spacing .2 — technical metadata
  /// (timestamps, counters, status labels).
  static const TextStyle textMonoCaption = TextStyle(
    fontFamily: _fontMono,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0.2,
  );

  // ---------------------------------------------------------------------
  // Spacing — prototype-extract.md §3 "Spacing" (4 dp grid)
  // ---------------------------------------------------------------------

  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacing2xl = 48;

  // ---------------------------------------------------------------------
  // Radii — prototype-extract.md §3 "Radii"
  // ---------------------------------------------------------------------

  /// Inputs, chips.
  static const double radiusSm = 8;

  /// Cards, bubbles.
  static const double radiusMd = 16;

  /// Sheets, modals.
  static const double radiusLg = 24;

  /// Avatars, pills.
  static const double radiusFull = 999;

  // ---------------------------------------------------------------------
  // Elevation — prototype-extract.md §3 "Elevation"
  // ---------------------------------------------------------------------

  /// `0 1px 3px rgba(36,31,25,.08)` — cards at rest.
  static const List<BoxShadow> elevation1 = [
    BoxShadow(
      color: Color.fromRGBO(36, 31, 25, 0.08),
      offset: Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  /// `0 4px 16px rgba(36,31,25,.14)` — sheets, modals.
  static const List<BoxShadow> elevation2 = [
    BoxShadow(
      color: Color.fromRGBO(36, 31, 25, 0.14),
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];

  // ---------------------------------------------------------------------
  // Components — named constants that don't fit color/typography/
  // spacing/radii (epic context's "components" token category; see
  // Story 1.2 Design Notes).
  // ---------------------------------------------------------------------

  /// Initials avatar — side menu (40dp).
  static const double avatarSizeSm = 40;

  /// Initials avatar — Configurações (52dp, Epic 8).
  static const double avatarSizeLg = 52;

  /// Text field default/unfocused border width.
  static const double borderWidthDefault = 1;

  /// Text field focused (`colorPrimary`) or error (`colorError`) border
  /// width — the prototype gives both states the same 1.5dp weight.
  static const double borderWidthEmphasis = 1.5;

  // ---------------------------------------------------------------------
  // Layout insets — not named in prototype-extract.md §3, but every
  // `EdgeInsets.*` construction must live here (see Story 1.2
  // Verification's RNF08 literal grep), built from the spacing scale
  // above rather than new literals.
  // ---------------------------------------------------------------------

  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: spacingLg,
    vertical: spacingSm,
  );

  static const EdgeInsets textFieldContentPadding = EdgeInsets.symmetric(
    horizontal: spacingMd,
    vertical: spacingSm,
  );

  static const EdgeInsets avatarInitialsPadding = EdgeInsets.all(spacingXs);
}
