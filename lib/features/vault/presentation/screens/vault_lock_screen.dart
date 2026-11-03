import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/repositories/vault_repository.dart';
import '../widgets/pin_keypad.dart';

/// `/vault` — the epic's one lock screen, shown whenever
/// `VaultRepository.currentStatus` isn't `VaultStatus.unlocked`
/// (`core/navigation/app_router.dart`'s `_redirect`). Auto-triggers the OS
/// biometric prompt once in [initState]; a successful
/// [VaultRepository.authenticate] call flips `currentStatus` to `unlocked`,
/// which — via `statusStream`/`refreshListenable` — re-runs the redirect and
/// navigates away from here on its own, so this widget never navigates
/// imperatively itself.
///
/// Story 2.2: every biometric failure (decline/cancel/any OS lockout — the
/// generic `authenticate()` catches already cover it, spec-2-2) falls
/// through to a real [PinKeypad] + error band, never a second biometric
/// "Tentar novamente" affordance (AC2). The "Usar PIN" ghost link reaches
/// the same keypad directly, with no error band, before any biometric
/// failure has happened. [VaultRepository.submitPin]'s own success emits
/// `VaultStatus.unlocked`, same as [VaultRepository.authenticate] — this
/// widget navigates away on that exactly the same way, with no branch for
/// "which path unlocked it".
class VaultLockScreen extends StatefulWidget {
  const VaultLockScreen({
    required this.vaultRepository,
    required this.attemptBiometricFirst,
    super.key,
  });

  final VaultRepository vaultRepository;

  /// Story 2.4 — `AccountSettingsRepository.currentBiometricEnabled`, read
  /// by `core/navigation/app_router.dart`'s `/vault` builder. `true`
  /// (including the default before the boot fetch resolves, Design Notes)
  /// auto-triggers [VaultRepository.authenticate] in [initState] exactly
  /// as before this story; `false` skips straight to the PIN keypad — PIN
  /// remains the access method regardless (Boundaries).
  final bool attemptBiometricFirst;

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  static const _biometricFailureMessage =
      'Não foi possível reconhecer — digite seu PIN';

  /// No specific copy is given anywhere in `docs/input/` for a PIN
  /// mismatch (the I/O matrix only specifies the `Failure` returned) —
  /// decided here (Design Notes), mirroring the biometric failure band's
  /// own tone.
  static const _pinMismatchMessage = 'PIN incorreto. Tente novamente.';

  /// No specific copy is given anywhere in `docs/input/` for a
  /// `submitPin` call that never resolves (decided here, Design Notes) —
  /// review finding: without a bound, a hung secure-storage channel call
  /// would leave [_submittingPin] stuck `true` forever, permanently
  /// blocking every future attempt and contradicting the spec's own
  /// "never a dead end" boundary.
  static const _submitTimeoutMessage =
      'Não foi possível verificar o PIN. Tente novamente.';

  static const _submitPinTimeout = Duration(seconds: 10);

  bool _showPinKeypad = false;
  String? _errorMessage;

  /// Re-entrancy guard for [_submitPin], also passed to [PinKeypad] as
  /// `enabled: !_submittingPin` — [PinKeypad] clears its own buffer and
  /// accepts new taps immediately after calling `onSubmit`, before the
  /// awaited [VaultRepository.submitPin] below resolves, so a fast second
  /// 4-digit entry could otherwise be accepted and then silently dropped
  /// here with no feedback; gating the keypad itself means it's never
  /// accepted in the first place.
  bool _submittingPin = false;

  @override
  void initState() {
    super.initState();
    if (widget.attemptBiometricFirst) {
      _attemptAuthenticate();
    } else {
      // Story 2.4 — the preference is already `false` by the time this
      // screen builds: skip the OS biometric prompt entirely and show the
      // PIN keypad directly, with no error band (same "pre-failure" look
      // as tapping "Usar PIN" manually).
      _showPinKeypad = true;
    }
  }

  Future<void> _attemptAuthenticate() async {
    final result = await widget.vaultRepository.authenticate();
    if (!mounted) {
      return;
    }

    // On success, `currentStatus` is already `unlocked` and the router's
    // own `refreshListenable` will navigate away from `/vault` on its own —
    // this widget has nothing further to do (and may already be in the
    // process of being disposed by the time that happens).
    var shouldAnnounceFailure = false;
    result.match(
      (_) {
        // If the user already reached the keypad manually (via "Usar
        // PIN") before this pending call resolved, this late failure must
        // never clobber whatever the keypad is currently showing — AC2's
        // "no second biometric-retry affordance" only concerns the
        // biometric view itself, which is no longer on screen.
        final alreadyOnKeypad = _showPinKeypad;
        shouldAnnounceFailure = !alreadyOnKeypad;
        if (!alreadyOnKeypad) {
          setState(() {
            _showPinKeypad = true;
            _errorMessage = _biometricFailureMessage;
          });
        }
      },
      (_) {},
    );

    // `sendAnnouncement()` (see `_announce` below) is honored on both
    // Android and iOS — this app is iOS-only, where VoiceOver doesn't
    // reliably treat a live-region subtree update as an announcement on
    // its own, so the biometric->PIN transition is spoken explicitly
    // here rather than relying on any ambient live region.
    if (shouldAnnounceFailure && mounted) {
      await _announce(_biometricFailureMessage);
    }
  }

