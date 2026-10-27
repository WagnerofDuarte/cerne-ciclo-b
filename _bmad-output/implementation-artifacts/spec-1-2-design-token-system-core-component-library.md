---
title: 'Story 1.2: Design Token System & Core Component Library'
type: 'feature'
created: '2026-10-27'
status: 'done'
review_loop_iteration: 0
baseline_commit: '164e1d259a206420d612c5378adf74fefa72772c'
context:
  - '{project-root}/_bmad-output/implementation-artifacts/epic-1-context.md'
  - '{project-root}/docs/input/prototype/prototype-extract.md'
  - '{project-root}/_bmad-output/planning-artifacts/architecture/architecture-cerne-ciclo-b-2026-10-26/ARCHITECTURE-SPINE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `lib/core/design_tokens.dart` is a typed stub (Story 1.1), and no shared, reusable UI widgets exist yet; Stories 1.3, 1.5 and 1.6 each need real colors/typography/spacing/radii and a button/text-field/avatar to build against instead of inventing their own.

**Approach:** Implement `design_tokens.dart` verbatim from `docs/input/prototype/prototype-extract.md` §3, bundle the three prototype type families as static font assets, and build the three cross-feature widgets the epic names as consumed downstream (button variants, text field, avatar) in a new `lib/core/widgets/` location.

## Boundaries & Constraints

**Always:**
- Every color/typography/spacing/radius/elevation value in `design_tokens.dart` matches `prototype-extract.md` §3 verbatim; nothing is redefined or hardcoded elsewhere (RNF08).
- Disabled buttons render `colorBorder` background + `colorTextSecondary` text, never dimmed opacity; text fields expose default/focused(`colorPrimary`, 1.5px)/error(`colorError`) border states.
- Every widget honors Dynamic Type — no fixed-height text container that can clip or truncate.
- `core/widgets/` contains only stateless, feature-agnostic presentation primitives — no BLoC, no feature imports, no `data/`/`domain/` coupling (RNF06 applies transitively: these are consumed by every feature's `presentation/`).

**Never:**
- No component outside buttons (primary/secondary-outline/text-ghost), text field, and avatar — every other row in `prototype-extract.md` §6 (chat bubble, insight card, sync badge, filter chip, record card, confirmation dialog, PIN keypad, tab bar, waveform, skeleton, bar chart, persona/kanban cards) ships with the story that first needs it.
- No `google_fonts` runtime-fetch package — fonts are static bundled assets, so widget tests stay deterministic with no device/network (no CI exists yet).
- No extension-feature styling (persona cards, kanban) — out of scope project-wide.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Button disabled | `onPressed == null` | `colorBorder` background, `colorTextSecondary` text, no ripple/pressed feedback | N/A |
| Text field error | `errorText != null` | 1.5px `colorError` border, error text shown below field | N/A |
| Dynamic Type max scale | System text-scale increased | Label wraps/grows; never clips or truncates | N/A |

</frozen-after-approval>

## Code Map

- `lib/core/design_tokens.dart` -- placeholder stub to replace with real `colors`/`typography`/`spacing`/`radii`/`elevation` constants (currently just a doc comment pointing here).
- `docs/input/prototype/prototype-extract.md` §3 (tokens) and §6 (component table) -- read-only ground truth for every literal value and the exact variations each widget must support.
- `pubspec.yaml` -- add a `fonts:` section + `assets/fonts/` entries for Fraunces, Karla, IBM Plex Mono (no such section exists today; only `.env` is declared as an asset).
- `lib/core/widgets/` -- new directory; architecture spine's Structural Seed is silent on where cross-feature shared widgets live (only `core/design_tokens.dart` is named) — decided here per AGENTS.md's "decide and proceed" policy, analogous placement to `core/design_tokens.dart`.
- `_bmad-output/implementation-artifacts/epic-1-context.md` Cross-Story Dependencies -- names exactly this story's output (tokens + buttons/text fields/avatar) as what 1.3/1.5/1.6 consume; do not expand scope beyond it.
- `_bmad-output/implementation-artifacts/spec-1-1-project-scaffold-stack-integration-core-infrastructure.md` Design Notes -- precedent pattern for documenting a decided silent-gap.

## Tasks & Acceptance

**Execution:**
- [x] `lib/core/design_tokens.dart` -- implement real color/typography/spacing/radii/elevation constants verbatim from `prototype-extract.md` §3 -- RNF08 single source of truth
- [x] `assets/fonts/*` + `pubspec.yaml` -- bundle Fraunces/Karla/IBM Plex Mono as static font assets -- deterministic text rendering with no device/CI
- [x] `lib/core/widgets/app_button.dart` -- primary, secondary (outline), text (ghost) variants with the disabled-state rule -- consumed by 1.3/1.5/1.6
- [x] `lib/core/widgets/app_text_field.dart` -- default/focused/error border states -- consumed by 1.3
- [x] `lib/core/widgets/avatar.dart` -- initials circle, 40px and 52px size variants -- consumed by 1.6 and Epic 8
- [x] `test/core/widgets/app_button_test.dart`, `app_text_field_test.dart`, `avatar_test.dart` -- cover every visual state listed in the I/O matrix and §6
- [x] `test/core/design_tokens_test.dart` -- spot-check token values against `prototype-extract.md` §3

**Acceptance Criteria:**
- Given any token category, when read from `design_tokens.dart`, then its value matches `prototype-extract.md` §3 verbatim.
- Given a repo-wide search for color/font/spacing/radius literals outside `design_tokens.dart`, then none exist (RNF08).
- Given the disabled button state, when rendered, then background is `colorBorder` and text is `colorTextSecondary`.
- Given the text field error state, when rendered, then the border is 1.5px `colorError`.
- Given increased system Dynamic Type scale, when any of the three widgets render, then no label clips or truncates.

## Spec Change Log

- **Review round 1 (patch findings, no spec-level change):** three parallel reviews (blind-hunter, edge-case-hunter, verification-gap) surfaced 6 distinct patchable gaps, all fixed in place: (1) added a `DesignTokens — layout insets` test group for `buttonPadding`/`textFieldContentPadding`/`avatarInitialsPadding`, previously untested; (2) added a `side.resolve({disabled})` assertion to `AppButton`'s secondaryOutline disabled test; (3) `AppButton.secondaryOutline`'s `BorderSide` now passes `width: DesignTokens.borderWidthDefault` explicitly instead of silently falling back to Flutter's default (RNF08 literal bypass); (4) documented the button-corner-radius decision below (was undocumented); (5) corrected `AppTextField.errorText`'s doc comment, which overstated the contract ("non-null and non-empty") beyond the frozen spec's actual `errorText != null` condition; (6) added `radiusSm` assertions to the `AppButton` primary and `AppTextField` default-state tests. Rejected as non-issues: `textColor` no-op on non-ghost variants (documented by design), `Avatar` empty-initials fallback (caller's responsibility per its own doc), missing pressed-overlay on secondary/ghost (prototype never defines one), barrel file/a11y/form-hooks suggestions (deferred or out of scope, see `deferred-work.md`).

