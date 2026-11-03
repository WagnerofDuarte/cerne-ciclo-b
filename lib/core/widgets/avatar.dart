import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Initials avatar (prototype-extract.md §6): a solid `colorPrimary`
/// circle with 1–2 uppercase initials, in two sizes — 40dp in the side
/// menu (Story 1.6), 52dp in Configurações (Epic 8).
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.initials,
    this.size = AvatarSize.small,
  });

  /// Expected to be 1–2 characters; rendered as given (uppercased) with
  /// no truncation enforced here — the caller owns deriving initials
  /// from a name.
  final String initials;

  final AvatarSize size;

  double get _diameter {
    switch (size) {
      case AvatarSize.small:
        return DesignTokens.avatarSizeSm;
      case AvatarSize.large:
        return DesignTokens.avatarSizeLg;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _diameter,
      height: _diameter,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: DesignTokens.colorPrimary,
        shape: BoxShape.circle,
      ),
      // The circle is a fixed design-token size (not a text container
      // sized to its content); FittedBox shrinks the initials to fit
      // under extreme Dynamic Type scales instead of clipping/truncating.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: DesignTokens.avatarInitialsPadding,
          child: Text(
            initials.toUpperCase(),
            style: DesignTokens.textTitleSm.copyWith(
              color: DesignTokens.colorOnPrimary,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}

enum AvatarSize { small, large }
