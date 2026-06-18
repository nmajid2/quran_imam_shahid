import 'package:flutter/material.dart';

/// Calm, distraction-free, ad-free. Light + dark.
class AppTheme {
  static const _seed = Color(0xFF14746F); // teal-green

  static ThemeData light() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        brightness: Brightness.light,
      );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      );

  /// Arabic ayah text style — larger, generous line height for readability.
  static const TextStyle arabic = TextStyle(
    fontSize: 28,
    height: 1.9,
    fontFamilyFallback: ['Scheherazade New', 'Amiri', 'serif'],
  );
}
