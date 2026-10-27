---
name: Cerne
description: Reflective-journaling companion. Warm paper-and-ink identity, one deliberate accent, zero clinical framing. Light mode only — faithful to the frozen prototype.
status: final
updated: 2026-10-26
sources:
  - docs/input/prototype/prototype-extract.md
  - docs/input/prototype/cerne-prototype.html
colors:
  colorPrimary: '#1F3D34'
  colorPrimaryPressed: '#16281F'
  colorOnPrimary: '#F5F1E8'
  colorAccent: '#C98A3E'
  colorOnAccent: '#241C0D'
  colorSecondary: '#7C8B6F'
  colorSurfaceBg: '#F2EFE7'
  colorSurfaceElevated: '#FBF9F4'
  colorBorder: '#E1DACB'
  colorTextPrimary: '#241F19'
  colorTextSecondary: '#6B6255'
  colorError: '#B3402A'
  colorSuccess: '#4C6B4F'
  colorWarningSync: '#C98A3E'
  colorInfoOffline: '#5C7A93'
  colorChatBubbleUser: '#D9DFD3'
  colorOnCategoryChip: '#3F4A38'
typography:
  textDisplayLg:
    fontFamily: Fraunces
    fontWeight: 600
    fontSize: 32px
    lineHeight: 38px
  textHeadlineMd:
    fontFamily: Fraunces
    fontWeight: 600
    fontSize: 24px
    lineHeight: 30px
  textTitleLg:
    fontFamily: Karla
    fontWeight: 700
    fontSize: 20px
    lineHeight: 26px
  textTitleSm:
    fontFamily: Karla
    fontWeight: 700
    fontSize: 16px
    lineHeight: 22px
  textBodyLg:
    fontFamily: Karla
    fontWeight: 400
    fontSize: 16px
    lineHeight: 24px
  textBodyMd:
    fontFamily: Karla
    fontWeight: 400
    fontSize: 14px
    lineHeight: 20px
  textLabelMd:
    fontFamily: Karla
    fontWeight: 500
    fontSize: 13px
    lineHeight: 18px
  textMonoCaption:
    fontFamily: IBM Plex Mono
    fontWeight: 500
    fontSize: 12px
    lineHeight: 16px
    letterSpacing: 0.2px
rounded:
  radiusSm: 8dp
  radiusMd: 16dp
  radiusLg: 24dp
  radiusFull: 999dp
spacing:
  spacingXs: 4dp
  spacingSm: 8dp
  spacingMd: 16dp
  spacingLg: 24dp
  spacingXl: 32dp
  spacing2xl: 48dp
