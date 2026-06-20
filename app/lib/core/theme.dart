import 'package:flutter/material.dart';

/// A selectable, professional theme preset. Each is a seed colour from which a
/// full Material 3 light/dark scheme is derived, plus a subtle background
/// gradient for an elegant, "deep" feel (gradients are GPU-cheap — no blur).
class AppPreset {
  final String id;
  final String label;
  final Color seed;
  final Color accent;
  const AppPreset(this.id, this.label, this.seed, this.accent);

  ColorScheme scheme(Brightness b) => ColorScheme.fromSeed(
        seedColor: seed,
        brightness: b,
        secondary: accent,
      );
}

/// The themes the user can pick from. All tuned to read as professional/elegant.
const List<AppPreset> kPresets = [
  AppPreset('sahar', 'Sahar', Color(0xFF0F766E), Color(0xFFD4A24E)), // teal + gold (default)
  AppPreset('aurora', 'Aurora', Color(0xFF4F46E5), Color(0xFF22D3EE)), // indigo + cyan
  AppPreset('emerald', 'Emerald', Color(0xFF047857), Color(0xFF34D399)),
  AppPreset('amber', 'Amber', Color(0xFFB45309), Color(0xFF14746F)), // warm luxe
  AppPreset('plum', 'Plum', Color(0xFF7C3AED), Color(0xFFEC4899)),
];

AppPreset presetById(String id) =>
    kPresets.firstWhere((p) => p.id == id, orElse: () => kPresets.first);

class AppTheme {
  /// Build a full ThemeData for a preset + brightness with a shared, refined
  /// design language (rounded geometry, soft depth, generous typography).
  static ThemeData build(AppPreset preset, Brightness brightness) {
    final cs = preset.scheme(brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: cs);
    final isDark = brightness == Brightness.dark;

    return base.copyWith(
      scaffoldBackgroundColor: cs.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: _text(base.textTheme, cs),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: cs.onSurface,
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        margin: EdgeInsets.zero,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.6),
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _FadeThroughTransitions(),
        TargetPlatform.iOS: _FadeThroughTransitions(),
      }),
    );
  }

  static TextTheme _text(TextTheme t, ColorScheme cs) => t.copyWith(
        headlineSmall: t.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        titleLarge: t.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: t.bodyLarge?.copyWith(height: 1.5),
        labelLarge: t.labelLarge?.copyWith(letterSpacing: 0.2),
      );

  /// A subtle full-screen background gradient derived from the active scheme.
  static Gradient backgroundGradient(ColorScheme cs) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.surface,
          Color.alphaBlend(cs.primary.withValues(alpha: 0.05), cs.surface),
          Color.alphaBlend(cs.secondary.withValues(alpha: 0.06), cs.surface),
        ],
      );

  /// Arabic ayah text style — larger, generous line height for readability.
  static const TextStyle arabic = TextStyle(
    fontSize: 28,
    height: 1.9,
    fontFamilyFallback: ['Scheherazade New', 'Amiri', 'serif'],
  );
}

/// Lightweight fade-through page transition (opacity + tiny scale — GPU cheap,
/// no expensive clipping or blur).
class _FadeThroughTransitions extends PageTransitionsBuilder {
  const _FadeThroughTransitions();

  @override
  Widget buildTransitions<T>(route, context, animation, secondary, child) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween(begin: 0.98, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}
