---
title: 'Story 4.3: Empty-State Handling'
type: 'feature'
created: '2026-11-05'
status: 'done'
review_loop_iteration: 0
context: []
baseline_commit: '526b6bf0085b1ff5c0f70f9d567833633caf5248'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Story 4.1 deliberately shipped `MeusRegistrosEmpty` with only plain "no entries yet" text and explicitly deferred a polished CTA to this story (FR-16) — a user with zero Entries currently has no path back to capture from this screen, only a static sentence.

**Approach:** Replace `_EmptyState`'s plain text with the prototype's dedicated empty state (Tela 4 — Vazio): notebook icon, "Nenhum registro ainda" copy, and a primary CTA button ("Criar primeiro registro") that opens the same Insertion Modal the Home/Chat "+" FAB already opens. No cubit/state changes — `MeusRegistrosCubit` already emits `MeusRegistrosEmpty` correctly (spec-4-2); this is presentation-only.

## Boundaries & Constraints

**Always:**
- Exact prototype markup (`cerne-prototype.html`'s Tela 4 — Vazio block): `ph-notebook` icon (88px, `colorBorder`) → `Icons.menu_book_outlined` (no icon-font dependency, same approximation convention as `DesignTokens.dialogIconSize`/`biometricIconSize`); text "Nenhum registro ainda" (`textBodyMd`/`colorTextSecondary`, exact prototype copy — no added period); CTA "Criar primeiro registro" as `AppButton(variant: AppButtonVariant.primary)` (bg `colorPrimary`/text `colorOnPrimary`/`radiusSm` already match the prototype's button exactly).
- New token `DesignTokens.entriesEmptyStateIconSize = 88` (RNF08 — no raw literal in the widget); gap between icon/text/button uses `DesignTokens.spacingMd` (prototype's `gap:16px`).
- CTA `onPressed` calls `InsertionModal.show(context, cubit: sl<TextEntryCubit>(), audioCubit: sl<AudioEntryCubit>(), photoCubit: sl<PhotoEntryCubit>())` — identical call shape to the Home/Chat FAB (`placeholder_screens.dart:97-102`), fresh factory-scoped cubits per tap. No explicit reload after the modal closes: a resulting capture flows through the shared `PendingEntryWriteTracker`, which `MeusRegistrosCubit` already subscribes to for its whole lifetime (spec-4-2) — it transitions out of `MeusRegistrosEmpty` on its own.
- `_EmptyState` stays the single widget both `MeusRegistrosEmpty()` and `_EntryList`'s `groups.isEmpty` fallback (malformed-`occurredAt` case, spec-4-1 review fix) render — no second empty-state implementation.

**Ask First:** none — scope is fully pinned by the prototype and spec-4-2's existing tracker wiring.

**Never:** any `MeusRegistrosCubit`/`MeusRegistrosState` change; a second way to open the Insertion Modal; an explicit `loadFirstPage()` re-call after the modal closes (the tracker overlay already handles it).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Zero entries, first load | `MeusRegistrosEmpty` emitted | Icon + "Nenhum registro ainda" + CTA render | N/A |
| CTA tapped | User taps "Criar primeiro registro" | Insertion Modal opens (Texto/Áudio/Foto tabs), same as Home FAB | N/A |
| Save from empty-state-opened modal | Capture succeeds | Modal closes; screen transitions to `MeusRegistrosLoaded` via the tracker's existing `confirmedWrites`/`pendingWrites` overlay (spec-4-2) — no new wiring | N/A |
| All entries have malformed `occurredAt` | `MeusRegistrosLoaded` but `groups.isEmpty` | Same `_EmptyState` (icon + text + CTA), not blank | N/A |

</frozen-after-approval>

## Code Map

- `lib/features/entries/presentation/screens/meus_registros_screen.dart:141-157` -- `_EmptyState` — replace plain `Text` with icon + text + `AppButton` CTA; add imports for `AppButton`, `InsertionModal`, the three capture cubits, and `sl`
- `lib/core/design_tokens.dart:266` (near `biometricIconCircleSize`) -- add `entriesEmptyStateIconSize = 88`
- `lib/core/widgets/app_button.dart` -- reuse `AppButton(variant: AppButtonVariant.primary)` as-is, no changes
- `lib/features/capture/presentation/widgets/insertion_modal.dart:63-68` -- `InsertionModal.show()` signature to call verbatim
- `lib/core/navigation/placeholder_screens.dart:96-107` -- the exact call shape to mirror (Home FAB)
- `lib/core/di/injection_container.dart` -- `sl` accessor, already registers `TextEntryCubit`/`AudioEntryCubit`/`PhotoEntryCubit` as factories
- `lib/features/entries/presentation/cubit/meus_registros_state.dart:23-27` -- `MeusRegistrosEmpty` doc comment referencing "no polished CTA — that's story 4.3" — update now that this story resolves it
- `test/features/entries/presentation/screens/meus_registros_screen_test.dart:250,271,296,573` -- update `'Nenhum registro ainda.'` assertions (drop the period to match exact prototype copy) and the now-obsolete "no polished CTA this story" test description (line ~262)
- `test/core/navigation/placeholder_screens_test.dart:169-202` -- the existing FAB-tap-opens-modal test pattern (fakes + `resetCoreDependencies()`) to mirror for the new CTA test

## Tasks & Acceptance

**Execution:**
- [x] `design_tokens.dart` -- add `entriesEmptyStateIconSize = 88` with a doc comment citing Tela 4 — Vazio's `ph-notebook` 88px icon
- [x] `meus_registros_screen.dart` -- rewrite `_EmptyState`: `Icon(Icons.menu_book_outlined, size: entriesEmptyStateIconSize, color: colorBorder)`, `SizedBox(height: spacingMd)`, `Text('Nenhum registro ainda', style: textBodyMd.copyWith(color: colorTextSecondary))`, `SizedBox(height: spacingMd)`, `AppButton(label: 'Criar primeiro registro', onPressed: () => InsertionModal.show(context, cubit: sl<TextEntryCubit>(), audioCubit: sl<AudioEntryCubit>(), photoCubit: sl<PhotoEntryCubit>()))`
- [x] `meus_registros_state.dart` -- update `MeusRegistrosEmpty`'s doc comment (drop the forward reference to this now-complete story)
- [x] `meus_registros_screen_test.dart` -- update the 4 existing `'Nenhum registro ainda.'` assertions to the no-period copy; rename/update the "no polished CTA this story" test; add a test asserting the icon + CTA button render in the empty state; add a test (mirroring `placeholder_screens_test.dart`'s fakes) that tapping the CTA opens the Insertion Modal (asserts `find.text('Texto')`/`'Áudio'`/`'Foto'`)

**Acceptance Criteria:**
- [x] Given zero Entries, when Meus Registros loads, then a dedicated empty state renders (icon, copy, CTA) — never a blank list or plain-text-only state.
- [x] Given the empty state, when the user taps "Criar primeiro registro", then the Insertion Modal opens, identical to the Home/Chat "+" FAB's own modal.

### Review Findings

- [x] [Review][Patch] `_EmptyState`'s container uses uniform `DesignTokens.screenPadding` (24px all sides) instead of the prototype's exact `padding:64px 24px` for the Tela 4 — Vazio block, half the intended vertical breathing room above/below the icon+copy+CTA group — deviates from the Boundaries' "Exact prototype markup" commitment [meus_registros_screen.dart:157] — fixed: added `DesignTokens.entriesEmptyStateVerticalPadding = 64` and switched to `EdgeInsets.symmetric(vertical: entriesEmptyStateVerticalPadding, horizontal: spacingLg)`.
- [x] [Review][Patch] `tests/test-summary.md`'s Verification section states `fvm flutter test — 677/677 passed`; running it against the actual committed tree gives `679/679 passed` — stale/wrong by 2 [`_bmad-output/implementation-artifacts/tests/test-summary.md:274`] — fixed: count corrected to `679/679`.
- [x] [Review][Defer] Tapping "Criar primeiro registro" twice rapidly can open two stacked Insertion Modal instances — no debounce guard on the CTA's `onPressed` [meus_registros_screen.dart:176] — deferred, pre-existing: reproduces the identical, already-shipped, unguarded pattern on the Home/Chat FAB (`placeholder_screens.dart:97`); a fix belongs to both call sites together, not this story alone.



The CTA deliberately calls `InsertionModal.show` directly from `_EmptyState` (a `StatelessWidget`, same as `HomeChatPlaceholderScreen`'s FAB) rather than threading a callback through `MeusRegistrosCubit`/`MeusRegistrosScreen` — opening the modal is pure navigation/DI wiring with no cubit-observable state of its own, and `placeholder_screens.dart` already establishes this exact call-directly-from-the-widget convention for the only other place this modal is opened.

## Verification

**Commands:**
- `fvm flutter analyze` -- expected: zero issues
- `fvm flutter test` -- expected: all tests pass

**Manual checks (if no CLI):**
- With zero Entries, open Meus Registros: confirm the icon, "Nenhum registro ainda", and the CTA render; tap the CTA and confirm the Insertion Modal opens with its three tabs.

## Suggested Review Order

**Empty-state UI — the core of this story**

- Entry point — `_EmptyState` rebuilt as icon + copy + CTA, replacing the plain-text placeholder.
  [`meus_registros_screen.dart:147`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L147)

- CTA wiring — opens the Insertion Modal via `sl<...>()`, identical call shape to the Home/Chat FAB.
  [`meus_registros_screen.dart:174`](../../lib/features/entries/presentation/screens/meus_registros_screen.dart#L174)

**Design token**

- New `entriesEmptyStateIconSize` token — keeps the 88px icon size out of the widget (RNF08).
  [`design_tokens.dart:277`](../../lib/core/design_tokens.dart#L277)

**Domain doc**

- `MeusRegistrosEmpty`'s doc comment updated to describe the now-complete empty state.
  [`meus_registros_state.dart:27`](../../lib/features/entries/presentation/cubit/meus_registros_state.dart#L27)

**Peripherals — tests**

- Empty state renders icon + copy + CTA (Acceptance Criteria's first bullet).
  [`meus_registros_screen_test.dart:345`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L345)

- CTA tap opens the Insertion Modal, mirroring the Home FAB's own DI-fake test pattern.
  [`meus_registros_screen_test.dart:361`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L361)

- I/O matrix row 4 — all-malformed-`occurredAt` entries still render the dedicated empty state, not blank.
  [`meus_registros_screen_test.dart:399`](../../test/features/entries/presentation/screens/meus_registros_screen_test.dart#L399)

