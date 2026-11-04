import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../cubit/audio_entry_cubit.dart';
import '../cubit/text_entry_cubit.dart';

/// The Insertion Modal — a 3-tab bottom sheet (Texto/Áudio/Foto) opened
/// from the Home/Chat "+" control (`placeholder_screens.dart`). Texto and
/// Áudio are both functional as of spec-3-2 (Boundaries) — Foto still
/// renders its own idle, non-interactive placeholder (Story 3.3).
class InsertionModal extends StatelessWidget {
  const InsertionModal({required this.cubit, required this.audioCubit, super.key});

  final TextEntryCubit cubit;
  final AudioEntryCubit audioCubit;

  /// Presents the modal exactly as the Boundaries dictate:
  /// `showModalBottomSheet(isScrollControlled: true, barrierColor:
  /// colorScrimHeavy)`, `radiusLg` top corners + `elevation2` (drawn by
  /// this widget's own `Container`, not Material's `elevation` double —
  /// same convention `ConfirmationDialog`'s card already uses), and a
  /// `durationSheetUp` entrance that collapses to zero under Reduce
  /// Motion (`MediaQuery.disableAnimations`).
  ///
  /// [cubit]/[audioCubit] are both fresh, `get_it`-factory-scoped
  /// instances — one pair per "+" tap (Boundaries: "Modal open resets") —
  /// closed here once the sheet is gone, regardless of how it closed
  /// (Salvar success, "x", swipe-down, or barrier dismiss) — the caller
  /// never has to remember to do this itself.
  static Future<void> show(
    BuildContext context, {
    required TextEntryCubit cubit,
    required AudioEntryCubit audioCubit,
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
        builder: (_) => InsertionModal(cubit: cubit, audioCubit: audioCubit),
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
      // Review finding: dismissing the whole modal while recording/
      // processing (the "x" button, swipe-down, or barrier tap — as
      // opposed to switching to another tab, which already went through
      // this same `cancel()`) never stopped the native recording session;
      // `close()` alone only cancels the elapsed-seconds timer, not the
      // recorder itself.
      await audioCubit.cancel();
      await audioCubit.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider.value(value: audioCubit),
      ],
      child: const _InsertionModalBody(),
    );
  }
}

/// Coarse `AudioCaptureState` discriminator used only to decide whether a
/// given emission is a genuine transition worth announcing — e.g.
/// [AudioRecording]'s own per-second timer tick re-emits the same kind
/// repeatedly and must never re-announce "Gravando áudio" every second.
enum _AudioAnnounceKind { idle, recording, processing, transcribed, saving, saved, error }

_AudioAnnounceKind _audioAnnounceKindOf(AudioCaptureState state) => switch (state) {
  AudioIdle() => _AudioAnnounceKind.idle,
  AudioRecording() => _AudioAnnounceKind.recording,
  AudioProcessing() => _AudioAnnounceKind.processing,
  AudioTranscribed(saving: true) => _AudioAnnounceKind.saving,
  AudioTranscribed() => _AudioAnnounceKind.transcribed,
  AudioSaved() => _AudioAnnounceKind.saved,
  AudioError() => _AudioAnnounceKind.error,
};

class _InsertionModalBody extends StatefulWidget {
  const _InsertionModalBody();

  @override
  State<_InsertionModalBody> createState() => _InsertionModalBodyState();
}

class _InsertionModalBodyState extends State<_InsertionModalBody> {
  final _textController = TextEditingController();

  /// The Áudio tab's own text field controller — lifted up here rather
  /// than owned by `_AudioTab` itself so it survives `_AudioTab` being
  /// rebuilt on every `AudioCaptureState` change without losing cursor
  /// position/focus, same rationale as [_textController] living here
  /// instead of inside `_TextoTab`.
  final _audioTextController = TextEditingController();

  /// The last `AudioTranscribed.path` this controller's text was synced
  /// from — only a *new* transcription (a different/first path) resets
  /// the controller's text; the user's own edits via `onChanged` never
  /// get clobbered by an unrelated rebuild.
  String? _lastSyncedAudioPath;

  /// Tracks the previously-seen `activeTab` so the listener can tell a
  /// genuine tab switch apart from the many other `TextEntryIdle`
  /// emissions a keystroke produces (`updateText` also emits `Idle`) —
  /// initialized from the cubit's own current state so the very first
  /// comparison (before any emission the listener sees) is still correct.
  late CaptureTab _lastAnnouncedTab;

  /// Same "only announce a genuine transition" guard as [_lastAnnouncedTab],
  /// for `AudioEntryCubit` (see [_audioAnnounceKindOf]).
  late _AudioAnnounceKind _lastAudioAnnouncedKind;