  void _useManualPin() {
    setState(() {
      _showPinKeypad = true;
      _errorMessage = null;
    });
  }

  @override
  void didUpdateWidget(covariant VaultLockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Review finding: `attemptBiometricFirst` was only ever consulted
    // once, in `initState` — defensive future-proofing in case this
    // already-mounted widget is ever rebuilt with a new value (today,
    // nothing actually does: `app_router.dart` reads `currentBiometricEnabled`
    // fresh only when `/vault` is newly built, not while already resident
    // there — see its own doc comment). If that ever changes, e.g. a boot-
    // time `fetchBiometricEnabled()` resolving to `false` while `/vault` is
    // already mounted (with the default `true`) and already auto-triggered
    // the OS biometric prompt: that in-flight prompt can't be retracted
    // from here, but the preference can still be honored going forward: if
    // we're still waiting on it (haven't fallen through to the keypad yet),
    // switch to it proactively — exactly as if the user had tapped "Usar
    // PIN" themselves. A `false` -> `true` change is deliberately left
    // alone: re-triggering biometric out from under a user who's already
    // on the keypad (whether because it failed or because they chose "Usar
    // PIN") would be a surprise, not a fix, and PIN remains the access
    // method regardless either way (Boundaries).
    if (oldWidget.attemptBiometricFirst &&
        !widget.attemptBiometricFirst &&
        !_showPinKeypad) {
      _useManualPin();
    }
  }

  Future<void> _submitPin(String pin) async {
    if (_submittingPin) {
      return;
    }
    // Review finding: previously left in place, a stale mismatch/timeout
    // message from a prior attempt lingered unchanged through this new
    // attempt, with nothing distinguishing "old error, nothing happening"
    // from "new attempt in flight" — cleared here so only this attempt's
    // own outcome (or the keypad's disabled/dimmed state) is visible.
    setState(() {
      _submittingPin = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.vaultRepository
          .submitPin(pin)
          .timeout(_submitPinTimeout);
      if (!mounted) {
        return;
      }
      if (result.isLeft()) {
        // Mismatch: stays locked, no attempt cap — the keypad itself has
        // already cleared its own buffer by the time this runs
        // (PinKeypad's own contract), so the user can simply try again.
        setState(() => _errorMessage = _pinMismatchMessage);
        await _announce(_pinMismatchMessage);
      }
      // On a match (first-use or later), `currentStatus` is already
      // `unlocked` and the router navigates away on its own, same as a
      // successful `authenticate()`.
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      // Bounds the wait so a hung secure-storage call can never leave
      // `_submittingPin` stuck `true` forever — the `finally` below still
      // runs because this `await` has now actually completed (with a
      // thrown `TimeoutException`), same retryable outcome as a mismatch.
      setState(() => _errorMessage = _submitTimeoutMessage);
      await _announce(_submitTimeoutMessage);
    } finally {
      if (mounted) {
        setState(() => _submittingPin = false);
      } else {
        _submittingPin = false;
      }
    }
  }

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
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Center(
        child: Padding(
          padding: DesignTokens.screenPadding,
          // No ambient `Semantics(liveRegion: true)` wrapper here — it
          // would re-trigger on every single digit tap inside `PinKeypad`
          // (its own `_ProgressDots` label changes each tap), not just the
          // two transitions that actually need announcing. Those two
          // (biometric failure, PIN mismatch) are already covered
          // explicitly and reliably by `_announce()` below.
          child: _showPinKeypad
              ? _PinView(
                  errorMessage: _errorMessage,
                  onSubmit: _submitPin,
                  enabled: !_submittingPin,
                )
              : _BiometricView(onUsePin: _useManualPin),
        ),
      ),
    );
  }
}

class _BiometricView extends StatelessWidget {
  const _BiometricView({required this.onUsePin});

  final VoidCallback onUsePin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.lock_outline,
          size: DesignTokens.spacing2xl,
          color: DesignTokens.colorTextSecondary,
        ),
        const SizedBox(height: DesignTokens.spacingMd),
        Text(
          'Cerne bloqueado',
          textAlign: TextAlign.center,
          style: DesignTokens.textHeadlineMd.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Text(
          'Use a biometria do seu dispositivo para continuar.',
          textAlign: TextAlign.center,
          style: DesignTokens.textBodyMd.copyWith(
            color: DesignTokens.colorTextSecondary,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        AppButton(
          variant: AppButtonVariant.textGhost,
          label: 'Usar PIN',
          onPressed: onUsePin,
        ),
      ],
    );
  }
}

class _PinView extends StatelessWidget {
  const _PinView({
    required this.errorMessage,
    required this.onSubmit,
    required this.enabled,
  });

  final String? errorMessage;
  final ValueChanged<String> onSubmit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Digite seu PIN',
          textAlign: TextAlign.center,
          style: DesignTokens.textHeadlineMd.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: DesignTokens.spacingSm),
          Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: DesignTokens.textBodyMd.copyWith(
              color: DesignTokens.colorError,
            ),
          ),
        ],
        const SizedBox(height: DesignTokens.spacingLg),
        PinKeypad(onSubmit: onSubmit, enabled: enabled),
      ],
    );
  }
}
