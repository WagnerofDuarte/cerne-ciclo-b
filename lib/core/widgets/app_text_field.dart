import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Shared text field primitive (prototype-extract.md §6) with the three
/// border states the project's boundaries fix: default, focused
/// (`colorPrimary`, 1.5dp) and error (`colorError`, 1.5dp). Consumed by
/// Story 1.3's login/signup screen.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.focusNode,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;

  /// Non-null switches the field to the error border state and shows
  /// this text below the field (matches `InputDecorator`'s own rule:
  /// any non-null value, including an empty string, counts as an error).
  final String? errorText;

  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  /// `null` allows unlimited lines (e.g. the insertion modal's "Texto"
  /// tab); defaults to a single line for form fields like login.
  final int? maxLines;

  OutlineInputBorder _border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: const BorderRadius.all(
        Radius.circular(DesignTokens.radiusSm),
      ),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      maxLines: obscureText ? 1 : maxLines,
      minLines: null,
      style: DesignTokens.textBodyLg.copyWith(
        color: DesignTokens.colorTextPrimary,
      ),
      cursorColor: DesignTokens.colorPrimary,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        // Unbounded so a long error message wraps instead of being
        // truncated under Dynamic Type.
        errorMaxLines: null,
        filled: true,
        fillColor: DesignTokens.colorSurfaceElevated,
        contentPadding: DesignTokens.textFieldContentPadding,
        labelStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
        hintStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorTextSecondary,
        ),
        errorStyle: DesignTokens.textBodyMd.copyWith(
          color: DesignTokens.colorError,
        ),
        border: _border(
          DesignTokens.colorBorder,
          DesignTokens.borderWidthDefault,
        ),
        enabledBorder: _border(
          DesignTokens.colorBorder,
          DesignTokens.borderWidthDefault,
        ),
        focusedBorder: _border(
          DesignTokens.colorPrimary,
          DesignTokens.borderWidthEmphasis,
        ),
        errorBorder: _border(
          DesignTokens.colorError,
          DesignTokens.borderWidthEmphasis,
        ),
        focusedErrorBorder: _border(
          DesignTokens.colorError,
          DesignTokens.borderWidthEmphasis,
        ),
      ),
    );
  }
}
