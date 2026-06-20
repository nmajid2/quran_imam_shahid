import 'dart:ui';
import 'package:flutter/material.dart';

/// Frosted-glass surface (real backdrop blur). Use ONLY on a few fixed widgets
/// (app bar, player bar, sheets) — never per list item — to keep scrolling fast.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = 18,
    this.opacity,
    this.border = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blur;
  final double? opacity;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface
                .withValues(alpha: opacity ?? (dark ? 0.55 : 0.65)),
            borderRadius: radius,
            border: border
                ? Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.10 : 0.5),
                    width: 1)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
