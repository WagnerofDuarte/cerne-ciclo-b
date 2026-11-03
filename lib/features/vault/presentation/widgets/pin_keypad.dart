import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';

/// Tela 0.1b/0.1c's PIN entry component (prototype-extract.md §2.1/§6,
/// UX-DR14): 4 progress dots above a 3×4 numeric grid + backspace.
///
/// Owns its own digit buffer — the caller never resets it. After the 4th
/// digit, it waits 350ms with no explicit confirm tap (UX-DR14), then
/// clears the buffer and calls [onSubmit] with the 4-digit string. The
/// buffer is cleared *before* [onSubmit] is invoked, regardless of what
/// the caller later does with the result, so the keypad is always ready
/// for another attempt — the I/O matrix's "keypad clears for another
/// attempt — never a dead end".
///
/// Structural palette only (Boundaries: "no accent on digits") — every
/// color below is [DesignTokens.colorSurfaceElevated]/[DesignTokens.
/// colorBorder]/[DesignTokens.colorTextPrimary]/[DesignTokens.
/// colorTextSecondary]/[DesignTokens.colorPrimary], never [DesignTokens.
/// colorAccent]. Every button is at least [DesignTokens.pinKeypadButtonSize]
/// (UX-DR23: ≥44pt tap targets). Digit glyphs are wrapped in a
/// [FittedBox] so the largest Dynamic Type size shrinks them to fit rather
/// than clipping or truncating (UX-DR22).
class PinKeypad extends StatefulWidget {
  const PinKeypad({required this.onSubmit, super.key});

  /// Invoked once, 350ms after the 4th digit — never while a 1st-3rd digit
  /// is the most recent entry.
  final ValueChanged<String> onSubmit;

  /// The epic's one PIN length — no screen anywhere in `docs/input/`
  /// shows a different digit count.
  static const int pinLength = 4;

  @override
  State<PinKeypad> createState() => _PinKeypadState();
}

class _PinKeypadState extends State<PinKeypad> {
  final List<String> _digits = [];
  Timer? _advanceTimer;

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _onDigitTap(String digit) {
    if (_digits.length >= PinKeypad.pinLength) {
      // Defensive — the 350ms auto-advance window already clears the
      // buffer before a 5th tap could land, but a very fast double-tap on
      // the same frame must still never overflow past pinLength.
      return;
    }
    setState(() => _digits.add(digit));
    if (_digits.length == PinKeypad.pinLength) {
      final pin = _digits.join();
      _advanceTimer = Timer(const Duration(milliseconds: 350), () {
        if (!mounted) {
          return;
        }
        setState(_digits.clear);
        widget.onSubmit(pin);
      });
    }
  }

  void _onBackspaceTap() {
    // Unconditional, before the `isEmpty` check below — a backspace
    // during the 350ms auto-advance window must always invalidate the
    // scheduled submit, even though the buffer itself isn't touched until
    // after this. Without this, a correction typed inside that window
    // would be silently discarded: the stale pre-backspace `pin` string
    // still fires via `onSubmit` once the timer elapses, and its own
    // `setState(_digits.clear)` wipes whatever the user had re-typed by
    // then.
    _advanceTimer?.cancel();
    if (_digits.isEmpty) {
      return;
    }
    setState(_digits.removeLast);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ProgressDots(filledCount: _digits.length),
        const SizedBox(height: DesignTokens.spacingLg),
        _KeypadGrid(onDigitTap: _onDigitTap, onBackspaceTap: _onBackspaceTap),
      ],
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.filledCount});

  final int filledCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filledCount de ${PinKeypad.pinLength} dígitos do PIN',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(PinKeypad.pinLength, (index) {
          final filled = index < filledCount;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignTokens.pinProgressDotGap / 2,
            ),
            child: Container(
              width: DesignTokens.pinProgressDotSize,
              height: DesignTokens.pinProgressDotSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled
                    ? DesignTokens.colorPrimary
                    : DesignTokens.colorBorder,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _KeypadGrid extends StatelessWidget {
  const _KeypadGrid({required this.onDigitTap, required this.onBackspaceTap});

  final ValueChanged<String> onDigitTap;
  final VoidCallback onBackspaceTap;

  static const List<String> _digitRows1to9 = [
    '123',
    '456',
    '789',
  ];

  Widget _digitButton(String digit) {
    return _KeypadButton(
      onTap: () => onDigitTap(digit),
      semanticLabel: digit,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          digit,
          style: DesignTokens.textHeadlineMd.copyWith(
            color: DesignTokens.colorTextPrimary,
          ),
        ),
      ),
    );
  }

  Widget _spacedRow(List<Widget> cells) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final cell in cells)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: DesignTokens.pinKeypadGap / 2,
            ),
            child: cell,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final backspaceButton = _KeypadButton(
      onTap: onBackspaceTap,
      semanticLabel: 'Apagar',
      child: const Icon(
        Icons.backspace_outlined,
        size: DesignTokens.pinKeypadBackspaceIconSize,
        color: DesignTokens.colorTextSecondary,
      ),
    );
    const emptyCell = SizedBox(
      width: DesignTokens.pinKeypadButtonSize,
      height: DesignTokens.pinKeypadButtonSize,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final digits in _digitRows1to9) ...[
          _spacedRow([for (final digit in digits.split('')) _digitButton(digit)]),
          const SizedBox(height: DesignTokens.pinKeypadGap),
        ],
        _spacedRow([emptyCell, _digitButton('0'), backspaceButton]),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.onTap,
    required this.semanticLabel,
    required this.child,
  });

  final VoidCallback onTap;
  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: SizedBox(
        width: DesignTokens.pinKeypadButtonSize,
        height: DesignTokens.pinKeypadButtonSize,
        child: Material(
          color: DesignTokens.colorSurfaceElevated,
          shape: const CircleBorder(
            side: BorderSide(
              color: DesignTokens.colorBorder,
              width: DesignTokens.borderWidthDefault,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
