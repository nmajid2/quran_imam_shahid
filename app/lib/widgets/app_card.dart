import 'package:flutter/material.dart';

/// Futuristic translucent card: gradient hairline border, subtle top sheen, and
/// an accent glow when selected. No BackdropFilter — safe to use in long lists.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.selected = false,
    this.translucent = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final bool selected;

  /// Extra-transparent fill so a vivid background (e.g. galaxy) shows through.
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(22);

    final borderColors = selected
        ? [cs.primary, cs.secondary]
        : dark
            ? [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.03)]
            : [Colors.white.withValues(alpha: 0.9), cs.outlineVariant.withValues(alpha: 0.5)];

    return DecoratedBox(
      // Gradient border ring.
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: borderColors,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? cs.primary.withValues(alpha: dark ? 0.45 : 0.28)
                : Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
            blurRadius: selected ? 24 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.3), // border thickness
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark
                  ? [
                      cs.surfaceContainerHigh
                          .withValues(alpha: translucent ? 0.34 : 0.72),
                      cs.surfaceContainer
                          .withValues(alpha: translucent ? 0.22 : 0.62),
                    ]
                  : [
                      Colors.white.withValues(alpha: translucent ? 0.42 : 0.88),
                      cs.surfaceContainerLow
                          .withValues(alpha: translucent ? 0.30 : 0.80),
                    ],
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(21),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
