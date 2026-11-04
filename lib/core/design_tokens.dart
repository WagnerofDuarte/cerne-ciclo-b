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

  /// Scrim behind the session-expiry overlay specifically (Story 1.5) —
  /// `rgba(36,31,25,.22)`, the exact value `cerne-prototype.html` uses for
  /// *this* overlay. Its other overlays (drawer, insertion modal,
  /// filter/export sheets, account-deletion confirm) use the heavier
  /// `rgba(36,31,25,.4)` instead — that value belongs to whichever later
  /// story builds those, never this one.
  static const Color colorScrim = Color(0x38241F19);

  /// Heavier scrim behind every *other* overlay (Story 1.6's drawer; a later
  /// story's insertion modal/filter/export sheets, account-deletion
  /// confirm) — `rgba(36,31,25,.4)` per `cerne-prototype.html`'s
  /// `<!-- OVERLAY: Drawer -->` block. Distinct from [colorScrim], which
  /// stays the session-expiry overlay's own lighter value (see that
  /// constant's doc).
  static const Color colorScrimHeavy = Color(0x66241F19);

  /// PIN error band fill (Story 2.2 correction) — `rgba(179,64,42,.08)`,
  /// `cerne-prototype.html`'s Tela 0.1c error band background, `colorError`
  /// at 8% alpha.
  static const Color colorErrorBg = Color(0x14B3402A);

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

  /// Karla 400 · 12/16 — PIN error band caption (Story 2.2 correction).
  /// `cerne-prototype.html`'s Tela 0.1c error band is `font-size:12px`
  /// Karla, not on the rest of the type scale (the closest existing
  /// token, [textLabelMd], is both a different weight and size).
  static const TextStyle textCaptionSm = TextStyle(
    fontFamily: _fontKarla,
    fontWeight: FontWeight.w400,
    fontSize: 12,
    height: 16 / 12,
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
  // Motion (Story 3.1) — the first `Duration` token this file defines
  // (RNF08: every such literal belongs here, not hardcoded in a widget).
  // ---------------------------------------------------------------------

  /// Insertion Modal's own entrance choreography — `200ms`
  /// (`cerne-prototype.html` calls this transition `sheetUp`). The caller
  /// (`InsertionModal.show`) substitutes `Duration.zero` instead whenever
  /// `MediaQuery.disableAnimations` is true (Reduce Motion), rather than
  /// this file encoding that condition itself.
  static const Duration durationSheetUp = Duration(milliseconds: 200);

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

  /// Confirmation-dialog lock icon (Story 1.5) — the prototype's
  /// `ph-lock-key` is `font-size:20px`; approximated here with a built-in
  /// Material icon (Design Notes — no new icon-font dependency), sized to
  /// match.
  static const double dialogIconSize = 20;

  /// Tela 0.1's biometric icon circle (Story 2.1 correction) —
  /// `cerne-prototype.html`'s `96px` circle, `colorSurfaceElevated` fill,
  /// `colorBorder` outline, [elevation1] shadow.
  static const double biometricIconCircleSize = 96;

  /// Tela 0.1's `ph-fingerprint` icon (Story 2.1 correction) —
  /// `font-size:44px`; approximated with a built-in Material icon, same
  /// rationale as [dialogIconSize].
  static const double biometricIconSize = 44;

  /// Confirmation-dialog card's internal gap between stacked elements
  /// (icon+title row, body text, button, caption) — the overlay's markup
  /// (prototype-extract.md's "Sessão expirada" block) uses 14px, which
  /// isn't on the existing 4dp spacing scale.
  static const double dialogContentGap = 14;

  /// Insertion Modal's "x" close button, each tab button, and (spec-3-2)
  /// the circular stop-recording control's minimum tap target (Story 3.1
  /// review finding) — UX-DR23's 44pt floor, same rationale
  /// [pinKeypadButtonSize] already cites, named here instead of
  /// hardcoded in `insertion_modal.dart` (RNF08).
  static const double insertionModalTapTargetMin = 44;

  // ---------------------------------------------------------------------
  // Navigation shell (Story 1.6) — `cerne-prototype.html`'s
  // `<!-- OVERLAY: Drawer -->` block, the `Tela 1/5/6` header blocks, and
  // the `Tela 5 — Planos de Ação` kanban block.
  // ---------------------------------------------------------------------

  /// Side-menu `Drawer` width — 80% of the fixed 390 frame (312dp), per the
  /// drawer markup's `width:80%`.
  static const double drawerWidth = 312;

  /// ☰ hamburger icon (Home/Chat's dark-green header) — `ph-list`,
  /// `font-size:24px`.
  static const double navMenuIconSize = 24;

  /// Back-arrow icon on every non-Home destination's header (Meus
  /// Registros/Planos de Ação/Configurações placeholders) — `ph-caret-left`,
  /// `font-size:22px`.
  static const double navBackIconSize = 22;

  /// Icon-title gap shared by every app-shell header (Home/Chat's ☰+
  /// wordmark grid gap is implicit via its 3-column grid, but the
  /// back-arrow headers and the kanban column header all use an explicit
  /// `gap:12px`) and by each drawer nav item's own icon-label gap.
  static const double navHeaderGap = 12;

  /// Drawer nav item icon size (`ph-notebook`/`ph-kanban`/`ph-gear`, and
  /// the "Novo Chat" `ph-plus`) — `font-size:20px`.
  static const double drawerItemIconSize = 20;

  /// Drawer header row's avatar-label gap — `gap:10px`, distinct from
  /// [navHeaderGap] (the drawer markup uses a different value here than
  /// its own nav items do).
  static const double drawerHeaderGap = 10;

  /// Kanban board's column-to-column gap and each column's dot-title-count
  /// gap — `gap:12px`/`gap:8px`; the latter is already [spacingSm].
  static const double kanbanColumnGap = 12;

  /// Kanban column width — `min-width:150px`.
  static const double kanbanColumnMinWidth = 150;

  /// Kanban column header's gap above its first card — `margin-bottom:10px`.
  static const double kanbanColumnHeaderGap = 10;

  /// Kanban column-color dot — `width/height:8px`.
  static const double kanbanDotSize = 8;

  /// Kanban card's left color spine — `width:3px`.
  static const double kanbanCardSpineWidth = 3;

  // ---------------------------------------------------------------------
  // PIN keypad (Story 2.2) — prototype-extract.md §6 names the "PIN
  // keypad" component (digits 0–9 + backspace, progress dots above) and
  // UX-DR14 gives its behavior, but neither gives pixel values — decided
  // here (Design Notes) rather than left hardcoded in the widget.
  // ---------------------------------------------------------------------

  /// Each digit/backspace button — a circle at least UX-DR23's 44pt tap
  /// target, with headroom for a comfortable thumb target on a 390pt-wide
  /// frame hosting a 3-column grid.
  static const double pinKeypadButtonSize = 64;

  /// Gap between keypad buttons, both axes.
  static const double pinKeypadGap = spacingMd;

  /// Backspace glyph (`Icons.backspace_outlined` — no new icon-font
  /// dependency, same approximation rationale as [dialogIconSize]).
  static const double pinKeypadBackspaceIconSize = 24;

  /// Progress-dot diameter (4 dots above the grid, one per digit).
  static const double pinProgressDotSize = 12;

  /// Gap between progress dots — `cerne-prototype.html`'s Tela 0.1b/c dots
  /// row is `gap:14px`, not on the 4dp spacing scale (corrected from the
  /// previous [spacingSm], Story 2.2 correction).
  static const double pinProgressDotGap = 14;

  /// Progress-dot border width — every dot (filled or not) keeps a
  /// [colorPrimary] outline per the prototype's `border:1.5px solid
  /// #1F3D34`; same weight as [borderWidthEmphasis].
  static const double pinProgressDotBorderWidth = borderWidthEmphasis;

  /// PIN error band icon size — `ph-warning-circle`, `font-size:14px` in
  /// the prototype's Tela 0.1c error band (Story 2.2 correction).
  static const double pinErrorBandIconSize = 14;

  /// PIN error band's icon-text gap — `gap:6px`, not on the 4dp scale.
  static const double pinErrorBandIconGap = 6;

  /// PIN error band's own padding — `padding:8px 12px`; vertical matches
  /// [spacingSm], horizontal (12) isn't on the existing scale.
  static const EdgeInsets pinErrorBandPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: spacingSm,
  );

  /// Tela 0.1b/c's own screen padding — `padding:120px 32px 40px`, top-
  /// aligned (not centered) unlike the generic [screenPadding]; 120 clears
  /// the status bar + breathing room above the title, 40 isn't on the
  /// existing scale.
  static const EdgeInsets pinScreenPadding = EdgeInsets.fromLTRB(
    spacingXl,
    120,
    spacingXl,
    40,
  );

  /// Review finding (story 2.4) — small inline spinner shown next to the
  /// Configurações biometric toggle while a `PATCH /account/settings`
  /// call is in flight (RNF01: a loading indicator for calls over
  /// 300ms), not named anywhere in prototype-extract.md since this
  /// control didn't exist in the prototype.
  static const double accountSettingsSavingIndicatorSize = 20;

  /// [accountSettingsSavingIndicatorSize]'s own stroke width — thinner
  /// than the default 4.0 so it reads cleanly at this small a size.
  static const double accountSettingsSavingIndicatorStrokeWidth = 2;

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

  /// Outer content padding for a single-column form screen (Tela 0.1a's
  /// login/signup, Story 1.3).
  static const EdgeInsets screenPadding = EdgeInsets.all(spacingLg);

  /// Confirmation-dialog card's horizontal distance from the screen edges
  /// (Story 1.5) — `left:20px;right:20px` in the overlay's markup
  /// (prototype-extract.md's "Sessão expirada" block).
  static const EdgeInsets dialogScreenMargin = EdgeInsets.symmetric(
    horizontal: 20,
  );

  /// Confirmation-dialog card's own internal padding (Story 1.5) —
  /// `padding:24px 20px` in the same markup: vertical matches [spacingLg],
  /// but the horizontal axis (20) isn't on the existing scale.
  static const EdgeInsets dialogCardPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: spacingLg,
  );

  /// Shared app-shell header padding (Story 1.6) — Home/Chat's dark-green
  /// header and every back-arrow header's `padding:59px 16px 16px`; 59
  /// clears the status bar in the prototype's fixed frame and isn't on the
  /// 4dp spacing scale.
  static const EdgeInsets navHeaderPadding = EdgeInsets.fromLTRB(
    spacingMd,
    59,
    spacingMd,
    spacingMd,
  );

  /// Drawer's own outer content padding — `padding:59px 16px 24px`.
  static const EdgeInsets drawerContentPadding = EdgeInsets.fromLTRB(
    spacingMd,
    59,
    spacingMd,
    spacingLg,
  );

  /// Drawer header row's bottom padding, above its `border-bottom` —
  /// `padding-bottom:16px`.
  static const EdgeInsets drawerHeaderPadding = EdgeInsets.only(
    bottom: spacingMd,
  );

  /// Drawer's own nav items (Meus Registros/Planos de Ação/Configurações) —
  /// `padding:10px 4px`; 10 isn't on the 4dp scale.
  static const EdgeInsets drawerNavItemPadding = EdgeInsets.symmetric(
    horizontal: 4,
    vertical: 10,
  );

  /// Drawer's "Novo Chat" filled action — `padding:10px 12px`.
  static const EdgeInsets drawerPrimaryActionPadding = EdgeInsets.symmetric(
    horizontal: spacingSm + 4,
    vertical: 10,
  );

  /// Top padding of the drawer's second, static-nav section (Meus
  /// Registros/Planos de Ação/Configurações), below its own `border-top`
  /// divider — `border-top:1px solid #E1DACB;padding-top:12px` (code
  /// review, Story 1.6) in the drawer markup's second block, distinct from
  /// the scrollable first block holding "Novo Chat" (ground truth:
  /// `cerne-prototype.html`'s `<!-- OVERLAY: Drawer -->` block).
  static const EdgeInsets drawerSectionDividerPadding = EdgeInsets.only(
    top: 12,
  );

  /// Kanban board's scrollable row padding — `padding:0 16px 16px`.
  static const EdgeInsets kanbanBoardPadding = EdgeInsets.fromLTRB(
    spacingMd,
    0,
    spacingMd,
    spacingMd,
  );

  /// Kanban card's own padding — `padding:12px 12px 12px 18px` (extra left
  /// clears the card's own color spine).
  static const EdgeInsets kanbanCardPadding = EdgeInsets.fromLTRB(
    18,
    spacingSm + 4,
    spacingSm + 4,
    spacingSm + 4,
  );
}