components:
  button-primary:
    background: '{colors.colorPrimary}'
    backgroundPressed: '{colors.colorPrimaryPressed}'
    backgroundDisabled: '{colors.colorBorder}'
    text: '{colors.colorOnPrimary}'
    textDisabled: '{colors.colorTextSecondary}'
    textStyle: '{typography.textLabelMd}'
    radius: '{rounded.radiusSm}'
  button-secondary:
    border: '{colors.colorPrimary}'
    text: '{colors.colorPrimary}'
    textStyle: '{typography.textLabelMd}'
    background: transparent
    radius: '{rounded.radiusSm}'
  button-text:
    text: '{colors.colorPrimary}'
    textMuted: '{colors.colorTextSecondary}'
    textStyle: '{typography.textLabelMd}'
  text-field:
    background: '{colors.colorSurfaceElevated}'
    border: '{colors.colorBorder}'
    borderFocused: '{colors.colorPrimary}'
    borderFocusedWidth: 1.5px
    borderError: '{colors.colorError}'
    radius: '{rounded.radiusSm}'
    textStyle: '{typography.textBodyLg}'
  chat-bubble-user:
    background: '{colors.colorChatBubbleUser}'
    text: '{colors.colorTextPrimary}'
    textStyle: '{typography.textBodyLg}'
    radius: '{rounded.radiusMd}'
    squareCorner: bottom-right
  chat-bubble-ai:
    background: '{colors.colorSurfaceElevated}'
    text: '{colors.colorTextPrimary}'
    textStyle: '{typography.textBodyLg}'
    radius: '{rounded.radiusMd}'
    squareCorner: bottom-left
    elevation: 0 1px 3px rgba(36,31,25,.08)
  insight-card:
    spine: '{colors.colorAccent}'
    label: INSIGHT
    labelStyle: '{typography.textMonoCaption}'
    background: '{colors.colorSurfaceElevated}'
    radius: '{rounded.radiusMd}'
  bookmark-button:
    idle: outline, color '{colors.colorTextSecondary}'
    saving: spinner, color '{colors.colorTextSecondary}'
    saved: check, color '{colors.colorAccent}'
    error: warning, color '{colors.colorError}'
  sync-badge:
    synced: dot, color '{colors.colorSuccess}'
    synchronizing: dot, color '{colors.colorWarningSync}'
    error: dot, color '{colors.colorError}'
  banner-offline:
    background: '{colors.colorInfoOffline}'
    text: '{colors.colorOnPrimary}'
    icon: ph-wifi-slash
  banner-send-error:
    background: rgba(179,64,42,.08)
    text: '{colors.colorError}'
    icon: ph-warning-circle
  record-card:
    background: '{colors.colorSurfaceElevated}'
    radius: '{rounded.radiusMd}'
    elevation: 0 1px 3px rgba(36,31,25,.08)
    spineManual: '{colors.colorPrimary}'
    spineAudio: olive-green
    spinePhoto: gray
    spineChat: '{colors.colorAccent}'
  filter-chip:
    background: '{colors.colorSecondary}'
    text: '{colors.colorOnCategoryChip}'
    radius: '{rounded.radiusFull}'
    textStyle: '{typography.textLabelMd}'
  search-bar:
    background: '{colors.colorSurfaceElevated}'
    border: '{colors.colorBorder}'
    radius: '{rounded.radiusSm}'
    text: '{colors.colorTextPrimary}'
    placeholder: '{colors.colorTextSecondary}'
    icon: ph-funnel
  filter-sheet:
    background: '{colors.colorSurfaceElevated}'
    radius: '{rounded.radiusLg}'
    elevation: 0 4px 16px rgba(36,31,25,.14)
    groupLabelStyle: '{typography.textMonoCaption}'
  tab-bar:
    background: '{colors.colorSurfaceElevated}'
    activeBackground: '{colors.colorPrimary}'
    activeText: '{colors.colorOnPrimary}'
    inactiveText: '{colors.colorTextSecondary}'
    textStyle: '{typography.textLabelMd}'
  audio-waveform:
    activeColor: '{colors.colorError}'
    frozenOpacity: 0.35
    timerStyle: '{typography.textMonoCaption}'
  avatar:
    background: '{colors.colorPrimary}'
    text: '{colors.colorOnPrimary}'
    radius: '{rounded.radiusFull}'
    sizeMenu: 40px
    sizeSettings: 52px
  export-sheet:
    background: '{colors.colorSurfaceElevated}'
    radius: '{rounded.radiusLg}'
    elevation: 0 4px 16px rgba(36,31,25,.14)
  confirmation-dialog:
    background: '{colors.colorSurfaceElevated}'
    scrim: rgba(36,31,25,.4)
    radius: '{rounded.radiusLg}'
    titleNeutral: '{colors.colorTextPrimary}'
    titleDestructive: '{colors.colorError}'
  skeleton:
    background: '{colors.colorBorder}'
    shimmer: '{colors.colorSurfaceElevated}'
    showAfter: 300ms
---