  @override
  void initState() {
    super.initState();
    _lastAnnouncedTab = context.read<TextEntryCubit>().state.activeTab;
    _lastAudioAnnouncedKind = _audioAnnounceKindOf(
      context.read<AudioEntryCubit>().state,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioTextController.dispose();
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

  void _onTextEntryStateChange(BuildContext context, TextEntryState state) {
    // Review finding: a tab switch (re-emitted as `TextEntryIdle`,
    // same as every keystroke) previously went unannounced —
    // detected here by comparing against the last tab seen, so a
    // plain keystroke (same `activeTab`) never re-triggers it.
    if (state.activeTab != _lastAnnouncedTab) {
      final previousTab = _lastAnnouncedTab;
      _lastAnnouncedTab = state.activeTab;
      _announce('Aba ${_tabLabels[state.activeTab]} selecionada');
      // spec-3-2's Code Map: tab-switch detection also drives
      // `AudioEntryCubit.startRecording()`/`.cancel()` — entering Áudio
      // starts recording immediately (Acceptance Criteria), leaving it
      // stops/releases the recorder (I/O matrix: "Leave tab
      // mid-recording"), never the full Story 3.4 cancel choreography.
      final audioCubit = context.read<AudioEntryCubit>();
      if (state.activeTab == CaptureTab.audio) {
        unawaited(audioCubit.startRecording());
      } else if (previousTab == CaptureTab.audio) {
        unawaited(audioCubit.cancel());
      }
    }
    switch (state) {
      case TextEntrySaved():
        // I/O matrix: "success closes the modal". Review finding:
        // wait for the announcement to actually be sent before
        // popping — previously fired-and-forgot in the same tick,
        // risking the announcement being cut off by the dismiss
        // transition.
        unawaited(
          _announce('Registro salvo').then((_) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }),
        );
      case TextEntrySaving():
        _announce('Salvando registro');
      case TextEntryError():
        _announce(state.message);
      case TextEntryIdle():
        break;
    }
  }

  void _onAudioStateChange(BuildContext context, AudioCaptureState state) {
    if (state is AudioTranscribed && state.path != _lastSyncedAudioPath) {
      _lastSyncedAudioPath = state.path;
      _audioTextController.text = state.text;
    }
    final kind = _audioAnnounceKindOf(state);
    if (kind == _lastAudioAnnouncedKind) {
      return;
    }
    _lastAudioAnnouncedKind = kind;
    switch (state) {
      case AudioRecording():
        _announce('Gravando áudio');
      case AudioProcessing():
        _announce('Transcrevendo áudio');
      case AudioTranscribed(saving: true):
        _announce('Salvando registro');
      case AudioTranscribed():
        _announce('Transcrição concluída. Revise o texto antes de salvar.');
      case AudioError(message: final message):
        _announce(message);
      case AudioSaved():
        // Same "wait for the announcement" rationale as
        // `TextEntrySaved` above.
        unawaited(
          _announce('Registro salvo').then((_) {
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          }),
        );
      case AudioIdle():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AudioEntryCubit, AudioCaptureState>(
      listener: _onAudioStateChange,
      // Review finding: `isSaving` below previously only read
      // `TextEntryCubit`'s state, so the tab bar/"x" close button stayed
      // tappable while an *audio* save was in flight (`AudioTranscribed.
      // saving == true`) — the same race Story 3.1's own review fixed for
      // the Texto tab, just unguarded on the Áudio side. Wrapping in this
      // `BlocBuilder` makes the whole subtree rebuild on an `AudioEntryCubit`
      // state change too, not only a `TextEntryCubit` one.
      child: BlocBuilder<AudioEntryCubit, AudioCaptureState>(
        builder: (context, audioState) {
          final isAudioSaving =
              audioState is AudioTranscribed && audioState.saving;
          return BlocConsumer<TextEntryCubit, TextEntryState>(
            listener: _onTextEntryStateChange,
            builder: (context, state) {
              final isSaving = state is TextEntrySaving || isAudioSaving;
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
                  // Keeps the Texto field clear of the on-screen keyboard —
                  // the sheet is `isScrollControlled: true`, so it already
                  // grows to fit; this is the standard companion fix for
                  // the keyboard inset itself.
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
                          CaptureTab.audio => _AudioTab(
                            controller: _audioTextController,
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
        },
      ),
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
      // Review finding: without this, VoiceOver can also pick up the
      // inner `Text(label)`'s own implicit semantics as a separate node,
      // announcing the tab name twice back-to-back.
      excludeSemantics: true,
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
            constraints: const BoxConstraints(
              minHeight: DesignTokens.insertionModalTapTargetMin,
            ),
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
          width: DesignTokens.insertionModalTapTargetMin,
          height: DesignTokens.insertionModalTapTargetMin,
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
    // Review finding: also false while TextEntrySaved — the sheet is
    // about to pop (same rationale as TextEntryCubit.save()'s own guard),
    // so Salvar shouldn't be tappable during that brief window either.
    final canSave =
        controller.text.trim().isNotEmpty && !isSaving && state is! TextEntrySaved;
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
            // Review finding: suppresses Material's default "0/20000"
            // counter — the prototype's Texto state shows no such
            // element, and nothing here accounts for its styling.
            counterText: '',
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

/// The Áudio tab — spec-3-2's new recording -> processing ->
/// transcribed/error pipeline UI, mirroring `_TextoTab`'s own structure
/// (a `BlocBuilder`-driven switch over its cubit's state, an inline error
/// message in `colorError`, and the same `AppButton` Salvar convention).
/// [controller] is `_InsertionModalBodyState`'s own persistent
/// `TextEditingController` for the transcribed text (see its own doc) —
/// never created locally here, so a rebuild never loses cursor position.
class _AudioTab extends StatelessWidget {
  const _AudioTab({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AudioEntryCubit, AudioCaptureState>(
      builder: (context, state) {
        return switch (state) {
          AudioIdle() => const _AudioLoading(),
          AudioRecording(elapsedSeconds: final elapsed) => _AudioRecordingView(
            elapsedSeconds: elapsed,
          ),
          AudioProcessing() => const _AudioProcessingView(),
          AudioTranscribed(saving: final saving) => _AudioTranscribedView(
            controller: controller,
            saving: saving,
          ),
          AudioError(path: final path, message: final message, text: final text) =>
            _AudioErrorView(
              controller: controller,
              message: message,
              canRetry: path == null || text == null,
            ),
          // Brief, between `save()`'s success and `InsertionModal`'s own
          // listener popping the sheet (same instantaneous-state rationale
          // as `_TextoTab` never needing a dedicated `TextEntrySaved`
          // rendering branch — `_TextoTab` simply stops being built once
          // `state.activeTab` no longer matters, but `_AudioTab` is still
          // reached once more here before that pop completes).
          AudioSaved() => const _AudioLoading(),
        };
      },
    );
  }
}

class _AudioLoading extends StatelessWidget {
  const _AudioLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: DesignTokens.spacingXl),
      child: Center(
        child: SizedBox(
          width: DesignTokens.accountSettingsSavingIndicatorSize,
          height: DesignTokens.accountSettingsSavingIndicatorSize,
          child: CircularProgressIndicator(
            color: DesignTokens.colorPrimary,
            strokeWidth: DesignTokens.accountSettingsSavingIndicatorStrokeWidth,
          ),
        ),
      ),
    );
  }
}

/// A fixed count of amplitude bars — a layout choice, not a visual value
/// (color/font/spacing/radius) under RNF08, so it isn't a
/// `design_tokens.dart` constant.
const _waveformBarCount = 24;

class _AudioRecordingView extends StatelessWidget {
  const _AudioRecordingView({required this.elapsedSeconds});

  final int elapsedSeconds;

  String get _formattedElapsed {
    final minutes = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Waveform(
          amplitudeStream: context.read<AudioEntryCubit>().amplitudeStream,
          opacity: 1,
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          _formattedElapsed,
          style: DesignTokens.textMonoCaption.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Semantics(
          button: true,
          label: 'Parar gravação',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: const BorderRadius.all(
              Radius.circular(DesignTokens.radiusFull),
            ),
            onTap: () => context.read<AudioEntryCubit>().stopRecording(),
            child: Container(
              width: DesignTokens.insertionModalTapTargetMin,
              height: DesignTokens.insertionModalTapTargetMin,
              decoration: const BoxDecoration(
                color: DesignTokens.colorError,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.stop, color: DesignTokens.colorOnPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioProcessingView extends StatelessWidget {
  const _AudioProcessingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Acceptance Criteria: "the waveform freezes at 35% opacity
        // during processing" — no live `amplitudeStream` while stopped,
        // so this renders a static bar pattern rather than the live
        // recording's actual last shape (no audio-capture mock exists in
        // prototype-extract.md to match pixel-for-pixel; Design Notes:
        // decide and proceed).
        const _Waveform(amplitudeStream: null, opacity: 0.35),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          'Transcrevendo áudio...',
          style: DesignTokens.textBodyMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
      ],
    );
  }
}

class _AudioTranscribedView extends StatelessWidget {
  const _AudioTranscribedView({required this.controller, required this.saving});

  final TextEditingController controller;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final canSave = controller.text.trim().isNotEmpty && !saving;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          enabled: !saving,
          minLines: 3,
          maxLines: null,
          maxLength: 20000,
          onChanged: (value) =>
              context.read<AudioEntryCubit>().updateText(value),
          style: DesignTokens.textBodyLg.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            contentPadding: DesignTokens.textFieldContentPadding,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.radiusSm),
              ),
              borderSide: BorderSide(
                color: DesignTokens.colorBorder,
                width: DesignTokens.borderWidthDefault,
              ),
            ),
            focusedBorder: OutlineInputBorder(
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
        const SizedBox(height: DesignTokens.spacingMd),
        AppButton(
          label: saving ? 'Salvando...' : 'Salvar',
          onPressed: canSave
              ? () => context.read<AudioEntryCubit>().save()
              : null,
        ),
      ],
    );
  }
}

/// Covers both `AudioError` shapes (I/O matrix): no recorded file
/// (permission denied, "no file to preserve") or a file whose
/// transcription failed both set [canRetry] `true`, rendering "Tentar
/// novamente" (re-requesting permission or re-transcribing in place,
/// respectively — `AudioEntryCubit.retry()` tells the two apart itself).
/// [canRetry] `false` means a *save* failure from `AudioTranscribed`
/// instead — the text field stays editable with Salvar re-enabled rather
/// than a "Tentar novamente" control, mirroring `_TextoTab`'s own
/// `TextEntryError` rendering.
class _AudioErrorView extends StatelessWidget {
  const _AudioErrorView({
    required this.controller,
    required this.message,
    required this.canRetry,
  });

  final TextEditingController controller;
  final String message;
  final bool canRetry;

  @override
  Widget build(BuildContext context) {
    if (canRetry) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: DesignTokens.colorError),
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorError,
            ),
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          AppButton(
            label: 'Tentar novamente',
            onPressed: () => context.read<AudioEntryCubit>().retry(),
          ),
        ],
      );
    }
    final canSave = controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 3,
          maxLines: null,
          maxLength: 20000,
          onChanged: (value) =>
              context.read<AudioEntryCubit>().updateText(value),
          style: DesignTokens.textBodyLg.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
          decoration: const InputDecoration(
            counterText: '',
            contentPadding: DesignTokens.textFieldContentPadding,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(DesignTokens.radiusSm),
              ),
              borderSide: BorderSide(
                color: DesignTokens.colorBorder,
                width: DesignTokens.borderWidthDefault,
              ),
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          message,
          style: DesignTokens.textBodyMd.copyWith(color: DesignTokens.colorError),
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        AppButton(
          label: 'Salvar',
          onPressed: canSave
              ? () => context.read<AudioEntryCubit>().save()
              : null,
        ),
      ],
    );
  }
}

