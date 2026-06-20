import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Futuristic "aurora" background: a deep base with slowly drifting radial
/// colour glows. Painted in a RepaintBoundary so the animation never
/// invalidates foreground content; pure gradient fills (no blur) = GPU-cheap.
class AppBackground extends StatefulWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _AuroraPainter(cs, dark, _c.value),
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.cs, this.dark, this.t);
  final ColorScheme cs;
  final bool dark;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Deep base.
    final base = dark
        ? const [Color(0xFF080B16), Color(0xFF0C1226), Color(0xFF0A0E1C)]
        : [
            cs.surface,
            Color.alphaBlend(cs.primary.withValues(alpha: 0.04), cs.surface),
            Color.alphaBlend(cs.secondary.withValues(alpha: 0.05), cs.surface),
          ];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: base,
        ).createShader(rect),
    );

    final a = t * 2 * math.pi;
    final glowAlpha = dark ? 0.40 : 0.16;
    _glow(canvas, size, cs.primary, glowAlpha,
        Alignment(0.6 * math.cos(a) - 0.3, 0.5 * math.sin(a) - 0.6), 0.95);
    _glow(canvas, size, cs.secondary, glowAlpha,
        Alignment(0.5 * math.cos(a + 2) + 0.4, 0.5 * math.sin(a + 2) + 0.7),
        0.85);
    _glow(canvas, size, cs.tertiary, glowAlpha * 0.7,
        Alignment(0.7 * math.cos(a + 4), 0.4 * math.sin(a + 4) + 0.1), 0.7);
  }

  void _glow(Canvas canvas, Size size, Color color, double alpha,
      Alignment align, double radiusFactor) {
    final center = align.alongSize(size);
    final radius = size.shortestSide * radiusFactor;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.dark != dark || old.cs != cs;
}
