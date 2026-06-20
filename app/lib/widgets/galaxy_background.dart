import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A cosmic zoom-out hero scene. Scrolling = zooming OUT through scales:
///   near the top → our Solar System (sun + the real planets orbiting it)
///   scroll down  → pull back to the Milky Way (a rotating spiral galaxy)
///   scroll more  → a field of distant galaxies (deep cosmos)
/// Structures cross-fade and shrink toward a focal point as you zoom out.
///
/// Idle (no scroll): the camera/zoom is still — only planets orbit, the galaxy
/// rotates, and stars twinkle in place. Cheap canvas fills (no blur), in a
/// RepaintBoundary.
class GalaxyBackground extends StatefulWidget {
  const GalaxyBackground({super.key, required this.child, this.scroll});
  final Widget child;
  final ValueListenable<double>? scroll;

  @override
  State<GalaxyBackground> createState() => _GalaxyBackgroundState();
}

class _Star {
  final double x, y, r, baseA, phase, speed;
  const _Star(this.x, this.y, this.r, this.baseA, this.phase, this.speed);
}

class _MwStar {
  final double angle, rad, size, b;
  const _MwStar(this.angle, this.rad, this.size, this.b);
}

class _Galaxy {
  final double x, y, size, rot;
  final int colorIndex;
  const _Galaxy(this.x, this.y, this.size, this.rot, this.colorIndex);
}

class _Planet {
  final Color lit, dark;
  final double sizeF, orbitF, speed, phase;
  final bool ring, bands, earthlike;
  const _Planet(this.lit, this.dark, this.sizeF, this.orbitF, this.speed,
      this.phase,
      {this.ring = false, this.bands = false, this.earthlike = false});
}

const List<_Planet> _kPlanets = [
  _Planet(Color(0xFF9A8F80), Color(0xFF45403A), 0.018, 0.105, 0.20, 0.4),
  _Planet(Color(0xFFE6D2A0), Color(0xFF8A734A), 0.030, 0.155, 0.15, 2.1),
  _Planet(Color(0xFF4A90D9), Color(0xFF15386B), 0.032, 0.215, 0.125, 3.4,
      earthlike: true),
  _Planet(Color(0xFFC1502E), Color(0xFF5E2417), 0.025, 0.270, 0.10, 5.0),
  _Planet(Color(0xFFD8B48C), Color(0xFF6E4E32), 0.072, 0.375, 0.07, 1.2,
      bands: true),
  _Planet(Color(0xFFE3CD92), Color(0xFF9A8350), 0.058, 0.485, 0.055, 2.7,
      ring: true, bands: true),
  _Planet(Color(0xFFAFE3E8), Color(0xFF4D8F99), 0.044, 0.590, 0.045, 4.3),
  _Planet(Color(0xFF3F6FD8), Color(0xFF1C3680), 0.042, 0.685, 0.035, 0.8),
];

class _GalaxyBackgroundState extends State<GalaxyBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier<double>(0);
  late final List<_Star> _stars;
  late final List<_MwStar> _mw;
  late final List<_Galaxy> _galaxies;
  static final _zero = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(11);
    _stars = List.generate(140, (_) {
      return _Star(rnd.nextDouble(), rnd.nextDouble(), 0.4 + rnd.nextDouble() * 1.6,
          0.28 + rnd.nextDouble() * 0.72, rnd.nextDouble() * math.pi * 2,
          0.5 + rnd.nextDouble() * 1.3);
    });
    // Milky Way: stars along 2 logarithmic spiral arms + scatter.
    _mw = List.generate(420, (i) {
      final arm = i % 2;
      final t = rnd.nextDouble();
      final spread = (rnd.nextDouble() - 0.5) * 0.5 * (0.3 + t);
      final angle = arm * math.pi + t * 3.1 * math.pi + spread;
      final rad = (0.06 + t * 0.94) + spread * 0.15;
      return _MwStar(angle, rad.clamp(0.0, 1.0),
          0.5 + rnd.nextDouble() * 1.1, 0.35 + rnd.nextDouble() * 0.65);
    });
    _galaxies = List.generate(22, (i) {
      return _Galaxy(rnd.nextDouble(), rnd.nextDouble(),
          0.02 + rnd.nextDouble() * 0.05, rnd.nextDouble() * math.pi, i % 4);
    });
    _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scroll = widget.scroll ?? _zero;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_time, scroll]),
              builder: (_, __) => CustomPaint(
                painter: _GalaxyPainter(
                    _stars, _mw, _galaxies, cs, _time.value, scroll.value),
              ),
            ),
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}

