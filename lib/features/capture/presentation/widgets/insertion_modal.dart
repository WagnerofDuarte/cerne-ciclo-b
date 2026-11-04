import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../cubit/text_entry_cubit.dart';

/// The Insertion Modal — a 3-tab bottom sheet (Texto/Áudio/Foto) opened
/// from the Home/Chat "+" control (`placeholder_screens.dart`). Only
/// Texto is functional this story (Boundaries) — Áudio/Foto each render
/// their own idle, non-interactive placeholder (Stories 3.2/3.3).
class InsertionModal extends StatelessWidget {
  const InsertionModal({required this.cubit, super.key});

  final TextEntryCubit cubit;

  /// Presents the modal exactly as the Boundaries dictate:
  /// `showModalBottomSheet(isScrollControlled: true, barrierColor:
  /// colorScrimHeavy)`, `radiusLg` top corners + `elevation2` (drawn by
  /// this widget's own `Container`, not Material's `elevation` double —
  /// same convention `ConfirmationDialog`'s card already uses), and a
  /// `durationSheetUp` entrance that collapses to zero under Reduce
  /// Motion (`MediaQuery.disableAnimations`).
  ///
  /// [cubit] is a fresh, `get_it`-factory-scoped instance — one per "+"
  /// tap (Boundaries: "Modal open resets"), closed here once the sheet is
  /// gone, regardless of how it closed (Salvar success, "x", swipe-down,
  /// or barrier dismiss) — the caller never has to remember to do this
  /// itself.
  static Future<void> show(
    BuildContext context, {
    required TextEntryCubit cubit,
  }) async {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final controller =
        BottomSheet.createAnimationController(Navigator.of(context))
          ..duration = reduceMotion
              ? Duration.zero
              : DesignTokens.durationSheetUp
          // Boundaries only names the entrance, but Reduce Motion should
          // collapse the exit the same way — otherwise dismissing the
          // sheet would still animate for anyone who asked for no motion.
          ..reverseDuration = reduceMotion ? Duration.zero : null;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        barrierColor: DesignTokens.colorScrimHeavy,
        backgroundColor: Colors.transparent,
        elevation: 0,
        transitionAnimationController: controller,
        builder: (_) => InsertionModal(cubit: cubit),
      );
    } finally {
      // `showModalBottomSheet`'s own Future completes as soon as the
      // route is popped — *before* the exit (`reverse()`) animation the
      // framework drives on this same controller actually finishes.
      // Disposing immediately would cancel that animation's ticker
      // mid-flight, permanently freezing the sheet on screen (its
      // `AnimatedBuilder` keeps rendering the controller's last value,
      // and the route itself never reaches `AnimationStatus.dismissed`
      // to be removed from the `Overlay`). Documented behavior
      // (`BottomSheet.transitionAnimationController`'s own doc: "the
      // caller is responsible for disposing it when the controller is
      // no longer needed") — waiting for `dismissed` first is that
      // "no longer needed" point.
      if (!controller.isDismissed) {
        final animationDone = Completer<void>();
        void onStatusChange(AnimationStatus status) {
          if (status == AnimationStatus.dismissed) {
            animationDone.complete();
          }
        }

        controller.addStatusListener(onStatusChange);
        await animationDone.future;
        controller.removeStatusListener(onStatusChange);
      }
      controller.dispose();
      await cubit.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(value: cubit, child: const _InsertionModalBody());
  }
}

class _InsertionModalBody extends StatefulWidget {
  const _InsertionModalBody();

  @override
  State<_InsertionModalBody> createState() => _InsertionModalBodyState();
}

class _InsertionModalBodyState extends State<_InsertionModalBody> {
  final _textController = TextEditingController();

  /// Tracks the previously-seen `activeTab` so the listener can tell a
  /// genuine tab switch apart from the many other `TextEntryIdle`
  /// emissions a keystroke produces (`updateText` also emits `Idle`) —
  /// initialized from the cubit's own current state so the very first
  /// comparison (before any emission the listener sees) is still correct.
  late CaptureTab _lastAnnouncedTab;

