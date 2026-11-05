import 'package:flutter/widgets.dart';

import '../design_tokens.dart';

/// Generic shimmering placeholder rectangle — spec-4-1's own requirement:
/// "built only from existing tokens — no new colors" (Boundaries). Built
/// purely from [DesignTokens.colorBorder] (its one color) pulsed between
/// two opacities via an implicit `AnimationController`; [width]/[height]/
/// [borderRadius] are supplied by the caller from its own existing tokens
/// (`entry_skeleton_card.dart`), never a new literal here.
///
/// The pulse's own duration isn't a color/font/spacing/radius value
/// (RNF08's covered categories) — same precedent `BootSplashScreen`'s own
/// local `Timer` threshold already sets for a one-off motion constant that
/// isn't itself a visual token.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = DesignTokens.radiusSm,
    super.key,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  static const _pulseDuration = Duration(milliseconds: 800);

  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _pulseDuration)
      ..repeat(reverse: true);
    _opacity = _controller.drive(Tween<double>(begin: 0.4, end: 1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignTokens.colorBorder,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
        child: SizedBox(width: widget.width, height: widget.height),
      ),
    );
  }
}
