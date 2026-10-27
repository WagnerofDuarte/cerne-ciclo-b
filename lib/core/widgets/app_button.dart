import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// The three button variants named in prototype-extract.md §6's component
/// table: primary (filled), secondary (outline), text (ghost).
enum AppButtonVariant { primary, secondaryOutline, textGhost }

/// Shared button primitive consumed by every feature's `presentation/`
/// (Story 1.3 login/signup, Story 1.5 overlay, Story 1.6 nav shell).
///
/// Disabled state is identical across all three variants, per the
/// project-wide rule: `colorBorder` background + `colorTextSecondary`
/// text, never a dimmed-opacity look.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.textColor,
  });

  /// Button label. Rendered with no `maxLines`/`overflow` clamp so it
  /// wraps rather than clips or truncates under Dynamic Type.
  final String label;

  /// Null disables the button and switches it to the disabled visual
  /// state (see class doc).
  final VoidCallback? onPressed;

  final AppButtonVariant variant;

  /// Only consulted for [AppButtonVariant.textGhost]: the component table
  /// allows ghost buttons to use either `colorPrimary` or
  /// `colorTextSecondary` depending on context (e.g. "Fechar"/"Limpar").
  /// Defaults to `colorPrimary`.
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final Widget child = Text(label, textAlign: TextAlign.center, style: DesignTokens.textLabelMd);

    final ButtonStyle baseStyle = ButtonStyle(
      padding: const WidgetStatePropertyAll(DesignTokens.buttonPadding),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusSm)),
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
    );

    switch (variant) {
      case AppButtonVariant.primary:
        return ElevatedButton(
          onPressed: onPressed,
          style: baseStyle.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorBorder;
              }
              return DesignTokens.colorPrimary;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorTextSecondary;
              }
              return DesignTokens.colorOnPrimary;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return DesignTokens.colorPrimaryPressed;
              }
              return Colors.transparent;
            }),
          ),
          child: child,
        );

      case AppButtonVariant.secondaryOutline:
        return OutlinedButton(
          onPressed: onPressed,
          style: baseStyle.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorBorder;
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorTextSecondary;
              }
              return DesignTokens.colorPrimary;
            }),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: DesignTokens.colorBorder, width: DesignTokens.borderWidthDefault);
              }
              return const BorderSide(color: DesignTokens.colorPrimary, width: DesignTokens.borderWidthDefault);
            }),
          ),
          child: child,
        );

      case AppButtonVariant.textGhost:
        return TextButton(
          onPressed: onPressed,
          style: baseStyle.copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorBorder;
              }
              return Colors.transparent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return DesignTokens.colorTextSecondary;
              }
              return textColor ?? DesignTokens.colorPrimary;
            }),
          ),
          child: child,
        );
    }
  }
}