  @override
  void initState() {
    super.initState();
    _lastAnnouncedTab = context.read<TextEntryCubit>().state.activeTab;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Labels for the 3 tabs, shared between the announcement below and
  // `_TabBar`'s own rendering (`_TabBar._tabs`) — kept here too since
  // `selectTab`'s announcement needs the label for whichever tab the
  // user just switched *to*, not the cubit's own (enum-only) state.
  static const _tabLabels = {
    CaptureTab.texto: 'Texto',
    CaptureTab.audio: 'Áudio',
    CaptureTab.foto: 'Foto',
  };

  // Mirrors `account_settings_screen.dart`'s own `_announce` — VoiceOver
  // (this app is iOS-only) doesn't reliably treat a live-region subtree
  // update as an announcement on its own, so every state change this
  // story introduces — saving, success, failure, and a tab switch — is
  // spoken explicitly here instead (Acceptance Criteria: "no
  // color/animation alone").
  Future<void> _announce(String message) async {
    if (!mounted) {
      return;
    }
    await SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      TextDirection.ltr,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TextEntryCubit, TextEntryState>(
      listener: (context, state) {
        // Review finding: a tab switch (re-emitted as `TextEntryIdle`,
        // same as every keystroke) previously went unannounced —
        // detected here by comparing against the last tab seen, so a
        // plain keystroke (same `activeTab`) never re-triggers it.
        if (state.activeTab != _lastAnnouncedTab) {
          _lastAnnouncedTab = state.activeTab;
          _announce('Aba ${_tabLabels[state.activeTab]} selecionada');
        }
        switch (state) {
          case TextEntrySaved():
            // I/O matrix: "success closes the modal". Announced before
            // popping — review finding: this previously fell through to
            // `break` with no announcement at all.
            _announce('Registro salvo');
            Navigator.of(context).pop();
          case TextEntrySaving():
            _announce('Salvando registro');
          case TextEntryError():
            _announce(state.message);
          case TextEntryIdle():
            break;
        }
      },
      builder: (context, state) {
        final isSaving = state is TextEntrySaving;
        return Container(
          padding: DesignTokens.screenPadding,
          decoration: const BoxDecoration(
            color: DesignTokens.colorSurfaceElevated,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(DesignTokens.radiusLg),
            ),
            boxShadow: DesignTokens.elevation2,
          ),
          child: Padding(
            // Keeps the Texto field clear of the on-screen keyboard — the
            // sheet is `isScrollControlled: true`, so it already grows to
            // fit; this is the standard companion fix for the keyboard
            // inset itself.
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _TabBar(
                          activeTab: state.activeTab,
                          isSaving: isSaving,
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spacingSm),
                      _CloseButton(isSaving: isSaving),
                    ],
                  ),
                  const SizedBox(height: DesignTokens.spacingMd),
                  switch (state.activeTab) {
                    CaptureTab.texto => _TextoTab(
                      controller: _textController,
                      state: state,
                    ),
                    CaptureTab.audio => const _IdleTabPlaceholder(
                      icon: Icons.mic_none,
                      label: 'Áudio chega em breve',
                    ),
                    CaptureTab.foto => const _IdleTabPlaceholder(
                      icon: Icons.photo_camera_outlined,
                      label: 'Foto chega em breve',
                    ),
                  },
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.activeTab, required this.isSaving});

  final CaptureTab activeTab;

  /// Review finding: a save already in flight must disable the tab bar —
  /// without this, switching tabs mid-save let that stale `save()` call's
  /// eventual `TextEntrySaved`/`TextEntryError` land against a tab/text
  /// the user has since left (popping the modal unexpectedly, or showing
  /// an error nobody is looking at). `TextEntryCubit.selectTab` also
  /// guards against this independently — this is the UI-level half of
  /// that same fix.
  final bool isSaving;

  static const _tabs = [
    (CaptureTab.texto, 'Texto'),
    (CaptureTab.audio, 'Áudio'),
    (CaptureTab.foto, 'Foto'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < _tabs.length; i++) ...[
          Expanded(
            child: _TabButton(
              tab: _tabs[i].$1,
              label: _tabs[i].$2,
              isActive: _tabs[i].$1 == activeTab,
              isSaving: isSaving,
            ),
          ),
          if (i < _tabs.length - 1)
            const SizedBox(width: DesignTokens.spacingSm),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.label,
    required this.isActive,
    required this.isSaving,
  });

  final CaptureTab tab;
  final String label;
  final bool isActive;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isActive,
      label: 'Aba $label',
      child: Material(
        color: isActive ? DesignTokens.colorPrimary : Colors.transparent,
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusSm),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(
            Radius.circular(DesignTokens.radiusSm),
          ),
          // Review finding: `null` while a save is in flight, same
          // "disabled `onTap` can never start a second, overlapping call"
          // convention `account_settings_screen.dart`'s `Switch` already
          // uses.
          onTap: isSaving
              ? null
              : () => context.read<TextEntryCubit>().selectTab(tab),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            alignment: Alignment.center,
            padding: DesignTokens.buttonPadding,
            child: Text(
              label,
              style: DesignTokens.textLabelMd.copyWith(
                color: isActive
                    ? DesignTokens.colorOnPrimary
                    : DesignTokens.colorTextPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.isSaving});

  /// Review finding — same rationale as `_TabBar.isSaving`: disabled
  /// while a save is in flight, so "x" can't pop the modal out from under
  /// a `save()` call that's about to emit `TextEntrySaved`/`TextEntryError`
  /// against the tab/text it captured at call time. (Swipe-down/barrier
  /// dismiss can still close the sheet mid-save — that gap is tracked
  /// separately in `deferred-work.md`, not part of this fix.)
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Fechar',
      child: InkWell(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusFull),
        ),
        // I/O matrix: "Cancel before save" — closes/resets, never calls
        // `create` (this handler never touches the cubit at all).
        onTap: isSaving ? null : () => Navigator.of(context).pop(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.close,
            color: isSaving
                ? DesignTokens.colorTextSecondary
                : DesignTokens.colorTextPrimary,
          ),
        ),
      ),
    );
  }
}