/// Cosmic zoom level at the bottom of the scroll. `scroll` arrives normalized
/// (0..1 journey progress) so the journey is paced to the list length and ends
/// right as the deepest galaxies arrive — no motionless tail past the spiral.
const double _kZoomSpan = 2.7;

/// Ramp 0→1 over [up0,up1], hold 1 to [down0], 1→0 over [down0,down1].
double _ramp(double z, double up0, double up1, double down0, double down1) {
  if (z <= up0 || z >= down1) return 0;
  if (z < up1) return (z - up0) / (up1 - up0);
  if (z <= down0) return 1;
  return (down1 - z) / (down1 - down0);
}

Color _a(Color c, double m) => c.withValues(alpha: (c.a * m).clamp(0.0, 1.0));

class _GalaxyPainter extends CustomPainter {
  _GalaxyPainter(
      this.stars, this.mw, this.galaxies, this.cs, this.time, this.scroll);
  final List<_Star> stars;
  final List<_MwStar> mw;
  final List<_Galaxy> galaxies;
  final ColorScheme cs;
  final double time;
  final double scroll;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF04050C), Color(0xFF080917), Color(0xFF0B0720)],
        ).createShader(rect),
    );

    // Zoom level from normalized scroll progress (0..1) → full cosmic journey.
    final z = scroll * _kZoomSpan;
    final focal = Offset(size.width * 0.5, size.height * 0.34);

    // Background void stars (twinkle in place; fade a bit as we zoom out).
    final bgOp = (1.1 - z * 0.35).clamp(0.25, 1.0);
    _starfield(canvas, size, bgOp);

    // Layer order: distant galaxies (deep) → Milky Way → Solar System (near).
    final gfOp = _ramp(z, 1.8, 2.7, 99, 100);
    if (gfOp > 0.02) _galaxiesField(canvas, size, focal, gfOp, z);

    final mwOp = _ramp(z, 0.55, 1.2, 1.9, 2.9);
    if (mwOp > 0.02) {
      _milkyWay(canvas, size, focal, (1.55 - 0.5 * z).clamp(0.25, 1.4), mwOp);
    }

    final ssOp = _ramp(z, -1, 0.05, 0.6, 1.25);
    if (ssOp > 0.02) {
      _solarSystem(canvas, size, focal, (0.92 - 0.8 * z).clamp(0.02, 0.92), ssOp);
    }
  }

  void _starfield(Canvas canvas, Size size, double op) {
    final glow = Paint();
    final dot = Paint();
    for (final s in stars) {
      final x = s.x * size.width, y = s.y * size.height;
      final tw = 0.45 + 0.55 * math.sin(time * (0.7 + s.speed) + s.phase);
      final alpha = (s.baseA * tw * op).clamp(0.0, 1.0);
      if (s.r > 1.15) {
        glow.shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: alpha * 0.5),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: Offset(x, y), radius: s.r * 3));
        canvas.drawCircle(Offset(x, y), s.r * 3, glow);
      }
      dot.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), s.r, dot);
    }
  }

  // ---------- Solar system ----------
  void _solarSystem(
      Canvas canvas, Size size, Offset center, double scale, double op) {
    final R = size.shortestSide;
    const tilt = 0.34;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.05 * op);
    for (final p in _kPlanets) {
      final a = R * p.orbitF * scale;
      canvas.drawOval(
          Rect.fromCenter(center: center, width: a * 2, height: a * 2 * tilt),
          ring);
    }
    final back = <_Placed>[], front = <_Placed>[];
    for (final p in _kPlanets) {
      final th = p.phase + time * p.speed;
      final a = R * p.orbitF * scale;
      final pos = Offset(
          center.dx + a * math.cos(th), center.dy + a * tilt * math.sin(th));
      (math.sin(th) < 0 ? back : front)
          .add(_Placed(p, pos, R * p.sizeF * scale));
    }
    for (final pl in back) {
      _planet(canvas, pl, op);
    }
    _sun(canvas, center, R * 0.10 * scale, op);
    for (final pl in front) {
      _planet(canvas, pl, op);
    }
  }

  void _sun(Canvas canvas, Offset c, double r, double op) {
    final pulse = 0.5 + 0.5 * math.sin(time * 0.8);
    final coronaR = r * (2.8 + 0.35 * pulse);
    canvas.drawCircle(
      c,
      coronaR,
      Paint()
        ..shader = RadialGradient(colors: [
          _a(const Color(0xFFFFE9A8), op * 0.55),
          _a(const Color(0xFFFF9D3B), op * 0.22),
          _a(cs.primary, op * 0.10),
          Colors.transparent,
        ], stops: const [0.0, 0.35, 0.6, 1.0])
            .createShader(Rect.fromCircle(center: c, radius: coronaR)),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          _a(Colors.white, op),
          _a(const Color(0xFFFFE9A8), op),
          _a(const Color(0xFFFFB13B), op),
        ], stops: const [0.0, 0.5, 1.0])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  void _planet(Canvas canvas, _Placed pl, double op) {
    final c = pl.pos, r = pl.r, p = pl.spec;
    if (r < 0.5) return;
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..shader = RadialGradient(colors: [_a(p.lit, op * 0.2), _a(p.lit, 0)])
            .createShader(Rect.fromCircle(center: c, radius: r * 1.5)),
    );
    if (p.ring) _ring(canvas, c, r, op, front: false);
    final bodyRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.45),
          radius: 1.15,
          colors: [
            _a(Color.lerp(p.lit, Colors.white, 0.35)!, op),
            _a(p.lit, op),
            _a(p.dark, op),
            _a(const Color(0xFF04050C), op),
          ],
          stops: const [0.0, 0.42, 0.8, 1.0],
        ).createShader(bodyRect),
    );
    if (p.bands && r > 6) {
      canvas.save();
      canvas.clipPath(Path()..addOval(bodyRect));
      final band = Paint();
      for (int i = -2; i <= 2; i++) {
        final yy = c.dy + i * r * 0.34;
        band.color = _a(
            i.isEven ? p.dark : Color.lerp(p.lit, Colors.white, 0.15)!,
            op * 0.28);
        canvas.drawRect(
            Rect.fromLTRB(c.dx - r, yy - r * 0.16, c.dx + r, yy + r * 0.16),
            band);
      }
      canvas.restore();
    }
    if (p.earthlike && r > 5) {
      canvas.save();
      canvas.clipPath(Path()..addOval(bodyRect));
      final land = Paint()..color = _a(const Color(0xFF3E8C52), op * 0.75);
      canvas.drawCircle(Offset(c.dx - r * 0.25, c.dy - r * 0.1), r * 0.34, land);
      canvas.drawCircle(Offset(c.dx + r * 0.3, c.dy + r * 0.28), r * 0.26, land);
      canvas.restore();
    }
    if (p.ring) _ring(canvas, c, r, op, front: true);
  }

  void _ring(Canvas canvas, Offset c, double r, double op, {required bool front}) {
    canvas.save();
    canvas.clipRect(front
        ? Rect.fromLTRB(c.dx - r * 3, c.dy, c.dx + r * 3, c.dy + r * 3)
        : Rect.fromLTRB(c.dx - r * 3, c.dy - r * 3, c.dx + r * 3, c.dy));
    final rect = Rect.fromCenter(center: c, width: r * 4.6, height: r * 1.5);
    canvas.drawOval(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.5
        ..shader = SweepGradient(colors: [
          _a(const Color(0xFFE3CD92), 0),
          _a(const Color(0xFFEAD8A0), op * 0.8),
          _a(const Color(0xFFC9B070), op * 0.33),
          _a(const Color(0xFFEAD8A0), op * 0.8),
          _a(const Color(0xFFE3CD92), 0),
        ]).createShader(rect),
    );
    canvas.restore();
  }

  // ---------- Milky Way ----------
  void _milkyWay(
      Canvas canvas, Size size, Offset center, double scale, double op) {
    final gR = size.shortestSide * 1.15 * scale;
    const tilt = 0.5;
    final rot = time * 0.05;
    // Disk glow (elliptical).
    final diskRect = Rect.fromCenter(
        center: center, width: gR * 2.3, height: gR * 2.3 * tilt);
    canvas.drawOval(
      diskRect,
      Paint()
        ..shader = RadialGradient(colors: [
          _a(cs.primary, op * 0.22),
          _a(cs.secondary, op * 0.12),
          Colors.transparent,
        ], stops: const [0.0, 0.5, 1.0]).createShader(diskRect),
    );
    // Spiral-arm stars.
    final dot = Paint();
    for (final s in mw) {
      final a = s.angle + rot;
      final rr = s.rad * gR;
      final pos = Offset(
          center.dx + math.cos(a) * rr, center.dy + math.sin(a) * rr * tilt);
      // Warmer near the core, bluer in the arms.
      final col = Color.lerp(const Color(0xFFFFE6B0), Colors.white, s.rad)!;
      dot.color = _a(col, op * s.b);
      canvas.drawCircle(pos, s.size * scale.clamp(0.5, 1.2), dot);
    }
    // Bright bulge.
    final bulgeR = gR * 0.22;
    canvas.drawCircle(
      center,
      bulgeR,
      Paint()
        ..shader = RadialGradient(colors: [
          _a(Colors.white, op),
          _a(const Color(0xFFFFE6B0), op * 0.8),
          _a(const Color(0xFFFFB347), 0),
        ], stops: const [0.0, 0.4, 1.0])
            .createShader(Rect.fromCircle(center: center, radius: bulgeR)),
    );
  }

  // ---------- Distant galaxies ----------
  void _galaxiesField(
      Canvas canvas, Size size, Offset focal, double op, double z) {
    final cols = [
      Colors.white,
      const Color(0xFFBFD6FF),
      const Color(0xFFFFD0B0),
      const Color(0xFFE6C0FF),
    ];
    // Keep flying in as we zoom out further: galaxies grow and drift outward
    // from the focal point so the deepest scale still reads as motion.
    final zoom = 1.0 + (z - 1.8).clamp(0.0, 4.0) * 0.5;
    for (final g in galaxies) {
      final drift = math.sin(time * 0.05 + g.rot) * 6;
      final base = Offset(g.x * size.width + drift, g.y * size.height);
      final c = focal + (base - focal) * zoom;
      final r = size.shortestSide * g.size * zoom;
      final col = cols[g.colorIndex];
      // Tilted disk glow.
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(g.rot);
      final rect = Rect.fromCenter(center: Offset.zero, width: r * 2, height: r);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [_a(col, op * 0.7), _a(col, 0)])
              .createShader(rect),
      );
      canvas.restore();
      // Core.
      canvas.drawCircle(c, r * 0.28, Paint()..color = _a(Colors.white, op));
    }
  }

  @override
  bool shouldRepaint(_GalaxyPainter old) => true;
}

class _Placed {
  final _Planet spec;
  final Offset pos;
  final double r;
  const _Placed(this.spec, this.pos, this.r);
}