> **[ASSUMPTION]** Color/typography/spacing/radius token *names* intentionally mirror `docs/input/prototype/prototype-extract.md` section 3 verbatim (camelCase, not the spec's conventional kebab-case) rather than being re-cased, so this file maps 1:1 to the eventual `lib/core/design_tokens.dart` constants with zero translation step. Elevation values are inlined as literal shadow strings inside `components` (matching `elevation1`/`elevation2` below) rather than cross-referenced, since the DESIGN.md spec's frontmatter token categories don't include an `elevation` path.

## Brand & Style

Cerne reads as a paper journal, not a productivity tool. The palette is forest-and-ink: a deep green (`colorPrimary`, `#1F3D34`) anchors every structural surface — app bar, primary buttons, wordmark — the color of a leather journal cover, not a corporate brand blue. The canvas underneath (`colorSurfaceBg` `#F2EFE7`, `colorSurfaceElevated` `#FBF9F4`) is warm paper, never clinical white. One accent — ochre (`colorAccent`, `#C98A3E`) — is the single chromatic signal in the entire system, reserved for the three moments the product wants the user to notice: a proactive insight, a saved bookmark, a primary call-to-action. Everything else stays in the green/paper/ink register.

Typography carries the same editorial intent: `Fraunces` (a serif with visible character) is reserved for the two moments that deserve weight — the splash wordmark and section headlines — while `Karla` (a clean grotesque) carries every working UI surface, and `IBM Plex Mono` marks anything that is data rather than prose (timestamps, counters, status labels), the way a ledger distinguishes dates from narrative.

The product is explicitly **not** a mental-health or clinical tool (`docs/input/requirements.md` RF05, known-limitation note). Nothing in the visual system should borrow clinical signifiers — no stethoscope-blue, no checklist-green, no alarmist red beyond the one error token used sparingly. The identity is "quiet companion with a notebook," not "app for a diagnosis."

## Colors

- **`colorPrimary` / `colorPrimaryPressed`** — the structural green. App bar, primary buttons, the splash wordmark. Pressed state is a darker shade of the same hue, never a different color — reinforces "same surface, pushed in."
- **`colorOnPrimary`** — warm off-white text/icon color on any green surface. Never pure white.
- **`colorAccent` / `colorOnAccent`** — ochre, the system's only decorative color. Used exclusively for: the insight-card spine, the saved-bookmark check, and primary CTAs that need to stand out from the structural green (e.g., "Baixar PDF"). Never used for navigation, never for more than one element on screen at a time.
- **`colorSecondary`** — sage green. Tags, chips, the "synchronizing" badge dot. A quieter, desaturated cousin of the primary — present but not asking for attention.
- **`colorSurfaceBg` / `colorSurfaceElevated`** — two tones of warm paper. `Bg` is the canvas; `Elevated` is anything that sits on top of it (cards, bubbles, sheets) — the only separation device besides `elevation1`/`elevation2`, never a hard border.
- **`colorBorder`** — the only line-weight gray. Dividers, input borders, disabled-button fill. Kept at low contrast on purpose — a divider is punctuation, not a wall.
- **`colorTextPrimary` / `colorTextSecondary`** — ink, full and half-strength. Primary for anything the user wrote or needs to read; secondary for metadata and supporting text.
- **`colorError`** — a muted brick red, not a siren red. Used for destructive actions, validation, and failure states — but deliberately desaturated to avoid an alarmist tone in a journaling context.
- **`colorSuccess`** — reuses the sage-adjacent dark green family for "synchronized" and confirmations. Success is quiet, not celebratory (no bright green, no confetti-adjacent hue).
- **`colorWarningSync`** — literally the same hex as `colorAccent`. The "synchronizing" badge intentionally borrows the accent rather than introducing a fourth warm hue — a transient, benign state shares the visual register of "something good is happening," not alarm.
- **`colorInfoOffline`** — a single-use blue-gray, the only cool color in the system. Reserved for the offline banner alone, so its appearance is unambiguous: this color means "no connection," nowhere else.
- **`colorChatBubbleUser`** — a pale sage, distinguishing the user's own words from the AI's ivory bubble without introducing a new hue family.

**Avoid:** using `colorError` for anything short of a real failure — the muted tone depends on rarity to still read as serious. (Accent/offline-color misuse and the extension-screen placeholder rule are covered once, in **Do's and Don'ts**, rather than restated here.)

## Typography

Two families carry meaning; the third carries data:

- **`Fraunces`** (`textDisplayLg`, `textHeadlineMd`) — the only serif, the only place personality shows through letterforms. Splash wordmark and section titles only. Never body text, never a button label.
- **`Karla`** (`textTitleLg` through `textLabelMd`) — every working surface: app-bar titles, chat bubbles, entries, buttons, chips, descriptions. The weight ramp (700 → 400 → 500) carries hierarchy, not size alone.
- **`IBM Plex Mono`** (`textMonoCaption`) — exclusively technical metadata: timestamps, audio counters ("00:12"), sync-status labels. Monospace reads as "machine-reported fact," which is exactly the register a timestamp or a counter should carry, distinct from anything the user or the AI composed.

Dynamic type is honored at every level (see **Accessibility Floor** in `EXPERIENCE.md`) — no UI value is hardcoded outside `design_tokens.dart` per RNF08, and no control should truncate or clip at the largest accessibility text size.

## Layout & Spacing

4dp grid throughout: `spacingXs` (4) for the tightest relationships (icon-to-label), up to `spacing2xl` (48) between fully unrelated sections. Frame is fixed at 390×844 logical points, portrait only, single column — there is no tablet or landscape layout to reconcile against (`docs/input/requirements.md` section 13: "Platform: iOS, portrait only").

Overlays stack **at most one level deep**: a bottom sheet or dialog sits on a darkened scrim over exactly one base screen (Home/Chat, Meus Registros, or Configurações). No overlay opens another overlay on top of itself — the insertion modal's three tabs are internal states of one sheet, not nested sheets.

## Elevation & Depth

Two tokens only, both soft and low-contrast — this is a paper surface, not a glossy one:

- **`elevation1`** — `0 1px 3px rgba(36,31,25,.08)`. Resting cards, chat bubbles, record cards. A hint of lift, nothing dramatic.
- **`elevation2`** — `0 4px 16px rgba(36,31,25,.14)`. Sheets and modals only — the one visual cue, together with the scrim, that something is temporarily on top of the normal flow.

Nothing else carries elevation. Hierarchy between a card and its background comes primarily from the `colorSurfaceBg` / `colorSurfaceElevated` tonal step, with shadow as a secondary, minimal reinforcement.

## Shapes

- **`radiusSm`** (8dp) — inputs, chips. The smallest, most utilitarian corner.
- **`radiusMd`** (16dp) — cards, chat bubbles. Each bubble additionally squares off exactly one corner (bottom-right for the user, bottom-left for the AI) — the one place the system breaks a uniform radius, as the deliberate speech-bubble "tail" substitute.
- **`radiusLg`** (24dp) — sheets and modals — the largest radius, reinforcing "this is a different layer of the UI," paired with `elevation2`.
- **`radiusFull`** (999dp) — avatars and pills (filter chips) only.

## Components

- **Buttons** — primary (filled `colorPrimary`, darkens to `colorPrimaryPressed`), secondary (outline, no fill, for "Tentar novamente" / "Cancelar" / "Baixar dados brutos"), text/ghost (no chrome at all, for mode-toggle links and "Fechar" / "Limpar"). Disabled state is always `colorBorder` background with `colorTextSecondary` text — never a dimmed opacity of the active state.
- **Chat bubbles** — user (sage, square bottom-right) vs. AI (ivory, `elevation1`, square bottom-left, shadow present because it sits on the paper canvas the same way a sticky note would). Streaming state adds a blinking cursor at the text's end; no other visual change while generating.
- **Insight card** — ochre spine on the left edge, mono "INSIGHT" label, dismiss "x." The spine color is the only accent-colored element inside the chat stream — it must stand out against both bubble colors.
- **Bookmark button** — four states on every user message: idle (outline), saving (spinner), saved (ochre check — the second of the system's two accent uses), error (red warning). State is carried by icon + color together, never color alone (see Accessibility Floor).
- **Record card** — spine colored by origin: manual = `colorPrimary` (dark green), audio = olive green, photo = gray, chat = `colorAccent`. The spine is the *only* place color encodes a data dimension (entry source) rather than a UI state — keep it that way; don't reuse spine coloring logic for anything else.
- **Sync badge** — a small dot, not a pill or label by default: green/ochre/red for synced/synchronizing/error. Color is reinforced by an accessible label on tap or long-focus (see Accessibility Floor) since dot color alone is not sufficient signal.
- **Filter chip** — sage background, dark-olive text (`colorOnCategoryChip`), fully rounded. Single-choice (date range) and multi-choice (category, type) look identical; the difference is behavioral, not visual (see `EXPERIENCE.md`).
- **Search bar** — paper-elevated input with a trailing funnel icon button; same visual family as `text-field` but permanently docked at the top of Meus Registros, never submitted with a button.
- **Filter sheet** — a `radiusLg`/`elevation2` sheet, same surface language as any other bottom sheet; groups are labeled in `textMonoCaption` (treated as metadata about the list, not prose).
- **Tab bar** (insertion modal) — three equal-width segments; the active segment alone gets a filled `colorPrimary` background, the other two stay transparent with secondary-colored text.
- **Audio waveform** — animated bars in the structural palette while recording; frozen at 35% opacity while processing — the opacity drop alone communicates "this is no longer live," no additional label needed over the "Transcrevendo..." text.
- **Avatar** — solid `colorPrimary` circle, 1–2 uppercase initials in `colorOnPrimary`, two fixed sizes (40px menu, 52px Settings). No photo avatars anywhere in the product. In Configurações, the pencil icon beside the editable name/e-mail becomes a check icon in edit mode — the only place an icon itself changes meaning rather than just color.
- **PIN keypad** — numeric 3×4 grid + backspace, progress dots above, all in the structural palette (no accent color on digits).
- **Export sheet** — the heaviest surface after a full-screen modal (`radiusLg` + `elevation2`), since it carries a multi-stage async job.
- **Confirmation dialog** — neutral title (`colorTextPrimary`) for session expiry, red title (`colorError`) for destructive deletion — the title color is the only signal distinguishing "routine interruption" from "irreversible action," so it must never be muted.
- **Skeleton** — shown only past the 300ms loading-indicator threshold (RNF01); appears as a `colorBorder`-toned shimmer, never a spinner, for content (not action) loading.

## Do's and Don'ts

| Do | Don't |
|---|---|
| Keep `colorAccent` to its two canonical uses (insight spine, saved bookmark) plus primary CTAs that need emphasis | Use the accent decoratively, or add a second chromatic accent |
| Pull every color/type/space/radius value from `design_tokens.dart` (RNF08) | Hardcode a hex, font size, or dp value anywhere in a widget |
| Style extension screens (Planos de Ação, persona cards) with full visual polish | Mark unimplemented features with a visibly "unfinished" or grayed-out treatment |
| Pair every state color with an icon or label (bookmark, sync badge) | Encode state (saved / error / synchronizing) in color alone |
| Keep `Fraunces` for display/headline only | Set body text, buttons, or labels in `Fraunces` |
| Treat `colorInfoOffline` as single-use (offline banner only) | Reuse the offline blue-gray for any other informational banner |
| Ship one light theme, faithful to the prototype's single palette | Add a dark-mode variant not present in the frozen Design Tokens panel |