/// A live (or frozen) amplitude-bar waveform. `amplitudeStream == null`
/// renders a static placeholder pattern at [opacity] instead of
/// subscribing — the "frozen" rendering `_AudioProcessingView` uses.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.amplitudeStream, required this.opacity});

  final Stream<double>? amplitudeStream;
  final double opacity;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  // `growable: true` — `build()` below reads this with `removeAt`/`add`
  // on every new amplitude sample, which `List.filled`'s own default
  // fixed-length list doesn't support.
  final List<double> _samples = List.filled(
    _waveformBarCount,
    0.1,
    growable: true,
  );
  StreamSubscription<double>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.amplitudeStream?.listen((amplitude) {
      if (!mounted) {
        return;
      }
      setState(() {
        _samples.removeAt(0);
        // `num.clamp` returns `num`, not `double` — `_samples` is
        // `List<double>`.
        _samples.add(amplitude.clamp(0.1, 1.0).toDouble());
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.opacity,
      child: SizedBox(
        height: DesignTokens.spacing2xl,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < _samples.length; i++) ...[
              AnimatedContainer(
                duration: DesignTokens.durationSheetUp,
                width: DesignTokens.spacingXs,
                height: DesignTokens.spacing2xl * _samples[i],
                decoration: const BoxDecoration(
                  color: DesignTokens.colorError,
                  borderRadius: BorderRadius.all(
                    Radius.circular(DesignTokens.radiusFull),
                  ),
                ),
              ),
              if (i < _samples.length - 1)
                const SizedBox(width: DesignTokens.spacingXs),
            ],
          ],
        ),
      ),
    );
  }
}