## Design Notes

Gaps silent in all planning docs, decided here per AGENTS.md's "decide and proceed" policy:
- **Shared widget location:** `lib/core/widgets/` — the Structural Seed only names `core/design_tokens.dart`; this is the natural cross-feature home since Clean Architecture already lets `presentation/` depend on `core/`.
- **Font sourcing:** static `.ttf` files committed under `assets/fonts/` and declared in `pubspec.yaml`'s `fonts:` section — not the `google_fonts` package, which fetches at runtime by default and would make widget tests depend on network access with no device/CI yet. Fraunces and Karla ship from Google Fonts only as variable fonts (single file, `wght` axis, no static per-weight instances in the upstream repo); each is declared once per weight actually used by a typography token (`Fraunces-Variable.ttf` at weight 600; `Karla-Variable.ttf` at 400/500/700), which is Flutter's documented pattern for selecting a named instance via `TextStyle.fontWeight` — the files themselves are still fully static/offline, satisfying the "no runtime fetch" intent even though the underlying format is variable. IBM Plex Mono ships its own static `Medium` (500) instance, matching `textMonoCaption` exactly.
- **Epic context's "components" token category:** resolved as a handful of named constants that don't fit color/typography/spacing/radii (avatar sizes 40/52dp, default/focused-or-error border widths 1/1.5dp) — still declared inside `design_tokens.dart`, just grouped for readability.
- **Two colors named in prototype-extract.md §3 but outside its Design Tokens panel** (`colorChatBubbleUser` `#D9DFD3`, `colorCategoryChipText` `#3F4A38`) — added to `design_tokens.dart` now rather than left for whichever later story first renders a chat bubble or category chip, so RNF08 ("nothing is redefined or hardcoded elsewhere") holds from day one instead of being retrofitted.
- **Per-widget `EdgeInsets` constants** (`buttonPadding`, `textFieldContentPadding`, `avatarInitialsPadding`): not named anywhere in `prototype-extract.md` §3, but required so `lib/core/widgets/*.dart` never constructs `EdgeInsets.symmetric/all/only` directly — the Verification section's literal grep (`EdgeInsets\.(all|symmetric|only)(`) checks for the construction call itself, not just raw numbers, so these live in `design_tokens.dart` too, built from the existing spacing scale.
- **Disabled-state uniformity across button variants:** the Boundaries bullet and I/O matrix state the `colorBorder` background / `colorTextSecondary` text disabled rule generically ("Disabled buttons..."), and §6's component table only spells it out for the primary variant. Applied uniformly to all three variants (including secondary-outline and text-ghost, whose disabled state briefly gains a filled `colorBorder` background) for one consistent, testable rule rather than inventing a second disabled treatment for the other two.
- **Avatar vs. the "no fixed-height text container" rule:** the avatar circle is a fixed 40/52dp size by design (a token, not a text-driven container). It wraps its initials in a `FittedBox(fit: BoxFit.scaleDown)` so at extreme Dynamic Type scales the initials shrink to fit rather than clip or truncate — satisfying the letter of "never clips or truncates" without growing the circle itself.
- **Button corner radius:** `radiusSm` (8dp), applied to all three `AppButton` variants. `prototype-extract.md` §3's Radii section only names "inputs, chips" for `radiusSm` and never assigns a radius to buttons by name — buttons are the closest analog in size and visual weight to chips/inputs, so `radiusSm` was chosen over introducing an undocumented new radius value.
- **Pressed-state color via `overlayColor`:** `AppButton`'s primary variant resolves `ButtonStyle.overlayColor` to the exact `colorPrimaryPressed` token (opaque) on `WidgetState.pressed`, rather than relying on Material's default semi-transparent overlay tint — keeps the pressed color exact and avoids an unintended "dimmed opacity" look.