class _IdleTabPlaceholder extends StatelessWidget {
  const _IdleTabPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: DesignTokens.spacing2xl,
            color: DesignTokens.colorTextSecondary,
          ),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            label,
            textAlign: TextAlign.center,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextoTab extends StatelessWidget {
  const _TextoTab({required this.controller, required this.state});

  final TextEditingController controller;
  final TextEntryState state;

  @override
  Widget build(BuildContext context) {
    final isSaving = state is TextEntrySaving;
    final canSave = controller.text.trim().isNotEmpty && !isSaving;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: !isSaving,
          minLines: 3,
          maxLines: null,
          // Mirrors `POST /entries`'s own `content` cap
          // (`openapi.yaml`: `maxLength: 20000`) — avoids an avoidable
          // round-trip failure for text typed past the backend's limit.
          maxLength: 20000,
          onChanged: (value) =>
              context.read<TextEntryCubit>().updateText(value),
          style: DesignTokens.textBodyLg.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
          decoration: InputDecoration(
            // prototype-extract.md §2.3's Texto state: placeholder
            // "Escreva livremente...".
            hintText: 'Escreva livremente...',
            contentPadding: DesignTokens.textFieldContentPadding,
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.radiusSm),
              ),
              borderSide: BorderSide(
                color: DesignTokens.colorBorder,
                width: DesignTokens.borderWidthDefault,
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.radiusSm),
              ),
              borderSide: BorderSide(
                color: DesignTokens.colorPrimary,
                width: DesignTokens.borderWidthEmphasis,
              ),
            ),
          ),
        ),
        if (state is TextEntryError) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            (state as TextEntryError).message,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorError,
            ),
          ),
        ],
        const SizedBox(height: DesignTokens.spacingMd),
        AppButton(
          label: isSaving ? 'Salvando...' : 'Salvar',
          onPressed: canSave
              ? () => context.read<TextEntryCubit>().save()
              : null,
        ),
      ],
    );
  }
}