## Verification

**Commands:**
- `fvm flutter pub get` -- resolves with the new font assets declared, no conflicts
- `fvm flutter test` -- all new token/widget tests pass
- `fvm flutter analyze` -- zero issues
- `grep -rn "Color(0x\|fontSize:\|EdgeInsets\.\(all\|symmetric\|only\)(" lib --include=*.dart | grep -v "core/design_tokens.dart"` -- expected: no matches (RNF08 literal check)

## Suggested Review Order

**Design tokens (RNF08 single source)**

- Entry point: every color/typography/spacing/radii/elevation constant, transcribed verbatim from the prototype panel.
  [`design_tokens.dart:10`](../../lib/core/design_tokens.dart#L10)
- "Components" and "Layout insets" groups are the two categories the prototype leaves unnamed — decided here, documented below.
  [`design_tokens.dart:195`](../../lib/core/design_tokens.dart#L195)
- Font assets bundled statically (not `google_fonts`) so widget tests stay deterministic with no device/CI.
  [`pubspec.yaml:106`](../../pubspec.yaml#L106)

**AppButton (shared primitive, three variants)**

- Variant switch — primary/secondaryOutline/textGhost share one disabled rule, diverge on fill/outline/ghost styling.
  [`app_button.dart:54`](../../lib/core/widgets/app_button.dart#L54)
- Patched post-review: `secondaryOutline`'s border now reads `borderWidthDefault` explicitly instead of silently defaulting to 1.0.
  [`app_button.dart:97`](../../lib/core/widgets/app_button.dart#L97)

**AppTextField (border states)**

- Default/focused/error borders resolved from tokens; patched post-review to correct a doc comment that overstated the error contract.
  [`app_text_field.dart:31`](../../lib/core/widgets/app_text_field.dart#L31)
- `errorMaxLines: null` — the Dynamic Type boundary: long error text wraps instead of truncating.
  [`app_text_field.dart:69`](../../lib/core/widgets/app_text_field.dart#L69)

**Avatar (fixed-size + Dynamic Type)**

- `FittedBox` shrinks initials to fit a fixed-size circle under extreme text scales, rather than growing the circle.
  [`avatar.dart:40`](../../lib/core/widgets/avatar.dart#L40)

**Tests (peripherals)**

- Token values spot-checked against the prototype extract, including the post-review layout-insets group.
  [`design_tokens_test.dart:1`](../../test/core/design_tokens_test.dart#L1)
- Every I/O-matrix row (disabled button, text-field error, Dynamic Type) covered per widget, plus the post-review disabled-border assertion.
  [`app_button_test.dart:1`](../../test/core/widgets/app_button_test.dart#L1)
- [`app_text_field_test.dart:1`](../../test/core/widgets/app_text_field_test.dart#L1)
- [`avatar_test.dart:1`](../../test/core/widgets/avatar_test.dart#L1)
